"""Port of `cronjobs/archive_cleanup.php`.

Bounds the growth of `shares_archive` by deleting rows older than a
configurable retention window. Without this, every archived share
accumulates forever and pplns_payout's archive-fill query slows
down linearly with the table size.

The PHP version's algorithm trims a percentage of oldest rows that
predate either NOW − 30min OR the Nth-most-recent block's first
share. Effectively a "delete the oldest few percent" knob.

We use a simpler, more predictable rule: **delete rows older than
`archive.retention_days` days** (default 30). The Nth-most-recent
block is also retained — even if older than the cutoff — by gating
on `block_id NOT IN (the N most recent block ids)`. This means
archive rows linked to recent blocks survive past the cutoff,
preserving full PPLNS history within the window.

Per-slot — each tick trims the per-slot `shares_archive_<slot>`
table independently. (In our merge-mining setup only the parent
slot's archive is non-empty, but the job runs for every slot
defensively.)
"""

from __future__ import annotations

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
        retention_days = int(archive_cfg.get("retention_days", 30))
        keep_recent_blocks = int(archive_cfg.get("keep_recent_blocks", 50))

        if retention_days <= 0:
            log.debug("[%s/%s] archive.retention_days <= 0; skipping",
                      self.name, slot_label)
            return

        # Slot-aware table names via the existing helpers.
        archive_table = db._shares_archive_table(self.slot)
        block_table = db._blocks_table(self.slot)

        # Delete rows older than the cutoff UNLESS they belong to one of
        # the most-recent N blocks (so we don't trim the active PPLNS
        # window). The IFNULL on block_id keeps free-floating archive
        # rows in scope of the cutoff.
        sql = (
            f"DELETE FROM {archive_table} "
            f"WHERE time < DATE_SUB(NOW(), INTERVAL %s DAY) "
            f"  AND IFNULL(block_id, 0) NOT IN ("
            f"    SELECT id FROM ("
            f"      SELECT id FROM {block_table} "
            f"      ORDER BY height DESC LIMIT %s"
            f"    ) AS keep"
            f"  )"
        )
        try:
            deleted = db.execute(sql, (retention_days, keep_recent_blocks))
        except Exception as exc:
            raise Skip(f"archive cleanup query failed: {exc}")

        if deleted:
            log.info("[%s/%s] purged %d archived shares older than %d days",
                     self.name, slot_label, deleted, retention_days)
        else:
            log.debug("[%s/%s] no archived shares to purge",
                      self.name, slot_label)
