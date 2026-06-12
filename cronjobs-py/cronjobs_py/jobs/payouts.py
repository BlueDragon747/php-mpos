"""Port of `cronjobs/payouts.php` (parent chain).

Find users whose pending balance is at or above their `ap_threshold`,
issue an on-chain `sendtoaddress`, and record the matching `Debit_AP`
transaction. One round-trip per eligible user — daemon's transaction
batching is fine at our scale.

Wave 1 hardening (idempotency on retry):

The PHP version (and the pre-Wave-1 cronjobs-py) treated `sendtoaddress`
as if it were idempotent — on a connection error or timeout, the cron
would log a warning and skip the user, then on the next tick re-enter
the loop and issue `sendtoaddress` AGAIN against the same balance. If
the first send had actually been broadcast, the user would be paid
twice and the pool's wallet would silently drain.

Wave 1 closes that hole with a pre-broadcast outbox state machine:

  1. INSERT a row into `transactions_outbox` with status='pending' and
     a unique `wallet_comment` of the form
     `mpos:{slot}:{account_id}:{outbox_id}:{nonce_hex8}`.
  2. Pass that wallet_comment into `sendtoaddress` as the bitcoin-core
     `comment` parameter — wallet-local, never goes on chain, but is
     queryable via `listtransactions` / `gettransaction`.
  3. The RPC call is routed through `RpcClient.call_nonidempotent`,
     which raises `Indeterminate` on any timeout / connection error
     / 5xx / non-JSON response (i.e. any case where we don't have a
     clear "yes the daemon broadcast" or "no the daemon refused"
     answer).
  4. On clean broadcast: outbox row goes status='broadcast', txid
     recorded, matching Debit_AP transaction inserted in the SAME
     DB transaction.
  5. On `Indeterminate`: outbox row goes status='indeterminate', the
     job raises Fatal so the scheduler sets the slot-wide poison flag.
     A reconciliation pass (Wave 2) queries the wallet for transactions
     matching `wallet_comment` to figure out which outcome actually
     happened, and either advances the row to 'reconciled' (with the
     real txid) or 'abandoned' (no broadcast happened).
  6. On `Fatal` from the daemon (auth error, malformed address, etc.):
     outbox row goes status='abandoned'; user balance unchanged.

Other Wave 1 differences vs the pre-Wave-1 version:

- We never send if the daemon's spendable balance is below the total
  payout amount. PHP did this check too but `getbalance` failures fell
  through to `0`, which silently disabled all payouts.
"""

from __future__ import annotations

import secrets
from dataclasses import dataclass

from ..errors import Fatal, Indeterminate, Skip
from ..logger import get
from ..scheduler import JobContext
from ..settings import slot_int

log = get(__name__)


def _make_wallet_comment(*, slot: str, account_id: int) -> str:
    """Build the idempotency anchor that goes both into the outbox row
    and the wallet's `sendtoaddress` comment param.

    Format: `mpos:{slot}:{account_id}:{nonce_hex16}`. The nonce alone
    makes it unique (enforced by the outbox `wallet_comment` UNIQUE
    column), so the value does NOT embed the outbox id — that lets the
    row be inserted with its final anchor atomically, with no
    placeholder-then-update window. bitcoind's `comment` field accepts
    arbitrary text; we keep it short to fit the VARCHAR(64) column. The
    slot can be empty (parent chain).
    """
    nonce = secrets.token_hex(8)  # 16 hex chars
    return f"mpos:{slot}:{account_id}:{nonce}"


def _wallet_max_weight_error(exc: Exception) -> bool:
    message = str(exc).lower()
    return (
        "inputs size exceeds the maximum weight" in message
        or "maximum weight" in message
        or "too many small utxos" in message
    )


def _wallet_max_weight_message(slot_label: str) -> str:
    return (
        f"{slot_label} wallet has too many small UTXOs for this payout "
        "as one transaction; consolidate wallet UTXOs before retrying."
    )


def _slot_threshold_max(raw: dict, slot: str) -> float:
    key = "ap_threshold" if slot == "" else f"ap_threshold_{slot}"
    threshold_cfg = raw.get(key)
    value = threshold_cfg.get("max") if isinstance(threshold_cfg, dict) else None
    try:
        cap = round(float(value), 8)
    except (TypeError, ValueError):
        return 0.0
    return cap if cap > 0 else 0.0


