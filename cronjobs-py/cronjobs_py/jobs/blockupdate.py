"""Port of `cronjobs/blockupdate.php` (per-slot confirmation tracking).

Walks each `blocks_<slot>` row whose `confirmations` is below the
network/pool confirmation threshold and refreshes it from the daemon.
If the daemon's coinbase transaction for the block now reports
`category: orphan`, the row is flagged with `confirmations = -1` so
downstream cronjobs treat it as orphaned (PPLNS reverses credits,
findblock skips re-attribution).

Differences vs the PHP version:

- Uses our retry-aware RPC layer; per-call failures don't abort the
  whole job.
- Per-slot — each cron tick refreshes all coin slots that have a
  registered RPC client.
- Skips blocks already marked orphaned (`confirmations < 0`) so we
  don't re-query them every tick.
"""

from __future__ import annotations

from dataclasses import dataclass

from ..errors import Skip, Transient
from ..logger import get
from ..scheduler import JobContext
from ..settings import slot_int

log = get(__name__)


@dataclass
class BlockUpdate:
    name: str = "blockupdate"
    interval_seconds: int = 120
    slot: str = ""

    def run(self, ctx: JobContext) -> None:
        rpc = ctx.rpc(self.slot)
        db = ctx.db
        slot_label = self.slot or "parent"

        # Threshold: keep refreshing until we're well past the pool's
        # `confirmations` setting. MPOS uses
        # `max(config.network_confirmations, config.confirmations)`.
        cfg = ctx.settings
        threshold = max(
            slot_int(cfg.raw, "network_confirmations", self.slot, 120),
            slot_int(cfg.raw, "confirmations", self.slot, 100),
        )

        rows = db.get_blocks_below_threshold_confirmations(self.slot, threshold)
        if not rows:
            log.debug("[%s/%s] no blocks below %d confirmations",
                      self.name, slot_label, threshold)
            return

        log.info("[%s/%s] refreshing %d blocks below %d confirmations",
                 self.name, slot_label, len(rows), threshold)

        for row in rows:
            block_id = int(row["id"])
            blockhash = row["blockhash"]
            old_confs = int(row.get("confirmations") or 0)
            try:
                info = rpc.getblock(blockhash)
            except Transient as exc:
                log.warning("[%s/%s] block %d: getblock transient (%s); will retry",
                            self.name, slot_label, block_id, exc)
                continue
            except Exception as exc:
                log.error("[%s/%s] block %d: getblock failed: %s",
                          self.name, slot_label, block_id, exc)
                continue

            new_confs = int(info.get("confirmations", -1))

            # Detect orphans by walking the coinbase transaction's
            # `category`. Daemons report category='orphan' when the
            # block is no longer on the canonical chain.
            try:
                tx_id = info.get("tx", [None])[0]
                if tx_id:
                    tx_info = rpc.call("gettransaction", tx_id)
                    details = tx_info.get("details") or []
                    if details and details[0].get("category") == "orphan":
                        if db.set_block_confirmations(self.slot, block_id, -1):
                            log.warning(
                                "[%s/%s] block %d (height %s) marked ORPHAN",
                                self.name, slot_label, block_id, row.get("height"),
                            )
                        continue
            except (Transient, Exception) as exc:
                log.warning("[%s/%s] block %d: gettransaction failed: %s",
                            self.name, slot_label, block_id, exc)

            if new_confs == old_confs:
                continue
            if not db.set_block_confirmations(self.slot, block_id, new_confs):
                log.error("[%s/%s] block %d: failed to update confirmations",
                          self.name, slot_label, block_id)
                continue
            log.info("[%s/%s] block %d height=%s confirmations %d -> %d",
                     self.name, slot_label, block_id, row.get("height"),
                     old_confs, new_confs)
