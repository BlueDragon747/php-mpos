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

log = get(__name__)


def _make_wallet_comment(*, slot: str, account_id: int,
                        outbox_id: int) -> str:
    """Build the idempotency anchor that goes both into the outbox row
    and the wallet's `sendtoaddress` comment param.

    Format: `mpos:{slot}:{account_id}:{outbox_id}:{nonce_hex8}`.
    Constraints: bitcoind's `comment` field accepts arbitrary text up
    to a kilobyte or so, but we keep it short to fit our outbox's
    VARCHAR(64) UNIQUE column. The slot can be empty (parent chain).
    """
    nonce = secrets.token_hex(4)  # 8 hex chars
    return f"mpos:{slot}:{account_id}:{outbox_id}:{nonce}"


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
        # blocks that have at least this many confirmations. Defaults to
        # MPOS's `config.confirmations` (100 in the live config) — the
        # standard bitcoin-core coinbase maturity. Orphaned blocks
        # (`confirmations = -1`) drop out of the balance automatically.
        min_confs = int(cfg.raw.get("confirmations", 100))

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
        auto_candidates = self._filter_valid_payout_rows(
            ctx, auto_candidates, slot_label=slot_label, queue_name="auto",
        )

        if not manual_queue and not auto_candidates:
            log.debug("[%s/%s] no payout candidates after address preflight",
                      self.name, slot_label)
            return

        manual_queue = self._with_fee_quotes(
            ctx, manual_queue, slot_label=slot_label,
            queue_name="manual", amount_key="amount",
        )
        auto_candidates = self._with_fee_quotes(
            ctx, auto_candidates, slot_label=slot_label,
            queue_name="auto", amount_key="balance",
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
        total_manual = sum(float(p["amount"]) for p in manual_queue)
        total_auto = sum(float(c["balance"]) for c in auto_candidates)
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
            amount = round(float(p["amount"]), 8)
            payout_id = int(p["payout_id"])
            if amount <= 0:
                continue
            self._pay_one(
                ctx, account_id=account_id, username=username,
                address=address, amount=amount, slot_label=slot_label,
                kind="Debit_MP",
                estimated_txfee=float(p.get("_fee_quote", 0.0)),
                manual_payout_id=payout_id,
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
            amount = round(float(c["balance"]), 8)
            if amount <= 0:
                continue
            self._pay_one(
                ctx, account_id=account_id, username=username,
                address=address, amount=amount, slot_label=slot_label,
                kind="Debit_AP",
                estimated_txfee=float(c.get("_fee_quote", 0.0)),
                manual_payout_id=None,
            )

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
                         amount_key: str) -> list[dict]:
        """Attach wallet-calculated fee quotes to payout rows.

        Quotes use walletcreatefundedpsbt with subtractFeeFromOutputs so the
        estimate matches the final policy: the network fee comes out of the
        amount being paid to the user, not from a fixed MPOS config value.
        """
        if not rows:
            return []
        rpc = ctx.rpc(self.slot)
        quoted: list[dict] = []
        for row in rows:
            address = str(row.get("payout_address") or "")
            username = str(row.get("username") or "")
            account_id = row.get("account_id", row.get("id", "?"))
            amount = round(float(row.get(amount_key) or 0.0), 8)
            if amount <= 0:
                continue
            try:
                quote = rpc.walletcreatefundedpsbt(address, amount)
            except Exception as exc:
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
            enriched["_fee_quote"] = fee
            enriched["_send_amount_quote"] = send_amount
            quoted.append(enriched)
        return quoted

    def _pay_one(self, ctx: JobContext, *, account_id: int,
                 username: str, address: str, amount: float,
                 slot_label: str, kind: str = "Debit_AP",
                 estimated_txfee: float = 0.0,
                 manual_payout_id: int | None = None) -> None:
        """Pay one user. The flow is:

          1. Reserve outbox row (status=pending) with a fresh
             wallet_comment idempotency anchor.
          2. Call sendtoaddress through call_nonidempotent — no retries
             on timeout. Send the gross user balance with
             subtractfeefromamount=true so the wallet calculates the real
             network fee and deducts it from the recipient amount.
          3. On success: in one transaction, mark outbox=broadcast,
             insert Debit_AP/Debit_MP for the net recipient amount,
             insert TXFee for the wallet-reported fee, mark older
             transactions archived (so the next cycle doesn't re-net the
             same Credit/Fee rows), and (for manual payouts) mark
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

        # Step 1. Reserve outbox row before touching the wallet.
        # We can't pre-compute the wallet_comment because it embeds the
        # outbox_id, so insert the row with an interim placeholder, get
        # the id back, then UPDATE the comment to the real value.
        placeholder = f"pending:{secrets.token_hex(8)}"
        outbox_id = db.insert_outbox_pending(
            slot=self.slot,
            account_id=account_id,
            coin_address=address,
            amount=estimated_send_amount,
            wallet_comment=placeholder,
        )
        wallet_comment = _make_wallet_comment(
            slot=self.slot, account_id=account_id, outbox_id=outbox_id,
        )
        db.execute(
            "UPDATE transactions_outbox SET wallet_comment = %s "
            "WHERE id = %s",
            (wallet_comment, outbox_id),
        )

        log.info(
            "[%s/%s] sending gross %.8f to %s (%s), fee deducted by wallet "
            "(estimated %.8f) kind=%s outbox=%d comment=%s",
            self.name, slot_label, amount,
            username, address, estimated_txfee,
            kind, outbox_id, wallet_comment,
        )

        # Step 2. Issue the wallet send. NO retries.
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
            raise Fatal(
                f"E0091: sendtoaddress for {username} (account {account_id}) "
                f"was rejected by the daemon: {exc}. "
                f"Outbox {outbox_id} marked abandoned; "
                f"user balance unchanged."
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
            db.mark_outbox_indeterminate(
                outbox_id,
                f"txid {txid} broadcast but wallet fee {txfee:.8f} "
                f"consumed gross amount {amount:.8f}",
            )
            raise Fatal(
                f"E0093: txid {txid} broadcast but wallet fee {txfee:.8f} "
                f"consumed gross amount {amount:.8f}; outbox {outbox_id} "
                f"requires operator review."
            )

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
        #   archive older transactions (so the next cycle reads a
        #   fresh balance from this user — credits already paid out
        #   don't re-net into the AP queue)
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
                # Archive older Credit / Fee / Donation / *_PPS rows up
                # to (but excluding) this Debit. PHP-parity with
                # createPayoutDebitRecord.
                archived_count = db.set_account_transactions_archived(
                    cur=cur,
                    account_id=account_id,
                    insert_id_max=debit_id,
                    slot=self.slot,
                )
                if manual_payout_id is not None:
                    db.mark_manual_payout_complete(
                        self.slot, manual_payout_id, cur=cur,
                    )
        except Exception as exc:
            # On-chain broadcast happened but DB write failed. Outbox
            # stays pending → reconciliation can match wallet_comment.
            raise Fatal(
                f"E0092: sendtoaddress for {username} (account {account_id}) "
                f"completed with txid {txid} (wallet_comment={wallet_comment}) "
                f"but the {kind}+TXFee+archive step failed to commit: "
                f"{exc}. Reconcile via wallet_comment lookup."
            )

        log.info(
            "[%s/%s] %s paid %.8f gross (kind=%s, txfee=%.8f), "
            "txid=%s outbox=%d archived=%d transactions",
            self.name, slot_label, username, amount, kind, txfee,
            txid, outbox_id, archived_count,
        )
