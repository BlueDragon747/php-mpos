"""Port of `cronjobs/findblock.php` (parent chain).

Behaviour parity with the PHP version, with these differences:

- RPC failures retry transparently (3 attempts with backoff) before they
  become a job-level error. `findblock.php` patched to logWarn+continue
  on E0010, but didn't actually retry.
- `getblock` calls for unaccounted blocks are batched into one HTTP
  round-trip when there's more than one — the PHP version issues N
  sequential calls.
- E0001/E0005/E0062 stay warn-and-skip (matching the PHP patches).
- E0002/E0003/E0004 stay fatal (genuine data-integrity failures).
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from ..errors import Fatal, Skip
from ..logger import get
from ..scheduler import JobContext

log = get(__name__)

OUT_OF_ORDER_TOLERANCE = 100  # shares — matches PHP findblock.php line 134
MAX_REORDER_ATTEMPTS = 10     # matches PHP findblock.php line 100


@dataclass
class FindBlock:
    name: str = "findblock"
    interval_seconds: int = 60
    slot: str = ""  # "" = parent chain; future: support mm/mm1/...
    # Wave 1: findblock writes share_id / account_id onto block rows,
    # which is the upstream signal pplns_payout uses to credit accounts.
    # A Fatal here means we may have a malformed or duplicate share→block
    # match — freeze the slot's coin-moving group until operator reviews.
    coin_moving: bool = True

    def run(self, ctx: JobContext) -> None:
        rpc = ctx.rpc(self.slot)
        db = ctx.db
        cfg = ctx.settings

        # 1. Find new generated transactions since the last block we know about.
        last_block = db.get_last_block(self.slot)
        last_hash = last_block["blockhash"] if last_block and last_block.get("blockhash") else ""
        log.info("[findblock] last hash=%s", last_hash or "(none)")

        try:
            tx_resp = rpc.listsinceblock(last_hash)
        except Exception as exc:
            log.warning(
                "listsinceblock failed (likely transient daemon hiccup), "
                "will retry on next tick: %s",
                exc,
            )
            return

        new_blocks = [
            tx for tx in tx_resp.get("transactions", [])
            if tx.get("category") in ("generate", "immature")
        ]

        # 2. Insert any new blocks as unaccounted (share_id IS NULL).
        if new_blocks:
            self._insert_new_blocks(rpc, db, cfg, new_blocks)
        else:
            log.debug("no new generate/immature transactions since last block")

        # 3. For each unaccounted block (height ASC for chronological
        #    matching), find its upstream pool share and credit the finder.
        unset = db.get_blocks_without_share_id(self.slot)
        unset.sort(key=lambda b: int(b.get("height") or 0))
        running_prev = db.get_last_share_id(self.slot)
        for block in unset:
            try:
                running_prev = self._account_block(
                    rpc, db, cfg, block, running_prev
                )
            except Skip as exc:
                log.warning("block %s: %s", block.get("height"), exc)
                continue

    # ------------------------------------------------------------------

    def _insert_new_blocks(self, rpc, db, cfg, new_blocks) -> None:
        # Batch all the getblock calls in one round-trip.
        block_calls = [("getblock", [tx["blockhash"]]) for tx in new_blocks]
        try:
            block_infos = rpc.batch(block_calls)
        except Fatal:
            # Fall back to per-call so a single bad blockhash doesn't poison
            # the whole batch.
            block_infos = []
            for tx in new_blocks:
                try:
                    block_infos.append(rpc.getblock(tx["blockhash"]))
                except Exception as exc:
                    log.warning("getblock %s failed: %s", tx["blockhash"], exc)
                    block_infos.append(None)

        for tx, info in zip(new_blocks, block_infos):
            if info is None:
                continue
            # Skip PoS blocks — Blakecoin is PoW-only but we mirror PHP's
            # check for safety.
            flags = info.get("flags") or ""
            if "proof-of-stake" in flags:
                log.info(
                    "block height %s is PoS, skipping insert", info.get("height")
                )
                continue
            amount = float(tx["amount"]) if cfg.reward_type == "block" else cfg.reward
            ok = db.add_block(
                self.slot,
                blockhash=tx["blockhash"],
                height=int(info["height"]),
                amount=amount,
                confirmations=int(tx.get("confirmations", 0)),
                difficulty=float(info.get("difficulty", 0)),
                time_=int(tx.get("time", 0)),
            )
            if not ok:
                log.error(
                    "failed to insert block height=%s hash=%s",
                    info.get("height"),
                    tx["blockhash"],
                )
            else:
                log.info(
                    "inserted block height=%s hash=%s amount=%s diff=%s ts=%s",
                    info["height"],
                    tx["blockhash"][:15] + "...",
                    amount,
                    info.get("difficulty"),
                    datetime.fromtimestamp(int(tx.get("time", 0))).isoformat(timespec="seconds"),
                )

    def _account_block(self, rpc, db, cfg, block, prev_share_id: int) -> int:
        """Assign share_id to one block. Returns the share_id assigned so the
        caller can advance the running prev_share_id pointer."""
        block_id = int(block["id"])
        height = int(block["height"])
        info = rpc.getblock(block["blockhash"])
        # Use block.time from the daemon (authoritative) over the row's time
        # column, which gets stamped at insert and may drift.
        block_time = int(info.get("time") or block.get("time") or 0)
        # Only the parent slot (BLC) requires upstream_result='Y' (the
        # share also had to win the parent chain). Aux slots match any
        # valid pool share, since the merge-mined aux solve is carried
        # alongside the share's normal PoW work.
        require_upstream = (self.slot == "")
        share = db.find_upstream_share(
            blockhash=block["blockhash"],
            prev_share_id=prev_share_id,
            block_time=block_time,
            require_upstream=require_upstream,
        )

        if share is None:
            # Upstream-share lookup failed: non-pool / solo-mined block, or
            # the share row hasn't been written yet. Originally MPOS aborted
            # the cron here (E0005); we already patched the PHP version to
            # warn-and-skip and we keep that here.
            raise Skip(
                f"E0005: no matching upstream share for block {height} "
                f"(likely non-pool/solo-mined); leaving share_id=NULL"
            )

        current_share_id = int(share["id"])

        # If the matched share isn't strictly later than the previous block's
        # share, search for a later valid candidate.
        if current_share_id <= prev_share_id:
            log.debug(
                "block %s: matched share %s is <= prev %s, searching alt",
                height, current_share_id, prev_share_id,
            )
            tried = [current_share_id]
            found_alt = False
            for attempt in range(MAX_REORDER_ATTEMPTS):
                # Pass block_time on the retry too — without it
                # find_upstream_share short-circuits to None and the
                # alternative-share search can never succeed.
                alt = db.find_upstream_share(
                    blockhash=block["blockhash"],
                    prev_share_id=prev_share_id,
                    block_time=block_time,
                    exclude_ids=tried,
                    require_upstream=require_upstream,
                )
                if alt is None:
                    break
                alt_id = int(alt["id"])
                if alt_id > prev_share_id:
                    current_share_id = alt_id
                    share = alt
                    found_alt = True
                    log.debug(
                        "found valid alt share %s on attempt %d",
                        current_share_id, attempt + 1,
                    )
                    break
                tried.append(alt_id)
            if not found_alt:
                raise Skip(
                    f"E0063: no valid share found for block {height} "
                    f"(all candidates <= prev_share_id={prev_share_id}); "
                    f"will retry next tick"
                )

        # Out-of-order detection — only fatal beyond the tolerance window.
        if (
            current_share_id < prev_share_id
            and (prev_share_id - current_share_id) > OUT_OF_ORDER_TOLERANCE
        ):
            raise Fatal(
                f"E0001: block {height} matched share {current_share_id} "
                f"which is {prev_share_id - current_share_id} earlier than "
                f"the previous block's share {prev_share_id}"
            )

        # Wave 2: diff-normalized round share count for `block.shares`.
        # PHP `Share::getRoundShares` returns the diff-weighted total
        # so the value displayed on the block page (and consumed by
        # pplns_payout's blockavg target compute) reflects difficulty.
        difficulty_const = int(cfg.raw.get("difficulty", 21))
        round_shares = int(round(db.get_round_shares_diff(
            prev_share_id, current_share_id,
            difficulty_const=difficulty_const,
        )))
        finder_username = share.get("username", "")
        account_id = db.get_user_id(finder_username) if finder_username else None
        worker = finder_username.split(".", 1)[1] if "." in finder_username else None

        log.info(
            "block_id=%s height=%s amount=%s share_id=%s shares=%s finder=%s worker=%s",
            block_id, height, block.get("amount"), current_share_id,
            round_shares, finder_username, worker,
        )

        shadow = bool(cfg.shadow_mode)
        if shadow:
            log.debug(
                "shadow_mode=1; not mutating block %s share/finder fields",
                height,
            )
        else:
            if not db.set_block_share_id(self.slot, block_id, current_share_id):
                log.error("failed to set share_id for block %s", height)
            if account_id is not None:
                if not db.set_block_finder(self.slot, block_id, account_id):
                    log.error("failed to set finder for block %s", height)
            if worker is not None:
                if not db.set_block_finding_worker(self.slot, block_id, worker):
                    log.error("failed to set finding worker for block %s", height)
            if not db.set_block_shares(self.slot, block_id, round_shares):
                log.error("failed to set round shares for block %s", height)

        # Wave 2: per-block bonus to the finder. PHP `findblock.php:191`
        # writes a `Bonus` transaction for the finder's account when
        # `config.block_bonus > 0`. Wave 1 left this on Settings but
        # never wrote it. The Bonus row is gated by the same
        # confirmation logic as Credit/Bonus in the canonical balance
        # SQL, so an orphaned block automatically drops the Bonus
        # from the finder's confirmed balance — no reversal needed.
        # Idempotency is enforced by the cronjobs_py_accounting guard
        # table just like pplns_payout — if findblock retries on the
        # same block, the UNIQUE catches the duplicate Bonus row.
        #
        # Wave 5 shadow mode: write the guard (with mode='shadow') but
        # SKIP the transactions_<slot> Bonus row insert; PHP cron's
        # findblock writes the authoritative Bonus row.
        block_bonus = float(cfg.raw.get("block_bonus", 0.0) or 0.0)
        if block_bonus > 0 and account_id is not None:
            guard_mode = "shadow" if shadow else "live"
            try:
                with db.transaction() as cur:
                    if db.insert_accounting_guard(
                        slot=self.slot, block_id=block_id,
                        account_id=int(account_id), tx_type="Bonus",
                        amount=block_bonus, txn_id=None, cur=cur,
                        mode=guard_mode,
                    ):
                        if not shadow:
                            bonus_id = db.add_transaction_in_tx(
                                cur=cur,
                                account_id=int(account_id),
                                amount=block_bonus,
                                kind="Bonus",
                                block_id=block_id,
                                slot=self.slot,
                            )
                            cur.execute(
                                "UPDATE cronjobs_py_accounting "
                                "SET txn_id = %s "
                                "WHERE slot = %s AND block_id = %s "
                                "  AND account_id = %s AND tx_type = %s",
                                (bonus_id, self.slot, block_id,
                                 int(account_id), "Bonus"),
                            )
                        log.info(
                            "block %s: %s Bonus %.8f for finder "
                            "account %s (%s)",
                            height,
                            "shadow-predicted" if shadow else "awarded",
                            block_bonus, account_id, finder_username,
                        )
                    else:
                        log.debug(
                            "block %s: Bonus already credited to finder "
                            "(guard row exists); skipping",
                            height,
                        )
            except Exception as exc:
                # A failed Bonus shouldn't poison the slot — it's
                # an additive credit, not a correctness-critical one.
                # Log and continue; operator can backfill from the
                # log if needed.
                log.error(
                    "block %s: failed to record Bonus for finder %s: %s",
                    height, finder_username, exc,
                )

        return current_share_id
