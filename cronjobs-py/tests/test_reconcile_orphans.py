"""Replay tests for the outbox orphan recovery job.

An orphan is an outbox row whose `sendtoaddress` succeeded but whose
Debit/TXFee/archive commit then rolled back: coins on-chain, row stuck
at 'pending', user balance never debited. `reconcile-orphans`:

  1. heals a row matched to a real wallet send (by txid, then by comment)
     — writes the missing Debit/TXFee, closes the manual request, flips to
     'broadcast' for reconcile-payouts;
  2. abandons a placeholder-anchor row (provably no send was issued);
  3. NEVER auto-abandons a real-anchor row with no wallet match (a wallet
     rebuild could hide a real send -> double-pay) — leaves it for the
     operator;
  4. clears the slot poison flag once nothing unresolved remains, but
     keeps it set while an operator-flagged row lingers.

MariaDB-backed (skipped without CRONJOBS_PY_TEST_DSN; see conftest).
"""

from __future__ import annotations

import pytest

from cronjobs_py.db import Db
from cronjobs_py.scheduler import JobContext
from cronjobs_py.jobs.reconcile_orphans import ReconcileOrphans
from tests.conftest import insert_account, insert_block


class _OrphanRpc:
    """Stub wallet. `by_txid` / `by_comment` map the lookup keys the job
    uses to a send record, or None to simulate 'wallet has no such send'.
    """

    def __init__(self, *, by_txid=None, by_comment=None):
        self._by_txid = by_txid or {}
        self._by_comment = by_comment or {}
        self.calls: list[tuple] = []

    def get_send_by_txid(self, txid):
        self.calls.append(("get_send_by_txid", txid))
        return self._by_txid.get(txid)

    def find_send_by_comment(self, comment, *, address=None):
        self.calls.append(("find_send_by_comment", comment, address))
        return self._by_comment.get(comment)


def _ctx(fresh_db: Db, rpc) -> JobContext:
    from cronjobs_py.settings import Settings, DbConfig

    s = Settings(
        php_config_path="/dev/null",  # type: ignore
        db=DbConfig("", 0, "", "", ""),
        coins=[],
        reward=0.0,
        reward_type="block",
        block_bonus=0.0,
        raw={"confirmations": 100},
    )
    return JobContext(settings=s, db=fresh_db, rpc_by_slot={"": rpc}, cache=None)


def _insert_orphan(db: Db, *, account_id: int, comment: str,
                   tx_kind: str = "Debit_AP", amount: float = 0.9,
                   txid: str | None = None,
                   manual_payout_id: int | None = None,
                   send_attempted: bool = True) -> int:
    outbox_id = db.insert_outbox_pending(
        slot="", account_id=account_id, coin_address="addr_a",
        amount=amount, wallet_comment=comment, archive_on_reconcile=True,
        tx_kind=tx_kind, manual_payout_id=manual_payout_id,
    )
    # Most orphans are post-send-attempt (send may have broadcast); the
    # no-send abandon cases pass send_attempted=False.
    if send_attempted:
        db.mark_outbox_send_attempted(outbox_id)
    if txid:
        db.set_outbox_txid_pending(outbox_id, txid)
    return outbox_id


def _outbox(db: Db, outbox_id: int) -> dict:
    return db.fetchone(
        "SELECT * FROM transactions_outbox WHERE id = %s", (outbox_id,)
    )


def _txns(db: Db, account_id: int) -> list[dict]:
    return db.fetchall(
        "SELECT type, amount, txid FROM transactions "
        "WHERE account_id = %s ORDER BY id", (account_id,)
    )


