"""Port of `cronjobs/archive_cleanup.php`.

Bounds the growth of `shares_archive` by deleting rows older than a
configurable retention window. Without this, every archived share
accumulates forever and pplns_payout's archive-fill query slows
down linearly with the table size.

The PHP version's algorithm trims a percentage of oldest rows that
predate either NOW − 30min OR the Nth-most-recent block's first
share. Effectively a "delete the oldest few percent" knob.

We use a simpler, more predictable rule: delete archive rows older
than the configured prune window. The Nth-most-recent block is also
retained, even if older than the cutoff, by gating on `block_id NOT IN
(the N most recent block ids)`. This means archive rows linked to recent
blocks survive past the cutoff, preserving full PPLNS history within
the active window.

Per-slot — each tick trims the per-slot `shares_archive_<slot>`
table independently. (In our merge-mining setup only the parent
slot's archive is non-empty, but the job runs for every slot
defensively.)
"""

from __future__ import annotations

import time
from dataclasses import dataclass

from ..errors import Skip
from ..logger import get
from ..scheduler import JobContext

log = get(__name__)


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
        # 180 days keeps roughly six months of history while bounding archive growth.
        retention_days = db.get_setting_int(
            "db_prune_after_days",
            default=int(archive_cfg.get("retention_days", 180) or 180),
            floor=7,
        )
        keep_recent_blocks = db.get_setting_int(
            "db_prune_keep_recent_blocks",
            default=int(archive_cfg.get("keep_recent_blocks", 100) or 100),
            floor=1,
        )
        batch_size = db.get_setting_int(
            "db_prune_batch_size",
            default=int(archive_cfg.get("batch_size", 50000) or 50000),
            floor=1000,
        )
        max_batches = db.get_setting_int(
            "db_prune_max_batches",
            default=int(archive_cfg.get("max_batches", 4) or 4),
            floor=1,
        )

        if retention_days <= 0:
            log.debug("[%s/%s] db_prune_after_days <= 0; skipping",
                      self.name, slot_label)
            return

        # Slot-aware table names via the existing helpers.
        archive_table = db._shares_archive_table(self.slot)
        block_table = db._blocks_table(self.slot)

        # Delete in bounded oldest-first batches. That keeps an oversized
        # archive cleanup from creating one long-running DELETE and lets the
        # hourly scheduler make steady progress under load.
        sql = (
            f"DELETE FROM {archive_table} "
            f"WHERE time < DATE_SUB(NOW(), INTERVAL %s DAY) "
            f"  AND IFNULL(block_id, 0) NOT IN ("
            f"    SELECT id FROM ("
            f"      SELECT id FROM {block_table} "
            f"      ORDER BY height DESC LIMIT %s"
            f"    ) AS keep"
            f"  ) "
            f"ORDER BY time ASC "
            f"LIMIT %s"
        )
        total_deleted = 0
        try:
            for _ in range(max_batches):
                deleted = db.execute(sql, (retention_days, keep_recent_blocks, batch_size))
                total_deleted += deleted
                if deleted < batch_size:
                    break
        except Exception as exc:
            db.set_setting("db_prune_last_run", str(int(time.time())))
            db.set_setting("db_prune_last_status", f"{slot_label}: failed: {exc}")
            raise Skip(f"archive cleanup query failed: {exc}")

        db.set_setting("db_prune_last_run", str(int(time.time())))
        db.set_setting("db_prune_last_deleted", str(total_deleted))
        db.set_setting(
            "db_prune_last_status",
            f"{slot_label}: deleted {total_deleted} older than {retention_days}d",
        )

        if total_deleted:
            log.info("[%s/%s] purged %d archived shares older than %d days",
                     self.name, slot_label, total_deleted, retention_days)
        else:
            log.debug("[%s/%s] no archived shares to purge",
                      self.name, slot_label)
