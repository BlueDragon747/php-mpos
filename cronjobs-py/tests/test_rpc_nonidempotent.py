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

    def post(self, *_args, **_kwargs):
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