def _slot_threshold_min(raw: dict, slot: str) -> float:
    key = "ap_threshold" if slot == "" else f"ap_threshold_{slot}"
    threshold_cfg = raw.get(key)
    value = threshold_cfg.get("min") if isinstance(threshold_cfg, dict) else None
    try:
        floor = round(float(value), 8)
    except (TypeError, ValueError):
        return 0.0
    return floor if floor > 0 else 0.0


def _next_fallback_amount(amount: float, floor: float) -> float:
    amount = round(float(amount), 8)
    floor = round(float(floor), 8)
    if amount <= 0 or (floor > 0 and amount <= floor):
        return 0.0
    next_amount = round(amount / 2, 8)
    if floor > 0 and next_amount < floor:
        next_amount = floor
    if next_amount <= 0 or next_amount >= amount:
        return 0.0
    return next_amount


def _row_payout_amount(row: dict, amount_key: str) -> float:
    return round(float(row.get("_payout_amount", row.get(amount_key) or 0.0)), 8)


def _row_effective_payout_cap(row: dict, configured_cap: float) -> float:
    configured_cap = round(float(configured_cap or 0.0), 8)
    try:
        user_threshold = round(float(row.get("threshold") or 0.0), 8)
    except (TypeError, ValueError):
        user_threshold = 0.0
    if user_threshold > 0 and (configured_cap <= 0 or user_threshold < configured_cap):
        return user_threshold
    return configured_cap


