"""Single-process scheduler that replaces cron + PHP-CLI fork-on-tick.

Each registered job has its own interval, retry budget, and per-coin scope.
The runtime keeps a persistent set of `RpcClient` and `Db` instances so
keepalive amortizes across calls instead of being thrown away between
PHP forks.

Wave 1 additions (idempotency / poison / per-job kill switch):

- Each job may declare `coin_moving = True` to opt into the slot-wide
  poison flag. When ANY coin-moving job in a slot raises Fatal, the
  scheduler writes a row to `cronjobs_py_disabled` keyed `slot:{slot}`
  and skips every later tick of any coin-moving job in that slot until
  an operator clears the row. Non-coin-moving jobs (stats, blockupdate,
  archive_cleanup, token_cleanup, tickerupdate, notifications) keep
  ticking — the dashboard stays alive while the operator investigates.
- `Settings.disabled_jobs` (env: `CRONJOBS_PY_DISABLED_JOBS`,
  comma-separated job-name list) lets the operator pre-disable specific
  job names at scheduler startup, without editing code. Used in the
  Wave 1 cutover: PHP cron stays authoritative for findblock / pplns /
  payouts / liquid_payout, and cronjobs-py runs only the safe subset.
"""

from __future__ import annotations

import dataclasses
import signal
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass
from typing import Protocol

from .cache import Cache
from .db import Db
from .errors import Disabled, Fatal, Skip, Transient
from .logger import get
from .rpc import RpcClient
from .settings import CoinConfig, Settings

log = get(__name__)


class Job(Protocol):
    name: str
    interval_seconds: int
    # Wave 1: jobs in the coin-moving group opt in via this attribute.
    # Default False if a job doesn't declare it (most jobs are read-only
    # or non-balance-affecting).
    coin_moving: bool
    slot: str

    def run(self, ctx: "JobContext") -> None: ...


@dataclass
class JobContext:
    settings: Settings
    db: Db
    rpc_by_slot: dict[str, RpcClient]
    cache: Cache | None = None

    def rpc(self, slot: str = "") -> RpcClient:
        return self.rpc_by_slot[slot]


@dataclass
class _State:
    next_run: float
    last_error: str | None = None
    consecutive_errors: int = 0


