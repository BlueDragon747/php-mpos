r"""Wave 4 replay-test fixtures.

These tests need a real MariaDB instance because the diff-normalised
PPLNS code paths use MariaDB-specific running-total user variables
(`@total := @total + ...`) that don't translate to SQLite. Each test
gets a fresh schema in a temp database — no shared state between tests.

Configure the fixture via `CRONJOBS_PY_TEST_DSN` env var:

    CRONJOBS_PY_TEST_DSN=user:pass@host:port

If unset, tests are SKIPPED (so `pytest` against a checkout without a
MariaDB still passes). On the dev box the operator can:

    sudo mariadb -e "CREATE USER IF NOT EXISTS 'cjpy_test'@'localhost' IDENTIFIED BY 'cjpy_test';"
    sudo mariadb -e "GRANT ALL PRIVILEGES ON \`cjpy_test_%\`.* TO 'cjpy_test'@'localhost';"
    export CRONJOBS_PY_TEST_DSN=cjpy_test:cjpy_test@127.0.0.1:3306

Each test gets its own database name `cjpy_test_<random>` which is
DROP'd after the test. Schema is loaded from MPOS's
`sql/database_blank.sql` plus our Wave 1 migration
`deploy-bundle/sql/01-cronjobs-py-wave1.sql`.
"""

from __future__ import annotations

import os
import secrets
from pathlib import Path

import pytest

try:
    import pymysql  # noqa: F401
except ImportError:
    pytest.skip("pymysql not installed", allow_module_level=True)

from cronjobs_py.db import Db
from cronjobs_py.settings import DbConfig

REPO_ROOT = Path(__file__).resolve().parent.parent.parent


def _parse_dsn(dsn: str) -> dict:
    """Parse user:pass@host:port (no path) into kwargs for pymysql."""
    if "@" not in dsn:
        raise ValueError(f"DSN must be user:pass@host:port; got {dsn!r}")
    creds, hostport = dsn.split("@", 1)
    if ":" not in creds:
        raise ValueError(f"DSN must include password: user:pass@host:port; got {dsn!r}")
    user, password = creds.split(":", 1)
    if ":" in hostport:
        host, port = hostport.split(":", 1)
        port = int(port)
    else:
        host, port = hostport, 3306
    return {"host": host, "port": port, "user": user, "password": password}


def _admin_connect(dsn_kwargs: dict):
    import pymysql
    return pymysql.connect(
        host=dsn_kwargs["host"], port=dsn_kwargs["port"],
        user=dsn_kwargs["user"], password=dsn_kwargs["password"],
        autocommit=True,
    )


@pytest.fixture(scope="session")
def _dsn_kwargs() -> dict:
    dsn = os.environ.get("CRONJOBS_PY_TEST_DSN")
    if not dsn:
        pytest.skip(
            "set CRONJOBS_PY_TEST_DSN=user:pass@host:port to run "
            "MariaDB-backed replay tests"
        )
    return _parse_dsn(dsn)


@pytest.fixture
def fresh_db(_dsn_kwargs):
    """One isolated test database per test, with the MPOS schema +
    Wave 1 migration applied.

    Schema files:
      - sql/database_blank.sql (MPOS upstream)
      - deploy-bundle/sql/01-cronjobs-py-wave1.sql (our additions)

    Yields a `Db` instance pointed at the temp database. Drops the
    database on teardown.
    """
    suffix = secrets.token_hex(4)
    db_name = f"cjpy_test_{suffix}"

    admin = _admin_connect(_dsn_kwargs)
    try:
        with admin.cursor() as cur:
            cur.execute(
                f"CREATE DATABASE `{db_name}` "
                f"DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci"
            )
            cur.execute(f"USE `{db_name}`")
            for schema_file in (
                REPO_ROOT / "sql" / "database_blank.sql",
                REPO_ROOT / "deploy-bundle" / "sql" / "01-cronjobs-py-wave1.sql",
                REPO_ROOT / "deploy-bundle" / "sql" / "02-cronjobs-py-wave5.sql",
                REPO_ROOT / "deploy-bundle" / "sql" / "03-pplns-shares.sql",
            ):
                if not schema_file.exists():
                    pytest.skip(f"missing schema file: {schema_file}")
                _apply_sql_file(cur, schema_file)
    finally:
        admin.close()

    db = Db(DbConfig(
        host=_dsn_kwargs["host"], port=_dsn_kwargs["port"],
        user=_dsn_kwargs["user"], password=_dsn_kwargs["password"],
        database=db_name,
    ))
    try:
        yield db
    finally:
        db.close()
        admin = _admin_connect(_dsn_kwargs)
        try:
            with admin.cursor() as cur:
                cur.execute(f"DROP DATABASE IF EXISTS `{db_name}`")
        finally:
            admin.close()


