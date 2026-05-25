"""Port of `cronjobs/pplns_payout.php` (parent chain).

For each unaccounted block:

1. Get the round share window — `(last_accounted.share_id, current.share_id]`.
2. Group shares in that window by account.
3. Distribute the block reward proportionally to valid shares per account.
4. Apply the configured fee % (deducted as a separate `Fee` transaction).
5. Apply the per-account donation % (separate `Donation` transaction).
6. Archive + delete the shares in the round window.
7. Mark the block accounted, persist `last_accounted_block_id`.

Differences vs the PHP version:

- The "potential double payout" path (PHP E0015) is treated as a Skip
  here, not a Fatal. The triggering condition fires whenever blocks are
  iterated by id but compared by height — common when `findblock` walked
  `listsinceblock` whose order doesn't match height order. PHP aborted
  the whole cron at that point, blocking every later block from being
  credited.
- Failure to archive shares (PHP E0016) is still Fatal — losing share
  rows we already credited is data corruption.
- Mail notification on credit is omitted; logging is enough for
  operators and avoids the sendmail-recipient-misconfig tar-pit that
  silently kills the PHP cron.

Wave 1 hardening (idempotency + transactional atomicity):

- Each block's accounting is done inside a single `db.transaction()` —
  the guard-row insert, every Credit/Fee row, the archive INSERT/DELETE,
  and the `accounted = 1` UPDATE all commit together or roll back
  together. If any step fails, the block stays unaccounted on disk
  for the next tick to retry from a clean state.
- Before crediting, we acquire a `SELECT ... FOR UPDATE` row lock on
  the block. Two concurrent ticks of pplns_payout for the same slot
  serialise on this lock instead of double-crediting.
- Every accounting row INSERT writes a matching guard row in
  `cronjobs_py_accounting` first. The UNIQUE on
  (slot, block_id, account_id, tx_type) means a retry from partial
  state can detect "already credited" via IntegrityError instead of
  duplicating the work.
- Fatal escapes the transaction (it raises after rollback) and the
  scheduler then writes a slot-wide entry to `cronjobs_py_disabled`
  so no further coin-moving jobs in this slot tick until an operator
  clears it.
"""

from __future__ import annotations

from dataclasses import dataclass

from ..errors import Fatal, Skip
from ..logger import get
from ..scheduler import JobContext

log = get(__name__)


