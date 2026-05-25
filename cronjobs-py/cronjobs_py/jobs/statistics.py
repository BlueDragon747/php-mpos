"""Port of `cronjobs/statistics.php`.

Pre-computes the four pool-wide aggregations the MPOS web UI displays
on its dashboard, and writes them to memcached under the same keys
the PHP `Statistics` class reads from. Each PHP stat method has a SQL
fall-through that recomputes on cache miss, so a degraded memcache
write doesn't break correctness — just performance.

This job does triple duty:

1. Pool-wide current hashrate (kH/s) — the headline number on the
   home page.
2. Per-user share counts (`valid` / `invalid`) — feeds the round
   progress bar and per-user totals.
3. Per-user hashrate + share counts in the recent window — feeds the
   "Top miners" leaderboard.
4. Top contributors by hashrate — same leaderboard, separate cache
   key so the UI can request just the top-N.

It also refreshes `pool_worker.shares_difficulty` so the per-worker
hashrate column on the dashboard isn't stuck at 0 (eloipool's
`ShareLogging` only writes the share row, not the rolling avg the UI
expects).
"""

from __future__ import annotations

import math
import time
from dataclasses import dataclass

from ..errors import Skip
from ..logger import get
from ..scheduler import JobContext

log = get(__name__)

STATISTICS_ALL_USER_SHARES = "STATISTICS_ALL_USER_SHARES"
STATISTICS_ALL_USER_HASHRATES = "STATISTICS_ALL_USER_HASHRATES"
STATISTICS_ALL_WORKER_HASHRATES = "STATISTICS_ALL_WORKER_HASHRATES"
TOP_CONTRIBUTORS_HASHES_15 = "getTopContributorshashes15"
# Memcache keys holding the EMA running state (value + timestamp) so
# successive ticks can blend the new sample with the previous estimate.
HASHRATE_EMA_STATE = "getCurrentHashrate_ema_state"
HASHRATE_USER_EMA_STATE = "getCurrentUserHashrate_ema_state"
HASHRATE_WORKER_EMA_STATE = "getCurrentWorkerHashrate_ema_state"


_EMA_FAST_RESPONSE_THRESHOLD = 0.20   # |sample - prev_ema| / prev_ema > 0.20
_EMA_FAST_RESPONSE_DIVISOR = 5         # effective tau on big change = tau / 5
_WORKER_STALE_SECONDS = 300            # no shares in this many sec → "going dormant"


def _ema_step(prev_value, prev_ts, sample, now_ts, tau, *, force_fast=False):
    """One step of a time-aware exponential moving average.

    `tau` is the time constant in seconds — the EMA decays toward `sample`
    with half-life ≈ 0.693 * tau. When `prev_value` is None we seed from
    the sample so the display doesn't start at zero. Time-aware alpha
    means a cron stall (large dt) catches up correctly instead of
    underweighting the recovered sample.

    Symmetric fast-response: when the new sample diverges from the
    previous EMA by more than _EMA_FAST_RESPONSE_THRESHOLD in either
    direction, use a tau divided by _EMA_FAST_RESPONSE_DIVISOR for
    this tick. Real load changes (drop or rise) converge in a fraction
    of the configured half-life; steady-state noise within the
    threshold keeps the configured tau for smoothness.

    `force_fast=True` skips the threshold check and always uses the
    short tau — used by the stale-worker decay path so a worker whose
    miner just disconnected drops in 2-3 ticks instead of waiting for
    the sample window to drain its old shares.
    """
    if prev_value is None or prev_ts is None:
        return float(sample)
    dt = max(1.0, float(now_ts) - float(prev_ts))
    prev_f = float(prev_value)
    rel_change = abs(float(sample) - prev_f) / max(1.0, prev_f)
    if force_fast or rel_change > _EMA_FAST_RESPONSE_THRESHOLD:
        effective_tau = max(60.0, float(tau) / _EMA_FAST_RESPONSE_DIVISOR)
    else:
        effective_tau = max(1.0, float(tau))
    alpha = 1.0 - math.exp(-dt / effective_tau)
    return alpha * float(sample) + (1.0 - alpha) * prev_f


