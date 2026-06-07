"""Port of `cronjobs/liquid_payout.php` (cold-wallet sweep).

Periodically moves excess hot-wallet balance to a configured cold-wallet
address. The amount kept hot is `locked_balance + reserve`, where:

- `locked_balance` = sum of net pending user credits in the per-slot
  transactions table (`Credit + Bonus − Fee − Donation − Debit_AP −
  Debit_MP`). This is the float we need to be able to pay miners on
  demand.
- `reserve` = `coldwallet.reserve` config (default 50). Buffer above
  the locked balance so payouts don't have to chase the cold wallet on
  every transient credit/payout cycle.

Sweep amount = `wallet_balance − (locked + reserve)`. If sweep amount is
above `coldwallet.threshold`, fire `sendtoaddress(coldwallet.address,
amount)` to move the excess to cold storage. If `coldwallet.address` is
empty (the deploy default), the job is a no-op.

Differences vs the PHP version:

- Per-slot. The PHP coldwallet config is singular; we use the same
  config keys for every slot, but each slot's locked balance and wallet
  balance come from the right slot-specific source.
- Wallet sends are guarded by `transactions_outbox` with account_id=0.
  This gives the sweep a durable wallet comment and prevents duplicate
  sends while a previous sweep is broadcast, pending, or indeterminate.
"""

from __future__ import annotations

import secrets
from dataclasses import dataclass

from ..errors import Fatal, Indeterminate, Skip
from ..logger import get
from ..scheduler import JobContext
from ..settings import slot_int

log = get(__name__)

SWEEP_WALLET_COMMENT_FORMAT = "mpos-sweep:{slot}:{outbox_id}:{nonce}"


def _make_wallet_comment(*, slot: str, outbox_id: int) -> str:
    """Build a durable wallet-local comment for cold-wallet sweeps."""
    nonce = secrets.token_hex(4)
    return SWEEP_WALLET_COMMENT_FORMAT.format(
        slot=slot,
        outbox_id=outbox_id,
        nonce=nonce,
    )


@dataclass
class LiquidPayout:
    name: str = "liquid_payout"
    # Wave 1: cold-wallet sweep is a non-idempotent on-chain send. Fatal
    # here means we may have moved coins or be in an unknown state;
    # freeze the slot's coin-moving group until operator confirms.
    coin_moving: bool = True

    interval_seconds: int = 600  # 10 minutes — operationally fine
    slot: str = ""

    def run(self, ctx: JobContext) -> None:
        cfg = ctx.settings
        rpc = ctx.rpc(self.slot)
        db = ctx.db
        slot_label = self.slot or "parent"

        # Wave 5: in shadow mode the cold-wallet sweep refuses to run
        # for the same reason payouts does — the on-chain effect is
        # binary. PHP cron's `liquid_payout.php` is authoritative
        # during the soak window.
        if cfg.shadow_mode:
            log.debug("[%s/%s] shadow_mode=1; liquid_payout is no-op",
                      self.name, slot_label)
            return

        open_sweeps = db.list_open_coldwallet_outbox(self.slot)
        if open_sweeps:
            first = open_sweeps[0]
            status = str(first.get("status") or "")
            if status == "broadcast":
                raise Skip(
                    f"cold-wallet sweep outbox {first.get('id')} already "
                    f"broadcast with txid {first.get('txid')}; waiting for "
                    "reconciliation before sending another sweep"
                )
            raise Fatal(
                f"cold-wallet sweep outbox {first.get('id')} is {status}; "
                "operator must reconcile or abandon it before another sweep"
            )

        cold = (cfg.raw.get("coldwallet") or {})
        address = cold.get("address") or ""
        reserve = float(cold.get("reserve") or 0)
        threshold = float(cold.get("threshold") or 0)

        if not address:
            log.debug("[%s/%s] coldwallet.address is empty; skipping",
                      self.name, slot_label)
            return

        try:
            info = rpc.validateaddress(address)
        except Exception as exc:
            raise Skip(f"validateaddress for coldwallet failed: {exc}")
        if not isinstance(info, dict) or not info.get("isvalid"):
            raise Skip(f"coldwallet.address is invalid for slot {slot_label}: {address}")

        try:
            wallet_balance = float(rpc.call("getbalance"))
        except Exception as exc:
            raise Skip(f"getbalance failed: {exc}")

        locked = db.get_locked_balance(
            self.slot,
            min_confirmations=slot_int(cfg.raw, "confirmations", self.slot, 100),
        )
        float_target = locked + reserve
        sweep = round(wallet_balance - float_target, 8)

        log.info(
            "[%s/%s] wallet=%.8f locked=%.8f reserve=%.8f sweep=%.8f threshold=%.8f",
            self.name, slot_label,
            wallet_balance, locked, reserve, sweep, threshold,
        )

        if sweep <= threshold:
            log.debug("[%s/%s] sweep amount below threshold; skipping",
                      self.name, slot_label)
            return

        placeholder = f"sweep-pending:{secrets.token_hex(8)}"
        outbox_id = db.insert_outbox_pending(
            slot=self.slot,
            account_id=0,
            coin_address=address,
            amount=sweep,
            wallet_comment=placeholder,
            archive_on_reconcile=False,
        )
        wallet_comment = _make_wallet_comment(
            slot=self.slot, outbox_id=outbox_id,
        )
        db.execute(
            "UPDATE transactions_outbox SET wallet_comment = %s WHERE id = %s",
            (wallet_comment, outbox_id),
        )

        try:
            txid = rpc.sendtoaddress(address, sweep, comment=wallet_comment)
        except Indeterminate as exc:
            db.mark_outbox_indeterminate(outbox_id, str(exc))
            raise Fatal(
                f"cold-wallet sweep outbox {outbox_id} is indeterminate; "
                f"wallet may have broadcast. Reconcile wallet_comment "
                f"{wallet_comment} before clearing the slot poison flag."
            )
        except Exception as exc:
            db.mark_outbox_abandoned(outbox_id, str(exc))
            raise Skip(f"sendtoaddress to coldwallet failed: {exc}")

        try:
            db.mark_outbox_broadcast(outbox_id, txid)
        except Exception as exc:
            raise Fatal(
                f"cold-wallet sweep txid {txid} returned, but outbox "
                f"{outbox_id} could not be marked broadcast: {exc}. "
                f"Reconcile wallet_comment {wallet_comment} before retrying."
            )

        log.warning("[%s/%s] swept %.8f to coldwallet %s, txid %s",
                    self.name, slot_label, sweep, address, txid)