@dataclass
class PplnsPayout:
    name: str = "pplns_payout"
    interval_seconds: int = 90
    slot: str = ""
    # Wave 1: writes Credit / Fee / Donation rows into transactions_<slot>.
    # A Fatal here means we may be in a partial-state ledger; freeze
    # every coin-moving job in the slot until operator reconciles.
    coin_moving: bool = True

    def run(self, ctx: JobContext) -> None:
        cfg = ctx.settings
        # Only PPLNS payout system supported by this job.
        payout_sys = cfg.raw.get(
            "payout_system" if self.slot == "" else f"payout_system_{self.slot}",
            "pplns",
        )
        if payout_sys != "pplns":
            log.info("[%s/%s] payout system is %r, not pplns; skipping",
                     self.name, self.slot or "parent", payout_sys)
            return

        db = ctx.db
        unaccounted = db.get_unaccounted_blocks(self.slot)
        if not unaccounted:
            log.debug("[%s/%s] no unaccounted blocks", self.name, self.slot or "parent")
            return
        shadow = bool(ctx.settings.shadow_mode)

        # Each slot keeps its own `last_accounted_block_id_<slot>` pointer so
        # the parent and aux ledgers don't interfere with each other.
        setting_key = (
            "last_accounted_block_id" if self.slot == ""
            else f"last_accounted_block_id_{self.slot}"
        )
        last_block_id = int(db.get_setting(setting_key) or 0)
        last_block = (
            db.get_block_by_id(self.slot, last_block_id) if last_block_id else None
        )
        # Track last-accounted by SHARE_ID (not height): pplns iterates
        # blocks share-id-ascending and the credit window is
        # `(prev_share_id, this.share_id]`. Height ordering can be
        # non-monotonic when findblock inserts in confirmation order.
        last_share_id = int(last_block["share_id"]) if last_block and last_block.get("share_id") else 0

        # PPLNS configuration. Live MPOS deploys typically use `blockavg`
        # so target adapts to round size. `default` mode falls back to
        # the fixed `pplns.shares.default`. `dynamic` blends the two.
        pplns_cfg = cfg.raw.get("pplns", {}) or {}
        target_type = str(pplns_cfg.get("shares", {}).get("type", "default"))
        pplns_default = int(pplns_cfg.get("shares", {}).get("default", 100))
        blockavg_count = int(pplns_cfg.get("blockavg", {}).get("blockcount", 3))
        dynamic_pct = float(pplns_cfg.get("dynamic", {}).get("percent", 10))
        fee_pct = float(cfg.raw.get("fees", 0))
        # Wave 2: PHP supports `reward_type='block'` (use block.amount —
        # the chain-side coinbase value, MPOS default for chains with
        # variable rewards) and `reward_type='fixed'` (use config.reward
        # — operator-controlled flat reward, useful for solo and
        # P2Pool-style schemes). Default 'block' matches MPOS dist.
        reward_type = str(cfg.raw.get("reward_type", "block"))
        fixed_reward = float(cfg.raw.get("reward", 0.0))
        # `config.difficulty` controls MPOS's diff-normalisation divisor.
        # BlakeStream 15.21/25.2 sets this to 21 (`diff_32`), so keep the
        # fallback aligned with global.inc.dist.php if the private override
        # is incomplete.
        difficulty_const = int(cfg.raw.get("difficulty", 21))

        log.info(
            "[%s/%s] %d unaccounted, last_share_id=%d, target_mode=%s "
            "(default=%d, blockavg=%d, dynamic_pct=%.1f%%), "
            "reward_type=%s, fee=%.2f%%, difficulty_const=%d",
            self.name, self.slot or "parent",
            len(unaccounted), last_share_id, target_type,
            pplns_default, blockavg_count, dynamic_pct,
            reward_type, fee_pct, difficulty_const,
        )

        for block in unaccounted:
            block_share_id = int(block.get("share_id") or 0)
            try:
                self._process_block(
                    ctx, block,
                    prev_share_id=last_share_id,
                    target_type=target_type,
                    pplns_default=pplns_default,
                    blockavg_count=blockavg_count,
                    dynamic_pct=dynamic_pct,
                    fee_pct=fee_pct,
                    reward_type=reward_type,
                    fixed_reward=fixed_reward,
                    difficulty_const=difficulty_const,
                )
                last_share_id = block_share_id
                last_block_id = int(block["id"])
                if not shadow:
                    db.set_setting(setting_key, str(last_block_id))
            except Skip as exc:
                log.warning("[%s/%s] block %s: %s",
                            self.name, self.slot or "parent",
                            block.get("id"), exc)
                # Live mode marks skipped blocks accounted so the slot can
                # keep moving. Shadow mode must leave that decision to the
                # authoritative PHP cron during the soak window.
                if not shadow:
                    db.set_block_accounted(self.slot, int(block["id"]))
                continue

    # ------------------------------------------------------------------

    def _compute_target(self, db, *, target_type: str, pplns_default: int,
                        height: int, blockavg_count: int,
                        dynamic_pct: float, block_shares: int) -> int:
        """Mirror PHP `pplns_payout.php:54-62`.

        - default: fixed `pplns.shares.default`.
        - blockavg: AVG(shares) over the last N blocks at or below height.
        - dynamic: blockavg * (100-pct)/100 + current_block.shares * pct/100.

        Falls back to `pplns_default` when blockavg returns 0 (no prior
        blocks yet — first round of the pool's life).
        """
        if target_type == "blockavg":
            avg = db.get_avg_block_shares(self.slot, height, blockavg_count)
            return max(int(round(avg)), 1) if avg > 0 else pplns_default
        if target_type == "dynamic":
            avg = db.get_avg_block_shares(self.slot, height, blockavg_count)
            if avg <= 0:
                return pplns_default
            blended = avg * (100.0 - dynamic_pct) / 100.0 \
                + block_shares * dynamic_pct / 100.0
            return max(int(round(blended)), 1)
        return pplns_default

    def _process_block(self, ctx: JobContext, block: dict, *,
                       prev_share_id: int, target_type: str,
                       pplns_default: int, blockavg_count: int,
                       dynamic_pct: float, fee_pct: float,
                       reward_type: str, fixed_reward: float,
                       difficulty_const: int) -> None:
        db = ctx.db
        block_id = int(block["id"])
        height = int(block["height"])
        share_id = block.get("share_id")
        if share_id is None:
            raise Skip(f"E0062: block {block_id} (height {height}) has no share_id")

        share_id = int(share_id)
        block_amount = float(block.get("amount") or 0)
        shadow = bool(ctx.settings.shadow_mode)
        guard_mode = "shadow" if shadow else "live"
        # Wave 2: respect MPOS's `reward_type` config.
        if reward_type == "block":
            reward = block_amount
        else:
            reward = fixed_reward

        if reward <= 0:
            raise Skip(
                f"block {block_id} has reward {reward} "
                f"(type={reward_type}, block.amount={block_amount}, "
                f"config.reward={fixed_reward}); skipping"
            )

        # We iterate by share_id, so by construction share_id > prev_share_id
        # unless duplicate share_id hits — that's the only out-of-order case
        # left and it means our findblock matched the same share to multiple
        # blocks. Skip the duplicates so we don't double-credit a single
        # round window.
        if share_id <= prev_share_id:
            raise Skip(
                f"block {block_id} share_id {share_id} <= prev {prev_share_id} "
                f"(duplicate findblock match); marking accounted"
            )

        # Wave 1 fast-path: in live mode only live guards represent real
        # credits. Shadow-only guards are cutover predictions and can be
        # promoted by insert_accounting_guard() below. In shadow mode, any
        # guard is enough to suppress a duplicate prediction.
        guard_filter = None if shadow else "live"
        if db.is_block_already_credited(self.slot, block_id, mode=guard_filter):
            log.info(
                "[%s/%s] block %d: cronjobs_py_accounting already has rows; "
                "skipping (live retry or duplicate shadow prediction)",
                self.name, self.slot or "parent", block_id,
            )
            # Live mode: also flip accounted=1 so we don't see the block
            # again. Shadow mode: leave accounted alone so PHP cron sees
            # the block as still pending and credits it (PHP is the
            # authoritative writer during the soak window).
            if not bool(ctx.settings.shadow_mode):
                db.set_block_accounted(self.slot, block_id)
            raise Skip(
                f"block {block_id} already credited (guard row exists)"
            )

        # 1. Pick the PPLNS target per the configured mode.
        target = self._compute_target(
            db,
            target_type=target_type,
            pplns_default=pplns_default,
            height=height,
            blockavg_count=blockavg_count,
            dynamic_pct=dynamic_pct,
            block_shares=int(block.get("shares") or 0),
        )

        # 2. Diff-normalized per-account share split. Wave 2 fix: PHP's
        # PPLNS proportions miners by diff-weighted share count, not raw
        # row count. A vardiff miner submitting one share at diff=1024
        # contributes 1024× more credit than a fixed-diff miner at diff=1.
        # The Wave 1 implementation used row counts which mis-distributed
        # whenever miners had different difficulties.
        round_breakdown = db.round_share_breakdown_diff(
            prev_share_id, share_id,
            difficulty_const=difficulty_const,
        )
        round_valid = sum(r["valid"] for r in round_breakdown)
        if round_valid == 0:
            raise Skip(
                f"block {block_id}: no valid (diff-normalized) shares in window "
                f"({prev_share_id}, {share_id}] — likely already archived"
            )

        # 3a. PPLNS round-narrowing (PHP `getMinimumShareId` parity).
        # When the round has MORE diff-normalized valid shares than the
        # target, PHP narrows the credit window to the most-recent N
        # shares whose diff sum equals `target`. Older shares in the
        # window aren't credited — they belong to a prior round.
        archive_extra = 0.0
        if round_valid >= target and target > 0:
            min_share_id = db.get_minimum_share_id(
                target=target, current_upstream=share_id,
                difficulty_const=difficulty_const,
            )
            if min_share_id > 0:
                # `id >` semantics in round_share_breakdown_diff so the
                # window is `(min_share_id - 1, share_id]`.
                round_breakdown = db.round_share_breakdown_diff(
                    min_share_id - 1, share_id,
                    difficulty_const=difficulty_const,
                )
                round_valid = sum(r["valid"] for r in round_breakdown)
                log.info(
                    "[%s/%s] block %d: target met; narrowed window "
                    "(%d, %d], round_valid=%.4f",
                    self.name, self.slot or "parent",
                    block_id, min_share_id - 1, share_id, round_valid,
                )

        per_account: dict[int, dict] = {}
        for r in round_breakdown:
            account_id = r.get("account_id")
            if not account_id:
                continue
            per_account[int(account_id)] = {
                "username": r["username"],
                "valid": float(r["valid"]),
                "invalid": float(r["invalid"]),
            }

        # 3b. Archive fill-up (PHP `getArchiveShares`/`Share::getMinArchiveShareId`):
        # if the current round has fewer diff-valid shares than the target,
        # fold in the most recent archived shares whose diff sum makes up
        # the difference. Diff-normalized so a vardiff archived share is
        # weighted correctly.
        if round_valid < target and target > 0:
            need = target - round_valid
            archive_breakdown = db.archive_share_breakdown_diff(
                target_extra=need, exclude_above_id=share_id,
                difficulty_const=difficulty_const,
            )
            for r in archive_breakdown:
                account_id = r.get("account_id")
                if not account_id:
                    continue
                if int(account_id) in per_account:
                    per_account[int(account_id)]["valid"] += r["valid"]
                    per_account[int(account_id)]["invalid"] += r["invalid"]
                else:
                    per_account[int(account_id)] = {
                        "username": r["username"],
                        "valid": float(r["valid"]),
                        "invalid": float(r["invalid"]),
                    }
                archive_extra += r["valid"]

        # 4. Divisor. PHP semantics:
        #  - Round >= target → divisor = target (we narrowed the window
        #    to that exact diff-sum already, so combined_valid ≈ target)
        #  - Round < target & archive filled → divisor = round + archive
        #  - Round < target & archive empty → divisor = combined_valid
        # Using the configured `target` here when round was below the
        # target and archive ran dry would over-pay (combined is the
        # actual contribution).
        combined_valid = sum(r["valid"] for r in per_account.values())
        divisor = max(combined_valid, 1e-12)

        log.info(
            "[%s/%s] block %d height %d reward %.8f window (%d, %d] "
            "round_valid=%.4f archive_extra=%.4f target=%d divisor=%.4f",
            self.name, self.slot or "parent",
            block_id, height, reward, prev_share_id, share_id,
            round_valid, archive_extra, target, divisor,
        )

        # ----------------------------------------------------------------
        # Wave 1: everything below this point is one atomic DB transaction.
        # The order is:
        #   a. SELECT FOR UPDATE on the block row (serialise concurrent
        #      pplns ticks on the same block).
        #   b. For each account, insert one cronjobs_py_accounting guard
        #      row per (Credit, Fee). UNIQUE catches duplicate work from
        #      a previous partial run; we abort the whole transaction in
        #      that case.
        #   c. INSERT into transactions_<slot> for each accounting row;
        #      record the new txn_id back on the guard row.
        #   d. archive_and_delete_shares (parent slot only).
        #   e. UPDATE block accounted = 1.
        # On commit success, the block is fully accounted. On any
        # exception, rollback discards every change so the next tick
        # retries from a clean state.
        #
        # Wave 5 shadow mode: when ctx.settings.shadow_mode is True,
        # only step (a) and step (b) execute; the rest is skipped (PHP
        # cron is the authoritative writer during the soak window).
        # The guard rows are tagged mode='shadow' so the drift-check
        # CLI can compare them to PHP's authoritative writes.
        # ----------------------------------------------------------------
        try:
            with db.transaction() as cur:
                # a. Lock the block row for the duration of this txn.
                locked = db.lock_block_for_update(self.slot, block_id, cur)
                if not locked:
                    # Block disappeared between get_unaccounted_blocks() and
                    # the FOR UPDATE — vanishingly rare, but treat as Skip.
                    raise Skip(f"block {block_id} not found at lock time")
                # In shadow mode `accounted=1` means PHP cron has already
                # credited this block; that's our cue that we can compare
                # predictions to authoritative writes via drift-check.
                # We still need to write the guard rows so drift-check
                # has something to compare against, so don't bail here
                # — keep going.
                if int(locked.get("accounted") or 0) == 1 and not shadow:
                    # In live mode this means a racing tick beat us.
                    raise Skip(
                        f"block {block_id} already accounted "
                        f"(racing pplns tick won the FOR UPDATE)"
                    )

                # b + c. Distribute proportional to combined diff-valid
                # shares. Per-account `no_fees` and `donate_percent` are
                # honoured per PHP `pplns_payout.php:200-232`:
                #   - Skip fees if `accounts.no_fees = 1`.
                #   - Donation = donate_percent / 100 * (payout - fee).
                # The Donation row is a debit on the user's account
                # (just like Fee). PHP credits it to a separate
                # operator-controlled donation address out-of-band; we
                # mirror PHP's accounting (debit-only, no recipient
                # row) — the operator-side receipt for donations is
                # handled outside the cronjobs path.
                for account_id, row in per_account.items():
                    if row["valid"] <= 0:
                        continue
                    pct = (row["valid"] / divisor) * 100.0
                    payout = round((pct / 100.0) * reward, 8)

                    meta = db.get_account_fee_meta(account_id)
                    if fee_pct > 0 and not meta["no_fees"]:
                        fee = round(fee_pct / 100.0 * payout, 8)
                    else:
                        fee = 0.0
                    donate_pct = meta["donate_percent"]
                    if donate_pct > 0:
                        donation = round(
                            donate_pct / 100.0 * (payout - fee), 8,
                        )
                    else:
                        donation = 0.0

                    log.info(
                        "  %-20s valid=%-8.4f pct=%6.3f%% "
                        "payout=%-12.8f fee=%-12.8f donation=%-12.8f "
                        "no_fees=%s donate=%.2f%%",
                        row["username"], row["valid"], pct,
                        payout, fee, donation,
                        meta["no_fees"], donate_pct,
                    )

                    # Credit guard + insert
                    if not db.insert_accounting_guard(
                        slot=self.slot, block_id=block_id,
                        account_id=account_id, tx_type="Credit",
                        amount=payout, txn_id=None, cur=cur,
                        mode=guard_mode,
                    ):
                        raise Fatal(
                            f"E0064: cronjobs_py_accounting Credit guard "
                            f"already exists for slot={self.slot} "
                            f"block={block_id} account={account_id}; "
                            f"refusing to double-credit. "
                            f"Investigate prior partial run."
                        )
                    if not shadow:
                        txn_id = db.add_transaction_in_tx(
                            cur=cur,
                            account_id=account_id,
                            amount=payout,
                            kind="Credit",
                            block_id=block_id,
                            slot=self.slot,
                        )
                        cur.execute(
                            "UPDATE cronjobs_py_accounting "
                            "SET txn_id = %s "
                            "WHERE slot = %s AND block_id = %s "
                            "  AND account_id = %s AND tx_type = %s",
                            (txn_id, self.slot, block_id, account_id, "Credit"),
                        )

                    if fee > 0:
                        if not db.insert_accounting_guard(
                            slot=self.slot, block_id=block_id,
                            account_id=account_id, tx_type="Fee",
                            amount=fee, txn_id=None, cur=cur,
                            mode=guard_mode,
                        ):
                            raise Fatal(
                                f"E0064: cronjobs_py_accounting Fee guard "
                                f"already exists for slot={self.slot} "
                                f"block={block_id} account={account_id}; "
                                f"refusing to double-charge. "
                                f"Investigate prior partial run."
                            )
                        if not shadow:
                            fee_id = db.add_transaction_in_tx(
                                cur=cur,
                                account_id=account_id,
                                amount=fee,
                                kind="Fee",
                                block_id=block_id,
                                slot=self.slot,
                            )
                            cur.execute(
                                "UPDATE cronjobs_py_accounting "
                                "SET txn_id = %s "
                                "WHERE slot = %s AND block_id = %s "
                                "  AND account_id = %s AND tx_type = %s",
                                (fee_id, self.slot, block_id, account_id, "Fee"),
                            )

                    if donation > 0:
                        if not db.insert_accounting_guard(
                            slot=self.slot, block_id=block_id,
                            account_id=account_id, tx_type="Donation",
                            amount=donation, txn_id=None, cur=cur,
                            mode=guard_mode,
                        ):
                            raise Fatal(
                                f"E0064: cronjobs_py_accounting Donation "
                                f"guard already exists for slot={self.slot} "
                                f"block={block_id} account={account_id}; "
                                f"refusing to double-charge."
                            )
                        if not shadow:
                            donation_id = db.add_transaction_in_tx(
                                cur=cur,
                                account_id=account_id,
                                amount=donation,
                                kind="Donation",
                                block_id=block_id,
                                slot=self.slot,
                            )
                            cur.execute(
                                "UPDATE cronjobs_py_accounting "
                                "SET txn_id = %s "
                                "WHERE slot = %s AND block_id = %s "
                                "  AND account_id = %s AND tx_type = %s",
                                (donation_id, self.slot, block_id,
                                 account_id, "Donation"),
                            )

                # c2. Persist the per-account PPLNS breakdown for the
                # round page. Diff-normalized (`valid`/`invalid` already
                # came from round_share_breakdown_diff), one row per
                # account, slot-aware so aux coins get their own
                # breakdown. Idempotent via UNIQUE (slot, block_id,
                # account_id) — a partial-rerun safely overwrites.
                # Skipped in shadow mode: PHP cron is the authoritative
                # writer there and would race us into the same rows.
                if not shadow:
                    pplns_written = db.insert_pplns_shares_in_tx(
                        cur=cur, slot=self.slot, block_id=block_id,
                        per_account=per_account,
                    )
                    if pplns_written:
                        log.debug(
                            "[%s/%s] block %d: pplns_shares wrote %d rows",
                            self.name, self.slot or "parent",
                            block_id, pplns_written,
                        )

                # d. Archive + delete shares we just credited (parent only).
                # Wave 5: skipped in shadow mode — PHP cron archives the
                # same shares as part of its own pplns_payout step.
                if not shadow:
                    archived, deleted = db.archive_and_delete_shares_in_tx(
                        cur=cur,
                        prev_share_id=prev_share_id,
                        current_share_id=share_id,
                        block_id=block_id,
                        slot=self.slot,
                    )
                    if archived or deleted:
                        log.info(
                            "[%s/%s] block %d: archived %d, deleted %d shares",
                            self.name, self.slot or "parent",
                            block_id, archived, deleted,
                        )

                # e. Mark accounted last — if anything above failed we
                # roll back to accounted=0.
                # Wave 5: in shadow mode we leave `accounted = 0` so PHP
                # cron sees the block as still pending and processes it.
                # The guard rows alone are enough to prevent cronjobs-py
                # from double-predicting on retry.
                if not shadow:
                    if not db.set_block_accounted_in_tx(
                        cur=cur, slot=self.slot, block_id=block_id,
                    ):
                        raise Fatal(
                            f"E0014: failed to set accounted=1 for block {block_id}"
                        )
        except Skip:
            # Skip propagates out cleanly; no Fatal-promotion.
            raise
        except Fatal:
            # Already a Fatal — bubble up to the scheduler so it sets
            # the slot-wide poison flag.
            raise
        except Exception as exc:
            # Any other exception inside the transaction means we
            # rolled back. Promote to Fatal so the operator sees the
            # poison flag and investigates.
            raise Fatal(
                f"E0016: pplns transaction for block {block_id} "
                f"failed mid-flight, rolled back: {exc}"
            ) from exc
