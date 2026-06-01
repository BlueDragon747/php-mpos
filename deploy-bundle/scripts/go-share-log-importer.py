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
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

import pymysql


DEFAULT_SHARE_LOG = "/var/log/blakestream-eliopool-25.2-go/shares.log"
DEFAULT_STATE_FILE = "/var/lib/blakestream-mpos/go-share-log-importer.state"
DEFAULT_BATCH_SIZE = 2000
DEFAULT_POLL_SECONDS = 1.0
DEFAULT_WORKER_REFRESH_SECONDS = 30.0

GO_DIFF1_TARGET = int(
    "00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffff", 16
)

RUNNING = True


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


def refresh_workers(conn: pymysql.Connection) -> set[str]:
    with conn.cursor() as cur:
        cur.execute("SELECT username FROM pool_worker")
        workers = {str(row[0]) for row in cur.fetchall() if row and row[0]}
    conn.commit()
    logging.info("loaded %d MPOS worker name(s)", len(workers))
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


def insert_rows(conn: pymysql.Connection, rows: Iterable[ShareRow]) -> int:
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
        return 0
    sql = (
        "INSERT INTO shares "
        "(rem_host, username, our_result, upstream_result, reason, solution, difficulty, time) "
        "VALUES (%s, %s, %s, %s, %s, %s, %s, %s)"
    )
    with conn.cursor() as cur:
        cur.executemany(sql, values)
    conn.commit()
    return len(values)


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

    conn = db_connect()
    workers = refresh_workers(conn)
    next_worker_refresh = time.monotonic() + worker_refresh_seconds
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
                    workers = refresh_workers(conn)
                    next_worker_refresh = time.monotonic() + worker_refresh_seconds

                pos = fh.tell()
                line = fh.readline()
                if line == "":
                    if batch:
                        inserted_total += insert_rows(conn, batch)
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
                if row.username not in workers:
                    skipped_unknown += 1
                    continue
                batch.append(row)

                if len(batch) >= batch_size:
                    inserted_total += insert_rows(conn, batch)
                    save_state(state_path, dev=st.st_dev, ino=st.st_ino, offset=fh.tell())
                    logging.info(
                        "imported %d share(s), total=%d, skipped_unknown=%d",
                        len(batch),
                        inserted_total,
                        skipped_unknown,
                    )
                    batch.clear()

            if batch:
                inserted_total += insert_rows(conn, batch)
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
            workers = refresh_workers(conn)
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
