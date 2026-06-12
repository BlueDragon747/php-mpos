"""The per-job overlap GET_LOCK must survive a mid-tick reconnect.

MySQL/MariaDB advisory locks (GET_LOCK) are connection-scoped: when a
connection closes, its locks release. The scheduler runs the job body on
`self.db`, whose `_run_with_retry` closes+reopens the connection on a
transient error — so if the overlap lock lived on `self.db` it would be
silently dropped mid-tick and two ticks of a coin-moving job could overlap.
The fix holds the lock on a dedicated `self.lock_db` connection the job body
never touches.
"""

from __future__ import annotations

from cronjobs_py.db import Db


def test_scheduler_uses_separate_lock_connection() -> None:
    """The overlap lock connection must be a distinct Db from the one jobs
    run their queries on. (No DB needed — construction is lazy.)"""
    from cronjobs_py.scheduler import Scheduler
    from cronjobs_py.settings import Settings, DbConfig

    s = Scheduler(Settings(
        php_config_path="/dev/null",  # type: ignore
        db=DbConfig("", 0, "", "", ""),
        coins=[],
        reward=0.0,
        reward_type="block",
        block_bonus=0.0,
        raw={},
    ))
    assert isinstance(s.db, Db)
    assert isinstance(s.lock_db, Db)
    assert s.lock_db is not s.db


def test_advisory_lock_survives_main_connection_reconnect(fresh_db: Db) -> None:
    """Hold the lock on a dedicated connection; reconnect the job's own
    connection; the lock must still be held by a competing connection's
    standard. (DB-backed.)"""
    lock_db = Db(fresh_db.cfg)
    other = Db(fresh_db.cfg)
    job_db = fresh_db
    scope = "job:overlap-test"
    try:
        # Lock acquired on the dedicated connection.
        assert lock_db.try_advisory_lock(scope, timeout=0) is True
        # Another connection cannot take it.
        assert other.try_advisory_lock(scope, timeout=0) is False

        # Simulate a mid-tick reconnect on the JOB's own connection.
        job_db.close()
        assert job_db.fetchone("SELECT 1 AS x")["x"] == 1  # reconnects

        # The lock must STILL be held by lock_db (the bug was it released here).
        assert other.try_advisory_lock(scope, timeout=0) is False

        # Releasing from the holder frees it.
        assert lock_db.release_advisory_lock(scope) is True
        assert other.try_advisory_lock(scope, timeout=0) is True
        other.release_advisory_lock(scope)
    finally:
        lock_db.close()
        other.close()
