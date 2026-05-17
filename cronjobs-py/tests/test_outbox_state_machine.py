"""Wave 4 replay test: payouts outbox state machine.

Covers QC C-1 (the double-spend hazard on `sendtoaddress` retry).
We simulate three RPC outcomes against a stubbed RpcClient:

  1. Clean broadcast → outbox row goes pending → broadcast,
     Debit_AP + (optional) TXFee inserted, slot poison stays clear.
  2. `Indeterminate` (timeout / connection error after submission) →
     outbox row stays pending → indeterminate, NO Debit_AP written,
     slot poison flag set, subsequent payouts ticks refuse to send.
  3. `Fatal` from daemon (bad address) → outbox row → abandoned,
     NO Debit_AP written, slot poison flag set.

The "no double-pay" guarantee is: between step 2 and the operator's
manual reconciliation, NO automatic action moves coins.
"""

from __future__ import annotations

import pytest

from cronjobs_py.db import Db
from cronjobs_py.errors import Indeterminate, Fatal
from cronjobs_py.scheduler import JobContext
from cronjobs_py.jobs.payouts import Payouts
from tests.conftest import insert_account, insert_block


class _StubRpc:
    """Minimal RpcClient stub. `script` is a list mirroring the
    sequence of expected calls, each entry either a string (return
    value for sendtoaddress) or an Exception instance to raise."""

    def __init__(self, *, balance: float = 100.0, sendtoaddress=None,
                 validateaddress=None):
        self.balance = balance
        self._sendtoaddress = sendtoaddress
        self._validateaddress = validateaddress
        self.calls: list[tuple] = []

    def call(self, method: str, *params):
        self.calls.append((method, params))
        if method == "getbalance":
            return self.balance
        raise NotImplementedError(method)

    def call_nonidempotent(self, method: str, *params):
        self.calls.append((method, params))
        if method == "sendtoaddress":
            if isinstance(self._sendtoaddress, Exception):
                raise self._sendtoaddress
            return self._sendtoaddress
        raise NotImplementedError(method)

    def sendtoaddress(self, address, amount, comment="", comment_to=""):
        params = [address, amount]
        if comment or comment_to:
            params.extend([comment, comment_to])
        return self.call_nonidempotent("sendtoaddress", *params)

    def validateaddress(self, address):
        self.calls.append(("validateaddress", (address,)))
        if isinstance(self._validateaddress, Exception):
            raise self._validateaddress
        if self._validateaddress is not None:
            return self._validateaddress
        return {"isvalid": True}


def _ctx(fresh_db, rpc, raw=None):
    from cronjobs_py.settings import Settings, DbConfig

    s = Settings(
        php_config_path="/dev/null",  # type: ignore
        db=DbConfig("", 0, "", "", ""),
        coins=[],
        reward=0.0,
        reward_type="block",
        block_bonus=0.0,
        raw=raw or {"confirmations": 100, "txfee_auto": 0.0001},
    )
    return JobContext(
        settings=s, db=fresh_db, rpc_by_slot={"": rpc}, cache=None,
    )


def _seed_payable_account(db: Db, *, balance: float = 1.0) -> None:
    """Insert one account with a confirmed Credit large enough to pay."""
    insert_account(
        db, account_id=10, username="alice",
        coin_address="addr_a", ap_threshold=0.5,
    )
    insert_block(
        db, block_id=1, height=100, blockhash="h1",
        amount=balance, share_id=10, confirmations=120,
    )
    db.execute(
        "INSERT INTO transactions (account_id, type, amount, "
        " block_id, timestamp) VALUES (10, 'Credit', %s, 1, NOW())",
        (balance,),
    )


@pytest.mark.needs_mariadb
def test_clean_broadcast_writes_debit_and_txfee(fresh_db: Db) -> None:
    """Successful sendtoaddress → Debit_AP + TXFee + outbox=broadcast,
    no poison flag."""
    db = fresh_db
    _seed_payable_account(db, balance=1.0)
    rpc = _StubRpc(balance=10.0, sendtoaddress="real_txid_abc")
    ctx = _ctx(db, rpc, raw={"confirmations": 100, "txfee_auto": 0.001})

    Payouts(slot="").run(ctx)

    # One outbox row, status=broadcast, txid set.
    rows = db.fetchall("SELECT status, txid FROM transactions_outbox")
    assert len(rows) == 1
    assert rows[0]["status"] == "broadcast"
    assert rows[0]["txid"] == "real_txid_abc"

    # One Debit_AP for full balance + one TXFee.
    debit = db.fetchall(
        "SELECT amount, txid FROM transactions WHERE type='Debit_AP'"
    )
    txfee = db.fetchall(
        "SELECT amount, txid FROM transactions WHERE type='TXFee'"
    )
    assert len(debit) == 1
    assert abs(float(debit[0]["amount"]) - 1.0) < 1e-9
    assert debit[0]["txid"] == "real_txid_abc"
    assert len(txfee) == 1
    assert abs(float(txfee[0]["amount"]) - 0.001) < 1e-9

    # No poison flag.
    poison = db.fetchall("SELECT * FROM cronjobs_py_disabled")
    assert len(poison) == 0


