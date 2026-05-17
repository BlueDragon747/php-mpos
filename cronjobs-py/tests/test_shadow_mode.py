"""Wave 5 replay test: shadow mode + drift-check.

Covers the soak-window cutover gate. Three scenarios:

  1. Shadow PPLNS writes guard rows (mode='shadow') but NOT
     transactions_<slot> rows. blocks.accounted stays at 0 so PHP
     cron sees the block as still pending.
  2. Drift-check matches shadow predictions to authoritative writes:
     - When PHP cron's amounts equal cronjobs-py's predictions →
       MATCH verdict.
     - When they differ → DIFF verdict, return code 1.
     - When PHP cron didn't write yet → MISSING verdict.
  3. Payouts and liquid_payout refuse to run in shadow mode.
"""

from __future__ import annotations

import pytest

from cronjobs_py.db import Db
from cronjobs_py import drift
from cronjobs_py.scheduler import JobContext
from cronjobs_py.jobs.pplns_payout import PplnsPayout
from cronjobs_py.jobs.payouts import Payouts
from cronjobs_py.jobs.liquid_payout import LiquidPayout
from cronjobs_py.settings import Settings, DbConfig
from tests.conftest import insert_account, insert_block, insert_share


def _ctx(db, *, shadow=False, raw=None):
    s = Settings(
        php_config_path="/dev/null",  # type: ignore
        db=DbConfig("", 0, "", "", ""),
        coins=[],
        reward=0.0,
        reward_type="block",
        block_bonus=0.0,
        shadow_mode=shadow,
        raw=raw or {
            "fees": 1.0, "confirmations": 100, "difficulty": 32,
            "pplns": {"shares": {"type": "default", "default": 1}},
        },
    )
    return JobContext(
        settings=s, db=db, rpc_by_slot={}, cache=None,
    )


class _NoOpRpc:
    def call(self, method, *params):
        return 0.0
    def call_nonidempotent(self, *args, **kwargs):
        raise AssertionError("RPC should not be called in shadow mode")
    def sendtoaddress(self, *args, **kwargs):
        raise AssertionError("sendtoaddress should not be called in shadow mode")


@pytest.mark.needs_mariadb
def test_shadow_pplns_writes_guard_but_no_transactions(fresh_db: Db) -> None:
    db = fresh_db
    insert_account(db, account_id=10, username="alice")
    for sid in range(1, 6):
        insert_share(db, share_id=sid, username="alice", difficulty=1.0)
    insert_block(
        db, block_id=1, height=100, blockhash="h1",
        amount=1.0, share_id=5, confirmations=120,
    )

    PplnsPayout(slot="").run(_ctx(db, shadow=True))

    # Guard rows tagged 'shadow'.
    guards = db.fetchall(
        "SELECT * FROM cronjobs_py_accounting WHERE mode = 'shadow'"
    )
    assert len(guards) >= 1
    assert all(g["txn_id"] is None for g in guards), (
        "shadow guards should have NULL txn_id (no real transaction "
        "row was written)"
    )

    # NO transactions_<slot> rows.
    txns = db.fetchall("SELECT * FROM transactions")
    assert len(txns) == 0, f"shadow mode wrote transactions: {txns}"

    # Block still accounted=0 — PHP's job to flip it.
    blk = db.fetchone("SELECT accounted FROM blocks WHERE id = 1")
    assert int(blk["accounted"]) == 0, (
        "shadow mode flipped accounted=1 — should leave for PHP cron"
    )
    assert db.get_setting("last_accounted_block_id") is None, (
        "shadow mode advanced the authoritative PPLNS cursor"
    )


@pytest.mark.needs_mariadb
def test_live_cutover_promotes_shadow_guards(fresh_db: Db) -> None:
    """A shadow prediction must not suppress the first live credit."""
    db = fresh_db
    insert_account(db, account_id=10, username="alice")
    for sid in range(1, 6):
        insert_share(db, share_id=sid, username="alice", difficulty=1.0)
    insert_block(
        db, block_id=1, height=100, blockhash="h1",
        amount=1.0, share_id=5, confirmations=120,
    )

    PplnsPayout(slot="").run(_ctx(db, shadow=True))
    PplnsPayout(slot="").run(_ctx(db, shadow=False))

    txns = db.fetchall(
        "SELECT type, amount FROM transactions ORDER BY type"
    )
    assert [(t["type"], float(t["amount"])) for t in txns] == [
        ("Credit", 1.0),
        ("Fee", 0.01),
    ]

    guards = db.fetchall(
        "SELECT mode, txn_id FROM cronjobs_py_accounting ORDER BY tx_type"
    )
    assert len(guards) == 2
    assert all(g["mode"] == "live" for g in guards)
    assert all(g["txn_id"] is not None for g in guards)

    blk = db.fetchone("SELECT accounted FROM blocks WHERE id = 1")
    assert int(blk["accounted"]) == 1


