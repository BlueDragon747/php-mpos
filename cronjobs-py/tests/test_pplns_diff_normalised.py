"""Wave 4 replay test: vardiff PPLNS distribution.

Covers QC C-3: the Wave 1 implementation row-counted shares for the
PPLNS proportional split, which mis-distributed under vardiff. Wave 2
added diff-normalised counterparts.

Scenario: two miners mine the same block.
  alice — 10 shares at difficulty 1     → diff-normalised credit = 10
  bob   — 1  share  at difficulty 100   → diff-normalised credit = 100

Block reward 0.5 BLC. Expected:
  bob   gets 100/110 = ~90.909% = ~0.45454545
  alice gets  10/110 =  ~9.091% = ~0.04545454

Wave 1's row-counter would have given alice 10/11 (~90.9%) and bob
1/11 (~9.1%) — the inverse of correctness.
"""

from __future__ import annotations

import pytest

from cronjobs_py.db import Db
from tests.conftest import insert_account, insert_block, insert_share


@pytest.mark.needs_mariadb
def test_diff_normalised_round_distribution(fresh_db: Db) -> None:
    db = fresh_db

    insert_account(db, account_id=10, username="alice", coin_address="addr_a")
    insert_account(db, account_id=20, username="bob", coin_address="addr_b")

    # 10 shares @ diff=1 from alice; 1 share @ diff=100 from bob.
    sid = 1
    for _ in range(10):
        insert_share(db, share_id=sid, username="alice", difficulty=1.0)
        sid += 1
    insert_share(db, share_id=sid, username="bob", difficulty=100.0)

    # Block at share_id=11. Reward 0.5 BLC.
    insert_block(
        db, block_id=1, height=100,
        blockhash="hash_block_100", amount=0.5,
        share_id=11, confirmations=120,
    )

    # Round window (0, 11], difficulty_const=32 (Blakecoin).
    rows = db.round_share_breakdown_diff(0, 11, difficulty_const=32)
    by_user = {r["username"]: r for r in rows}

    # diff-normalised valid counts:
    #   alice = 10 * 1   /  2^(32-16) = 10 / 65536 = 0.00015259
    #   bob   = 1  * 100 /  2^(32-16) =100 / 65536 = 0.00152588
    # Either way the ratio is 10:100 = 1:10. Bob gets ~10× alice.
    alice_v = by_user["alice"]["valid"]
    bob_v = by_user["bob"]["valid"]
    assert alice_v > 0 and bob_v > 0
    # Bob got 10x alice's diff-weight, so bob's pplns share is 10x.
    ratio = bob_v / alice_v
    assert 9.5 < ratio < 10.5, f"expected ratio ~10, got {ratio:.3f}"


@pytest.mark.needs_mariadb
def test_diff_normalised_total_matches_get_round_shares(fresh_db: Db) -> None:
    """`get_round_shares_diff` and the per-account breakdown should
    agree on the round total. (Two paths to the same number; if they
    disagree, one is wrong.)"""
    db = fresh_db

    insert_account(db, account_id=10, username="alice")
    insert_account(db, account_id=20, username="bob")
    insert_share(db, share_id=1, username="alice", difficulty=4.0)
    insert_share(db, share_id=2, username="bob", difficulty=16.0)
    insert_share(db, share_id=3, username="alice", difficulty=4.0)

    total = db.get_round_shares_diff(0, 3, difficulty_const=32)
    rows = db.round_share_breakdown_diff(0, 3, difficulty_const=32)
    sum_valid = sum(r["valid"] for r in rows)

    assert abs(total - sum_valid) < 1e-9, (
        f"get_round_shares_diff={total} but breakdown sum={sum_valid}"
    )
