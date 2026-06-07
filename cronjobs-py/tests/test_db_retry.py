import importlib.util
import sys
from pathlib import Path

import pytest
import pymysql

from cronjobs_py.db import Db
from cronjobs_py.settings import DbConfig


REPO_ROOT = Path(__file__).resolve().parent.parent.parent


def load_share_importer():
    path = REPO_ROOT / "deploy-bundle" / "scripts" / "go-share-log-importer.py"
    spec = importlib.util.spec_from_file_location("go_share_log_importer", path)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_db_retryable_codes_accept_any_pymysql_database_error_class():
    db = Db(DbConfig(
        host="127.0.0.1",
        port=3306,
        user="unused",
        password="unused",
        database="unused",
    ))

    assert db._is_retryable_db_error(
        pymysql.err.InternalError(1213, "Deadlock found when trying to get lock")
    )
    assert not db._is_retryable_db_error(
        pymysql.err.ProgrammingError(1064, "syntax error")
    )


class FakeCursor:
    def __init__(self, conn, exc):
        self.conn = conn
        self.exc = exc

    def __enter__(self):
        return self

    def __exit__(self, *_exc):
        return False

    def executemany(self, _sql, _values):
        self.conn.attempts += 1
        if self.conn.attempts == 1 and self.exc is not None:
            raise self.exc


class FakeConn:
    open = True

    def __init__(self, exc=None):
        self.exc = exc
        self.attempts = 0
        self.commits = 0
        self.rollbacks = 0

    def cursor(self):
        return FakeCursor(self, self.exc)

    def commit(self):
        self.commits += 1

    def rollback(self):
        self.rollbacks += 1


def share_row(module):
    return module.ShareRow(
        rem_host="127.0.0.1",
        username="admin.worker",
        our_result="Y",
        upstream_result="N",
        reason=None,
        solution="00",
        difficulty=32.0,
        time_utc="2026-06-06 00:00:00",
    )


def test_share_importer_retries_deadlocked_insert_batch():
    importer = load_share_importer()
    conn = FakeConn(pymysql.err.OperationalError(
        1213,
        "Deadlock found when trying to get lock",
    ))

    returned_conn, inserted = importer.insert_rows(
        conn,
        [share_row(importer)],
        max_attempts=2,
        backoff_seconds=0,
    )

    assert returned_conn is conn
    assert inserted == 1
    assert conn.attempts == 2
    assert conn.rollbacks == 1
    assert conn.commits == 1


def test_share_importer_does_not_retry_non_transient_insert_errors():
    importer = load_share_importer()
    conn = FakeConn(pymysql.err.ProgrammingError(1064, "syntax error"))

    with pytest.raises(pymysql.err.ProgrammingError):
        importer.insert_rows(
            conn,
            [share_row(importer)],
            max_attempts=3,
            backoff_seconds=0,
        )

    assert conn.attempts == 1
    assert conn.rollbacks == 1
    assert conn.commits == 0
