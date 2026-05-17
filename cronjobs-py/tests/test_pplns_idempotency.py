"""Wave 4 replay test: pplns_payout idempotency.

Covers QC C-4 (transactional accounting + UNIQUE guard). Replays the
same block twice through `_process_block` and asserts:

  - Two ticks produce ONE set of credit/fee/donation rows, not two.
  - The second tick's UNIQUE-on-cronjobs_py_accounting catches the
    duplicate and skips cleanly without raising Fatal (since the
    pre-flight `is_block_already_credited` short-circuits to Skip).
"""

from __future__ import annotations

import pytest

from cronjobs_py.db import Db
from cronjobs_py.scheduler import JobContext
from cronjobs_py.jobs.pplns_payout import PplnsPayout
from tests.conftest import insert_account, insert_block, insert_share


def _ctx(db, raw=None):
    from cronjobs_py.settings import Settings, DbConfig
    s = Settings(
        php_config_path="/dev/null",  # type: ignore
        db=DbConfig("", 0, "", "", ""),
        coins=[],
        reward=0.0,
        reward_type="block",
        block_bonus=0.0,
        raw=raw or {
            "fees": 1.0, "confirmations": 100, "difficulty": 32,
            "pplns": {"shares": {"type": "default", "default": 1}},
        },
    )
    return JobContext(
        settings=s, db=db, rpc_by_slot={}, cache=None,
    )


@pytest.mark.needs_mariadb
def test_pplns_replay_same_block_no_double_credit(fresh_db: Db) -> None:
    """Run pplns over the same block twice. Second run should be a Skip,
    not a Fatal, and no second set of Credit rows should appear."""
    db = fresh_db

    # 5 valid shares from alice, block credits her.
    insert_account(db, account_id=10, username="alice")
    for sid in range(1, 6):
        insert_share(db, share_id=sid, username="alice", difficulty=1.0)
    insert_block(
        db, block_id=1, height=100, blockhash="h1",
        amount=1.0, share_id=5, confirmations=120,
    )

    job = PplnsPayout(slot="")
    job.run(_ctx(db))

    credit_rows = db.fetchall(
        "SELECT amount FROM transactions WHERE type='Credit'"
    )
    fee_rows = db.fetchall(
        "SELECT amount FROM transactions WHERE type='Fee'"
    )
    guard_rows = db.fetchall(
        "SELECT * FROM cronjobs_py_accounting"
    )
    assert len(credit_rows) == 1
    assert abs(float(credit_rows[0]["amount"]) - 1.0) < 1e-9
    # Default _ctx fees=1.0% → expect a Fee row of 0.01 too.
    assert len(fee_rows) == 1
    assert abs(float(fee_rows[0]["amount"]) - 0.01) < 1e-9
    # One guard per (Credit, Fee) = 2 rows total.
    assert len(guard_rows) == 2

    # Reset accounted=0 so the next tick finds the block again.
    db.execute("UPDATE blocks SET accounted = 0 WHERE id = 1")
    # Reset last_accounted_block_id so prev_share_id calc starts fresh.
    db.execute("DELETE FROM settings WHERE name = 'last_accounted_block_id'")

    # Second tick. Should hit `is_block_already_credited` short-circuit
    # and Skip cleanly. NO new Credit row.
    job.run(_ctx(db))

    credit_rows_after = db.fetchall(
        "SELECT amount FROM transactions WHERE type='Credit'"
    )
    fee_rows_after = db.fetchall(
        "SELECT amount FROM transactions WHERE type='Fee'"
    )
    guard_rows_after = db.fetchall("SELECT * FROM cronjobs_py_accounting")
    assert len(credit_rows_after) == 1, (
        f"replay double-credited: {credit_rows_after}"
    )
    assert len(fee_rows_after) == 1
    assert len(guard_rows_after) == 2


@pytest.mark.needs_mariadb
def test_pplns_no_fees_account_skips_fee(fresh_db: Db) -> None:
    """`accounts.no_fees = 1` means the pool fee isn't charged."""
    db = fresh_db

    insert_account(db, account_id=10, username="alice", no_fees=True)
    for sid in range(1, 6):
        insert_share(db, share_id=sid, username="alice", difficulty=1.0)
    insert_block(
        db, block_id=1, height=100, blockhash="h1",
        amount=1.0, share_id=5, confirmations=120,
    )

    PplnsPayout(slot="").run(_ctx(db, raw={
        "fees": 5.0,  # 5% pool fee
        "confirmations": 100, "difficulty": 32,
        "pplns": {"shares": {"type": "default", "default": 1}},
    }))

    fee_rows = db.fetchall(
        "SELECT * FROM transactions WHERE type='Fee'"
    )
    assert len(fee_rows) == 0, f"fee charged despite no_fees=1: {fee_rows}"


@pytest.mark.needs_mariadb
def test_pplns_donate_percent_writes_donation_row(fresh_db: Db) -> None:
    """`accounts.donate_percent = 10` writes a Donation = 10% of
    (payout - fee). With no fee, that's 10% of payout."""
    db = fresh_db

    insert_account(db, account_id=10, username="alice", donate_percent=10.0)
    for sid in range(1, 6):
        insert_share(db, share_id=sid, username="alice", difficulty=1.0)
    insert_block(
        db, block_id=1, height=100, blockhash="h1",
        amount=1.0, share_id=5, confirmations=120,
    )

    PplnsPayout(slot="").run(_ctx(db, raw={
        "fees": 0.0,
        "confirmations": 100, "difficulty": 32,
        "pplns": {"shares": {"type": "default", "default": 1}},
    }))

    donation_rows = db.fetchall(
        "SELECT amount FROM transactions WHERE type='Donation'"
    )
    assert len(donation_rows) == 1
    assert abs(float(donation_rows[0]["amount"]) - 0.1) < 1e-9
