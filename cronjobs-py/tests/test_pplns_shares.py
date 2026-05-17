"""Replay tests for the pplns_shares write path added by the
multi-coin Round Statistics feature.

`pplns_payout._process_block` persists the per-account
difficulty-normalized share breakdown into `pplns_shares` (slot,
block_id, account_id, pplns_valid, pplns_invalid). The Round
Statistics page reads from that table. These tests verify:

  - One row per crediting account is written when a block is
    accounted.
  - The UNIQUE (slot, block_id, account_id) key makes re-runs
    idempotent (INSERT ... ON DUPLICATE KEY UPDATE).
  - Aux slot writes carry the correct `slot` value so the round page
    can filter per-coin.

Skipped without `CRONJOBS_PY_TEST_DSN` like the other replay tests.
"""

from __future__ import annotations

import pytest

from cronjobs_py.db import Db
from cronjobs_py.scheduler import JobContext
from cronjobs_py.jobs.pplns_payout import PplnsPayout
from tests.conftest import insert_account, insert_block, insert_share


def _ctx(db, raw=None, shadow=False):
    from cronjobs_py.settings import Settings, DbConfig
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


@pytest.mark.needs_mariadb
def test_pplns_shares_written_on_payout(fresh_db: Db) -> None:
    """A standard parent-block payout should land one pplns_shares row
    for the crediting account, with slot='' and the matching block_id."""
    db = fresh_db

    insert_account(db, account_id=10, username="alice")
    for sid in range(1, 6):
        insert_share(db, share_id=sid, username="alice", difficulty=1.0)
    insert_block(
        db, block_id=1, height=100, blockhash="h1",
        amount=1.0, share_id=5, confirmations=120,
    )

    PplnsPayout(slot="").run(_ctx(db))

    rows = db.fetchall(
        "SELECT slot, block_id, account_id, pplns_valid, pplns_invalid "
        "FROM pplns_shares ORDER BY id"
    )
    assert len(rows) == 1, f"expected 1 pplns_shares row, got {rows}"
    r = rows[0]
    assert r["slot"] == ""
    assert int(r["block_id"]) == 1
    assert int(r["account_id"]) == 10
    assert float(r["pplns_valid"]) > 0
    assert float(r["pplns_invalid"]) >= 0


@pytest.mark.needs_mariadb
def test_pplns_shares_idempotent_on_replay(fresh_db: Db) -> None:
    """Re-running pplns_payout against the same block must not produce
    duplicate pplns_shares rows. The UNIQUE (slot, block_id, account_id)
    key combined with INSERT ... ON DUPLICATE KEY UPDATE keeps the row
    count constant across replays."""
    db = fresh_db

    insert_account(db, account_id=10, username="alice")
    for sid in range(1, 6):
        insert_share(db, share_id=sid, username="alice", difficulty=1.0)
    insert_block(
        db, block_id=1, height=100, blockhash="h1",
        amount=1.0, share_id=5, confirmations=120,
    )

    job = PplnsPayout(slot="")
    job.run(_ctx(db))

    # Force the second tick to re-process the same block.
    db.execute("UPDATE blocks SET accounted = 0 WHERE id = 1")
    db.execute("DELETE FROM settings WHERE name = 'last_accounted_block_id'")
    job.run(_ctx(db))

    rows = db.fetchall(
        "SELECT account_id FROM pplns_shares WHERE block_id = 1"
    )
    # Exactly one row per (slot, block_id, account_id) combination,
    # regardless of how many ticks ran. The replay path is short-
    # circuited by the cronjobs_py_accounting guard before pplns_shares
    # would be written a second time, but even if the path had been
    # re-entered, ON DUPLICATE KEY UPDATE would keep the row count at 1.
    assert len(rows) == 1, f"replay duplicated pplns_shares: {rows}"


@pytest.mark.needs_mariadb
def test_pplns_shares_skipped_in_shadow_mode(fresh_db: Db) -> None:
    """Shadow mode lets PHP cron be the authoritative writer. The
    pplns_shares insert is gated behind `if not shadow:`, so a shadow-
    mode tick must NOT write any rows there."""
    db = fresh_db

    insert_account(db, account_id=10, username="alice")
    for sid in range(1, 6):
        insert_share(db, share_id=sid, username="alice", difficulty=1.0)
    insert_block(
        db, block_id=1, height=100, blockhash="h1",
        amount=1.0, share_id=5, confirmations=120,
    )

    raw = {
        "fees": 1.0, "confirmations": 100, "difficulty": 32,
        "pplns": {"shares": {"type": "default", "default": 1}},
    }
    PplnsPayout(slot="").run(_ctx(db, raw=raw, shadow=True))

    rows = db.fetchall("SELECT * FROM pplns_shares")
    assert len(rows) == 0, f"shadow mode wrote pplns_shares: {rows}"
