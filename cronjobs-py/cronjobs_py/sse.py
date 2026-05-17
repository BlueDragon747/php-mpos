"""SSE side-car for the MPOS dashboard.

Runs as a separate process (`cronjobs-py sse`) listening on
127.0.0.1:8090. Nginx proxies `/sse/*` to it. Web clients open one
`EventSource('/sse/pool')` connection and receive a stream of
`type: share | block | hello | keepalive` events.

Why SSE and not WebSockets:
  - One-way (server→client) is exactly what the dashboard needs.
  - Travels over a single long-lived HTTP/1.1 GET; works through
    nginx with `proxy_buffering off` and no `Upgrade:` header dance.
  - Browser-side is one line: `new EventSource(url).onmessage = ...`

Why not just AJAX poll faster:
  - The dashboard's existing 10–15 s polling already loads memcached
    plenty. Going to 1 s polling would multiply that load 10–15×;
    SSE pushes the same data with one DB poll thread shared across
    every viewer.

Architecture:
  - One `EventBus` per process (in-memory pub/sub, thread-safe).
  - One DB poller thread per event source (shares, blocks). Each
    polls every N seconds, fans out new rows to the bus.
  - The HTTP request handler subscribes a `queue.Queue` to the bus
    and translates events to SSE wire format. Pings every 30 s to
    keep nginx's idle timer happy.
  - Each subscriber's queue has a hard cap (default 200 events). On
    overflow we drop the oldest event so a slow client can't grow
    memory without bound.

Connecting from the web UI:
  - Add `<script src="/site_assets/mpos/js/sse-live.js"></script>` to
    the dashboard / pool workers / blocks pages. The JS opens
    EventSource('/sse/pool') and updates DOM cells with `data-sse`
    attributes.
"""

from __future__ import annotations

import json
import logging
import queue
import signal
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from socketserver import ThreadingMixIn

from .db import Db
from .rpc import RpcClient
from .settings import Settings, load

log = logging.getLogger(__name__)


# ---- per-process pub/sub ------------------------------------------------

class EventBus:
    """One queue per subscriber; publishers fan-out to every queue.

    Subscribers (HTTP handlers) call `subscribe()` to get a Queue,
    then read from it until disconnect. Publishers (DB pollers) call
    `publish(event)` — the call is non-blocking; if any subscriber's
    queue is full, the oldest event is dropped to make room.
    """

    def __init__(self, capacity_per_subscriber: int = 200) -> None:
        self._lock = threading.Lock()
        self._subs: list[queue.Queue] = []
        self._cap = capacity_per_subscriber

    def subscribe(self) -> queue.Queue:
        q: queue.Queue = queue.Queue(maxsize=self._cap)
        with self._lock:
            self._subs.append(q)
        return q

    def unsubscribe(self, q: queue.Queue) -> None:
        with self._lock:
            try:
                self._subs.remove(q)
            except ValueError:
                pass

    def subscriber_count(self) -> int:
        with self._lock:
            return len(self._subs)

    def publish(self, event: dict) -> None:
        with self._lock:
            subs = list(self._subs)
        for q in subs:
            try:
                q.put_nowait(event)
            except queue.Full:
                # Drop oldest, then push. Best-effort under contention;
                # if another thread wins between the two ops we just
                # skip this subscriber for this event.
                try:
                    q.get_nowait()
                except queue.Empty:
                    pass
                try:
                    q.put_nowait(event)
                except queue.Full:
                    pass


# ---- DB pollers ---------------------------------------------------------

