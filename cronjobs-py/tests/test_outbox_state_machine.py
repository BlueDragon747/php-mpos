"""Wave 4 replay test: payouts outbox state machine.

Covers QC C-1 (the double-spend hazard on `sendtoaddress` retry).
We simulate three RPC outcomes against a stubbed RpcClient:

  1. Clean broadcast → outbox row goes pending → broadcast,
     net Debit_AP + wallet-calculated TXFee inserted, slot poison stays clear.
  2. `Indeterminate` (timeout / connection error after submission) →
     outbox row stays pending → indeterminate, NO Debit_AP written,
     slot poison flag set, subsequent payouts ticks refuse to send.
  3. `Fatal` from daemon (bad address) → outbox row → abandoned,
     NO Debit_AP written, slot poison flag set.

The "no double-pay" guarantee is: between step 2 and the operator's
manual reconciliation, NO automatic action moves coins.
"""

from __future__ import annotations

from contextlib import contextmanager

import pytest

from cronjobs_py.db import Db
from cronjobs_py.errors import Indeterminate, Fatal
from cronjobs_py.scheduler import JobContext
from cronjobs_py.jobs.payouts import Payouts
from cronjobs_py.jobs.reconcile_payouts import ReconcilePayouts
from tests.conftest import insert_account, insert_block


class _StubRpc:
    """Minimal RpcClient stub. `script` is a list mirroring the
    sequence of expected calls, each entry either a string (return
    value for sendtoaddress) or an Exception instance to raise."""

    def __init__(self, *, balance: float = 100.0, sendtoaddress=None,
                 validateaddress=None, fee: float = 0.001):
        self.balance = balance
        self._sendtoaddress = sendtoaddress
        self._validateaddress = validateaddress
        self.fee = fee
        self.calls: list[tuple] = []

    def call(self, method: str, *params):
        self.calls.append((method, params))
        if method == "getbalance":
            return self.balance
        if method == "walletcreatefundedpsbt":
            return {"fee": self.fee, "changepos": 0, "psbt": "stub"}
        if method == "gettransaction":
            return {"fee": -self.fee, "confirmations": 0}
        raise NotImplementedError(method)

    def call_nonidempotent(self, method: str, *params):
        self.calls.append((method, params))
        if method == "sendtoaddress":
            if isinstance(self._sendtoaddress, Exception):
                raise self._sendtoaddress
            return self._sendtoaddress
        raise NotImplementedError(method)

    def sendtoaddress(self, address, amount, comment="", comment_to="",
                      subtract_fee_from_amount=False):
        params = [address, amount]
        if comment or comment_to or subtract_fee_from_amount:
            params.extend([comment, comment_to, subtract_fee_from_amount])
        return self.call_nonidempotent("sendtoaddress", *params)

    def walletcreatefundedpsbt(self, address, amount):
        self.calls.append(("walletcreatefundedpsbt", (address, amount)))
        return {"fee": self.fee, "changepos": 0, "psbt": "stub"}

    def validateaddress(self, address):
        self.calls.append(("validateaddress", (address,)))
        if isinstance(self._validateaddress, Exception):
            raise self._validateaddress
        if self._validateaddress is not None:
            return self._validateaddress
        return {"isvalid": True}


class _QuoteFailureRpc(_StubRpc):
    def __init__(self, *, fail_addresses: set[str]):
        super().__init__()
        self.fail_addresses = fail_addresses

    def walletcreatefundedpsbt(self, address, amount):
        self.calls.append(("walletcreatefundedpsbt", (address, amount)))
        if address in self.fail_addresses:
            raise Fatal("simulated quote failure")
        return {"fee": self.fee, "changepos": 0, "psbt": "stub"}


class _QuoteOnlyCtx:
    def __init__(self, rpc):
        self._rpc = rpc

    def rpc(self, slot):
        return self._rpc


class _ReconcileRpc:
    def __init__(self):
        self.calls: list[tuple] = []

    def call(self, method, txid):
        self.calls.append((method, txid))
        if txid == "bad_tx":
            raise Fatal("simulated gettransaction failure")
        return {"confirmations": 6}


class _ReconcileDb:
    def __init__(self):
        self.reconciled: list[tuple[int, str, str]] = []

    def list_outbox_broadcast(self, slot):
        return [
            {"id": 1, "slot": slot, "txid": "bad_tx"},
            {"id": 2, "slot": slot, "txid": "good_tx"},
        ]

    @contextmanager
    def transaction(self):
        yield object()

    def reconcile_outbox_in_tx(self, *, cur, outbox_id, slot, txid):
        self.reconciled.append((outbox_id, slot, txid))
        return 2


