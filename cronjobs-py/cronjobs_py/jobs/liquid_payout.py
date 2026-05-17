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
- Sweep failure is `Skip`, not `Fatal` — the next tick retries.
"""

from __future__ import annotations

from dataclasses import dataclass

from ..errors import Skip
from ..logger import get
from ..scheduler import JobContext

log = get(__name__)


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

        locked = db.get_locked_balance(self.slot)
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

        try:
            txid = rpc.call("sendtoaddress", address, sweep)
        except Exception as exc:
            raise Skip(f"sendtoaddress to coldwallet failed: {exc}")

        log.warning("[%s/%s] swept %.8f to coldwallet %s, txid %s",
                    self.name, slot_label, sweep, address, txid)