class _StoppableThread(threading.Thread):
    def __init__(self, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self._stop = threading.Event()

    def stop(self) -> None:
        self._stop.set()


class _Poller(_StoppableThread):
    """Single poller thread that interleaves share + block polls
    against ONE PyMySQL connection.

    Earlier versions ran SharePoller and BlockPoller as separate
    threads, each with its own Db. PyMySQL's connection state isn't
    safely sharable across threads even when the *connection objects*
    are independent — under concurrent pings the protocol's
    sequence-number invariant breaks (`Packet sequence number wrong`).
    Combining the two pollers into one thread sidesteps all of that
    while the cadence (every 2s for shares, every 5s for blocks) is
    still well within useful real-time bounds.
    """

    SLOTS = ("", "mm", "mm1", "mm3", "mm4", "mm5")

    def __init__(self, db_cfg, bus: EventBus, *,
                 share_interval: float = 2.0,
                 block_interval: float = 5.0,
                 stats_interval: float = 10.0,
                 share_batch_limit: int = 500,
                 settings: Settings | None = None) -> None:
        super().__init__(daemon=True, name="sse-poller")
        self.db_cfg = db_cfg
        self.bus = bus
        self.share_interval = share_interval
        self.block_interval = block_interval
        # Stats event drives the live dashboard gauges. The
        # dashboard's hashrate dials don't change visually on
        # individual share events — they need a current pool /
        # network hashrate value to call JustGage `.refresh()`.
        self.stats_interval = stats_interval
        self.share_batch_limit = share_batch_limit
        # Used to compute hashrate (target_bits + difficulty
        # constants from MPOS config). And to find the parent-chain
        # RPC for the network hashrate query.
        self.settings = settings
        self._last_share_id: int | None = None
        self._last_block_id_by_slot: dict[str, int] = {}
        # Lazy-instantiated parent-chain RPC client for getnetworkhashps.
        self._parent_rpc = None

    def _init_cursors(self, db: Db) -> None:
        row = db.fetchone("SELECT MAX(id) AS m FROM shares")
        self._last_share_id = int((row or {}).get("m") or 0)
        log.info("share poll starting at id=%d", self._last_share_id)
        for slot in self.SLOTS:
            try:
                table = "blocks" if slot == "" else f"blocks_{slot}"
                row = db.fetchone(f"SELECT MAX(id) AS m FROM {table}")
                self._last_block_id_by_slot[slot] = int((row or {}).get("m") or 0)
            except Exception as exc:
                log.info("BlockPoller: skipping slot %r (%s)", slot, exc)

    def _poll_shares(self, db: Db) -> None:
        rows = db.fetchall(
            "SELECT id, username, our_result, upstream_result, "
            "       difficulty, UNIX_TIMESTAMP(time) AS ts "
            "FROM shares WHERE id > %s ORDER BY id ASC LIMIT %s",
            (self._last_share_id, self.share_batch_limit),
        )
        for r in rows:
            self.bus.publish({
                "type": "share",
                "id": int(r["id"]),
                "username": r.get("username") or "",
                "valid": (r.get("our_result") or "").upper() == "Y",
                "upstream": (r.get("upstream_result") or "").upper() == "Y",
                "difficulty": float(r.get("difficulty") or 0),
                "ts": int(r.get("ts") or 0),
            })
            self._last_share_id = int(r["id"])

    def _poll_blocks(self, db: Db) -> None:
        for slot, last in list(self._last_block_id_by_slot.items()):
            table = "blocks" if slot == "" else f"blocks_{slot}"
            try:
                rows = db.fetchall(
                    f"SELECT id, height, blockhash, amount, "
                    f"       confirmations, account_id, share_id, "
                    f"       UNIX_TIMESTAMP(time) AS ts "
                    f"FROM {table} WHERE id > %s ORDER BY id ASC LIMIT 50",
                    (last,),
                )
            except Exception as exc:
                log.warning("BlockPoller(%r) error: %s", slot, exc)
                continue
            for r in rows:
                self.bus.publish({
                    "type": "block",
                    "slot": slot,
                    "id": int(r["id"]),
                    "height": int(r.get("height") or 0),
                    "blockhash": r.get("blockhash") or "",
                    "amount": float(r.get("amount") or 0),
                    "confirmations": int(r.get("confirmations") or 0),
                    "account_id": int(r["account_id"]) if r.get("account_id") else None,
                    "share_id": int(r["share_id"]) if r.get("share_id") else None,
                    "ts": int(r.get("ts") or 0),
                })
                self._last_block_id_by_slot[slot] = int(r["id"])

    def _publish_stats(self, db: Db) -> None:
        """Compute current pool stats and publish a `stats` event.

        Mirrors the SQL the PHP web UI uses
        (`smarty_globals.inc.php` + `Statistics::getCurrentHashrate`)
        so the dashboard gauges, when refreshed via
        `JustGage.refresh()` in sse-live.js, agree with what a full
        page reload would show.

        Network hashrate comes from the parent-chain daemon's
        `getnetworkhashps` RPC. Falls back to 0 on RPC error so a
        flaky daemon doesn't break the stats stream.
        """
        if self.settings is None:
            return
        target_bits = int(self.settings.raw.get("target_bits", 32))
        difficulty_const = int(self.settings.raw.get("difficulty", 32))
        try:
            pool_kHs = float(db.stats_current_hashrate(
                target_bits=target_bits,
                difficulty_const=difficulty_const,
            ))
        except Exception as exc:
            log.warning("stats: pool hashrate failed: %s", exc)
            pool_kHs = 0.0
        # Network hashrate via parent-chain RPC.
        net_kHs = 0.0
        try:
            if self._parent_rpc is None:
                parent = self.settings.parent()
                self._parent_rpc = RpcClient(parent.endpoint, timeout=4.0)
            # getnetworkhashps returns H/s; convert to kH/s.
            net_kHs = float(self._parent_rpc.call("getnetworkhashps")) / 1000.0
        except Exception as exc:
            log.warning("stats: net hashrate failed: %s", exc)

        # Active workers — accounts that submitted a share recently.
        # Count distinct usernames across the last 5 min of `shares`.
        active = 0
        try:
            row = db.fetchone(
                "SELECT COUNT(DISTINCT username) AS n FROM shares "
                "WHERE time > DATE_SUB(NOW(), INTERVAL 5 MINUTE)"
            )
            active = int((row or {}).get("n") or 0)
        except Exception as exc:
            log.warning("stats: active workers failed: %s", exc)

        self.bus.publish({
            "type": "stats",
            "ts": int(time.time()),
            # Raw kH/s so the JS side can apply whatever modifier
            # the page was rendered with (KH / MH / GH / TH).
            "pool_hashrate_kHs": pool_kHs,
            "net_hashrate_kHs": net_kHs,
            "active_workers": active,
        })

    def run(self) -> None:
        db = Db(self.db_cfg)
        try:
            self._init_cursors(db)
            last_block_poll = 0.0
            last_stats_poll = 0.0
            while not self._stop.is_set():
                t0 = time.time()
                try:
                    self._poll_shares(db)
                except Exception as exc:
                    log.warning("SharePoll error: %s", exc)
                if t0 - last_block_poll >= self.block_interval:
                    try:
                        self._poll_blocks(db)
                    except Exception as exc:
                        log.warning("BlockPoll error: %s", exc)
                    last_block_poll = t0
                if t0 - last_stats_poll >= self.stats_interval:
                    try:
                        self._publish_stats(db)
                    except Exception as exc:
                        log.warning("StatsPoll error: %s", exc)
                    last_stats_poll = t0
                self._stop.wait(self.share_interval)
        finally:
            db.close()
            if self._parent_rpc is not None:
                try:
                    self._parent_rpc.close()
                except Exception:
                    pass


# ---- HTTP handler -------------------------------------------------------

class _Server(ThreadingHTTPServer):
    """Carries the EventBus reference into request handlers."""
    bus: EventBus
    daemon_threads = True
    # Allow rapid bind on restart.
    allow_reuse_address = True


class SSEHandler(BaseHTTPRequestHandler):
    # SSE keepalive cadence. Nginx default proxy_read_timeout is 60s;
    # we ping every 25s so the connection never goes idle long enough
    # to trip it.
    KEEPALIVE_SECONDS = 25
    # Block on the queue for at most this long before checking
    # connection liveness via a comment ping.
    QUEUE_GET_TIMEOUT = 5

    server: _Server  # type: ignore[assignment]

    def do_GET(self) -> None:  # noqa: N802 (stdlib API)
        if self.path == "/sse/health":
            self._respond_json({"status": "ok",
                                "subscribers": self.server.bus.subscriber_count()})
            return
        if self.path != "/sse/pool":
            self.send_response(404)
            self.end_headers()
            return

        self._stream_events()

    def _respond_json(self, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(body)

    def _stream_events(self) -> None:
        bus = self.server.bus
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        # Nginx hint: don't buffer this response (default is on for
        # text/* under proxy_pass; we disable in nginx config too).
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()

        q = bus.subscribe()
        try:
            self._send_event({"type": "hello", "ts": int(time.time())})
            last_ping = time.time()
            while True:
                try:
                    event = q.get(timeout=self.QUEUE_GET_TIMEOUT)
                    self._send_event(event)
                except queue.Empty:
                    pass
                # Periodic SSE comment line keeps the connection
                # warm. Comments are ignored by the browser
                # EventSource API so this is invisible to the JS.
                if time.time() - last_ping >= self.KEEPALIVE_SECONDS:
                    try:
                        self.wfile.write(b": keepalive\n\n")
                        self.wfile.flush()
                    except (BrokenPipeError, ConnectionResetError, OSError):
                        return
                    last_ping = time.time()
        except (BrokenPipeError, ConnectionResetError, OSError):
            return
        finally:
            bus.unsubscribe(q)

    def _send_event(self, event: dict) -> None:
        body = json.dumps(event, separators=(",", ":"))
        # Wire format:  data: <json>\n\n  (one event per blank line)
        # Optionally include id: and event: but we keep payload single-typed.
        self.wfile.write(f"data: {body}\n\n".encode("utf-8"))
        self.wfile.flush()

    # Silence the default per-request log line — they spam the journal
    # at SSE cadence. We keep our own structured log via the Python
    # logger.
    def log_message(self, format: str, *args) -> None:  # noqa: A002
        pass


# ---- entrypoint ---------------------------------------------------------

def serve(*, settings: Settings | None = None,
          bind: str = "127.0.0.1", port: int = 8090,
          share_interval: float = 2.0,
          block_interval: float = 5.0) -> None:
    """Block forever serving SSE. Use cronjobs-py sse subcommand."""
    settings = settings or load()
    bus = EventBus()

    # Single poller thread for shares + blocks. PyMySQL doesn't
    # tolerate concurrent connection use even across separate
    # connection objects in this version.
    pollers = [
        _Poller(settings.db, bus,
                share_interval=share_interval,
                block_interval=block_interval,
                settings=settings),
    ]
    for p in pollers:
        p.start()

    server = _Server((bind, port), SSEHandler)
    server.bus = bus
    log.info("SSE listening on %s:%d (subscribers: 0)", bind, port)

    def _shutdown(*_args) -> None:
        log.info("SSE shutting down")
        for p in pollers:
            p.stop()
        # ThreadingHTTPServer.shutdown blocks until the serve loop
        # exits. Call it from a separate thread so we don't deadlock
        # the signal handler.
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    server.serve_forever()