@pytest.mark.needs_mariadb
def test_drift_check_clean_match(fresh_db: Db) -> None:
    """Shadow + matching authoritative write → drift-check reports MATCH."""
    db = fresh_db
    insert_account(db, account_id=10, username="alice")
    for sid in range(1, 6):
        insert_share(db, share_id=sid, username="alice", difficulty=1.0)
    insert_block(
        db, block_id=1, height=100, blockhash="h1",
        amount=1.0, share_id=5, confirmations=120,
    )

    PplnsPayout(slot="").run(_ctx(db, shadow=True))

    # Now simulate PHP cron crediting alice with 1.0 + 0.01 fee.
    db.execute(
        "INSERT INTO transactions (account_id, type, amount, "
        " block_id, timestamp) VALUES (10, 'Credit', 1.0, 1, NOW())"
    )
    db.execute(
        "INSERT INTO transactions (account_id, type, amount, "
        " block_id, timestamp) VALUES (10, 'Fee', 0.01, 1, NOW())"
    )

    rows = drift.check_drift(db)
    verdicts = {(r.tx_type, r.verdict) for r in rows}
    assert ("Credit", "MATCH") in verdicts, rows
    assert ("Fee", "MATCH") in verdicts, rows


@pytest.mark.needs_mariadb
def test_drift_check_detects_amount_mismatch(fresh_db: Db) -> None:
    db = fresh_db
    insert_account(db, account_id=10, username="alice")
    for sid in range(1, 6):
        insert_share(db, share_id=sid, username="alice", difficulty=1.0)
    insert_block(
        db, block_id=1, height=100, blockhash="h1",
        amount=1.0, share_id=5, confirmations=120,
    )

    PplnsPayout(slot="").run(_ctx(db, shadow=True))

    # Simulate PHP cron writing the WRONG amount.
    db.execute(
        "INSERT INTO transactions (account_id, type, amount, "
        " block_id, timestamp) VALUES (10, 'Credit', 0.95, 1, NOW())"
    )

    rows = drift.check_drift(db)
    diffs = [r for r in rows if r.verdict == "DIFF"]
    assert len(diffs) >= 1
    assert diffs[0].shadow_amount == 1.0
    assert diffs[0].auth_amount == 0.95


@pytest.mark.needs_mariadb
def test_drift_check_missing_when_php_didnt_credit(fresh_db: Db) -> None:
    db = fresh_db
    insert_account(db, account_id=10, username="alice")
    for sid in range(1, 6):
        insert_share(db, share_id=sid, username="alice", difficulty=1.0)
    insert_block(
        db, block_id=1, height=100, blockhash="h1",
        amount=1.0, share_id=5, confirmations=120,
    )

    PplnsPayout(slot="").run(_ctx(db, shadow=True))

    # No PHP-cron writes.
    rows = drift.check_drift(db)
    missing = [r for r in rows if r.verdict == "MISSING"]
    assert len(missing) >= 1


@pytest.mark.needs_mariadb
def test_payouts_refuses_in_shadow_mode(fresh_db: Db) -> None:
    """Payouts must be a no-op in shadow mode (no on-chain shadow)."""
    db = fresh_db
    insert_account(
        db, account_id=10, username="alice",
        coin_address="addr_a", ap_threshold=0.5,
    )
    insert_block(db, block_id=1, height=100, blockhash="h1",
                 amount=1.0, share_id=10, confirmations=120)
    db.execute(
        "INSERT INTO transactions (account_id, type, amount, "
        " block_id, timestamp) VALUES (10, 'Credit', 1.0, 1, NOW())"
    )

    rpc = _NoOpRpc()
    ctx = JobContext(
        settings=Settings(
            php_config_path="/dev/null",  # type: ignore
            db=DbConfig("", 0, "", "", ""),
            coins=[], reward=0.0, reward_type="block",
            block_bonus=0.0, shadow_mode=True,
            raw={"confirmations": 100, "txfee_auto": 0.001},
        ),
        db=db, rpc_by_slot={"": rpc}, cache=None,
    )

    Payouts(slot="").run(ctx)

    # No outbox rows, no Debit_AP, no TXFee.
    outbox = db.fetchall("SELECT * FROM transactions_outbox")
    assert len(outbox) == 0
    debits = db.fetchall(
        "SELECT * FROM transactions WHERE type IN ('Debit_AP','TXFee')"
    )
    assert len(debits) == 0


@pytest.mark.needs_mariadb
def test_liquid_payout_refuses_in_shadow_mode(fresh_db: Db) -> None:
    db = fresh_db
    rpc = _NoOpRpc()
    ctx = JobContext(
        settings=Settings(
            php_config_path="/dev/null",  # type: ignore
            db=DbConfig("", 0, "", "", ""),
            coins=[], reward=0.0, reward_type="block",
            block_bonus=0.0, shadow_mode=True,
            raw={"coldwallet": {"address": "cold_addr",
                                "reserve": 50.0, "threshold": 1.0}},
        ),
        db=db, rpc_by_slot={"": rpc}, cache=None,
    )

    # Should return without raising. _NoOpRpc would fail any RPC call.
    LiquidPayout(slot="").run(ctx)