@dataclass
class Payouts:
    name: str = "payouts"
    interval_seconds: int = 300  # 5 minutes
    slot: str = ""
    # Wave 1: this job moves coins on-chain via sendtoaddress, so any
    # Fatal here freezes every coin-moving job in the same slot until
    # an operator clears `cronjobs_py_disabled scope = slot:<slot>`.
    coin_moving: bool = True

    def run(self, ctx: JobContext) -> None:
        rpc = ctx.rpc(self.slot)
        db = ctx.db
        slot_label = self.slot or "parent"
        cfg = ctx.settings

        # Wave 5: in shadow mode payouts refuses to run. There is no
        # safe way to "shadow" a sendtoaddress — the on-chain effect
        # is binary. Authoritative payouts during the soak window are
        # PHP cron's job; cronjobs-py shadow mode only shadow-predicts
        # the PPLNS / Bonus credit math.
        if cfg.shadow_mode:
            log.debug("[%s/%s] shadow_mode=1; payouts is no-op (PHP "
                      "cron is authoritative)", self.name, slot_label)
            return

        # Wave 2: operator-controlled kill switches in the settings table.
        # `disable_payouts` halts ALL payouts (manual + auto). The
        # operator sets this to take the pool's wallet offline for
        # maintenance without halting the rest of the cron loop.
        if (db.get_setting("disable_payouts") or "0") == "1":
            log.info("[%s/%s] disable_payouts=1; bailing out",
                     self.name, slot_label)
            return

        # Pre-flight: any indeterminate outbox rows for this slot mean
        # an earlier tick had a `sendtoaddress` whose outcome is still
        # unknown. We MUST NOT issue any new payouts until reconciliation
        # resolves them — otherwise we risk double-paying. The slot-wide
        # poison flag is the formal gate (the scheduler skips this tick
        # if scope `slot:{slot}` is set), but check here too as a
        # defence-in-depth in case the operator cleared the flag without
        # finishing reconciliation.
        indeterminate = db.list_outbox_indeterminate(self.slot)
        if indeterminate:
            ids = [r["id"] for r in indeterminate]
            raise Fatal(
                f"refusing to send: {len(indeterminate)} indeterminate "
                f"outbox rows for slot {self.slot or 'parent'} "
                f"(ids={ids}). Reconcile via wallet listtransactions "
                f"matched to wallet_comment, then re-run."
            )

        # Coinbase-maturity threshold: payouts only count credits from
        # blocks that have reached this slot's daemon maturity. Orphaned
        # blocks (`confirmations = -1`) drop out of the balance
        # automatically.
        min_confs = slot_int(cfg.raw, "confirmations", self.slot, 100)

        # Wave 2: pay out the manual queue first. Operator queues these
        # via the web UI when a user explicitly asks for a payout
        # below their auto threshold. We process them BEFORE auto so
        # the wallet's balance check covers both populations.
        manual_queue = db.get_manual_payout_queue(
            self.slot,
            min_confirmations=min_confs,
            txfee_manual=0.0,
        )
        # Auto-payout queue. The network fee is wallet-calculated per
        # candidate below, so the legacy fixed txfee_auto gate is disabled.
        auto_disabled = (
            db.get_setting("disable_auto_payouts") or "0"
        ) == "1"
        if auto_disabled:
            log.info("[%s/%s] disable_auto_payouts=1; only manual queue "
                     "will be processed this tick",
                     self.name, slot_label)
            auto_candidates: list[dict] = []
        else:
            auto_candidates = db.get_accounts_above_threshold(
                self.slot, min_confirmations=min_confs,
                txfee_auto=0.0,
            )

        if not manual_queue and not auto_candidates:
            log.debug("[%s/%s] no manual queue, no auto candidates",
                      self.name, slot_label)
            return

        manual_queue = self._filter_valid_payout_rows(
            ctx, manual_queue, slot_label=slot_label, queue_name="manual",
        )
        manual_queue = self._dedupe_manual_queue(
            ctx, manual_queue, slot_label=slot_label,
        )
        auto_candidates = self._filter_valid_payout_rows(
            ctx, auto_candidates, slot_label=slot_label, queue_name="auto",
        )

        if not manual_queue and not auto_candidates:
            log.debug("[%s/%s] no payout candidates after address preflight",
                      self.name, slot_label)
            return

        payout_cap = _slot_threshold_max(cfg.raw, self.slot)
        payout_floor = _slot_threshold_min(cfg.raw, self.slot)
        manual_queue = self._apply_payout_cap(
            manual_queue, amount_key="amount", cap=payout_cap,
            slot_label=slot_label, queue_name="manual",
        )
        auto_candidates = self._apply_payout_cap(
            auto_candidates, amount_key="balance", cap=payout_cap,
            slot_label=slot_label, queue_name="auto",
        )

        manual_queue = self._with_fee_quotes(
            ctx, manual_queue, slot_label=slot_label,
            queue_name="manual", amount_key="amount",
            min_amount=payout_floor,
        )
        auto_candidates = self._with_fee_quotes(
            ctx, auto_candidates, slot_label=slot_label,
            queue_name="auto", amount_key="balance",
            min_amount=payout_floor,
        )

        if not manual_queue and not auto_candidates:
            log.debug("[%s/%s] no payout candidates after fee quotes",
                      self.name, slot_label)
            return

        try:
            wallet_balance = float(rpc.call("getbalance"))
        except Exception as exc:
            raise Skip(f"getbalance failed: {exc}")

        # With subtractfeefromamount=true, each wallet transaction spends
        # the user's gross balance: recipient amount + network fee == gross.
        total_manual = sum(_row_payout_amount(p, "amount") for p in manual_queue)
        total_auto = sum(_row_payout_amount(c, "balance") for c in auto_candidates)
        total = total_manual + total_auto
        log.info(
            "[%s/%s] manual_queue=%d (%.8f), auto_candidates=%d (%.8f), "
            "estimated_fees=%.8f, total=%.8f, wallet=%.8f",
            self.name, slot_label, len(manual_queue), total_manual,
            len(auto_candidates), total_auto,
            sum(float(p.get("_fee_quote", 0.0)) for p in manual_queue)
            + sum(float(c.get("_fee_quote", 0.0)) for c in auto_candidates),
            total,
            wallet_balance,
        )
        if total > wallet_balance:
            raise Skip(
                f"insufficient wallet balance: need {total:.8f}, "
                f"have {wallet_balance:.8f}"
            )

        # Manual payouts first.
        paid_account_ids: set[int] = set()
        for p in manual_queue:
            account_id = int(p["account_id"])
            username = p["username"]
            address = p["payout_address"]
            amount = _row_payout_amount(p, "amount")
            payout_id = int(p["payout_id"])
            if amount <= 0:
                continue
            self._pay_one(
                ctx, account_id=account_id, username=username,
                address=address, amount=amount, slot_label=slot_label,
                kind="Debit_MP",
                estimated_txfee=float(p.get("_fee_quote", 0.0)),
                manual_payout_id=payout_id,
                archive_on_reconcile=not bool(p.get("_payout_partial")),
            )
            paid_account_ids.add(account_id)

        # Then auto. Skip accounts that just received a manual payout
        # this tick — auto_candidates was snapshotted before the manual
        # loop ran, so a user who sat on the cashout button until cron
        # started would otherwise be paid TWICE in the same tick
        # (Debit_MP + Debit_AP both drain a balance the manual already
        # zeroed).
        for c in auto_candidates:
            account_id = int(c["id"])
            if account_id in paid_account_ids:
                log.info(
                    "[%s/%s] skipping auto payout for account_id=%d — "
                    "already paid manual queue this tick",
                    self.name, slot_label, account_id,
                )
                continue
            username = c["username"]
            address = c["payout_address"]
            amount = _row_payout_amount(c, "balance")
            if amount <= 0:
                continue
            self._pay_one(
                ctx, account_id=account_id, username=username,
                address=address, amount=amount, slot_label=slot_label,
                kind="Debit_AP",
                estimated_txfee=float(c.get("_fee_quote", 0.0)),
                manual_payout_id=None,
                archive_on_reconcile=not bool(c.get("_payout_partial")),
            )

    def _dedupe_manual_queue(self, ctx: JobContext, rows: list[dict], *,
                             slot_label: str) -> list[dict]:
        """Keep only one legacy manual payout row per account and slot.

        The account page normally blocks duplicate manual cash-out rows,
        but concurrent submits or direct DB repair can still leave more
        than one completed=0 row. Only the oldest row should be processed;
        later duplicates are closed before fee quotes or wallet sends.
        """
        if not rows:
            return []
        kept: list[dict] = []
        seen_accounts: set[int] = set()
        for row in rows:
            account_id = int(row["account_id"])
            payout_id = int(row["payout_id"])
            if account_id in seen_accounts:
                log.warning(
                    "[%s/%s] closing duplicate manual payout row id=%d "
                    "for account_id=%d before wallet quote",
                    self.name, slot_label, payout_id, account_id,
                )
                with ctx.db.transaction() as cur:
                    ctx.db.mark_manual_payout_complete(
                        self.slot, payout_id, cur=cur,
                    )
                continue
            seen_accounts.add(account_id)
            kept.append(row)
        return kept

    def _apply_payout_cap(self, rows: list[dict], *, amount_key: str,
                          cap: float, slot_label: str,
                          queue_name: str) -> list[dict]:
        if not rows:
            return []
        capped_rows: list[dict] = []
        for row in rows:
            original = round(float(row.get(amount_key) or 0.0), 8)
            payout_amount = original
            partial = False
            row_cap = _row_effective_payout_cap(row, cap)
            if row_cap > 0 and original > row_cap:
                payout_amount = row_cap
                partial = True
                log.info(
                    "[%s/%s] capping %s payout for %s (account %s) "
                    "from %.8f to payout threshold %.8f",
                    self.name, slot_label, queue_name,
                    row.get("username", ""),
                    row.get("account_id", row.get("id", "?")),
                    original, row_cap,
                )
            enriched = dict(row)
            enriched["_payout_original_amount"] = original
            enriched["_payout_amount"] = payout_amount
            enriched["_payout_cap"] = row_cap
            enriched["_payout_partial"] = partial
            capped_rows.append(enriched)
        return capped_rows

    def _filter_valid_payout_rows(self, ctx: JobContext, rows: list[dict],
                                  *, slot_label: str,
                                  queue_name: str) -> list[dict]:
        """Return only rows whose payout address validates with the slot daemon.

        Invalid user addresses are a user/account problem, not a wallet
        broadcast problem. We skip them before reserving an outbox row so
        they cannot create abandoned sends, debit balances, or poison the
        entire slot. If the validation RPC itself fails, skip the job tick:
        we do not know enough to safely distinguish bad input from a daemon
        outage.
        """
        if not rows:
            return []
        rpc = ctx.rpc(self.slot)
        valid: list[dict] = []
        for row in rows:
            address = str(row.get("payout_address") or "")
            username = str(row.get("username") or "")
            account_id = row.get("account_id", row.get("id", "?"))
            try:
                info = rpc.validateaddress(address)
            except Exception as exc:
                raise Skip(
                    f"validateaddress failed for {queue_name} payout "
                    f"{username} (account {account_id}, slot {slot_label}): "
                    f"{exc}"
                )
            if not isinstance(info, dict) or not info.get("isvalid"):
                log.warning(
                    "[%s/%s] skipping %s payout for %s (account %s): "
                    "daemon rejected payout address %s",
                    self.name, slot_label, queue_name, username,
                    account_id, address,
                )
                continue
            valid.append(row)
        return valid

    def _with_fee_quotes(self, ctx: JobContext, rows: list[dict],
                         *, slot_label: str, queue_name: str,
                         amount_key: str, min_amount: float = 0.0) -> list[dict]:
        """Attach wallet-calculated fee quotes to payout rows.

        Quotes use walletcreatefundedpsbt with subtractFeeFromOutputs so the
        estimate matches the final policy: the network fee comes out of the
        amount being paid to the user, not from a fixed MPOS config value.
        If a fragmented wallet cannot quote the requested amount because the
        selected inputs exceed transaction weight limits, reduce the amount
        geometrically and send only the first quotable chunk this tick.
        """
        if not rows:
            return []
        rpc = ctx.rpc(self.slot)
        quoted: list[dict] = []
        for row in rows:
            address = str(row.get("payout_address") or "")
            username = str(row.get("username") or "")
            account_id = row.get("account_id", row.get("id", "?"))
            amount = _row_payout_amount(row, amount_key)
            if amount <= 0:
                continue
            attempts = 0
            max_attempts = 8
            try:
                while True:
                    try:
                        quote = rpc.walletcreatefundedpsbt(address, amount)
                        break
                    except Exception as exc:
                        if not _wallet_max_weight_error(exc):
                            raise
                        next_amount = _next_fallback_amount(
                            amount, min_amount,
                        )
                        if next_amount <= 0 or attempts >= (max_attempts - 1):
                            raise
                        attempts += 1
                        log.warning(
                            "[%s/%s] reducing %s payout quote for %s "
                            "(account %s) from %.8f to %.8f after wallet "
                            "input-weight limit",
                            self.name, slot_label, queue_name, username,
                            account_id, amount, next_amount,
                        )
                        amount = next_amount
            except Exception as exc:
                if _wallet_max_weight_error(exc):
                    log.error(
                        "[%s/%s] skipping %s payout for %s (account %s): "
                        "%s",
                        self.name, slot_label, queue_name, username,
                        account_id, _wallet_max_weight_message(slot_label),
                    )
                else:
                    log.warning(
                        "[%s/%s] skipping %s payout for %s (account %s): "
                        "wallet fee quote failed: %s",
                        self.name, slot_label, queue_name, username,
                        account_id, exc,
                    )
                continue

            fee = round(float(quote.get("fee", 0.0)), 8) if isinstance(quote, dict) else 0.0
            send_amount = round(amount - fee, 8)
            if fee < 0 or send_amount <= 0:
                log.warning(
                    "[%s/%s] skipping %s payout for %s (account %s): "
                    "quoted fee %.8f consumes amount %.8f",
                    self.name, slot_label, queue_name, username,
                    account_id, fee, amount,
                )
                continue
            enriched = dict(row)
            original = round(float(
                enriched.get("_payout_original_amount",
                             enriched.get(amount_key) or 0.0)
            ), 8)
            enriched["_payout_amount"] = amount
            enriched["_payout_partial"] = bool(
                enriched.get("_payout_partial") or amount < original
            )
            enriched["_wallet_limited"] = attempts > 0
            enriched["_fallback_attempts"] = attempts
            enriched["_fee_quote"] = fee
            enriched["_send_amount_quote"] = send_amount
            quoted.append(enriched)
        return quoted

    def _pay_one(self, ctx: JobContext, *, account_id: int,
                 username: str, address: str, amount: float,
                 slot_label: str, kind: str = "Debit_AP",
                 estimated_txfee: float = 0.0,
                 manual_payout_id: int | None = None,
                 archive_on_reconcile: bool = True) -> None:
        """Pay one user. The flow is:

          1. Reserve outbox row (status=pending) with a fresh
             wallet_comment idempotency anchor.
          2. Call sendtoaddress through call_nonidempotent — no retries
             on timeout. Send the gross user balance with
             subtractfeefromamount=true so the wallet calculates the real
             network fee and deducts it from the recipient amount.
          3. On success: in one transaction, mark outbox=broadcast,
             insert Debit_AP/Debit_MP for the net recipient amount,
             insert TXFee for the wallet-reported fee, archive only
             full-balance payouts, and (for manual payouts) mark
             `payouts.completed = 1`.
          4. On Indeterminate: mark outbox=indeterminate, raise Fatal.
          5. On Fatal from daemon: mark outbox=abandoned, close the
             manual queue row if this was a manual payout, then raise
             Fatal so the operator sees the slot poison flag and
             investigates.

        `kind` is "Debit_AP" for auto, "Debit_MP" for manual.
        `estimated_txfee` is used only for the short pending-outbox
        window before the wallet returns the actual fee. `manual_payout_id`
        is the row id from the `payouts` table for manual payouts —
        we mark it `completed = 1` once the on-chain send + balance
        bookkeeping commit. None for auto.
        """
        rpc = ctx.rpc(self.slot)
        db = ctx.db

        estimated_send_amount = round(amount - estimated_txfee, 8)
        if estimated_send_amount <= 0:
            log.warning(
                "[%s/%s] %s: amount %.8f <= quoted fee %.8f; skipping",
                self.name, slot_label, username, amount, estimated_txfee,
            )
            return

        # Step 1. Reserve the outbox row with its FINAL wallet_comment in
        # one atomic insert. The comment no longer embeds the outbox id, so
        # there is no placeholder-then-update window: a crash before the
        # send leaves a clean 'pending' row with send_attempted=0 (provably
        # unsent) that reconcile-orphans can abandon safely.
        wallet_comment = _make_wallet_comment(
            slot=self.slot, account_id=account_id,
        )
        outbox_id = db.insert_outbox_pending(
            slot=self.slot,
            account_id=account_id,
            coin_address=address,
            amount=estimated_send_amount,
            wallet_comment=wallet_comment,
            archive_on_reconcile=archive_on_reconcile,
            tx_kind=kind,
            manual_payout_id=manual_payout_id,
        )

        log.info(
            "[%s/%s] sending gross %.8f to %s (%s), fee deducted by wallet "
            "(estimated %.8f) kind=%s outbox=%d comment=%s",
            self.name, slot_label, amount,
            username, address, estimated_txfee,
            kind, outbox_id, wallet_comment,
        )

        # Step 2. Flip send_attempted=1 (the provable-no-send gate), then
        # issue the wallet send. NO retries.
        db.mark_outbox_send_attempted(outbox_id)
        try:
            txid = rpc.sendtoaddress(
                address, amount, comment=wallet_comment,
                subtract_fee_from_amount=True,
            )
        except Indeterminate as exc:
            db.mark_outbox_indeterminate(outbox_id, str(exc))
            raise Fatal(
                f"E0090: outbox {outbox_id} ({username}, {estimated_send_amount:.8f}) "
                f"is in indeterminate state — wallet may have broadcast. "
                f"Reconcile via listtransactions matching wallet_comment "
                f"{wallet_comment} before clearing the slot poison flag."
            )
        except Exception as exc:
            max_weight = _wallet_max_weight_error(exc)
            with db.transaction() as cur:
                cur.execute(
                    "UPDATE transactions_outbox "
                    "SET status = 'abandoned', rpc_error = %s "
                    "WHERE id = %s AND status = 'pending'",
                    (str(exc), outbox_id),
                )
                if manual_payout_id is not None:
                    db.mark_manual_payout_complete(
                        self.slot, manual_payout_id, cur=cur,
                    )
            if max_weight:
                raise Fatal(
                    f"E0092: sendtoaddress for {username} "
                    f"(account {account_id}) was rejected because "
                    f"{_wallet_max_weight_message(slot_label)} "
                    f"Outbox {outbox_id} marked abandoned; user balance "
                    f"unchanged."
                )
            raise Fatal(
                f"E0091: sendtoaddress for {username} (account {account_id}) "
                f"was rejected by the daemon: {exc}. "
                f"Outbox {outbox_id} marked abandoned; "
                f"user balance unchanged."
            )

        # Durability nudge: the coins are now on-chain. Record the txid on
        # the still-pending row before the bookkeeping runs, so if that
        # bookkeeping rolls back the orphaned 'pending' row already carries
        # its txid and reconcile-orphans can heal it directly.
        try:
            db.set_outbox_txid_pending(outbox_id, txid)
        except Exception as exc:
            log.warning(
                "[%s/%s] could not record txid on pending outbox %d "
                "(reconcile-orphans will fall back to comment lookup): %s",
                self.name, slot_label, outbox_id, exc,
            )

        txfee = round(float(estimated_txfee), 8)
        try:
            tx_info = rpc.call("gettransaction", txid)
            if isinstance(tx_info, dict) and "fee" in tx_info:
                txfee = round(abs(float(tx_info.get("fee", 0.0))), 8)
        except Exception as exc:
            log.warning(
                "[%s/%s] txid=%s broadcast but gettransaction failed; "
                "using fee quote %.8f for DB accounting: %s",
                self.name, slot_label, txid, estimated_txfee, exc,
            )
        send_amount = round(amount - txfee, 8)
        if send_amount <= 0:
            # Degenerate edge: the wallet fee met or exceeded the gross
            # amount. The tx IS broadcast (txid in hand) and the whole
            # balance has left the wallet, so the outcome is KNOWN — record
            # the recipient amount as 0 and the entire spend as fee, and let
            # the normal Step 3 mark the row 'broadcast' (NOT 'indeterminate',
            # which would falsely claim the send might not have happened). A
            # warning, not a slot-poisoning Fatal, for this benign case.
            log.warning(
                "[%s/%s] txid=%s wallet fee %.8f >= gross %.8f; recording "
                "recipient 0 and the full %.8f as fee",
                self.name, slot_label, txid, txfee, amount, amount,
            )
            send_amount = 0.0
            txfee = round(amount, 8)

        log.info(
            "[%s/%s] txid=%s sent %.8f (gross %.8f − wallet fee %.8f) "
            "to %s (%s) kind=%s outbox=%d",
            self.name, slot_label, txid, send_amount, amount, txfee,
            username, address, kind, outbox_id,
        )

        # Step 3. Broadcast confirmed. One transaction wraps:
        #   outbox → broadcast
        #   insert Debit row for `send_amount`
        #   insert TXFee row for `txfee` (if any)
        #   archive older transactions only for full-balance payouts.
        #   Capped partial payouts leave the old credits and this
        #   Debit/TXFee unarchived so the remaining balance stays visible.
        #   for manual payouts: mark payouts.completed = 1
        try:
            with db.transaction() as cur:
                cur.execute(
                    "UPDATE transactions_outbox "
                    "SET status = 'broadcast', txid = %s, amount = %s, "
                    "rpc_error = NULL "
                    "WHERE id = %s",
                    (txid, send_amount, outbox_id),
                )
                debit_id = db.add_transaction_in_tx(
                    cur=cur,
                    account_id=account_id,
                    amount=send_amount,
                    kind=kind,
                    block_id=None,
                    coin_address=address,
                    txid=txid,
                    slot=self.slot,
                )
                if txfee > 0:
                    db.add_transaction_in_tx(
                        cur=cur,
                        account_id=account_id,
                        amount=txfee,
                        kind="TXFee",
                        block_id=None,
                        coin_address=address,
                        txid=txid,
                        slot=self.slot,
                    )
                archived_count = 0
                if archive_on_reconcile:
                    # Archive older Credit / Fee / Donation / *_PPS rows up
                    # to (but excluding) this Debit. PHP-parity with
                    # createPayoutDebitRecord.
                    archived_count = db.set_account_transactions_archived(
                        cur=cur,
                        account_id=account_id,
                        insert_id_max=debit_id,
                        slot=self.slot,
                    )
                # Close the manual cash-out request only when the FULL
                # balance was paid. A capped/partial payout (archive_on_
                # reconcile is False) leaves the request open so the
                # remaining balance keeps paying down on later ticks.
                if manual_payout_id is not None and archive_on_reconcile:
                    db.mark_manual_payout_complete(
                        self.slot, manual_payout_id, cur=cur,
                    )
        except Exception as exc:
            # On-chain broadcast happened but the bookkeeping commit failed.
            # The row stays 'pending' with its txid (recorded above) and real
            # wallet_comment. reconcile-orphans heals it automatically by
            # matching the txid/comment to the wallet and writing the missing
            # Debit/TXFee. Distinct code from the pre-broadcast abandon (E0092)
            # because here the coins ARE on-chain.
            raise Fatal(
                f"E0094: sendtoaddress for {username} (account {account_id}) "
                f"completed with txid {txid} (wallet_comment={wallet_comment}) "
                f"but the {kind}+TXFee+archive step failed to commit: "
                f"{exc}. reconcile-orphans will heal outbox {outbox_id}; "
                f"do not delete the row by hand."
            )

        log.info(
            "[%s/%s] %s paid %.8f gross (kind=%s, txfee=%.8f), "
            "txid=%s outbox=%d archived=%d transactions",
            self.name, slot_label, username, amount, kind, txfee,
            txid, outbox_id, archived_count,
        )
