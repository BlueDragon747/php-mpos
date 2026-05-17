"""Wave 4 replay test: PHP `Share::getMinimumShareId` parity.

Covers QC C-3 (the over-credit gap when round_valid > target).

The PHP algorithm walks DESC from `current_upstream`, accumulating each
share's diff-weight contribution (`baseline` for difficulty=0,
otherwise the raw difficulty value), and returns MIN(id) where the
cumulative weight is <= `target * baseline`.

For tests we use `difficulty=0` so each share contributes exactly
`baseline = 2^(difficulty_const - 16)` — meaning each share is exactly
"1 unit" when divided by baseline. That makes the math clean: target=50
means "50 raw share-equivalents", and with monotonic ids 1..N all of
difficulty 0, the algorithm returns the share id whose cumulative count
from the top equals 50.
"""

from __future__ import annotations

import pytest

from cronjobs_py.db import Db
from tests.conftest import (
    insert_account, insert_share, insert_shares_archive_row,
)


@pytest.mark.needs_mariadb
def test_minimum_share_id_simple(fresh_db: Db) -> None:
    db = fresh_db

    insert_account(db, account_id=10, username="alice")
    # difficulty=0 → each share is exactly 1 unit (baseline weight).
    for sid in range(1, 101):
        insert_share(db, share_id=sid, username="alice", difficulty=0.0)

    min_id = db.get_minimum_share_id(
        target=50, current_upstream=100, difficulty_const=32,
    )

    # Spec: round window is (min_id - 1, current_upstream], so we want
    # 50 shares credited. With monotonic ids 1..100 each weighing 1
    # baseline unit, min_id should be 51 — meaning the window (50, 100]
    # = ids 51..100 = 50 shares.
    assert min_id == 51, (
        f"expected getMinimumShareId(50, 100) → 51 (so window has 50 "
        f"shares), got {min_id}"
    )


@pytest.mark.needs_mariadb
def test_minimum_share_id_with_invalid_shares_excluded(fresh_db: Db) -> None:
    """Invalid shares (our_result = 'N') should NOT count toward the
    target. Otherwise the round window would shrink to include their
    id range and credits would skip valid earlier shares."""
    db = fresh_db

    insert_account(db, account_id=10, username="alice")
    # 50 valid + 50 invalid + 50 valid; difficulty=0 so each share is
    # exactly 1 unit. Walking DESC from id=150, only 'Y' rows are
    # included (PHP and our SQL filter by our_result='Y').
    for sid in range(1, 51):
        insert_share(db, share_id=sid, username="alice",
                     difficulty=0.0, our_result="Y")
    for sid in range(51, 101):
        insert_share(db, share_id=sid, username="alice",
                     difficulty=0.0, our_result="N")
    for sid in range(101, 151):
        insert_share(db, share_id=sid, username="alice",
                     difficulty=0.0, our_result="Y")

    # Target = 50 valid shares. Walking DESC from 150, the first 50
    # valid shares are ids 150..101 (in DESC order). So min_id = 101.
    min_id = db.get_minimum_share_id(
        target=50, current_upstream=150, difficulty_const=32,
    )
    assert min_id == 101, (
        f"expected min_id=101 (window (100, 150] has 50 valid shares), "
        f"got {min_id}"
    )


@pytest.mark.needs_mariadb
def test_minimum_share_id_with_archived_shares(fresh_db: Db) -> None:
    """H4: aux PPLNS narrowing must work even when the relevant shares
    have already been moved from `shares` to `shares_archive` by an
    earlier parent payout. The pre-fix code only read from live
    `shares` and would skip narrowing in this case, distributing the
    aux block reward across too many shares.
    """
    db = fresh_db

    insert_account(db, account_id=10, username="alice")
    # 50 archived "older" shares (parent already paid + archived them)
    for sid in range(1, 51):
        insert_shares_archive_row(
            db, share_id=sid, username="alice",
            difficulty=0.0, our_result="Y",
        )
    # 50 live shares accumulated AFTER the archive happened
    for sid in range(51, 101):
        insert_share(db, share_id=sid, username="alice",
                     difficulty=0.0, our_result="Y")

    # Aux PPLNS runs against current_upstream=100 with target=50.
    # Walking DESC from id=100, the most-recent 50 valid shares are
    # ids 100..51 (live) — but if `current_upstream` happened to land
    # IN the archive range we would still need to find them. Try both:

    # (1) current_upstream in live range — narrowing across live only
    min_id = db.get_minimum_share_id(
        target=50, current_upstream=100, difficulty_const=32,
    )
    assert min_id == 51, (
        f"target=50 from live range should give min_id=51, got {min_id}"
    )

    # (2) current_upstream IN the archive range — pre-fix this would
    # return 0 (no live shares <= 30); after fix the archived shares
    # are visible too, so we get a real narrowing answer.
    min_id_archive = db.get_minimum_share_id(
        target=20, current_upstream=30, difficulty_const=32,
    )
    assert min_id_archive == 11, (
        f"target=20 from archive range should give min_id=11 "
        f"(archived shares 30..11 = 20 shares), got {min_id_archive}"
    )
