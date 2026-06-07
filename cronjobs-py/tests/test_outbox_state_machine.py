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
                 validateaddress=None, fee: float = 0.001,
                 confirmations: int = 0):
        self.balance = balance
        self._sendtoaddress = sendtoaddress
        self._validateaddress = validateaddress
        self.fee = fee
        self.confirmations = confirmations
        self.calls: list[tuple] = []

    def call(self, method: str, *params):
        self.calls.append((method, params))
        if method == "getbalance":
            return self.balance
        if method == "walletcreatefundedpsbt":
            return {"fee": self.fee, "changepos": 0, "psbt": "stub"}
        if method == "gettransaction":
            return {"fee": -self.fee, "confirmations": self.confirmations}
        raise NotImplementedError(method)

    def call_nonidempotent(self, method: str, *params):
        self.calls.append((method, params))
        if method == "sendtoaddress":
            if isinstance(self._sendtoaddress, list):
                if not self._sendtoaddress:
                    raise AssertionError("sendtoaddress called more than scripted")
                outcome = self._sendtoaddress.pop(0)
                if isinstance(outcome, Exception):
                    raise outcome
                return outcome
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
    def __init__(self, *, fail_addresses: set[str],
                 failure: Exception | None = None):
        super().__init__()
        self.fail_addresses = fail_addresses
        self.failure = failure or Fatal("simulated quote failure")

    def walletcreatefundedpsbt(self, address, amount):
        self.calls.append(("walletcreatefundedpsbt", (address, amount)))
        if address in self.fail_addresses:
            raise self.failure
        return {"fee": self.fee, "changepos": 0, "psbt": "stub"}


class _QuoteWeightByAmountRpc(_StubRpc):
    def __init__(self, *, max_quotable: float, **kwargs):
        super().__init__(**kwargs)
        self.max_quotable = max_quotable

    def walletcreatefundedpsbt(self, address, amount):
        self.calls.append(("walletcreatefundedpsbt", (address, amount)))
        if amount > self.max_quotable:
            raise Fatal("[-4] The inputs size exceeds the maximum weight")
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


