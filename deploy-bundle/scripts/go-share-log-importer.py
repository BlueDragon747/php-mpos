#!/usr/bin/env python3
"""Import accepted Go Eloipool share-log rows into MPOS MariaDB.

The 25.2 Go pool writes accepted shares as tab-separated rows. Legacy MPOS
expects accepted shares in the MariaDB `shares` table, so this bridge tails the
Go log and inserts rows for known MPOS workers only.
"""

from __future__ import annotations

import json
import logging
import os
import signal
import sys
import time
from collections import defaultdict
from dataclasses import dataclass, replace
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

import pymysql


DEFAULT_SHARE_LOG = "/var/log/blakestream-eliopool-25.2-go/shares.log"
DEFAULT_STATE_FILE = "/var/lib/blakestream-mpos/go-share-log-importer.state"
DEFAULT_BATCH_SIZE = 2000
DEFAULT_POLL_SECONDS = 1.0
DEFAULT_WORKER_REFRESH_SECONDS = 30.0
DEFAULT_DB_MAX_ATTEMPTS = 3
DEFAULT_DB_BACKOFF_SECONDS = 0.2

GO_DIFF1_TARGET = int(
    "00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffff", 16
)

RUNNING = True

RETRYABLE_MYSQL_CODES = {
    1040,  # too many connections
    1042,  # unable to connect to host
    1043,  # bad handshake
    1053,  # server shutdown
    1205,  # lock wait timeout
    1213,  # deadlock
    2003,  # cannot connect
    2006,  # server has gone away
    2013,  # lost connection
    2014,  # commands out of sync
}


@dataclass(frozen=True)
class ShareRow:
    rem_host: str
    username: str
    our_result: str
    upstream_result: str
    reason: str | None
    solution: str
    difficulty: float
    time_utc: str


def stop(_signum: int, _frame: object) -> None:
    global RUNNING
    RUNNING = False


def env(name: str, default: str | None = None, *, required: bool = False) -> str:
    value = os.environ.get(name, default)
    if required and (value is None or value == ""):
        raise SystemExit(f"missing required environment variable {name}")
    return "" if value is None else value


def env_int(name: str, default: int) -> int:
    raw = env(name, str(default))
    try:
        value = int(raw)
    except ValueError as exc:
        raise SystemExit(f"{name} must be an integer, got {raw!r}") from exc
    if value <= 0:
        raise SystemExit(f"{name} must be positive")
    return value


def env_float(name: str, default: float) -> float:
    raw = env(name, str(default))
    try:
        value = float(raw)
    except ValueError as exc:
        raise SystemExit(f"{name} must be a number, got {raw!r}") from exc
    if value <= 0:
        raise SystemExit(f"{name} must be positive")
    return value


def env_bool(name: str, default: bool) -> bool:
    raw = env(name, "1" if default else "0").strip().lower()
    if raw in {"1", "true", "yes", "on"}:
        return True
    if raw in {"0", "false", "no", "off"}:
        return False
    raise SystemExit(f"{name} must be a boolean, got {raw!r}")


def db_connect() -> pymysql.Connection:
    conn = pymysql.connect(
        host=env("MPOS_DB_HOST", "127.0.0.1"),
        port=env_int("MPOS_DB_PORT", 3306),
        user=env("MPOS_DB_USER", required=True),
        password=env("MPOS_DB_PASS", required=True),
        database=env("MPOS_DB_NAME", "mpos"),
        autocommit=False,
        charset="utf8mb4",
        cursorclass=pymysql.cursors.Cursor,
        read_timeout=20,
        write_timeout=20,
    )
    with conn.cursor() as cur:
        cur.execute("SET time_zone = '+00:00'")
    return conn


def is_retryable_db_error(exc: BaseException) -> bool:
    if isinstance(exc, pymysql.err.InterfaceError):
        return True
    if not isinstance(exc, pymysql.MySQLError):
        return False
    code = exc.args[0] if exc.args else None
    return code in RETRYABLE_MYSQL_CODES


def reconnect(conn: pymysql.Connection) -> pymysql.Connection:
    try:
        conn.close()
    except Exception:
        pass
    return db_connect()


def load_state(path: Path) -> dict[str, int]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    except (OSError, json.JSONDecodeError) as exc:
        logging.warning("could not read state file %s: %s", path, exc)
        return {}
    return {
        "dev": int(raw.get("dev", -1)),
        "ino": int(raw.get("ino", -1)),
        "offset": int(raw.get("offset", 0)),
    }