@pytest.mark.needs_mariadb
def test_indeterminate_no_debit_no_double_pay(fresh_db: Db) -> None:
    """RPC timeout after submission → outbox stays at indeterminate,
    NO Debit_AP, no TXFee, slot poison flag set. Re-running the job
    refuses to send anything until the operator reconciles."""
    db = fresh_db
    _seed_payable_account(db, balance=1.0)
    rpc = _StubRpc(
        balance=10.0,
        sendtoaddress=Indeterminate("simulated timeout after submission"),
    )
    ctx = _ctx(db, rpc, raw={"confirmations": 100, "txfee_auto": 0.001})

    # First tick: should raise Fatal (which the scheduler catches and
    # turns into a poison flag write — but we're calling .run() directly
    # so we observe the Fatal).
    with pytest.raises(Fatal):
        Payouts(slot="").run(ctx)

    rows = db.fetchall("SELECT status FROM transactions_outbox")
    assert len(rows) == 1
    assert rows[0]["status"] == "indeterminate"

    # NO Debit_AP — critical: this is the "no double-pay" property.
    debit = db.fetchall(
        "SELECT * FROM transactions WHERE type='Debit_AP'"
    )
    assert len(debit) == 0

    # Simulate scheduler's _on_fatal having set the slot poison flag.
    db.set_disabled_flag("slot:", "simulated indeterminate")

    # Second tick should refuse to send anything (the pre-flight catches
    # the indeterminate row).
    rpc2 = _StubRpc(balance=10.0, sendtoaddress="should_never_be_called")
    ctx2 = _ctx(db, rpc2, raw={"confirmations": 100, "txfee_auto": 0.001})
    with pytest.raises(Fatal):
        Payouts(slot="").run(ctx2)

    # The second tick must not have called sendtoaddress.
    sendtoaddress_calls = [
        c for c in rpc2.calls if c[0] == "sendtoaddress"
    ]
    assert len(sendtoaddress_calls) == 0


@pytest.mark.needs_mariadb
def test_daemon_reject_marks_abandoned_no_balance_change(fresh_db: Db) -> None:
    """Daemon explicitly rejected (e.g. bad address) → outbox abandoned,
    NO Debit_AP, user balance unchanged."""
    db = fresh_db
    _seed_payable_account(db, balance=1.0)
    rpc = _StubRpc(
        balance=10.0,
        sendtoaddress=Fatal("bad address"),
    )
    ctx = _ctx(db, rpc, raw={"confirmations": 100, "txfee_auto": 0.001})

    with pytest.raises(Fatal):
        Payouts(slot="").run(ctx)

    rows = db.fetchall("SELECT status FROM transactions_outbox")
    assert len(rows) == 1
    assert rows[0]["status"] == "abandoned"

    # No Debit, no TXFee. User's confirmed balance should still be 1.0.
    bal = db.compute_balance(10, min_confirmations=100)
    assert abs(bal["confirmed"] - 1.0) < 1e-9, bal


@pytest.mark.needs_mariadb
def test_invalid_address_preflight_skips_without_outbox(fresh_db: Db) -> None:
    """Invalid payout address is skipped before outbox reservation or wallet
    send. A bad user address should not poison the slot."""
    db = fresh_db
    _seed_payable_account(db, balance=1.0)
    rpc = _StubRpc(
        balance=10.0,
        sendtoaddress="should_not_send",
        validateaddress={"isvalid": False},
    )
    ctx = _ctx(db, rpc, raw={"confirmations": 100, "txfee_auto": 0.001})

    Payouts(slot="").run(ctx)

    rows = db.fetchall("SELECT * FROM transactions_outbox")
    assert len(rows) == 0
    debit = db.fetchall("SELECT * FROM transactions WHERE type='Debit_AP'")
    assert len(debit) == 0
    sendtoaddress_calls = [
        c for c in rpc.calls if c[0] == "sendtoaddress"
    ]
    assert len(sendtoaddress_calls) == 0