def test_heal_by_txid_writes_debit_and_txfee(fresh_db: Db) -> None:
    insert_account(fresh_db, account_id=10, username="alice",
                   coin_address="addr_a", ap_threshold=0.5)
    outbox_id = _insert_orphan(
        fresh_db, account_id=10, comment="mpos::10:1:aaaa1111",
        tx_kind="Debit_AP", amount=0.9, txid="healtx1",
    )
    rpc = _OrphanRpc(by_txid={
        "healtx1": {"txid": "healtx1", "net": 0.9, "fee": 0.1,
                    "confirmations": 3},
    })

    ReconcileOrphans(slot="", grace_seconds=0).run(_ctx(fresh_db, rpc))

    row = _outbox(fresh_db, outbox_id)
    assert row["status"] == "broadcast"
    assert row["txid"] == "healtx1"
    kinds = {(t["type"], float(t["amount"]), t["txid"]) for t in _txns(fresh_db, 10)}
    assert ("Debit_AP", 0.9, "healtx1") in kinds
    assert ("TXFee", 0.1, "healtx1") in kinds


def test_heal_by_comment_closes_manual_request(fresh_db: Db) -> None:
    insert_account(fresh_db, account_id=11, username="bob",
                   coin_address="addr_a", ap_threshold=0.5)
    fresh_db.execute(
        "INSERT INTO payouts (id, account_id, completed) VALUES (77, 11, 0)"
    )
    outbox_id = _insert_orphan(
        fresh_db, account_id=11, comment="mpos::11:2:bbbb2222",
        tx_kind="Debit_MP", amount=0.8, txid=None, manual_payout_id=77,
    )
    rpc = _OrphanRpc(by_comment={
        "mpos::11:2:bbbb2222": {"txid": "healtx2", "net": 0.8, "fee": 0.05,
                                "confirmations": 1, "address": "addr_a"},
    })

    ReconcileOrphans(slot="", grace_seconds=0).run(_ctx(fresh_db, rpc))

    row = _outbox(fresh_db, outbox_id)
    assert row["status"] == "broadcast"
    assert row["txid"] == "healtx2"
    kinds = {(t["type"], float(t["amount"])) for t in _txns(fresh_db, 11)}
    assert ("Debit_MP", 0.8) in kinds
    assert ("TXFee", 0.05) in kinds
    payout = fresh_db.fetchone("SELECT completed FROM payouts WHERE id = 77")
    assert int(payout["completed"]) == 1


def test_unsent_row_is_abandoned(fresh_db: Db) -> None:
    # Real anchor, but send_attempted=0 -> the send was never issued
    # (crash between insert and the send) -> provably safe to abandon.
    insert_account(fresh_db, account_id=12, username="carol",
                   coin_address="addr_a", ap_threshold=0.5)
    outbox_id = _insert_orphan(
        fresh_db, account_id=12, comment="mpos::12:6:ffff6666",
        tx_kind="Debit_AP", amount=0.7, send_attempted=False,
    )
    rpc = _OrphanRpc()

    ReconcileOrphans(slot="", grace_seconds=0).run(_ctx(fresh_db, rpc))

    row = _outbox(fresh_db, outbox_id)
    assert row["status"] == "abandoned"
    assert _txns(fresh_db, 12) == []
    assert rpc.calls == []  # no wallet lookup for a provably-unsent row


def test_legacy_placeholder_anchor_is_abandoned(fresh_db: Db) -> None:
    # Backward-compat: a pre-marker placeholder anchor is still abandoned.
    insert_account(fresh_db, account_id=17, username="heidi",
                   coin_address="addr_a", ap_threshold=0.5)
    outbox_id = _insert_orphan(
        fresh_db, account_id=17, comment="pending:deadbeefcafe0001",
        tx_kind="Debit_AP", amount=0.7, send_attempted=False,
    )
    rpc = _OrphanRpc()

    ReconcileOrphans(slot="", grace_seconds=0).run(_ctx(fresh_db, rpc))

    row = _outbox(fresh_db, outbox_id)
    assert row["status"] == "abandoned"
    assert _txns(fresh_db, 17) == []
    assert rpc.calls == []