class Scheduler:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.db = Db(settings.db)
        self.rpc_by_slot: dict[str, RpcClient] = {
            c.slot: RpcClient(c.endpoint) for c in settings.coins
        }
        # Connect to MPOS's memcached so stats jobs can warm the cache
        # the PHP web UI reads. Skipped silently if memcache config is
        # absent or the host is unreachable — the UI's fall-through
        # SQL path keeps things correct, just slower.
        mc = (settings.raw.get("memcache") or {})
        self.cache: Cache | None = None
        if mc.get("enabled") and mc.get("host"):
            try:
                self.cache = Cache(
                    host=str(mc["host"]),
                    port=int(mc.get("port", 11211)),
                    key_prefix=str(mc.get("keyprefix", "mpos_")),
                    default_ttl=int(mc.get("expiration", 300)),
                )
                log.info(
                    "memcache attached at %s:%s prefix=%r",
                    mc["host"], mc.get("port", 11211), mc.get("keyprefix", "mpos_"),
                )
            except Exception as exc:
                log.warning("memcache init failed: %s — UI will use SQL fall-through", exc)
        self._jobs: list[Job] = []
        self._stop = threading.Event()

    def register(self, job: Job) -> None:
        self._jobs.append(job)

    def stop(self) -> None:
        self._stop.set()

    def _ctx(self) -> JobContext:
        return JobContext(self.settings, self.db, self.rpc_by_slot, self.cache)

    def run_once(self, name: str | None = None) -> None:
        """Run one tick: invoke every registered job (or just `name`) once."""
        ctx = self._ctx()
        for job in self._jobs:
            if name is not None and job.name != name:
                continue
            self._run_one(job, ctx)

    def run_forever(self) -> None:
        """Long-lived scheduler. Runs each job at its declared interval."""
        signal.signal(signal.SIGTERM, lambda *_: self.stop())
        signal.signal(signal.SIGINT, lambda *_: self.stop())

        ctx = self._ctx()
        now = time.monotonic()
        states = {j.name: _State(next_run=now) for j in self._jobs}

        log.info("scheduler starting with %d job(s)", len(self._jobs))
        while not self._stop.is_set():
            now = time.monotonic()
            next_due = min(s.next_run for s in states.values()) if states else now + 60
            sleep_for = max(0.0, next_due - now)
            if sleep_for > 0:
                self._stop.wait(timeout=sleep_for)
                if self._stop.is_set():
                    break
            now = time.monotonic()
            for job in self._jobs:
                state = states[job.name]
                if state.next_run > now:
                    continue
                self._run_one(job, ctx)
                state.next_run = time.monotonic() + job.interval_seconds

        log.info("scheduler exiting")
        self.close()

    def _is_disabled(self, job: Job) -> tuple[bool, str | None]:
        """Decide whether to skip this tick based on operator-set
        kill-switch state. Returns (skip, reason).

        Three sources of "skip":

        1. The `disabled_jobs` settings field (env: CRONJOBS_PY_DISABLED_JOBS)
           — pre-deploy operator decision. Matches by exact job.name.
        2. The `cronjobs_py_disabled` table — runtime poison flag set
           when a previous tick raised Fatal. Checks scope `""` (global),
           `slot:{slot}` (slot-wide for coin-moving jobs), and
           `job:{name}` (job-specific override).
        3. The job-specific scope is checked for ALL jobs, not just
           coin-moving ones, so a stuck `statistics` can be parked
           by an operator without halting the rest of the loop.
        """
        if job.name in self.settings.disabled_jobs:
            return True, "in CRONJOBS_PY_DISABLED_JOBS"

        # Global kill-switch — any scope == "" row in cronjobs_py_disabled
        # halts every job.
        try:
            row = self.db.get_disabled_flag("")
        except Exception as exc:
            log.warning(
                "[%s] could not read cronjobs_py_disabled (%s); "
                "letting tick proceed without poison check",
                job.name, exc,
            )
            return False, None
        if row:
            return True, f"global poison: {row['reason']}"

        # Per-job override.
        row = self.db.get_disabled_flag(f"job:{job.name}")
        if row:
            return True, f"job poison: {row['reason']}"

        # Slot-wide poison only applies to coin-moving jobs.
        if getattr(job, "coin_moving", False):
            slot = getattr(job, "slot", "")
            row = self.db.get_disabled_flag(f"slot:{slot}")
            if row:
                return True, f"slot poison ({slot or 'parent'}): {row['reason']}"

        return False, None

    def _on_fatal(self, job: Job, exc: Fatal) -> None:
        """Persist the poison flag for the appropriate scope.

        For coin-moving jobs, scope = `slot:{slot}` so every coin-moving
        job in that slot freezes (pplns, payouts, liquid_payout, findblock
        all share state through the per-slot transactions ledger).

        For non-coin-moving jobs, scope = `job:{name}` so just this one
        job freezes — the dashboard / cleanup / notifications keep going.

        Best-effort: if the DB itself is the problem, we log and let the
        next tick try again. The flag is also useful as a runbook
        artefact (operator reads `SELECT * FROM cronjobs_py_disabled` to
        see what tripped).
        """
        scope = (
            f"slot:{getattr(job, 'slot', '')}"
            if getattr(job, "coin_moving", False)
            else f"job:{job.name}"
        )
        try:
            self.db.set_disabled_flag(scope, str(exc), set_by=job.name)
            log.error(
                "[%s] FATAL: %s — set cronjobs_py_disabled scope=%r",
                job.name, exc, scope,
            )
        except Exception as flag_exc:
            log.error(
                "[%s] FATAL: %s — could not persist disabled flag: %s",
                job.name, exc, flag_exc,
            )

    def _monitoring_name(self, job: Job) -> str:
        slot = getattr(job, "slot", "")
        suffix = "" if slot == "" else f"_{slot}"
        name = job.name

        if name.startswith("findblock-"):
            return f"findblock{suffix}"
        if name.startswith("pplns-"):
            return f"pplns_payout{suffix}"
        if name.startswith("payouts-"):
            return f"payouts{suffix}"
        if name.startswith("blockupdate-"):
            return f"blockupdate{suffix}"
        if name.startswith("liquid-"):
            return f"liquid_payout{suffix}"
        if name.startswith("archive-"):
            return f"archive_cleanup{suffix}"
        return name

    def _monitor_start(self, job: Job) -> tuple[str, int, float]:
        cron = self._monitoring_name(job)
        started_at = int(time.time())
        started_mono = time.monotonic()
        try:
            self.db.set_monitoring_status(f"{cron}_disabled", "yesno", 0)
            self.db.set_monitoring_status(f"{cron}_active", "yesno", 1)
            self.db.set_monitoring_status(f"{cron}_starttime", "date", started_at)
        except Exception as exc:
            log.warning("[%s] could not update monitoring start: %s", job.name, exc)
        return cron, started_at, started_mono

    def _monitor_end(self, cron: str, started_mono: float, *,
                     message: str, status: int, disabled: bool = False) -> None:
        try:
            self.db.set_monitoring_status(f"{cron}_active", "yesno", 0)
            self.db.set_monitoring_status(f"{cron}_message", "message", message)
            self.db.set_monitoring_status(f"{cron}_status", "okerror", status)
            self.db.set_monitoring_status(f"{cron}_endtime", "date", int(time.time()))
            self.db.set_monitoring_status(
                f"{cron}_runtime", "time", f"{time.monotonic() - started_mono:.6f}",
            )
            self.db.set_monitoring_status(
                f"{cron}_disabled", "yesno", 1 if disabled else 0,
            )
        except Exception as exc:
            log.warning("[%s] could not update monitoring end: %s", cron, exc)

    def _monitor_disabled_skip(self, job: Job, reason: str) -> None:
        cron, _started_at, started_mono = self._monitor_start(job)
        self._monitor_end(
            cron, started_mono,
            message=f"Disabled by cronjobs-py: {reason}",
            status=1,
            disabled=True,
        )

    def _run_one(self, job: Job, ctx: JobContext) -> None:
        skip, reason = self._is_disabled(job)
        if skip:
            log.info("[%s] disabled (%s); skipping tick", job.name, reason)
            self._monitor_disabled_skip(job, reason or "disabled")
            return

        log.info("[%s] tick", job.name)
        cron, _started_at, t0 = self._monitor_start(job)
        try:
            job.run(ctx)
            self._monitor_end(cron, t0, message="OK", status=0)
            log.info("[%s] ok in %.2fs", job.name, time.monotonic() - t0)
        except Skip as exc:
            self._monitor_end(cron, t0, message=str(exc), status=0)
            log.warning("[%s] skipped: %s", job.name, exc)
        except Disabled as exc:
            # Job code itself decided to bail (e.g. checked the poison
            # flag mid-run). Treated as a clean skip for telemetry.
            self._monitor_end(cron, t0, message=str(exc), status=0)
            log.info("[%s] disabled mid-run: %s", job.name, exc)
        except Transient as exc:
            self._monitor_end(cron, t0, message=str(exc), status=1)
            log.warning("[%s] transient (will retry next tick): %s", job.name, exc)
        except Fatal as exc:
            self._monitor_end(cron, t0, message=str(exc), status=1, disabled=True)
            self._on_fatal(job, exc)
        except Exception as exc:
            self._monitor_end(cron, t0, message=str(exc), status=1)
            log.exception("[%s] unexpected error: %s", job.name, exc)

    def close(self) -> None:
        for client in self.rpc_by_slot.values():
            client.close()
        self.db.close()
