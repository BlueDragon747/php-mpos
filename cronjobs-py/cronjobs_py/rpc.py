"""MMP-style JSON-RPC client.

What this gives us over the PHP `BitcoinClient`:

- Persistent HTTP keepalive across calls (each PHP cron forks fresh).
- Built-in retry with exponential backoff for transient errors.
- True batched JSON-RPC (one HTTP round trip for N calls), so a single
  cron tick that needs `getblock` + `validateaddress` + `getbalance` is
  one request, not three.
- Per-call timeout so a hung daemon doesn't pin the whole cronjob.

The interface mirrors `BitcoinClient` enough that porting a PHP cronjob
mostly means replacing `$bitcoin->getblock($h)` with `rpc.getblock(h)`.
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any, Iterable

import requests

from .errors import TRANSIENT_RPC_CODES, Fatal, Indeterminate, Transient
from .logger import get

log = get(__name__)


@dataclass(frozen=True)
class Endpoint:
    url: str
    user: str
    password: str
    label: str = ""

    @property
    def display(self) -> str:
        return self.label or self.url


class RpcClient:
    """One client per coin daemon. Reuses a single HTTP session."""

    def __init__(
        self,
        endpoint: Endpoint,
        *,
        timeout: float = 10.0,
        max_attempts: int = 3,
        backoff_base: float = 1.0,
    ) -> None:
        self.endpoint = endpoint
        self.timeout = timeout
        self.max_attempts = max_attempts
        self.backoff_base = backoff_base
        self._session = requests.Session()
        self._session.auth = (endpoint.user, endpoint.password)
        self._session.headers.update({"content-type": "application/json"})
        self._id = 0

    def close(self) -> None:
        self._session.close()

    def __enter__(self) -> "RpcClient":
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()

    def _next_id(self) -> int:
        self._id += 1
        return self._id

    def call(self, method: str, *params: Any) -> Any:
        """Idempotent JSON-RPC call. Retries on transient failures.

        Use this for read-only RPCs (`getblock`, `getblockcount`,
        `validateaddress`, `getbalance`, etc.) and for stateful RPCs
        whose retry semantics are safe (`importaddress`, etc.).

        For non-idempotent RPCs (`sendtoaddress`, `sendmany`,
        `sendrawtransaction`) use `call_nonidempotent` — those
        MUST NOT be retried on timeout because the daemon may have
        already broadcast the transaction.
        """
        payload = {
            "jsonrpc": "1.0",
            "id": self._next_id(),
            "method": method,
            "params": list(params),
        }
        return self._request_idempotent(payload)["result"]

    def call_nonidempotent(self, method: str, *params: Any) -> Any:
        """Single JSON-RPC call with NO retry on connection error/timeout.

        Use this for any RPC that mutates wallet state or broadcasts a
        transaction. The retry semantics differ from `call()` in one
        critical way: a `requests.Timeout` or `requests.ConnectionError`
        raises `Indeterminate` instead of being retried. The caller is
        expected to have persisted the request in `transactions_outbox`
        BEFORE invoking this method, so a later reconciliation pass
        can match the wallet's listtransactions output back to the
        outbox row via wallet_comment.

        On a clean error response from the daemon (e.g. invalid
        address, insufficient funds, auth failure) we still raise
        Fatal — the daemon explicitly told us it didn't accept the
        request, so retry is not a double-spend hazard.
        """
        payload = {
            "jsonrpc": "1.0",
            "id": self._next_id(),
            "method": method,
            "params": list(params),
        }
        return self._request_nonidempotent(payload, method)["result"]

    def batch(self, calls: Iterable[tuple[str, list[Any]] | tuple[str]]) -> list[Any]:
        """Batched JSON-RPC. Returns results in input order.

        `calls` is an iterable of `(method, [params...])` tuples. A failing
        sub-call raises Fatal, since a partial-success batch is hard to
        reason about — callers can fall back to per-call `call()` when
        they need partial-failure semantics.
        """
        items = list(calls)
        if not items:
            return []
        payload = []
        for entry in items:
            method = entry[0]
            params = list(entry[1]) if len(entry) > 1 else []
            payload.append({
                "jsonrpc": "1.0",
                "id": self._next_id(),
                "method": method,
                "params": params,
            })
        responses = self._request_idempotent(payload, batched=True)
        # Order responses to match input order by id.
        by_id = {r["id"]: r for r in responses}
        out: list[Any] = []
        for req in payload:
            r = by_id.get(req["id"])
            if r is None:
                raise Fatal(f"missing response id={req['id']} method={req['method']}")
            err = r.get("error")
            if err:
                raise Fatal(
                    f"{self.endpoint.display}: batched {req['method']} "
                    f"returned error {err}"
                )
            out.append(r["result"])
        return out

    def _request_idempotent(
        self, payload: Any, *, batched: bool = False
    ) -> Any:
        """Submit and retry on transport failure. Safe ONLY for calls
        whose retry semantics are idempotent — see `call_nonidempotent`
        for the wallet-mutating path that must not retry."""
        last_exc: Exception | None = None
        for attempt in range(1, self.max_attempts + 1):
            try:
                resp = self._session.post(
                    self.endpoint.url,
                    json=payload,
                    timeout=self.timeout,
                )
                resp.raise_for_status()
                body = resp.json()
                # Single-call body is a dict; batch is a list.
                if batched:
                    if not isinstance(body, list):
                        raise Fatal(
                            f"expected batched response, got {type(body).__name__}"
                        )
                    # Surface only transient sub-call errors as Transient;
                    # everything else falls through to the caller as Fatal
                    # via the loop in `batch()`.
                    for r in body:
                        err = r.get("error")
                        if err and err.get("code") in TRANSIENT_RPC_CODES:
                            raise Transient(
                                f"batched sub-call returned transient code "
                                f"{err.get('code')}: {err.get('message')}"
                            )
                    return body
                err = body.get("error")
                if err:
                    code = err.get("code")
                    if code in TRANSIENT_RPC_CODES:
                        raise Transient(
                            f"{payload['method']} returned transient code "
                            f"{code}: {err.get('message')}"
                        )
                    raise Fatal(
                        f"{self.endpoint.display}: {payload['method']} "
                        f"returned error {err}"
                    )
                return body
            except (
                requests.ConnectionError,
                requests.Timeout,
                Transient,
            ) as exc:
                last_exc = exc
                if attempt < self.max_attempts:
                    delay = self.backoff_base * (2 ** (attempt - 1))
                    log.warning(
                        "%s: %s on attempt %d/%d, retrying in %.1fs",
                        self.endpoint.display,
                        exc,
                        attempt,
                        self.max_attempts,
                        delay,
                    )
                    time.sleep(delay)
                continue
        # All attempts exhausted.
        raise Transient(
            f"{self.endpoint.display}: {self.max_attempts} attempts exhausted "
            f"(last error: {last_exc})"
        ) from last_exc

    def _request_nonidempotent(self, payload: Any, method: str) -> Any:
        """One-shot submit. Connection error or timeout raises
        `Indeterminate` (the request may have been broadcast). A
        confirmed daemon error response raises `Fatal` (the daemon
        explicitly rejected the request, so retry is safe but the
        caller should investigate).

        Crucially, `Transient` codes from the daemon are NOT retried
        here either — the caller has to decide whether to retry, and
        whether to coordinate that retry with the outbox state machine
        first.
        """
        try:
            resp = self._session.post(
                self.endpoint.url,
                json=payload,
                timeout=self.timeout,
            )
        except (requests.ConnectionError, requests.Timeout) as exc:
            # Crucial: we have NO idea whether the daemon got the
            # request, processed it, or broadcast it. Caller must
            # treat this as "the wallet may have moved coins" and run
            # reconciliation against the wallet_comment.
            raise Indeterminate(
                f"{self.endpoint.display}: {method} did not return cleanly "
                f"({type(exc).__name__}: {exc}) — outcome unknown, do not retry"
            ) from exc

        try:
            body = resp.json()
        except ValueError as exc:
            try:
                resp.raise_for_status()
            except requests.HTTPError as http_exc:
                # 5xx after submission is indeterminate only when the
                # daemon did not return a JSON-RPC error object. Bitcoin
                # Core uses HTTP 500 for clean wallet rejections too, so
                # JSON errors are handled below as Fatal.
                if 500 <= resp.status_code < 600:
                    raise Indeterminate(
                        f"{self.endpoint.display}: {method} returned HTTP "
                        f"{resp.status_code} — outcome unknown, do not retry"
                    ) from http_exc
                raise Fatal(
                    f"{self.endpoint.display}: {method} returned HTTP "
                    f"{resp.status_code}: {resp.text[:200]}"
                ) from http_exc
            # Non-JSON 200 is a real oddity. Treat as indeterminate to
            # be safe — wallet may still have applied state.
            raise Indeterminate(
                f"{self.endpoint.display}: {method} returned non-JSON "
                f"body — outcome unknown, do not retry"
            ) from exc

        err = body.get("error")
        if err:
            # The daemon answered with an error code. The request was
            # rejected before broadcast (auth, insufficient funds,
            # fee estimation, invalid address). Bitcoin Core commonly
            # returns these JSON-RPC errors with HTTP 500, but the JSON
            # error object is still a clean daemon answer — Fatal so the
            # caller can mark the outbox row abandoned.
            raise Fatal(
                f"{self.endpoint.display}: {method} returned error {err}"
            )
        try:
            resp.raise_for_status()
        except requests.HTTPError as exc:
            if 500 <= resp.status_code < 600:
                raise Indeterminate(
                    f"{self.endpoint.display}: {method} returned HTTP "
                    f"{resp.status_code} — outcome unknown, do not retry"
                ) from exc
            raise Fatal(
                f"{self.endpoint.display}: {method} returned HTTP "
                f"{resp.status_code}: {resp.text[:200]}"
            ) from exc
        return body

    # ---- ergonomic shortcuts mirroring BitcoinClient ----

    def can_connect(self) -> bool:
        try:
            self.call("getinfo")
            return True
        except (Transient, Fatal):
            return False

    def getblock(self, blockhash: str) -> dict:
        return self.call("getblock", blockhash)

    def listsinceblock(self, blockhash: str = "") -> dict:
        if blockhash:
            return self.call("listsinceblock", blockhash)
        return self.call("listsinceblock")

    def validateaddress(self, address: str) -> dict:
        return self.call("validateaddress", address)

    def getbalance(self) -> float:
        return self.call("getbalance")

    def sendtoaddress(self, address: str, amount: float,
                      comment: str = "", comment_to: str = "",
                      subtract_fee_from_amount: bool = False) -> str:
        """Wallet send. ALWAYS routed through the non-idempotent path.

        bitcoind's `sendtoaddress` signature is:
            sendtoaddress "address" amount ( "comment" "comment-to" )
        The `comment` is wallet-local — never goes on chain — but is
        queryable via `listtransactions` / `gettransaction`. We use it
        as the idempotency anchor: callers should pass the
        `wallet_comment` from a `transactions_outbox` row.
        """
        params: list[Any] = [address, amount]
        if comment or comment_to or subtract_fee_from_amount:
            params.extend([comment, comment_to, subtract_fee_from_amount])
        return self.call_nonidempotent("sendtoaddress", *params)

    def walletcreatefundedpsbt(self, address: str, amount: float) -> dict:
        outputs = [{address: f"{amount:.8f}"}]
        options = {"subtractFeeFromOutputs": [0]}
        return self.call(
            "walletcreatefundedpsbt", [], outputs, 0, options, True,
        )