def test_real_anchor_no_match_is_left_for_operator(fresh_db: Db) -> None:
    insert_account(fresh_db, account_id=13, username="dave",
                   coin_address="addr_a", ap_threshold=0.5)
    outbox_id = _insert_orphan(
        fresh_db, account_id=13, comment="mpos::13:3:cccc3333",
        tx_kind="Debit_AP", amount=0.6, txid="ghosttx",
    )
    # Wallet knows nothing about this txid or comment.
    rpc = _OrphanRpc()

    ReconcileOrphans(slot="", grace_seconds=0).run(_ctx(fresh_db, rpc))

    row = _outbox(fresh_db, outbox_id)
    # Must stay unresolved: abandoning could double-pay if the wallet
    # rebuilt and lost the record of a real send.
    assert row["status"] == "pending"
    assert _txns(fresh_db, 13) == []


def test_grace_window_skips_fresh_rows(fresh_db: Db) -> None:
    insert_account(fresh_db, account_id=14, username="erin",
                   coin_address="addr_a", ap_threshold=0.5)
    outbox_id = _insert_orphan(
        fresh_db, account_id=14, comment="pending:freshrow00000001",
        amount=0.5,
    )
    rpc = _OrphanRpc()

    # 1-hour grace: a row just inserted is far younger, so it's untouched.
    ReconcileOrphans(slot="", grace_seconds=3600).run(_ctx(fresh_db, rpc))

    assert _outbox(fresh_db, outbox_id)["status"] == "pending"


def test_poison_cleared_when_nothing_unresolved(fresh_db: Db) -> None:
    insert_account(fresh_db, account_id=15, username="frank",
                   coin_address="addr_a", ap_threshold=0.5)
    outbox_id = _insert_orphan(
        fresh_db, account_id=15, comment="mpos::15:4:dddd4444",
        tx_kind="Debit_AP", amount=0.9, txid="healtx5",
    )
    fresh_db.set_disabled_flag("slot:", "payouts E0094 orphan", set_by="payouts-parent")
    rpc = _OrphanRpc(by_txid={
        "healtx5": {"txid": "healtx5", "net": 0.9, "fee": 0.1,
                    "confirmations": 3},
    })

    ReconcileOrphans(slot="", grace_seconds=0).run(_ctx(fresh_db, rpc))

    assert _outbox(fresh_db, outbox_id)["status"] == "broadcast"
    # Healed -> no unresolved rows -> poison cleared.
    assert fresh_db.get_disabled_flag("slot:") is None


def test_poison_held_while_operator_row_lingers(fresh_db: Db) -> None:
    insert_account(fresh_db, account_id=16, username="grace",
                   coin_address="addr_a", ap_threshold=0.5)
    _insert_orphan(
        fresh_db, account_id=16, comment="mpos::16:5:eeee5555",
        tx_kind="Debit_AP", amount=0.6, txid="ghosttx2",
    )
    fresh_db.set_disabled_flag("slot:", "payouts E0094 orphan", set_by="payouts-parent")
    rpc = _OrphanRpc()  # no match -> operator-flagged, row stays pending

    ReconcileOrphans(slot="", grace_seconds=0).run(_ctx(fresh_db, rpc))

    # Unresolved row remains -> poison must NOT be cleared.
    assert fresh_db.get_disabled_flag("slot:") is not None