def _seed_payable_account(db: Db, *, balance: float = 1.0,
                          ap_threshold: float = 0.5) -> None:
    """Insert one account with a confirmed Credit large enough to pay."""
    insert_account(
        db, account_id=10, username="alice",
        coin_address="addr_a", ap_threshold=ap_threshold,
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


def test_fee_quote_max_weight_skips_row() -> None:
    """Fragmented-wallet fee quotes are pre-broadcast failures.

    They must not reserve an outbox row or abort the whole batch.
    """
    rpc = _QuoteFailureRpc(
        fail_addresses={"frag_addr"},
        failure=Fatal("[-4] The inputs size exceeds the maximum weight"),
    )
    ctx = _QuoteOnlyCtx(rpc)

    quoted = Payouts(slot="")._with_fee_quotes(
        ctx,
        [{
            "account_id": 10,
            "username": "fragmented",
            "payout_address": "frag_addr",
            "amount": 1.0,
        }],
        slot_label="parent",
        queue_name="manual",
        amount_key="amount",
    )

    assert quoted == []


def test_fee_quote_max_weight_falls_back_to_smaller_chunk() -> None:
    """A fragmented wallet should quote the largest bounded fallback chunk."""
    rpc = _QuoteWeightByAmountRpc(max_quotable=0.5)
    ctx = _QuoteOnlyCtx(rpc)

    quoted = Payouts(slot="")._with_fee_quotes(
        ctx,
        [{
            "account_id": 10,
            "username": "fragmented",
            "payout_address": "frag_addr",
            "amount": 2.0,
            "_payout_original_amount": 2.0,
            "_payout_amount": 2.0,
            "_payout_partial": False,
        }],
        slot_label="parent",
        queue_name="manual",
        amount_key="amount",
        min_amount=0.25,
    )

    assert len(quoted) == 1
    assert quoted[0]["_payout_amount"] == 0.5
    assert quoted[0]["_wallet_limited"] is True
    assert quoted[0]["_fallback_attempts"] == 2
    assert quoted[0]["_payout_partial"] is True
    quote_amounts = [c[1][1] for c in rpc.calls if c[0] == "walletcreatefundedpsbt"]
    assert quote_amounts == [2.0, 1.0, 0.5]


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
    _seed_payable_account(db, balance=1.0, ap_threshold=1.0)
    rpc = _StubRpc(balance=10.0, sendtoaddress="real_txid_abc")
    ctx = _ctx(db, rpc, raw={"confirmations": 100, "txfee_auto": 0.001})

    Payouts(slot="").run(ctx)

    # One outbox row, status=broadcast, txid set, net amount recorded.
    rows = db.fetchall(
        "SELECT status, txid, amount, archive_on_reconcile "
        "FROM transactions_outbox"
    )
    assert len(rows) == 1
    assert rows[0]["status"] == "broadcast"
    assert rows[0]["txid"] == "real_txid_abc"
    assert abs(float(rows[0]["amount"]) - 0.999) < 1e-9
    assert int(rows[0]["archive_on_reconcile"]) == 1

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
def test_capped_auto_payout_preserves_remaining_balance_after_reconcile(
    fresh_db: Db,
) -> None:
    """Large balances are paid in account-threshold chunks.

    Partial payout rows must not archive the old credits or the new
    Debit/TXFee, otherwise the unpaid remainder would disappear from
    compute_balance after reconciliation.
    """
    db = fresh_db
    _seed_payable_account(db, balance=10.0, ap_threshold=2.5)
    rpc = _StubRpc(
        balance=20.0, sendtoaddress="partial_txid", confirmations=6,
    )
    ctx = _ctx(
        db, rpc,
        raw={
            "confirmations": 100,
            "reconcile_min_confirmations": 6,
            "txfee_auto": 0.001,
            "ap_threshold": {"max": 2.5},
        },
    )

    Payouts(slot="").run(ctx)

    quote_calls = [c for c in rpc.calls if c[0] == "walletcreatefundedpsbt"]
    send_calls = [c for c in rpc.calls if c[0] == "sendtoaddress"]
    assert quote_calls[0][1][1] == 2.5
    assert send_calls[0][1][1] == 2.5

    outbox = db.fetchall(
        "SELECT status, amount, archive_on_reconcile FROM transactions_outbox"
    )
    assert len(outbox) == 1
    assert outbox[0]["status"] == "broadcast"
    assert abs(float(outbox[0]["amount"]) - 2.499) < 1e-9
    assert int(outbox[0]["archive_on_reconcile"]) == 0

    bal = db.compute_balance(10, min_confirmations=100)
    assert abs(bal["confirmed"] - 10.0) < 1e-9, bal
    assert abs(bal["inflight"] - 2.5) < 1e-9, bal

    ReconcilePayouts(slot="").run(ctx)

    outbox = db.fetchall(
        "SELECT status, archive_on_reconcile FROM transactions_outbox"
    )
    assert outbox[0]["status"] == "reconciled"
    assert int(outbox[0]["archive_on_reconcile"]) == 0

    txns = db.fetchall(
        "SELECT type, archived FROM transactions "
        "WHERE type IN ('Credit','Debit_AP','TXFee') ORDER BY id"
    )
    assert [(r["type"], int(r["archived"])) for r in txns] == [
        ("Credit", 0),
        ("Debit_AP", 0),
        ("TXFee", 0),
    ]
    bal = db.compute_balance(10, min_confirmations=100)
    assert abs(bal["confirmed"] - 7.5) < 1e-9, bal


@pytest.mark.needs_mariadb
def test_auto_payout_weight_fallback_sends_smaller_chunk(
    fresh_db: Db,
) -> None:
    """If the max-threshold chunk is too large for wallet input weight,
    send the first smaller chunk that the wallet can quote.
    """
    db = fresh_db
    _seed_payable_account(db, balance=10.0, ap_threshold=2.5)
    rpc = _QuoteWeightByAmountRpc(
        max_quotable=1.25,
        balance=20.0,
        sendtoaddress="weight_fallback_txid",
        confirmations=6,
    )
    ctx = _ctx(
        db, rpc,
        raw={
            "confirmations": 100,
            "reconcile_min_confirmations": 6,
            "txfee_auto": 0.001,
            "ap_threshold": {"min": 1.0, "max": 2.5},
        },
    )

    Payouts(slot="").run(ctx)

    quote_amounts = [
        c[1][1] for c in rpc.calls if c[0] == "walletcreatefundedpsbt"
    ]
    send_amounts = [c[1][1] for c in rpc.calls if c[0] == "sendtoaddress"]
    assert quote_amounts == [2.5, 1.25]
    assert send_amounts == [1.25]

    outbox = db.fetchall(
        "SELECT status, amount, archive_on_reconcile FROM transactions_outbox"
    )
    assert outbox[0]["status"] == "broadcast"
    assert abs(float(outbox[0]["amount"]) - 1.249) < 1e-9
    assert int(outbox[0]["archive_on_reconcile"]) == 0

    bal = db.compute_balance(10, min_confirmations=100)
    assert abs(bal["confirmed"] - 10.0) < 1e-9, bal
    assert abs(bal["inflight"] - 1.25) < 1e-9, bal

    ReconcilePayouts(slot="").run(ctx)

    bal = db.compute_balance(10, min_confirmations=100)
    assert abs(bal["confirmed"] - 8.75) < 1e-9, bal
    assert abs(bal["inflight"]) < 1e-9, bal


@pytest.mark.needs_mariadb
def test_auto_payout_uses_user_threshold_below_config_max(
    fresh_db: Db,
) -> None:
    """The account threshold is the chunk size, bounded by config max."""
    db = fresh_db
    _seed_payable_account(db, balance=10.0, ap_threshold=1.25)
    rpc = _StubRpc(
        balance=20.0, sendtoaddress="threshold_chunk_txid",
        confirmations=6,
    )
    ctx = _ctx(
        db, rpc,
        raw={
            "confirmations": 100,
            "reconcile_min_confirmations": 6,
            "txfee_auto": 0.001,
            "ap_threshold": {"max": 2.5},
        },
    )

    Payouts(slot="").run(ctx)

    send_amounts = [c[1][1] for c in rpc.calls if c[0] == "sendtoaddress"]
    assert send_amounts == [1.25]

    outbox = db.fetchall(
        "SELECT status, amount, archive_on_reconcile FROM transactions_outbox"
    )
    assert outbox[0]["status"] == "broadcast"
    assert abs(float(outbox[0]["amount"]) - 1.249) < 1e-9
    assert int(outbox[0]["archive_on_reconcile"]) == 0


@pytest.mark.needs_mariadb
def test_auto_payout_waits_for_reconcile_before_next_chunk(
    fresh_db: Db,
) -> None:
    """A large balance sends one chunk, then waits for reconciliation."""
    db = fresh_db
    _seed_payable_account(db, balance=10.0, ap_threshold=2.5)
    rpc = _StubRpc(
        balance=20.0,
        sendtoaddress=["chunk_tx_1", "chunk_tx_2"],
        confirmations=6,
    )
    ctx = _ctx(
        db, rpc,
        raw={
            "confirmations": 100,
            "reconcile_min_confirmations": 6,
            "txfee_auto": 0.001,
            "ap_threshold": {"max": 2.5},
        },
    )

    Payouts(slot="").run(ctx)
    Payouts(slot="").run(ctx)
    send_amounts = [
        c[1][1] for c in rpc.calls if c[0] == "sendtoaddress"
    ]
    assert send_amounts == [2.5]

    ReconcilePayouts(slot="").run(ctx)
    Payouts(slot="").run(ctx)
    send_amounts = [
        c[1][1] for c in rpc.calls if c[0] == "sendtoaddress"
    ]
    assert send_amounts == [2.5, 2.5]


@pytest.mark.needs_mariadb
def test_capped_manual_payout_uses_account_threshold_amount(fresh_db: Db) -> None:
    """Manual cash-out also sends only the account threshold chunk."""
    db = fresh_db
    _seed_payable_account(db, balance=10.0, ap_threshold=2.5)
    db.execute(
        "INSERT INTO payouts (account_id, time, completed) "
        "VALUES (10, NOW(), 0)"
    )
    rpc = _StubRpc(
        balance=20.0, sendtoaddress="manual_partial_txid", confirmations=6,
    )
    ctx = _ctx(
        db, rpc,
        raw={
            "confirmations": 100,
            "reconcile_min_confirmations": 6,
            "txfee_auto": 0.001,
            "txfee_manual": 0.001,
            "ap_threshold": {"max": 2.5},
        },
    )

    Payouts(slot="").run(ctx)

    send_calls = [c for c in rpc.calls if c[0] == "sendtoaddress"]
    assert send_calls[0][1][1] == 2.5

    outbox = db.fetchall(
        "SELECT amount, archive_on_reconcile FROM transactions_outbox"
    )
    assert abs(float(outbox[0]["amount"]) - 2.499) < 1e-9
    assert int(outbox[0]["archive_on_reconcile"]) == 0

    payout_rows = db.fetchall("SELECT completed FROM payouts")
    assert int(payout_rows[0]["completed"]) == 1
    debit = db.fetchall("SELECT amount FROM transactions WHERE type='Debit_MP'")
    assert abs(float(debit[0]["amount"]) - 2.499) < 1e-9
    bal = db.compute_balance(10, min_confirmations=100)
    assert abs(bal["confirmed"] - 10.0) < 1e-9, bal
    assert abs(bal["inflight"] - 2.5) < 1e-9, bal

    ReconcilePayouts(slot="").run(ctx)

    txns = db.fetchall(
        "SELECT type, archived FROM transactions "
        "WHERE type IN ('Credit','Debit_MP','TXFee') ORDER BY id"
    )
    assert [(r["type"], int(r["archived"])) for r in txns] == [
        ("Credit", 0),
        ("Debit_MP", 0),
        ("TXFee", 0),
    ]
    bal = db.compute_balance(10, min_confirmations=100)
    assert abs(bal["confirmed"] - 7.5) < 1e-9, bal


@pytest.mark.needs_mariadb
def test_duplicate_manual_rows_only_send_once(fresh_db: Db) -> None:
    """Concurrent manual queue rows for one account must not double-send."""
    db = fresh_db
    _seed_payable_account(db, balance=10.0, ap_threshold=2.5)
    db.execute(
        "INSERT INTO payouts (account_id, time, completed) "
        "VALUES (10, NOW(), 0), (10, NOW(), 0)"
    )
    rpc = _StubRpc(
        balance=20.0, sendtoaddress=["manual_once_txid"], confirmations=6,
    )
    ctx = _ctx(
        db, rpc,
        raw={
            "confirmations": 100,
            "reconcile_min_confirmations": 6,
            "txfee_auto": 0.001,
            "txfee_manual": 0.001,
            "ap_threshold": {"max": 2.5},
        },
    )

    Payouts(slot="").run(ctx)

    send_calls = [c for c in rpc.calls if c[0] == "sendtoaddress"]
    quote_calls = [c for c in rpc.calls if c[0] == "walletcreatefundedpsbt"]
    assert len(send_calls) == 1
    assert len(quote_calls) == 1
    assert send_calls[0][1][1] == 2.5

    outbox = db.fetchall("SELECT status, txid FROM transactions_outbox")
    assert len(outbox) == 1
    assert outbox[0]["status"] == "broadcast"
    assert outbox[0]["txid"] == "manual_once_txid"

    payout_rows = db.fetchall("SELECT completed FROM payouts ORDER BY id")
    assert [int(r["completed"]) for r in payout_rows] == [1, 1]
    debit = db.fetchall("SELECT amount FROM transactions WHERE type='Debit_MP'")
    assert len(debit) == 1
    assert abs(float(debit[0]["amount"]) - 2.499) < 1e-9


@pytest.mark.needs_mariadb
def test_auto_payout_chunks_until_final_full_balance_archives(
    fresh_db: Db,
) -> None:
    """Auto-payouts drain a large balance in account-threshold chunks."""
    db = fresh_db
    _seed_payable_account(db, balance=10.0, ap_threshold=2.5)
    rpc = _StubRpc(
        balance=20.0,
        sendtoaddress=["chunk_tx_1", "chunk_tx_2", "chunk_tx_3", "chunk_tx_4"],
        confirmations=6,
    )
    ctx = _ctx(
        db, rpc,
        raw={
            "confirmations": 100,
            "reconcile_min_confirmations": 6,
            "txfee_auto": 0.001,
            "ap_threshold": {"max": 2.5},
        },
    )

    for _ in range(4):
        Payouts(slot="").run(ctx)
        ReconcilePayouts(slot="").run(ctx)

    send_amounts = [
        c[1][1] for c in rpc.calls if c[0] == "sendtoaddress"
    ]
    assert send_amounts == [2.5, 2.5, 2.5, 2.5]

    outbox = db.fetchall(
        "SELECT status, archive_on_reconcile FROM transactions_outbox "
        "ORDER BY id"
    )
    assert [r["status"] for r in outbox] == [
        "reconciled", "reconciled", "reconciled", "reconciled",
    ]
    assert [int(r["archive_on_reconcile"]) for r in outbox] == [0, 0, 0, 1]

    bal = db.compute_balance(10, min_confirmations=100)
    assert abs(bal["confirmed"]) < 1e-9, bal
    assert abs(bal["inflight"]) < 1e-9, bal

    active_txns = db.fetchall(
        "SELECT * FROM transactions WHERE account_id = 10 AND archived = 0"
    )
    assert active_txns == []


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
def test_max_weight_send_reject_marks_abandoned_no_balance_change(
    fresh_db: Db,
) -> None:
    """If the wallet rejects the send for excessive input weight, no debit
    is written and the outbox is abandoned for operator review.
    """
    db = fresh_db
    _seed_payable_account(db, balance=1.0)
    rpc = _StubRpc(
        balance=10.0,
        sendtoaddress=Fatal(
            "[-4] The inputs size exceeds the maximum weight"
        ),
    )
    ctx = _ctx(db, rpc, raw={"confirmations": 100, "txfee_auto": 0.001})

    with pytest.raises(Fatal, match="E0092"):
        Payouts(slot="").run(ctx)

    rows = db.fetchall("SELECT status FROM transactions_outbox")
    assert len(rows) == 1
    assert rows[0]["status"] == "abandoned"

    debit = db.fetchall(
        "SELECT * FROM transactions WHERE type IN ('Debit_AP','TXFee')"
    )
    assert len(debit) == 0
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