class _ReconcileSettings:
    shadow_mode = False
    raw = {"reconcile_min_confirmations": 6, "confirmations": 100}


class _ReconcileCtx:
    def __init__(self, rpc, db):
        self.settings = _ReconcileSettings()
        self._rpc = rpc
        self.db = db

    def rpc(self, slot):
        return self._rpc


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


def test_fee_quote_failure_skips_only_bad_row() -> None:
    """One bad wallet fee quote should not abort the whole slot batch."""
    rpc = _QuoteFailureRpc(fail_addresses={"bad_addr"})
    ctx = _QuoteOnlyCtx(rpc)
    rows = [
        {
            "account_id": 10,
            "username": "bad",
            "payout_address": "bad_addr",
            "amount": 1.0,
        },
        {
            "account_id": 11,
            "username": "good",
            "payout_address": "good_addr",
            "amount": 2.0,
        },
    ]

    quoted = Payouts(slot="")._with_fee_quotes(
        ctx, rows, slot_label="parent", queue_name="auto",
        amount_key="amount",
    )

    assert len(quoted) == 1
    assert quoted[0]["account_id"] == 11
    assert quoted[0]["_fee_quote"] == 0.001
    assert quoted[0]["_send_amount_quote"] == 1.999


def test_reconcile_gettransaction_failure_skips_only_bad_row() -> None:
    """One missing/pruned wallet tx should not block other reconciles."""
    rpc = _ReconcileRpc()
    db = _ReconcileDb()
    ctx = _ReconcileCtx(rpc, db)

    ReconcilePayouts(slot="mm5").run(ctx)

    assert rpc.calls == [
        ("gettransaction", "bad_tx"),
        ("gettransaction", "good_tx"),
    ]
    assert db.reconciled == [(2, "mm5", "good_tx")]


@pytest.mark.needs_mariadb
def test_clean_broadcast_writes_debit_and_txfee(fresh_db: Db) -> None:
    """Successful sendtoaddress → Debit_AP + TXFee + outbox=broadcast,
    no poison flag."""
    db = fresh_db
    _seed_payable_account(db, balance=1.0)
    rpc = _StubRpc(balance=10.0, sendtoaddress="real_txid_abc")
    ctx = _ctx(db, rpc, raw={"confirmations": 100, "txfee_auto": 0.001})

    Payouts(slot="").run(ctx)

    # One outbox row, status=broadcast, txid set, net amount recorded.
    rows = db.fetchall("SELECT status, txid, amount FROM transactions_outbox")
    assert len(rows) == 1
    assert rows[0]["status"] == "broadcast"
    assert rows[0]["txid"] == "real_txid_abc"
    assert abs(float(rows[0]["amount"]) - 0.999) < 1e-9

    # One Debit_AP for net recipient amount + one wallet-calculated TXFee.
    debit = db.fetchall(
        "SELECT amount, txid FROM transactions WHERE type='Debit_AP'"
    )
    txfee = db.fetchall(
        "SELECT amount, txid FROM transactions WHERE type='TXFee'"
    )
    assert len(debit) == 1
    assert abs(float(debit[0]["amount"]) - 0.999) < 1e-9
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
def test_manual_daemon_reject_closes_manual_queue(fresh_db: Db) -> None:
    """A failed manual cash-out must not leave the account stuck behind
    a permanent "Manual - Pending payout" label."""
    db = fresh_db
    _seed_payable_account(db, balance=1.0)
    db.execute(
        "INSERT INTO payouts (account_id, time, completed) "
        "VALUES (10, NOW(), 0)"
    )
    rpc = _StubRpc(
        balance=10.0,
        sendtoaddress=Fatal("fee estimation failed"),
    )
    ctx = _ctx(
        db, rpc,
        raw={"confirmations": 100, "txfee_auto": 0.001, "txfee_manual": 0.001},
    )

    with pytest.raises(Fatal):
        Payouts(slot="").run(ctx)

    rows = db.fetchall("SELECT status FROM transactions_outbox")
    assert len(rows) == 1
    assert rows[0]["status"] == "abandoned"

    payout_rows = db.fetchall("SELECT completed FROM payouts")
    assert len(payout_rows) == 1
    assert int(payout_rows[0]["completed"]) == 1

    debit = db.fetchall(
        "SELECT * FROM transactions WHERE type IN ('Debit_MP','TXFee')"
    )
    assert len(debit) == 0
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
