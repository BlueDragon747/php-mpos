from __future__ import annotations

import pytest

from cronjobs_py.errors import Fatal, Indeterminate, Skip
from cronjobs_py.jobs.liquid_payout import LiquidPayout


class _Settings:
    shadow_mode = False
    raw = {
        "confirmations": 100,
        "coldwallet": {
            "address": "cold_addr",
            "reserve": 20,
            "threshold": 1,
        },
    }


class _Rpc:
    def __init__(self, *, balance: float = 100.0, send_result="cold_txid"):
        self.balance = balance
        self.send_result = send_result
        self.calls: list[tuple] = []

    def validateaddress(self, address):
        self.calls.append(("validateaddress", (address,)))
        return {"isvalid": True}

    def call(self, method, *params):
        self.calls.append((method, params))
        if method == "getbalance":
            return self.balance
        raise AssertionError(f"unexpected idempotent RPC: {method}")

    def sendtoaddress(self, address, amount, comment="", comment_to="",
                      subtract_fee_from_amount=False):
        self.calls.append((
            "sendtoaddress",
            (address, amount, comment, comment_to, subtract_fee_from_amount),
        ))
        if isinstance(self.send_result, Exception):
            raise self.send_result
        return self.send_result


class _Db:
    def __init__(self, *, locked: float = 10.0, open_sweeps=None):
        self.locked = locked
        self.open_sweeps = open_sweeps or []
        self.inserted: list[dict] = []
        self.updated_comments: list[tuple[str, int]] = []
        self.broadcast: list[tuple[int, str]] = []
        self.indeterminate: list[tuple[int, str]] = []
        self.abandoned: list[tuple[int, str]] = []
        self.send_attempted: list[int] = []

    def list_open_coldwallet_outbox(self, slot):
        return self.open_sweeps

    def get_locked_balance(self, slot, *, min_confirmations):
        return self.locked

    def insert_outbox_pending(self, **kwargs):
        outbox_id = len(self.inserted) + 1
        self.inserted.append({"id": outbox_id, **kwargs})
        return outbox_id

    def mark_outbox_send_attempted(self, outbox_id):
        self.send_attempted.append(outbox_id)

    def mark_outbox_broadcast(self, outbox_id, txid):
        self.broadcast.append((outbox_id, txid))

    def mark_outbox_indeterminate(self, outbox_id, rpc_error):
        self.indeterminate.append((outbox_id, rpc_error))

    def mark_outbox_abandoned(self, outbox_id, reason):
        self.abandoned.append((outbox_id, reason))


class _Ctx:
    def __init__(self, *, rpc, db):
        self.settings = _Settings()
        self._rpc = rpc
        self.db = db

    def rpc(self, slot):
        return self._rpc


def test_liquid_payout_uses_outbox_and_non_retry_send() -> None:
    rpc = _Rpc(balance=100.0, send_result="cold_txid")
    db = _Db(locked=10.0)
    ctx = _Ctx(rpc=rpc, db=db)

    LiquidPayout(slot="").run(ctx)

    assert len(db.inserted) == 1
    assert db.inserted[0]["account_id"] == 0
    assert db.inserted[0]["coin_address"] == "cold_addr"
    assert db.inserted[0]["amount"] == 70.0
    assert db.inserted[0]["archive_on_reconcile"] is False
    # Final wallet_comment is written atomically in the INSERT (no separate
    # UPDATE), and send_attempted is flipped before the send.
    assert db.inserted[0]["wallet_comment"].startswith("mpos-sweep::")
    assert db.send_attempted == [1]
    assert db.broadcast == [(1, "cold_txid")]
    send_calls = [c for c in rpc.calls if c[0] == "sendtoaddress"]
    assert len(send_calls) == 1
    assert send_calls[0][1][0] == "cold_addr"
    assert send_calls[0][1][1] == 70.0
    assert send_calls[0][1][2].startswith("mpos-sweep::")
    # The sweep fee comes out of the swept amount, not the reserve.
    assert send_calls[0][1][4] is True  # subtract_fee_from_amount


def test_liquid_payout_indeterminate_marks_outbox_and_fails_closed() -> None:
    rpc = _Rpc(
        balance=100.0,
        send_result=Indeterminate("timeout after submit"),
    )
    db = _Db(locked=10.0)
    ctx = _Ctx(rpc=rpc, db=db)

    with pytest.raises(Fatal, match="indeterminate"):
        LiquidPayout(slot="").run(ctx)

    assert db.indeterminate == [(1, "timeout after submit")]
    assert db.broadcast == []


def test_liquid_payout_waits_for_existing_broadcast_sweep() -> None:
    rpc = _Rpc(balance=100.0)
    db = _Db(open_sweeps=[{
        "id": 7,
        "status": "broadcast",
        "txid": "existing_txid",
    }])
    ctx = _Ctx(rpc=rpc, db=db)

    with pytest.raises(Skip, match="already broadcast"):
        LiquidPayout(slot="").run(ctx)

    assert rpc.calls == []
    assert db.inserted == []