def test_queue_excludes_account_with_indeterminate_outbox(fresh_db: Db) -> None:
    """An account with an 'indeterminate' outbox row is excluded from BOTH
    payout queues (defense in depth alongside the preflight Fatal)."""
    insert_account(fresh_db, account_id=30, username="ivy",
                   coin_address="addr_a", ap_threshold=0.5)
    insert_block(fresh_db, block_id=1, height=100, blockhash="h1",
                 amount=1.0, share_id=30, confirmations=120)
    fresh_db.execute(
        "INSERT INTO transactions (account_id, type, amount, block_id, "
        " timestamp) VALUES (30, 'Credit', 1.0, 1, NOW())")

    def in_auto():
        return any(int(r["id"]) == 30 for r in fresh_db.get_accounts_above_threshold(
            "", min_confirmations=100, txfee_auto=0.0))

    def in_manual():
        return any(int(r["account_id"]) == 30 for r in fresh_db.get_manual_payout_queue(
            "", min_confirmations=100, txfee_manual=0.0))

    # AUTO queue is payable (no open manual request, no outbox row yet).
    assert in_auto()
    ob = fresh_db.insert_outbox_pending(
        slot="", account_id=30, coin_address="addr_a", amount=0.9,
        wallet_comment="mpos::30:i:indet0001", tx_kind="Debit_AP")
    fresh_db.mark_outbox_send_attempted(ob)
    fresh_db.mark_outbox_indeterminate(ob, "timeout after submit")
    assert not in_auto()  # indeterminate row removes it from the auto queue

    # MANUAL queue: open a cash-out request. With the indeterminate row present
    # it must also be excluded; flipping the row to a terminal status
    # (abandoned) re-enables the queue, proving the indeterminate row is the
    # cause (not the request itself).
    fresh_db.execute("INSERT INTO payouts (account_id, completed) VALUES (30, 0)")
    assert not in_manual()
    fresh_db.execute(
        "UPDATE transactions_outbox SET status='abandoned' WHERE id=%s", (ob,))
    assert in_manual()


# ---- adversarial edge cases ----

def test_payouts_queue_excludes_account_with_pending_orphan(fresh_db: Db) -> None:
    """Concurrency safety: while a pending orphan exists for an account, the
    payouts queue must not select it — that is what stops a heal racing a
    fresh payout into a double-pay. (edge case: heal vs payout concurrency.)"""
    insert_account(fresh_db, account_id=20, username="ivan",
                   coin_address="addr_a", ap_threshold=0.5)
    insert_block(fresh_db, block_id=1, height=100, blockhash="h1",
                 amount=1.0, share_id=20, confirmations=120)
    fresh_db.execute(
        "INSERT INTO transactions (account_id, type, amount, block_id, "
        " timestamp) VALUES (20, 'Credit', 1.0, 1, NOW())"
    )
    # No outbox row yet -> the account is payable.
    before = fresh_db.get_accounts_above_threshold(
        "", min_confirmations=100, txfee_auto=0.0)
    assert any(int(r["id"]) == 20 for r in before)

    # A pending orphan for the same account must remove it from the queue.
    _insert_orphan(fresh_db, account_id=20, comment="mpos::20:7:aaaa7777",
                   tx_kind="Debit_AP", amount=0.9, txid="racetx")
    after = fresh_db.get_accounts_above_threshold(
        "", min_confirmations=100, txfee_auto=0.0)
    assert not any(int(r["id"]) == 20 for r in after)

    # Operator clears the slot poison flag WITHOUT reconciling the orphan
    # (the dangerous manual move). The payout queue must STILL exclude the
    # account, because the NOT EXISTS guard keys off the pending outbox row,
    # not the poison flag -> no automatic double-pay.
    # (edge case: operator clears poison without reconciling.)
    fresh_db.set_disabled_flag("slot:", "x", set_by="payouts-parent")
    fresh_db.clear_disabled_flag("slot:")
    still = fresh_db.get_accounts_above_threshold(
        "", min_confirmations=100, txfee_auto=0.0)
    assert not any(int(r["id"]) == 20 for r in still)