def _apply_sql_file(cur, path: Path) -> None:
    """Apply a .sql file via the cursor. MPOS's `database_blank.sql`
    starts with `CREATE DATABASE` + `USE` lines that we must skip
    (the test database already exists and is selected). Skip those
    and `LOCK TABLES` / `UNLOCK TABLES` / `SET ...` administrative
    lines too.
    """
    sql = path.read_text()
    statements = []
    current: list[str] = []
    for line in sql.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("--") or stripped.startswith("/*"):
            continue
        current.append(line)
        if stripped.endswith(";"):
            statements.append("\n".join(current))
            current = []
    if current:
        statements.append("\n".join(current))

    SKIP_PREFIXES = (
        "CREATE DATABASE", "DROP DATABASE", "USE ",
        "LOCK TABLES", "UNLOCK TABLES",
        "SET @", "SET NAMES", "SET FOREIGN_KEY_CHECKS",
        "SET SQL_MODE", "SET TIME_ZONE", "SET CHARACTER",
        "/*!", "DELIMITER",
    )
    for stmt in statements:
        s = stmt.strip().rstrip(";").strip()
        if not s:
            continue
        upper = s.upper()
        if any(upper.startswith(p) for p in SKIP_PREFIXES):
            continue
        try:
            cur.execute(s)
        except Exception as exc:
            raise RuntimeError(
                f"failed to apply statement from {path.name}: "
                f"{exc}\n--- statement ---\n{s[:400]}"
            ) from exc


# ---- helpers shared across replay tests ----

def insert_account(db: Db, *, username: str, account_id: int | None = None,
                   donate_percent: float = 0.0,
                   no_fees: bool = False,
                   is_locked: int = 0,
                   coin_address: str = "",
                   ap_threshold: float = 1.0) -> int:
    """Insert one accounts row; return the new id.

    The MPOS accounts table has a UNIQUE on `email` — give each test
    user a unique placeholder so multiple inserts in one test don't
    collide.
    """
    email = f"{username}@test.local"
    cur = db._connect().cursor()
    if account_id is not None:
        cur.execute(
            "INSERT INTO accounts (id, username, pass, pin, email, "
            " donate_percent, no_fees, is_locked, coin_address, ap_threshold) "
            "VALUES (%s, %s, '', '', %s, %s, %s, %s, %s, %s)",
            (account_id, username, email, donate_percent,
             int(no_fees), is_locked, coin_address, ap_threshold),
        )
        return account_id
    cur.execute(
        "INSERT INTO accounts (username, pass, pin, email, "
        " donate_percent, no_fees, is_locked, coin_address, ap_threshold) "
        "VALUES (%s, '', '', %s, %s, %s, %s, %s, %s)",
        (username, email, donate_percent, int(no_fees), is_locked,
         coin_address, ap_threshold),
    )
    return int(cur.lastrowid)


def insert_share(db: Db, *, share_id: int, username: str,
                 difficulty: float = 1.0, our_result: str = "Y",
                 upstream_result: str = "N",
                 time_offset: int = 0) -> None:
    """Insert one row into `shares`. `time_offset` lets the test
    arrange the temporal ordering relative to NOW().

    The MPOS `shares` schema declares `rem_host` and `solution` as
    NOT NULL with no default — fill them with placeholder values so
    strict-mode MariaDB doesn't reject the insert.
    """
    cur = db._connect().cursor()
    cur.execute(
        "INSERT INTO shares (id, rem_host, username, our_result, "
        " upstream_result, solution, time, difficulty) "
        "VALUES (%s, %s, %s, %s, %s, %s, "
        " DATE_SUB(NOW(), INTERVAL %s SECOND), %s)",
        (share_id, "127.0.0.1", username, our_result, upstream_result,
         "test_solution", time_offset, difficulty),
    )


def insert_shares_archive_row(db: Db, *, share_id: int, username: str,
                              difficulty: float = 1.0, our_result: str = "Y",
                              upstream_result: str = "N",
                              block_id: int | None = None,
                              time_offset: int = 0) -> None:
    """Insert one row into `shares_archive` directly.

    Real archives are populated by the pplns_payout job moving rows
    out of `shares` after a block is accounted; this helper lets a
    test set up the post-archive state without driving the full job.
    """
    cur = db._connect().cursor()
    cur.execute(
        "INSERT INTO shares_archive (share_id, username, our_result, "
        " upstream_result, block_id, difficulty, time) "
        "VALUES (%s, %s, %s, %s, %s, %s, "
        " DATE_SUB(NOW(), INTERVAL %s SECOND))",
        (share_id, username, our_result, upstream_result,
         block_id if block_id is not None else 0, difficulty, time_offset),
    )


def insert_block(db: Db, *, block_id: int, height: int, blockhash: str,
                 amount: float, share_id: int | None,
                 confirmations: int = 120,
                 account_id: int | None = None,
                 accounted: int = 0) -> None:
    cur = db._connect().cursor()
    cur.execute(
        "INSERT INTO blocks (id, height, blockhash, amount, "
        " confirmations, share_id, account_id, accounted, "
        " difficulty, time) "
        "VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 1.0, UNIX_TIMESTAMP())",
        (block_id, height, blockhash, amount, confirmations, share_id,
         account_id, accounted),
    )