@dataclass
class Statistics:
    name: str = "statistics"
    interval_seconds: int = 60
    # Pool-wide stats; the slot field is unused but kept so __main__'s
    # registration loop can hand any slot in without special-casing.
    slot: str = ""

    def run(self, ctx: JobContext) -> None:
        cfg = ctx.settings
        db = ctx.db
        cache = ctx.cache

        # MPOS config knobs that go into the hashrate math.
        target_bits = int(cfg.raw.get("target_bits", 32))
        difficulty_const = int(cfg.raw.get("difficulty", 21))
        # Sampling window for each raw hashrate read.
        interval = db.get_setting_int(
            "hashrate_window_seconds", default=900, floor=60
        )
        # EMA time constant. Half-life ≈ 0.693 * tau. Default 300s
        # (~3.5 min half-life) gives quick response to load changes
        # with most of the sample noise already smoothed out by the
        # wider 900s sampling window above.
        tau = db.get_setting_int(
            "hashrate_ema_tau_seconds", default=300, floor=60
        )

        # 1. Reserved for the pool hashrate write — done at the END of
        # this tick after per-worker EMAs are computed, so the pool
        # value is sum(worker EMAs). That way a single worker going
        # dormant via the stale-detection path cascades into the pool
        # chart on the same tick rather than waiting ~10 min for the
        # 900s pool-wide sample window to drain its old shares.
        now_ts = time.time()

        # 2. Per-user share counts for the current round.
        try:
            user_shares = db.stats_per_user_shares(
                difficulty_const=difficulty_const,
            )
            max_share_id = db.stats_max_share_id()
            round_id = db.stats_current_round_id()
        except Exception as exc:
            log.warning("[%s] per_user_shares query failed: %s",
                        self.name, exc)
            user_shares = []
            max_share_id = 0
            round_id = 0
        if cache:
            cache.set_round(
                STATISTICS_ALL_USER_SHARES,
                {
                    "share_id": max_share_id,
                    "data": {int(row["id"]): row for row in user_shares},
                },
                round_id=round_id,
                flag=0,
            )
        log.info("[%s] %d users with share rows", self.name, len(user_shares))

        # 3. Per-user mining stats. We still query the SQL aggregate
        # for sharerate / avgsharediff / id+username, but the displayed
        # `hashrate` is overwritten further down with sum(this-user's
        # worker EMAs) so the personal-hashrate gauge inherits the same
        # fast-drop + stale behaviour as the worker table and pool chart.
        try:
            user_mining = db.stats_per_user_mining(
                target_bits=target_bits,
                difficulty_const=difficulty_const,
                interval=interval,
            )
        except Exception as exc:
            log.warning("[%s] per_user_mining query failed: %s",
                        self.name, exc)
            user_mining = []

        # 3b. Per-worker EMA-smoothed hashrate. Keyed by the literal
        # `account.workername` string from the shares table so the
        # dashboard worker table can substitute these for the raw
        # per-window values it would otherwise compute via SQL.
        try:
            worker_mining = db.stats_per_worker_mining(
                target_bits=target_bits,
                difficulty_const=difficulty_const,
                interval=interval,
            )
        except Exception as exc:
            log.warning("[%s] per_worker_mining query failed: %s",
                        self.name, exc)
            worker_mining = []
        prev_w = cache.get_static(HASHRATE_WORKER_EMA_STATE) if cache else None
        prev_w_map = prev_w.get("data") if isinstance(prev_w, dict) else None
        prev_w_ts = prev_w.get("ts") if isinstance(prev_w, dict) else None
        smoothed_worker_map = {}
        # Workers visible in the current sampling window keyed by name.
        mining_by_worker = {r["worker"]: r for r in worker_mining}
        # Snapshot raw per-worker samples before the EMA loop mutates
        # each row's "hashrate" field in place. Used for the pool-tick
        # log line so we can report "raw sample vs smoothed EMA"
        # honestly instead of two identical numbers.
        raw_worker_samples = {
            w: float(r.get("hashrate") or 0.0)
            for w, r in mining_by_worker.items()
        }
        # Workers we need to update an EMA for: anyone in the current
        # window OR anyone in the previous cache (so a worker that just
        # disappeared from the window still gets a decay tick).
        all_workers = set(mining_by_worker.keys())
        if prev_w_map:
            all_workers.update(prev_w_map.keys())
        for wname in all_workers:
            row = mining_by_worker.get(wname)
            if row is not None:
                sample = float(row.get("hashrate") or 0.0)
                last_share_age = int(row.get("last_share_age_sec") or 0)
                stale = last_share_age > _WORKER_STALE_SECONDS
            else:
                # Worker dropped out of the window entirely.
                sample = 0.0
                last_share_age = -1
                stale = True
            if stale:
                # Force the sample to 0 and use the short tau so a
                # disconnected miner's EMA falls in 2-3 ticks instead
                # of waiting for the sample window to drain.
                sample_for_ema = 0.0
                force_fast = True
            else:
                sample_for_ema = sample
                force_fast = False
            prev_v = (prev_w_map or {}).get(wname) if prev_w_map else None
            new_ema = _ema_step(
                prev_v, prev_w_ts, sample_for_ema, now_ts, tau,
                force_fast=force_fast,
            )
            smoothed_worker_map[wname] = new_ema
            if row is not None:
                row["hashrate"] = new_ema
        if cache:
            cache.set_static(
                HASHRATE_WORKER_EMA_STATE,
                {"data": smoothed_worker_map, "ts": float(now_ts)},
            )
            cache.set_static(
                STATISTICS_ALL_WORKER_HASHRATES,
                {"data": smoothed_worker_map},
                expire=600,
            )

        # 3b. Per-user hashrate = sum of that user's worker EMAs.
        # Replaces what was previously a separately-EMA-smoothed user
        # value. Inherits the worker-level fast-drop + stale path so a
        # user whose miners just disconnected sees their hashrate
        # collapse on the same tick instead of waiting for the sample
        # window to drain.
        smoothed_user_map = {}
        for row in user_mining:
            uid = int(row["id"])
            account = str(row.get("account") or "")
            # `account.workername` for each worker — match the prefix.
            user_total = 0.0
            for wname, wval in smoothed_worker_map.items():
                if wname.split(".", 1)[0] == account:
                    user_total += float(wval)
            row["hashrate"] = user_total
            smoothed_user_map[uid] = user_total
        if cache:
            cache.set_static(
                STATISTICS_ALL_USER_HASHRATES,
                {"data": {int(row["id"]): row for row in user_mining}},
                expire=600,
            )

        # 1b. Pool hashrate = sum of per-worker EMAs.
        # Sourced from the just-computed smoothed_worker_map so the
        # pool chart inherits the worker-level fast-drop and stale
        # behaviour. The chart and worker table can't disagree.
        pool_hashrate = float(sum(smoothed_worker_map.values()))
        # Pool sample for the log — sum of raw per-worker samples
        # (the SQL-aggregate "hashrate" field BEFORE the EMA mutation
        # on the row). mining_by_worker rows have been mutated in
        # place above, so use the cached raw samples we captured.
        pool_sample = float(sum(raw_worker_samples.values()))
        log.info(
            "[%s] pool hashrate: sample=%.0f ema=%.0f kH/s "
            "(workers=%d, tau=%ds)",
            self.name, pool_sample, pool_hashrate,
            len(smoothed_worker_map), tau,
        )
        if cache:
            cache.set_static(
                HASHRATE_EMA_STATE,
                {"value": pool_hashrate, "ts": float(now_ts)},
            )
            cache.set_static("getCurrentHashrate", pool_hashrate)

        # 4. Top contributors leaderboard (hashrate ordered)
        try:
            top = db.stats_top_contributors(
                target_bits=target_bits,
                difficulty_const=difficulty_const,
                interval=600,
                limit=15,
            )
        except Exception as exc:
            log.warning("[%s] top_contributors query failed: %s",
                        self.name, exc)
            top = []
        if cache and top:
            cache.set_static(TOP_CONTRIBUTORS_HASHES_15, top)
        if top:
            log.info("[%s] top miner: %s @ %.0f kH/s",
                     self.name, top[0]["account"], top[0]["hashrate"])

        # 5. Per-worker live-hashrate refresh (pool_worker.shares_difficulty).
        # eloipool doesn't update this column; without our refresh the UI
        # shows 0 H/s per worker. Folded into statistics so it ticks at
        # the same cadence as the other dashboard data — covers item (5)
        # in the 100% gap list.
        try:
            n = db.update_pool_worker_difficulty(interval=interval)
            log.debug("[%s] refreshed shares_difficulty on %d pool_worker rows",
                      self.name, n)
        except Exception as exc:
            log.warning("[%s] pool_worker refresh failed: %s",
                        self.name, exc)
