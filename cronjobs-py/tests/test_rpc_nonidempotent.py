from __future__ import annotations

import json

import pytest
import requests

from cronjobs_py.errors import Fatal, Indeterminate
from cronjobs_py.rpc import Endpoint, RpcClient


class _FakeSession:
    def __init__(self, response: requests.Response):
        self.response = response
        self.auth = None
        self.headers = {}
        self.calls = []

    def post(self, *args, **kwargs):
        self.calls.append((args, kwargs))
        return self.response


def _json_response(status: int, body: dict) -> requests.Response:
    resp = requests.Response()
    resp.status_code = status
    resp._content = json.dumps(body).encode("utf-8")
    resp.headers["content-type"] = "application/json"
    resp.url = "http://127.0.0.1:8332/"
    return resp


def _client(response: requests.Response) -> RpcClient:
    client = RpcClient(Endpoint("http://127.0.0.1:8332/", "u", "p", "wallet"))
    client._session = _FakeSession(response)  # type: ignore[assignment]
    return client


def test_nonidempotent_json_rpc_error_on_http_500_is_fatal() -> None:
    client = _client(_json_response(500, {
        "result": None,
        "error": {
            "code": -4,
            "message": "Fee estimation failed. Fallbackfee is disabled.",
        },
        "id": 1,
    }))

    with pytest.raises(Fatal, match="Fee estimation failed"):
        client.call_nonidempotent("sendtoaddress", "addr", 1.0)


def test_nonidempotent_non_json_http_500_stays_indeterminate() -> None:
    resp = requests.Response()
    resp.status_code = 500
    resp._content = b"internal server error"
    resp.url = "http://127.0.0.1:8332/"
    client = _client(resp)

    with pytest.raises(Indeterminate, match="outcome unknown"):
        client.call_nonidempotent("sendtoaddress", "addr", 1.0)


def test_wallet_methods_use_wallet_endpoint_and_node_methods_use_root() -> None:
    response = _json_response(200, {
        "result": "ok",
        "error": None,
        "id": 1,
    })
    fake = _FakeSession(response)
    client = RpcClient(Endpoint(
        "http://127.0.0.1:8332",
        "u",
        "p",
        "wallet",
        wallet_url="http://127.0.0.1:8332/wallet/",
    ))
    client._session = fake  # type: ignore[assignment]

    client.call("getblockcount")
    client.call("getbalance")
    client.call_nonidempotent("sendtoaddress", "addr", 1.0)

    assert fake.calls[0][0][0] == "http://127.0.0.1:8332"
    assert fake.calls[1][0][0] == "http://127.0.0.1:8332/wallet/"
    assert fake.calls[2][0][0] == "http://127.0.0.1:8332/wallet/"


def test_mixed_root_wallet_batch_is_rejected() -> None:
    client = RpcClient(Endpoint(
        "http://127.0.0.1:8332",
        "u",
        "p",
        "wallet",
        wallet_url="http://127.0.0.1:8332/wallet/",
    ))

    with pytest.raises(Fatal, match="mixed root/wallet RPC batch"):
        client.batch([
            ("getblockcount", []),
            ("getbalance", []),
        ])