def test_heal_does_not_duplicate_an_existing_debit(fresh_db: Db) -> None:
    """Idempotency: if a Debit for this txid already exists (e.g. a prior
    partial heal), heal flips the row to broadcast but writes NO second
    Debit/TXFee. (edge case: heal idempotency vs duplicate Debit.)"""
    insert_account(fresh_db, account_id=21, username="judy",
                   coin_address="addr_a", ap_threshold=0.5)
    outbox_id = _insert_orphan(
        fresh_db, account_id=21, comment="mpos::21:8:bbbb8888",
        tx_kind="Debit_AP", amount=0.9, txid="duptx")
    # Pre-existing Debit for the same txid/account.
    fresh_db.execute(
        "INSERT INTO transactions (account_id, type, amount, txid, "
        " timestamp) VALUES (21, 'Debit_AP', 0.9, 'duptx', NOW())"
    )
    rpc = _OrphanRpc(by_txid={
        "duptx": {"txid": "duptx", "net": 0.9, "fee": 0.1, "confirmations": 3},
    })

    ReconcileOrphans(slot="", grace_seconds=0).run(_ctx(fresh_db, rpc))

    assert _outbox(fresh_db, outbox_id)["status"] == "broadcast"
    debits = fresh_db.fetchone(
        "SELECT COUNT(*) AS n FROM transactions "
        "WHERE txid='duptx' AND type='Debit_AP'")
    assert int(debits["n"]) == 1  # no duplicate
    txfees = fresh_db.fetchone(
        "SELECT COUNT(*) AS n FROM transactions "
        "WHERE txid='duptx' AND type='TXFee'")
    assert int(txfees["n"]) == 0  # guarded insert skipped both


def test_multi_slot_orphans_heal_independently(fresh_db: Db) -> None:
    """Two slots, two orphans: each heals into its own per-slot ledger and
    the poison flag is per-slot. (edge case: multi-slot independence.)"""
    insert_account(fresh_db, account_id=22, username="mallory",
                   coin_address="addr_a", ap_threshold=0.5)

    ob_parent = _insert_orphan(
        fresh_db, account_id=22, comment="mpos::22:9:cccc9999",
        tx_kind="Debit_AP", amount=0.9, txid="ptx")
    ob_mm = fresh_db.insert_outbox_pending(
        slot="mm", account_id=22, coin_address="addr_a", amount=0.5,
        wallet_comment="mpos:mm:22:dddd0000", archive_on_reconcile=True,
        tx_kind="Debit_AP")
    fresh_db.mark_outbox_send_attempted(ob_mm)
    fresh_db.execute(
        "UPDATE transactions_outbox SET txid='mtx' WHERE id=%s", (ob_mm,))

    fresh_db.set_disabled_flag("slot:", "x", set_by="payouts-parent")
    fresh_db.set_disabled_flag("slot:mm", "x", set_by="payouts-mm")

    rpc = _OrphanRpc(by_txid={
        "ptx": {"txid": "ptx", "net": 0.9, "fee": 0.1, "confirmations": 3},
        "mtx": {"txid": "mtx", "net": 0.5, "fee": 0.05, "confirmations": 3},
    })

    ReconcileOrphans(slot="", grace_seconds=0).run(_ctx(fresh_db, rpc))
    # Parent healed + parent poison cleared; mm still pending + mm poison held.
    assert _outbox(fresh_db, ob_parent)["status"] == "broadcast"
    assert _outbox(fresh_db, ob_mm)["status"] == "pending"
    assert fresh_db.get_disabled_flag("slot:") is None
    assert fresh_db.get_disabled_flag("slot:mm") is not None

    # Now run the mm slot job (its rpc is in rpc_by_slot under "mm").
    ctx_mm = _ctx(fresh_db, rpc)
    ctx_mm.rpc_by_slot["mm"] = rpc
    ReconcileOrphans(slot="mm", grace_seconds=0).run(ctx_mm)
    assert _outbox(fresh_db, ob_mm)["status"] == "broadcast"
    assert fresh_db.get_disabled_flag("slot:mm") is None
    # Each Debit landed in its own per-slot table.
    p = fresh_db.fetchone(
        "SELECT COUNT(*) AS n FROM transactions WHERE txid='ptx' AND type='Debit_AP'")
    m = fresh_db.fetchone(
        "SELECT COUNT(*) AS n FROM transactions_mm WHERE txid='mtx' AND type='Debit_AP'")
    assert int(p["n"]) == 1 and int(m["n"]) == 1
