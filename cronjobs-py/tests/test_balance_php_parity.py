"""Wave 4 replay test: `compute_balance` matches PHP `Transaction::getBalance`.

Covers QC H-2 (three-different-balance-SQLs disagree). This test
constructs a known transactions ledger by hand and asserts that
`compute_balance` returns the same numbers PHP would.
"""

from __future__ import annotations

import pytest

from cronjobs_py.db import Db
from tests.conftest import insert_account, insert_block


@pytest.mark.needs_mariadb
def test_balance_credit_minus_fee_minus_debit(fresh_db: Db) -> None:
    """Simple confirmed credit / fee / debit nets correctly."""
    db = fresh_db

    insert_account(db, account_id=10, username="alice")
    insert_block(db, block_id=1, height=100, blockhash="h1",
                 amount=1.0, share_id=10, confirmations=120)

    # 1.0 Credit, 0.01 Fee on confirmed block, 0.5 Debit_AP.
    db.execute(
        "INSERT INTO transactions (account_id, type, amount, "
        " block_id, timestamp) VALUES (10, 'Credit', 1.0, 1, NOW())"
    )
    db.execute(
        "INSERT INTO transactions (account_id, type, amount, "
        " block_id, timestamp) VALUES (10, 'Fee', 0.01, 1, NOW())"
    )
    db.execute(
        "INSERT INTO transactions (account_id, type, amount, "
        " timestamp) VALUES (10, 'Debit_AP', 0.5, NOW())"
    )

    bal = db.compute_balance(10, min_confirmations=100)
    # confirmed = 1.0 - 0.01 - 0.5 = 0.49
    assert abs(bal["confirmed"] - 0.49) < 1e-9, bal
    assert abs(bal["unconfirmed"] - 0.0) < 1e-9, bal
    assert abs(bal["orphaned"] - 0.0) < 1e-9, bal


@pytest.mark.needs_mariadb
def test_balance_orphaned_block_drops_credit(fresh_db: Db) -> None:
    """A block that goes orphan (confirmations=-1) must NOT count
    toward the user's confirmed balance. Wave 1's bespoke SQL got
    this right; the parity check ensures we keep getting it right."""
    db = fresh_db

    insert_account(db, account_id=10, username="alice")
    # Confirmed block id=1; orphaned block id=2.
    insert_block(db, block_id=1, height=100, blockhash="h1",
                 amount=1.0, share_id=10, confirmations=120)
    insert_block(db, block_id=2, height=101, blockhash="h2",
                 amount=1.0, share_id=20, confirmations=-1)

    db.execute(
        "INSERT INTO transactions (account_id, type, amount, "
        " block_id, timestamp) VALUES (10, 'Credit', 1.0, 1, NOW())"
    )
    db.execute(
        "INSERT INTO transactions (account_id, type, amount, "
        " block_id, timestamp) VALUES (10, 'Credit', 1.0, 2, NOW())"
    )

    bal = db.compute_balance(10, min_confirmations=100)
    assert abs(bal["confirmed"] - 1.0) < 1e-9, bal
    assert abs(bal["orphaned"] - 1.0) < 1e-9, bal


@pytest.mark.needs_mariadb
def test_archived_rows_excluded(fresh_db: Db) -> None:
    """`archived = 1` rows MUST NOT be summed (the QC's specific call-
    out — Wave 1 missed this filter)."""
    db = fresh_db

    insert_account(db, account_id=10, username="alice")
    insert_block(db, block_id=1, height=100, blockhash="h1",
                 amount=1.0, share_id=10, confirmations=120)

    db.execute(
        "INSERT INTO transactions (account_id, type, amount, "
        " block_id, archived, timestamp) "
        "VALUES (10, 'Credit', 1.0, 1, 1, NOW())"
    )
    db.execute(
        "INSERT INTO transactions (account_id, type, amount, "
        " timestamp) VALUES (10, 'Credit_PPS', 0.25, NOW())"
    )

    bal = db.compute_balance(10, min_confirmations=100)
    # archived Credit doesn't count; Credit_PPS does.
    assert abs(bal["confirmed"] - 0.25) < 1e-9, bal


@pytest.mark.needs_mariadb
def test_pps_types_always_count_regardless_of_block_confirmations(fresh_db: Db) -> None:
    """Credit_PPS / Donation_PPS / Fee_PPS / TXFee should always count
    — they're not gated on block confirmations because PPS payouts
    are paid per-share, not per-block."""
    db = fresh_db

    insert_account(db, account_id=10, username="alice")
    # No block — all PPS rows have block_id NULL.
    db.execute(
        "INSERT INTO transactions (account_id, type, amount, "
        " timestamp) VALUES (10, 'Credit_PPS', 1.0, NOW())"
    )
    db.execute(
        "INSERT INTO transactions (account_id, type, amount, "
        " timestamp) VALUES (10, 'Donation_PPS', 0.05, NOW())"
    )
    db.execute(
        "INSERT INTO transactions (account_id, type, amount, "
        " timestamp) VALUES (10, 'Fee_PPS', 0.02, NOW())"
    )
    db.execute(
        "INSERT INTO transactions (account_id, type, amount, "
        " timestamp) VALUES (10, 'TXFee', 0.001, NOW())"
    )

    bal = db.compute_balance(10, min_confirmations=100)
    # 1.0 - 0.05 - 0.02 - 0.001 = 0.929
    assert abs(bal["confirmed"] - 0.929) < 1e-9, bal