def save_state(path: Path, *, dev: int, ino: int, offset: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(
        json.dumps({"dev": dev, "ino": ino, "offset": offset}, separators=(",", ":")),
        encoding="utf-8",
    )
    os.replace(tmp, path)


def build_worker_lookup(
    worker_names: Iterable[str],
    *,
    allow_bare_suffixes: bool = True,
) -> dict[str, str]:
    """Return accepted share-log names mapped to canonical MPOS workers.

    Go Eloipool may log only the worker suffix for miners authenticated as
    ``account.worker``. Exact MPOS worker names are always preferred, and bare
    suffix aliases are accepted only when they identify one full worker.
    """
    exact = {str(name) for name in worker_names if name}
    lookup = {name: name for name in exact}
    if not allow_bare_suffixes:
        return lookup

    suffixes: dict[str, set[str]] = defaultdict(set)
    for name in exact:
        if "." not in name:
            continue
        _account, suffix = name.split(".", 1)
        if suffix:
            suffixes[suffix].add(name)

    for suffix, matches in suffixes.items():
        if suffix not in lookup and len(matches) == 1:
            lookup[suffix] = next(iter(matches))
    return lookup


def refresh_workers(
    conn: pymysql.Connection,
    *,
    allow_bare_suffixes: bool = True,
) -> dict[str, str]:
    with conn.cursor() as cur:
        cur.execute("SELECT username FROM pool_worker")
        worker_names = [str(row[0]) for row in cur.fetchall() if row and row[0]]
    conn.commit()
    workers = build_worker_lookup(
        worker_names,
        allow_bare_suffixes=allow_bare_suffixes,
    )
    alias_count = max(0, len(workers) - len(worker_names))
    logging.info(
        "loaded %d MPOS worker name(s), %d unique suffix alias(es)",
        len(worker_names),
        alias_count,
    )
    return workers


def difficulty_from_target(target_hex: str) -> float:
    target_hex = target_hex.strip()
    if len(target_hex) != 64:
        return 1.0
    try:
        target = int(target_hex, 16)
    except ValueError:
        return 1.0
    if target <= 0:
        return 1.0
    difficulty = GO_DIFF1_TARGET / target
    if difficulty <= 0:
        return 1.0
    return round(difficulty, 8)


def parse_share(line: str) -> ShareRow | None:
    parts = line.rstrip("\n").split("\t")
    if len(parts) != 8:
        logging.warning("skipping malformed share row with %d field(s)", len(parts))
        return None
    ts, remote, username, _job_id, solution, target, _bits, parent = parts
    username = username.strip()
    solution = solution.strip().upper()
    if not username or not solution:
        return None
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        logging.warning("skipping share with invalid timestamp %r", ts)
        return None
    time_utc = dt.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    return ShareRow(
        rem_host=remote.strip()[:255],
        username=username[:120],
        our_result="Y",
        upstream_result="Y" if parent.strip().lower() == "parent=true" else "N",
        reason=None,
        solution=solution[:257],
        difficulty=difficulty_from_target(target),
        time_utc=time_utc,
    )


def insert_rows(
    conn: pymysql.Connection,
    rows: Iterable[ShareRow],
    *,
    max_attempts: int = DEFAULT_DB_MAX_ATTEMPTS,
    backoff_seconds: float = DEFAULT_DB_BACKOFF_SECONDS,
) -> tuple[pymysql.Connection, int]:
    values = [
        (
            row.rem_host,
            row.username,
            row.our_result,
            row.upstream_result,
            row.reason,
            row.solution,
            row.difficulty,
            row.time_utc,
        )
        for row in rows
    ]
    if not values:
        return conn, 0
    sql = (
        "INSERT INTO shares "
        "(rem_host, username, our_result, upstream_result, reason, solution, difficulty, time) "
        "VALUES (%s, %s, %s, %s, %s, %s, %s, %s)"
    )
    for attempt in range(1, max_attempts + 1):
        try:
            with conn.cursor() as cur:
                cur.executemany(sql, values)
            conn.commit()
            return conn, len(values)
        except pymysql.MySQLError as exc:
            try:
                conn.rollback()
            except pymysql.MySQLError:
                pass
            if not is_retryable_db_error(exc) or attempt >= max_attempts:
                raise
            delay = backoff_seconds * (2 ** (attempt - 1))
            logging.warning(
                "share insert transient db error %s on attempt %d/%d; retrying in %.2fs",
                exc,
                attempt,
                max_attempts,
                delay,
            )
            if not getattr(conn, "open", True):
                conn = reconnect(conn)
            time.sleep(delay)
    return conn, 0


def open_at_state(log_path: Path, state_path: Path) -> tuple[object, os.stat_result]:
    state = load_state(state_path)
    st = log_path.stat()
    fh = log_path.open("r", encoding="utf-8", errors="replace")
    offset = int(state.get("offset", 0))
    same_file = state.get("dev") == st.st_dev and state.get("ino") == st.st_ino
    if same_file and 0 <= offset <= st.st_size:
        fh.seek(offset)
    else:
        fh.seek(0)
    logging.info("reading %s from offset %d", log_path, fh.tell())
    return fh, st


def main() -> int:
    logging.basicConfig(
        level=getattr(logging, env("SHARE_IMPORT_LOG_LEVEL", "INFO").upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(message)s",
    )
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    log_path = Path(env("GO_SHARE_LOG_PATH", DEFAULT_SHARE_LOG))
    state_path = Path(env("SHARE_IMPORT_STATE", DEFAULT_STATE_FILE))
    batch_size = env_int("SHARE_IMPORT_BATCH", DEFAULT_BATCH_SIZE)
    poll_seconds = env_float("SHARE_IMPORT_POLL_SECONDS", DEFAULT_POLL_SECONDS)
    worker_refresh_seconds = env_float(
        "SHARE_IMPORT_WORKER_REFRESH_SECONDS", DEFAULT_WORKER_REFRESH_SECONDS
    )
    allow_bare_suffixes = env_bool("SHARE_IMPORT_ALLOW_BARE_SUFFIX_MAPPING", True)
    db_max_attempts = env_int("SHARE_IMPORT_DB_MAX_ATTEMPTS", DEFAULT_DB_MAX_ATTEMPTS)
    db_backoff_seconds = env_float(
        "SHARE_IMPORT_DB_BACKOFF_SECONDS", DEFAULT_DB_BACKOFF_SECONDS
    )

    conn = db_connect()
    workers = refresh_workers(conn, allow_bare_suffixes=allow_bare_suffixes)
    next_worker_refresh = time.monotonic() + worker_refresh_seconds
    mapped_aliases_seen: set[tuple[str, str]] = set()
    inserted_total = 0
    skipped_unknown = 0

    while RUNNING:
        try:
            fh, st = open_at_state(log_path, state_path)
        except FileNotFoundError:
            logging.warning("share log %s does not exist yet", log_path)
            time.sleep(poll_seconds)
            continue

        batch: list[ShareRow] = []
        try:
            while RUNNING:
                if time.monotonic() >= next_worker_refresh:
                    workers = refresh_workers(
                        conn,
                        allow_bare_suffixes=allow_bare_suffixes,
                    )
                    next_worker_refresh = time.monotonic() + worker_refresh_seconds

                pos = fh.tell()
                line = fh.readline()
                if line == "":
                    if batch:
                        conn, inserted = insert_rows(
                            conn,
                            batch,
                            max_attempts=db_max_attempts,
                            backoff_seconds=db_backoff_seconds,
                        )
                        inserted_total += inserted
                        logging.info(
                            "imported %d share(s), total=%d, skipped_unknown=%d",
                            len(batch),
                            inserted_total,
                            skipped_unknown,
                        )
                        batch.clear()
                    save_state(state_path, dev=st.st_dev, ino=st.st_ino, offset=fh.tell())
                    time.sleep(poll_seconds)
                    current = log_path.stat()
                    if (
                        current.st_dev != st.st_dev
                        or current.st_ino != st.st_ino
                        or current.st_size < fh.tell()
                    ):
                        logging.info("share log rotated or truncated; reopening")
                        break
                    continue
                if not line.endswith("\n"):
                    fh.seek(pos)
                    time.sleep(poll_seconds)
                    continue

                row = parse_share(line)
                if row is None:
                    continue
                canonical_username = workers.get(row.username)
                if canonical_username is None:
                    skipped_unknown += 1
                    if skipped_unknown <= 5 or skipped_unknown % 1000 == 0:
                        logging.warning(
                            "skipping unknown share username %r, skipped_unknown=%d",
                            row.username,
                            skipped_unknown,
                        )
                    continue
                if canonical_username != row.username:
                    alias_key = (row.username, canonical_username)
                    if alias_key not in mapped_aliases_seen:
                        mapped_aliases_seen.add(alias_key)
                        logging.info(
                            "mapped bare share username %r to MPOS worker %r",
                            row.username,
                            canonical_username,
                        )
                    row = replace(row, username=canonical_username[:120])
                batch.append(row)

                if len(batch) >= batch_size:
                    conn, inserted = insert_rows(
                        conn,
                        batch,
                        max_attempts=db_max_attempts,
                        backoff_seconds=db_backoff_seconds,
                    )
                    inserted_total += inserted
                    save_state(state_path, dev=st.st_dev, ino=st.st_ino, offset=fh.tell())
                    logging.info(
                        "imported %d share(s), total=%d, skipped_unknown=%d",
                        len(batch),
                        inserted_total,
                        skipped_unknown,
                    )
                    batch.clear()

            if batch:
                conn, inserted = insert_rows(
                    conn,
                    batch,
                    max_attempts=db_max_attempts,
                    backoff_seconds=db_backoff_seconds,
                )
                inserted_total += inserted
                save_state(state_path, dev=st.st_dev, ino=st.st_ino, offset=fh.tell())
                logging.info(
                    "imported %d share(s), total=%d, skipped_unknown=%d",
                    len(batch),
                    inserted_total,
                    skipped_unknown,
                )
        except pymysql.MySQLError as exc:
            try:
                conn.rollback()
            except pymysql.MySQLError:
                pass
            logging.error("database error: %s; reconnecting", exc)
            try:
                conn.close()
            except Exception:
                pass
            time.sleep(poll_seconds)
            conn = db_connect()
            workers = refresh_workers(conn, allow_bare_suffixes=allow_bare_suffixes)
            next_worker_refresh = time.monotonic() + worker_refresh_seconds
        finally:
            try:
                fh.close()
            except Exception:
                pass

    conn.close()
    logging.info("stopped")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        sys.exit(0)
