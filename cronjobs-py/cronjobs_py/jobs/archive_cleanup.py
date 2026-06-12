"""Port of `cronjobs/archive_cleanup.php`.

Bounds the growth of `shares_archive` by deleting rows beyond the
configured raw-share retention window. Without this, every archived
share accumulates forever and pplns_payout's archive-fill query slows
down linearly with the table size.

The PHP version's algorithm trims a percentage of oldest rows that
predate either NOW − 30min OR the Nth-most-recent block's first share.
Effectively a "delete the oldest few percent" knob.

We use a more predictable rule: delete archive rows below a safe
`share_id` cutoff. The desired cutoff is the newer of:

- rows older than the configured prune window, and
- rows outside the configured "keep latest raw shares" cap.

That cutoff is then clamped below any unaccounted block's PPLNS window
across all configured slots.

Per-slot — each tick trims the per-slot `shares_archive_<slot>`
table independently. (In our merge-mining setup only the parent
slot's archive is non-empty, but the job runs for every slot
defensively.)
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any

from ..errors import Skip
from ..logger import get
from ..scheduler import JobContext

log = get(__name__)


# Keep 1M raw archived shares by default. Low-difficulty pools can produce
# enough valid shares that 250k becomes a thin history window even though it
# remains the absolute accounting safety floor.
MIN_KEEP_RECENT_SHARES = 250_000
DEFAULT_KEEP_RECENT_SHARES = 1_000_000
DEFAULT_MAX_BATCHES = 20


@dataclass
class ArchiveCleanup:
    name: str = "archive_cleanup"
    interval_seconds: int = 3600  # hourly is plenty
    slot: str = ""

    def run(self, ctx: JobContext) -> None:
        cfg = ctx.settings
        db = ctx.db
        slot_label = self.slot or "parent"

        archive_cfg = (cfg.raw.get("archive") or {})
        enabled = db.get_setting_int("db_prune_enabled", default=1)
        if enabled == 0:
            log.debug("[%s/%s] database prune disabled", self.name, slot_label)
            return

        # Prefer live DB settings so the System Status page can tune retention
        # without a redeploy. Config values remain deploy-time defaults before
        # the settings rows are seeded.
        # 180 days keeps roughly six months of history for lower-volume pools.
        # High-volume pools are additionally bounded by db_prune_keep_recent_shares
        # so a short burst cannot create a multi-million-row archive.
        retention_days = db.get_setting_int(
            "db_prune_after_days",
            default=int(archive_cfg.get("retention_days", 180) or 180),
            floor=1,
        )
        keep_recent_shares = db.get_setting_int(
            "db_prune_keep_recent_shares",
            default=int(
                archive_cfg.get("keep_recent_shares", DEFAULT_KEEP_RECENT_SHARES)
                or DEFAULT_KEEP_RECENT_SHARES
            ),
            floor=MIN_KEEP_RECENT_SHARES,
        )
        batch_size = db.get_setting_int(
            "db_prune_batch_size",
            default=int(archive_cfg.get("batch_size", 50000) or 50000),
            floor=1000,
        )
        max_batches = db.get_setting_int(
            "db_prune_max_batches",
            default=int(archive_cfg.get("max_batches", DEFAULT_MAX_BATCHES) or DEFAULT_MAX_BATCHES),
            floor=1,
        )

        if retention_days <= 0:
            log.debug("[%s/%s] db_prune_after_days <= 0; skipping",
                      self.name, slot_label)
            return

        # Slot-aware table names via the existing helpers.
        archive_table = db._shares_archive_table(self.slot)

        max_share_id = self._max_archive_share_id(db, archive_table)
        if max_share_id <= 0:
            self._record_success(db, slot_label, 0, retention_days,
                                 keep_recent_shares, 0)
            log.debug("[%s/%s] no archived shares to purge",
                      self.name, slot_label)
            return

        age_cutoff = self._age_cutoff_share_id(db, archive_table, retention_days)
        cap_cutoff = max(0, max_share_id - keep_recent_shares)
        wanted_cutoff = max(age_cutoff, cap_cutoff)
        min_unaccounted_share_id = self._min_unaccounted_share_id(ctx, db)
        safety_cutoff = self._safety_cutoff_share_id(max_share_id,
                                                     keep_recent_shares,
                                                     min_unaccounted_share_id)
        delete_cutoff = min(wanted_cutoff, safety_cutoff)

        if delete_cutoff <= 0:
            if wanted_cutoff > 0 and min_unaccounted_share_id > 0:
                self._record_blocked(db, slot_label, retention_days,
                                     keep_recent_shares,
                                     min_unaccounted_share_id)
            else:
                self._record_success(db, slot_label, 0, retention_days,
                                     keep_recent_shares, 0)
            log.debug("[%s/%s] no archived shares to purge",
                      self.name, slot_label)
            return

        # Delete in bounded oldest-first batches. That keeps an oversized
        # archive cleanup from creating one long-running DELETE and lets the
        # hourly scheduler make steady progress under load.
        sql = (
            f"DELETE FROM {archive_table} "
            f"WHERE share_id <= %s "
            f"ORDER BY share_id ASC "
            f"LIMIT %s"
        )
        total_deleted = 0
        try:
            for _ in range(max_batches):
                deleted = db.execute(sql, (delete_cutoff, batch_size))
                total_deleted += deleted
                if deleted < batch_size:
                    break
        except Exception as exc:
            self._record_failure(db, slot_label, exc)
            raise Skip(f"archive cleanup query failed: {exc}")

        self._record_success(db, slot_label, total_deleted, retention_days,
                             keep_recent_shares, delete_cutoff)

        if total_deleted:
            log.info(
                "[%s/%s] purged %d archived shares up to share_id %d "
                "(older than %dd or outside latest %d shares)",
                self.name, slot_label, total_deleted, delete_cutoff,
                retention_days, keep_recent_shares,
            )
        else:
            log.debug("[%s/%s] no archived shares to purge",
                      self.name, slot_label)

    def _record_success(self, db: Any, slot_label: str, deleted: int,
                        retention_days: int, keep_recent_shares: int,
                        delete_cutoff: int) -> None:
        if deleted > 0 and delete_cutoff > 0:
            status = (
                f"{slot_label}: deleted {deleted} through share_id {delete_cutoff}; "
                f"target latest {keep_recent_shares} raw shares / {retention_days}d"
            )
        else:
            status = (
                f"{slot_label}: deleted {deleted}; target latest "
                f"{keep_recent_shares} raw shares / {retention_days}d"
            )
        self._record_slot_result(db, slot_label, deleted, status)

    def _record_blocked(self, db: Any, slot_label: str, retention_days: int,
                        keep_recent_shares: int,
                        min_unaccounted_share_id: int) -> None:
        self._record_slot_result(
            db,
            slot_label,
            0,
            f"{slot_label}: blocked by unaccounted block at share_id "
            f"{min_unaccounted_share_id}; target latest "
            f"{keep_recent_shares} raw shares / {retention_days}d",
        )

    def _record_failure(self, db: Any, slot_label: str, exc: Exception) -> None:
        self._record_slot_result(
            db,
            slot_label,
            0,
            f"{slot_label}: failed: {exc}",
            force_visible=True,
        )

    def _record_slot_result(self, db: Any, slot_label: str, deleted: int,
                            status: str, force_visible: bool = False) -> None:
        now = str(int(time.time()))
        slot_key = "parent" if slot_label == "parent" else slot_label
        db.set_setting("db_prune_last_run", now)
        db.set_setting(f"db_prune_last_run_{slot_key}", now)
        db.set_setting(f"db_prune_last_deleted_{slot_key}", str(deleted))
        db.set_setting(f"db_prune_last_status_{slot_key}", status)
        if force_visible or slot_label == "parent":
            db.set_setting("db_prune_last_deleted", str(deleted))
            db.set_setting("db_prune_last_status", status)

    def _max_archive_share_id(self, db: Any, archive_table: str) -> int:
        row = db.fetchone(
            f"SELECT IFNULL(MAX(share_id), 0) AS max_share_id FROM {archive_table}"
        )
        return int((row or {}).get("max_share_id") or 0)

    def _age_cutoff_share_id(self, db: Any, archive_table: str,
                             retention_days: int) -> int:
        row = db.fetchone(
            f"SELECT IFNULL(MAX(share_id), 0) AS cutoff_share_id "
            f"FROM {archive_table} "
            f"WHERE time < DATE_SUB(NOW(), INTERVAL %s DAY)",
            (retention_days,),
        )
        return int((row or {}).get("cutoff_share_id") or 0)

    def _safety_cutoff_share_id(self, max_share_id: int,
                                keep_recent_shares: int,
                                min_unaccounted: int) -> int:
        if min_unaccounted <= 0:
            return max_share_id
        return max(0, min_unaccounted - keep_recent_shares)

    def _min_unaccounted_share_id(self, ctx: JobContext, db: Any) -> int:
        block_tables = self._block_tables_for_safety(ctx, db)
        if not block_tables:
            return 0
        selects = [
            f"SELECT MIN(share_id) AS share_id FROM {table} "
            f"WHERE accounted = 0 AND share_id IS NOT NULL "
            f"AND confirmations >= 0"
            for table in block_tables
        ]
        row = db.fetchone(
            "SELECT MIN(share_id) AS min_share_id FROM ("
            + " UNION ALL ".join(selects)
            + ") AS unaccounted"
        )
        return int((row or {}).get("min_share_id") or 0)

    def _block_tables_for_safety(self, ctx: JobContext, db: Any) -> list[str]:
        coins = getattr(getattr(ctx, "settings", None), "coins", None) or []
        slots = []
        for coin in coins:
            slots.append(getattr(coin, "slot", "") or "")
        if not slots:
            slots = [self.slot]
        return sorted({db._blocks_table(slot) for slot in slots})
