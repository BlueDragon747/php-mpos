"""Wave 2: reconcile broadcast payouts against the daemon.

Wave 1 closed the payout idempotency hole by inserting a
`transactions_outbox` row before each `sendtoaddress` and advancing it
to `status='broadcast'` once the daemon returned a txid (along with
the matching `Debit_AP`/`Debit_MP` and `TXFee` rows in
`transactions_<slot>`, written in the same DB transaction).

What Wave 1 did NOT do is close the loop on chain. The Debit_AP row is
left `archived=0` so that the user's balance reflects the in-flight
payout; the dashboard subtracts it from confirmed balance. Until
something archives it, the balance reads as `−Debit_AP` for as long as
the active credits sit at zero — visually misleading even though the
funds genuinely left the wallet.

Wave 2 watches each slot's broadcast outbox rows and, once the daemon
reports the matching txid with enough confirmations, archives the
matching `Debit_AP` / `Debit_MP` / `TXFee` rows AND advances the outbox
to `status='reconciled'` — atomically. After that, the user's balance
returns to a clean number reflecting only post-payout credits.

Behaviour summary:

  - Read-only daemon RPC (`gettransaction`) — safe to retry, idempotent.
    No `coin_moving=True` flag; this job never moves funds.
  - Per-slot, ticks every 5 minutes by default.
  - Conflicted / dropped / RBF'd transactions (negative confirmations)
    are left in `broadcast` and logged loudly. Operator decides
    whether to mark them `abandoned` (and reissue) — Wave 2 doesn't
    auto-abandon because that would put real-money decisions inside a
    cron loop.
  - `gettransaction` with an unknown txid (e.g. wallet-pruned) is also
    left in place; this can happen if the wallet's tx history was
    rebuilt or the txid was relayed by a different node. Same
    operator-review path.

The threshold for "enough confirmations" is configurable via
`reconcile_min_confirmations` (in global.inc.php). If unset, falls
back to `confirmations` (the coinbase-maturity bar, default 100).
Payout transactions spend already-mature wallet outputs, so they
don't need the full coinbase-maturity wait — operators can dial this
down (e.g. to 6) to shrink the window where a freshly-broadcast
payout shows as `inflight` in the balance UI.
"""

from __future__ import annotations

from dataclasses import dataclass

from ..logger import get
from ..scheduler import JobContext
from ..settings import slot_int

log = get(__name__)


@dataclass
class ReconcilePayouts:
    name: str = "reconcile-payouts"
    interval_seconds: int = 300  # 5 minutes
    slot: str = ""
    # Read-only: gettransaction + a localised UPDATE inside one DB tx.
    # No coin_moving flag — this job never moves funds.

    def run(self, ctx: JobContext) -> None:
        rpc = ctx.rpc(self.slot)
        db = ctx.db
        slot_label = self.slot or "parent"
        cfg = ctx.settings

        if cfg.shadow_mode:
            log.debug("[%s/%s] shadow_mode=1; reconcile is no-op",
                      self.name, slot_label)
            return

        rows = db.list_outbox_broadcast(self.slot)
        if not rows:
            log.debug("[%s/%s] no broadcast outbox rows to reconcile",
                      self.name, slot_label)
            return

        # Threshold: prefer `reconcile_min_confirmations` if set,
        # otherwise fall back to the coinbase-maturity bar
        # (`confirmations`, default 100). Payout transactions spend
        # already-mature wallet outputs; they don't need full coinbase
        # maturity to be considered final. The standard non-coinbase
        # finality bar is ~6 confirmations on busy chains; operators
        # who want faster reconciliation set this lower than
        # `confirmations` to shrink the in-flight UX window. Leaving
        # it unset keeps the conservative behaviour from before this
        # tunable existed.
        min_confs = int(
            cfg.raw.get("reconcile_min_confirmations")
            or slot_int(cfg.raw, "confirmations", self.slot, 100)
        )

        log.info(
            "[%s/%s] checking %d broadcast outbox row(s) at min_confs=%d",
            self.name, slot_label, len(rows), min_confs,
        )

        reconciled = 0
        for row in rows:
            outbox_id = int(row["id"])
            txid = row.get("txid")
            if not txid:
                log.warning(
                    "[%s/%s] outbox %d in 'broadcast' has NULL txid; "
                    "skipping (operator should investigate)",
                    self.name, slot_label, outbox_id,
                )
                continue

            try:
                info = rpc.call("gettransaction", txid)
            except Exception as exc:
                # Don't poison the slot or block unrelated rows: the
                # daemon may just be missing one wallet transaction or
                # restarting. Leave this row broadcast and retry next tick.
                log.warning(
                    "[%s/%s] gettransaction(%s) failed for outbox %d; "
                    "will retry next tick: %s",
                    self.name, slot_label, txid, outbox_id, exc,
                )
                continue

            confs = int(info.get("confirmations", 0)) if isinstance(info, dict) else 0

            if confs < 0:
                # Conflicted: the wallet sees a competing tx that
                # double-spent these inputs. Don't auto-resolve — flag
                # for operator review.
                log.warning(
                    "[%s/%s] outbox %d txid %s confirmations=%d "
                    "(conflicted / RBF'd / dropped). Leaving in "
                    "'broadcast'; operator should investigate.",
                    self.name, slot_label, outbox_id, txid, confs,
                )
                continue

            if confs < min_confs:
                log.debug(
                    "[%s/%s] outbox %d txid %s confs=%d < %d; "
                    "not yet eligible",
                    self.name, slot_label, outbox_id, txid, confs,
                    min_confs,
                )
                continue

            # Eligible. Archive matching Debit/TXFee rows and advance
            # the outbox in one DB transaction so a mid-flight crash
            # never leaves a half-reconciled state.
            try:
                with db.transaction() as cur:
                    archived = db.reconcile_outbox_in_tx(
                        cur=cur,
                        outbox_id=outbox_id,
                        slot=self.slot,
                        txid=txid,
                    )
            except Exception as exc:
                log.exception(
                    "[%s/%s] reconcile of outbox %d (txid=%s) raised; "
                    "leaving row in 'broadcast': %s",
                    self.name, slot_label, outbox_id, txid, exc,
                )
                continue

            if archived == 0:
                # Outbox row claimed broadcast status but no matching
                # transactions row found by txid. Could happen if a
                # legacy row was reconciled by hand. Still advance the
                # outbox so we stop polling it.
                log.warning(
                    "[%s/%s] outbox %d txid %s reconciled with 0 "
                    "matching transactions_<slot> rows (already "
                    "archived by hand?); marked reconciled anyway",
                    self.name, slot_label, outbox_id, txid,
                )
            else:
                log.info(
                    "[%s/%s] outbox %d txid %s confs=%d → reconciled "
                    "(%d transaction row(s) archived)",
                    self.name, slot_label, outbox_id, txid, confs,
                    archived,
                )
            reconciled += 1

        if reconciled:
            log.info(
                "[%s/%s] tick reconciled %d/%d row(s)",
                self.name, slot_label, reconciled, len(rows),
            )
