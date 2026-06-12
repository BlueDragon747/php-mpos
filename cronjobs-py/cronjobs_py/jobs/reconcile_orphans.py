"""Recover orphaned payout outbox rows.

A payout whose `sendtoaddress` succeeds but whose Debit/TXFee/archive
commit then rolls back (DB deadlock, transient drop, constraint error)
leaves the outbox row stuck at `status='pending'`: the coins have left
the wallet, but no Debit was written and the user's balance was never
debited. `reconcile_payouts` only scans `broadcast` rows and the payouts
preflight only gates on `indeterminate` rows, so nothing else heals a
`pending` orphan. The queue NOT-EXISTS guard keeps the account out of
future payouts while the row sits there, so it cannot silently re-pay —
but the books stay diverged and the user is frozen until this job runs.

What this job does, per unresolved row older than the grace window:

  - Placeholder anchor (`pending:<hex>`): the real wallet_comment is
    written before `sendtoaddress` is ever called and the send always
    uses it, so a row still showing the placeholder provably had no send
    issued. Safe to mark `abandoned`; the user re-enters the queue.

  - Real anchor, matched to a wallet send (by txid if the durability
    nudge recorded one, else by scanning the wallet for the comment):
    HEAL — write the missing Debit/TXFee, close any manual request, flip
    the row to `broadcast` so reconcile_payouts archives it on confs.

  - Real anchor, NO matching wallet send: do NOT auto-abandon. A wallet
    rebuild/rescan can hide a real send, and abandoning would let the
    account re-enter the queue and double-pay. Log loudly for the
    operator to verify against the wallet by hand.

This job never calls `sendtoaddress`: it only reads on-chain truth and
writes the DB, so it cannot move coins. It is therefore NOT coin-moving
and runs even while a slot is poisoned — it is the cleanup that resolves
the condition the poison flag was raised for. Once a slot has no
unresolved rows left, it clears that slot's poison flag.
"""

from __future__ import annotations

from dataclasses import dataclass

from ..logger import get
from ..scheduler import JobContext

log = get(__name__)


@dataclass
class ReconcileOrphans:
    name: str = "reconcile-orphans"
    interval_seconds: int = 180  # 3 minutes
    slot: str = ""
    # Send-free (read-only daemon RPC + DB writes). Deliberately NOT
    # coin_moving: it must run while the slot is poisoned so it can heal
    # the orphan and clear the freeze.
    coin_moving: bool = False
    # Don't touch a row a payouts tick may legitimately still be working
    # through. 15 minutes is well past a normal tick.
    grace_seconds: int = 900

    def run(self, ctx: JobContext) -> None:
        rpc = ctx.rpc(self.slot)
        db = ctx.db
        cfg = ctx.settings
        slot_label = self.slot or "parent"

        if cfg.shadow_mode:
            log.debug("[%s/%s] shadow_mode=1; reconcile-orphans is no-op",
                      self.name, slot_label)
            return

        rows = db.list_outbox_unresolved_aged(self.slot, self.grace_seconds)
        healed = abandoned = flagged = 0

        for row in rows:
            outbox_id = int(row["id"])
            account_id = int(row.get("account_id") or 0)
            comment = str(row.get("wallet_comment") or "")
            address = str(row.get("coin_address") or "")
            status = row.get("status")
            txid = row.get("txid")

            # Cold-wallet sweeps (account_id=0) carry no Debit and are owned
            # by liquid_payout / reconcile_payouts; leave them alone.
            if account_id == 0:
                continue

            # Provably-unsent row -> abandon. The modern marker is
            # send_attempted=0 (flipped to 1 atomically just before the
            # send), so a still-pending row at 0 cannot have broadcast.
            # `pending:` is the legacy placeholder anchor from before that
            # marker existed; treat it the same way.
            send_attempted = int(row.get("send_attempted") or 0)
            if status == "pending" and (
                send_attempted == 0 or comment.startswith("pending:")
            ):
                db.mark_outbox_abandoned(
                    outbox_id,
                    "reconcile-orphans: no send was issued (send_attempted=0)",
                )
                abandoned += 1
                log.warning(
                    "[%s/%s] abandoned outbox %d (account %d): no broadcast "
                    "happened (send_attempted=0); user balance unchanged",
                    self.name, slot_label, outbox_id, account_id,
                )
                continue

            # Locate the on-chain send: txid first (durability nudge), then
            # fall back to scanning the wallet for the comment.
            match = None
            try:
                if txid:
                    match = rpc.get_send_by_txid(str(txid))
                if match is None:
                    match = rpc.find_send_by_comment(comment, address=address)
            except Exception as exc:
                log.warning(
                    "[%s/%s] wallet lookup for outbox %d failed; will retry "
                    "next tick: %s",
                    self.name, slot_label, outbox_id, exc,
                )
                continue

            if match is None or not match.get("txid"):
                # Real anchor with no wallet match. NEVER auto-abandon: the
                # coins may already be on-chain and a wallet rebuild could be
                # hiding the record. Abandoning here would risk a double-pay.
                flagged += 1
                log.error(
                    "[%s/%s] OPERATOR ACTION REQUIRED: outbox %d (account %d, "
                    "%s) has real anchor %s but no matching wallet send. Coins "
                    "may already be on-chain. Verify with gettransaction / "
                    "listtransactions matching the comment BEFORE abandoning; "
                    "do not delete the row blindly.",
                    self.name, slot_label, outbox_id, account_id, address,
                    comment,
                )
                continue

            # Found on-chain. Heal: write the missing Debit/TXFee + close any
            # manual request + flip to 'broadcast' for reconcile_payouts.
            try:
                with db.transaction() as cur:
                    ok = db.heal_outbox_in_tx(
                        cur=cur, outbox_id=outbox_id, slot=self.slot,
                        txid=str(match["txid"]),
                        net_amount=float(match["net"]),
                        fee=float(match["fee"]),
                    )
            except Exception as exc:
                log.exception(
                    "[%s/%s] heal of outbox %d (txid=%s) raised; leaving "
                    "unresolved: %s",
                    self.name, slot_label, outbox_id, match.get("txid"), exc,
                )
                continue

            if ok:
                healed += 1
                log.info(
                    "[%s/%s] healed orphan outbox %d (account %d) -> broadcast "
                    "txid %s (net %.8f, fee %.8f); reconcile-payouts will "
                    "archive once confirmed",
                    self.name, slot_label, outbox_id, account_id,
                    match["txid"], float(match["net"]), float(match["fee"]),
                )
            else:
                log.info(
                    "[%s/%s] outbox %d already resolved by another path; "
                    "skipped",
                    self.name, slot_label, outbox_id,
                )

        # Guarded auto-clear of the slot poison flag: only once nothing is
        # unresolved (pending/indeterminate). Operator-flagged rows stay
        # 'pending', so they keep the slot frozen until resolved by hand.
        try:
            if db.get_disabled_flag(f"slot:{self.slot}"):
                if not db.list_outbox_unresolved(self.slot):
                    db.clear_disabled_flag(f"slot:{self.slot}")
                    log.info(
                        "[%s/%s] no unresolved outbox rows remain; cleared "
                        "slot poison flag",
                        self.name, slot_label,
                    )
        except Exception as exc:
            log.warning(
                "[%s/%s] slot poison auto-clear check failed: %s",
                self.name, slot_label, exc,
            )

        if healed or abandoned or flagged:
            log.info(
                "[%s/%s] tick: healed=%d abandoned=%d operator_flagged=%d",
                self.name, slot_label, healed, abandoned, flagged,
            )
