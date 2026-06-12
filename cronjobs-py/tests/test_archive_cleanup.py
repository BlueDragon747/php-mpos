from __future__ import annotations

from types import SimpleNamespace

from cronjobs_py.db import Db
from cronjobs_py.jobs.archive_cleanup import ArchiveCleanup
from cronjobs_py.settings import DbConfig


class FakeDb:
    def __init__(self, settings=None, deletes=None, *,
                 max_share_id=2_000_000, age_cutoff_share_id=2_000_000,
                 min_unaccounted_share_id=None,
                 unaccounted_blocks=None):
        self.settings = dict(settings or {})
        self.deletes = list(deletes or [])
        self.max_share_id = max_share_id
        self.age_cutoff_share_id = age_cutoff_share_id
        self.min_unaccounted_share_id = min_unaccounted_share_id
        self.unaccounted_blocks = list(unaccounted_blocks or [])
        self.execute_calls = []
        self.fetchone_calls = []
        self.writes = {}

    def get_setting(self, name):
        return self.settings.get(name)

    def get_setting_int(self, name, *, default, floor=0):
        value = self.settings.get(name, default)
        try:
            return max(floor, int(value))
        except (TypeError, ValueError):
            return max(floor, int(default))

    def _shares_archive_table(self, slot):
        return "shares_archive" if slot == "" else f"shares_archive_{slot}"

    def _blocks_table(self, slot):
        return "blocks" if slot == "" else f"blocks_{slot}"

    def fetchone(self, sql, params=()):
        self.fetchone_calls.append((sql, params))
        if "MAX(share_id), 0) AS max_share_id" in sql:
            return {"max_share_id": self.max_share_id}
        if "MAX(share_id), 0) AS cutoff_share_id" in sql:
            return {"cutoff_share_id": self.age_cutoff_share_id}
        if "MIN(share_id) AS min_share_id" in sql:
            if self.unaccounted_blocks:
                include_orphans = "confirmations >= 0" not in sql
                share_ids = [
                    int(row["share_id"])
                    for row in self.unaccounted_blocks
                    if include_orphans or int(row.get("confirmations", 0)) >= 0
                ]
                return {"min_share_id": min(share_ids) if share_ids else None}
            return {"min_share_id": self.min_unaccounted_share_id}
        return {}

    def execute(self, sql, params=()):
        self.execute_calls.append((sql, params))
        return self.deletes.pop(0) if self.deletes else 0

    def set_setting(self, name, value):
        self.writes[name] = str(value)


def _ctx(db, raw=None):
    return SimpleNamespace(settings=SimpleNamespace(raw=raw or {}), db=db)


def test_archive_cleanup_respects_disable_switch():
    db = FakeDb(settings={"db_prune_enabled": "0"}, deletes=[10])

    ArchiveCleanup().run(_ctx(db))

    assert db.execute_calls == []
    assert db.writes == {}


def test_get_setting_int_allows_zero_when_floor_allows():
    db = Db(DbConfig("127.0.0.1", 3306, "mpos", "", "mpos"))
    db.fetchone = lambda *_args, **_kwargs: {"value": "0"}  # type: ignore[method-assign]

    assert db.get_setting_int("db_prune_enabled", default=1, floor=0) == 0
    assert db.get_setting_int("db_prune_after_days", default=180, floor=1) == 1


def test_archive_cleanup_deletes_in_bounded_batches_and_records_status():
    db = FakeDb(
        settings={
            "db_prune_after_days": "90",
            "db_prune_keep_recent_blocks": "25",
            "db_prune_keep_recent_shares": "1000000",
            "db_prune_batch_size": "1000",
            "db_prune_max_batches": "3",
        },
        deletes=[1000, 1000, 1000],
    )

    ArchiveCleanup().run(_ctx(db))

    assert len(db.execute_calls) == 3
    for sql, params in db.execute_calls:
        assert "DELETE FROM shares_archive" in sql
        assert "share_id <= %s" in sql
        assert "ORDER BY share_id ASC" in sql
        assert "LIMIT %s" in sql
        assert params == (2000000, 1000)
    assert db.writes["db_prune_last_deleted"] == "3000"
    assert db.writes["db_prune_last_status"] == (
        "parent: deleted 3000 through share_id 2000000; "
        "target latest 1000000 raw shares / 90d"
    )


def test_archive_cleanup_stops_when_batch_is_not_full():
    db = FakeDb(
        settings={
            "db_prune_after_days": "180",
            "db_prune_batch_size": "5000",
            "db_prune_max_batches": "4",
        },
        deletes=[5000, 42],
    )

    ArchiveCleanup(slot="mm3").run(_ctx(db))

    assert len(db.execute_calls) == 2
    assert db.execute_calls[0][0].startswith("DELETE FROM shares_archive_mm3")
    assert "db_prune_last_deleted" not in db.writes
    assert "db_prune_last_status" not in db.writes
    assert db.writes["db_prune_last_deleted_mm3"] == "5042"
    assert db.writes["db_prune_last_status_mm3"] == (
        "mm3: deleted 5042 through share_id 2000000; "
        "target latest 1000000 raw shares / 180d"
    )


def test_archive_cleanup_defaults_to_one_million_raw_shares():
    db = FakeDb(
        settings={
            "db_prune_after_days": "180",
            "db_prune_batch_size": "5000",
            "db_prune_max_batches": "1",
        },
        deletes=[5000],
        max_share_id=1_500_000,
        age_cutoff_share_id=0,
    )

    ArchiveCleanup().run(_ctx(db))

    assert len(db.execute_calls) == 1
    assert db.execute_calls[0][1] == (500000, 5000)
    assert "target latest 1000000 raw shares / 180d" in (
        db.writes["db_prune_last_status"]
    )


def test_archive_cleanup_raw_share_cap_can_prune_fresh_bursts():
    db = FakeDb(
        settings={
            "db_prune_after_days": "180",
            "db_prune_keep_recent_shares": "1000",
            "db_prune_batch_size": "5000",
            "db_prune_max_batches": "1",
        },
        deletes=[5000],
        max_share_id=1_000_000,
        age_cutoff_share_id=0,
    )

    ArchiveCleanup().run(_ctx(db))

    assert len(db.execute_calls) == 1
    assert db.execute_calls[0][1] == (750000, 5000)
    assert "through share_id 750000" in db.writes["db_prune_last_status"]


def test_archive_cleanup_clamps_below_unaccounted_block_window():
    db = FakeDb(
        settings={
            "db_prune_after_days": "180",
            "db_prune_keep_recent_shares": "1000",
            "db_prune_batch_size": "5000",
            "db_prune_max_batches": "1",
        },
        deletes=[5000],
        max_share_id=1_000_000,
        age_cutoff_share_id=0,
        min_unaccounted_share_id=300000,
    )

    ArchiveCleanup().run(_ctx(db))

    assert len(db.execute_calls) == 1
    assert db.execute_calls[0][1] == (50000, 5000)
    assert "through share_id 50000" in db.writes["db_prune_last_status"]


def test_archive_cleanup_skips_when_archive_is_under_raw_share_cap():
    db = FakeDb(
        settings={
            "db_prune_after_days": "180",
            "db_prune_keep_recent_shares": "1000",
        },
        max_share_id=200000,
        age_cutoff_share_id=0,
    )

    ArchiveCleanup().run(_ctx(db))

    assert db.execute_calls == []
    assert db.writes["db_prune_last_deleted"] == "0"


def test_archive_cleanup_reports_unaccounted_block_safety_block():
    db = FakeDb(
        settings={
            "db_prune_after_days": "180",
            "db_prune_keep_recent_shares": "1000",
        },
        max_share_id=1_000_000,
        age_cutoff_share_id=0,
        min_unaccounted_share_id=100000,
    )

    ArchiveCleanup().run(_ctx(db))

    assert db.execute_calls == []
    assert db.writes["db_prune_last_deleted"] == "0"
    assert db.writes["db_prune_last_status"] == (
        "parent: blocked by unaccounted block at share_id 100000; "
        "target latest 250000 raw shares / 180d"
    )


def test_archive_cleanup_ignores_orphaned_blocks_for_prune_safety():
    db = FakeDb(
        settings={
            "db_prune_after_days": "180",
            "db_prune_keep_recent_shares": "1000",
            "db_prune_batch_size": "5000",
            "db_prune_max_batches": "1",
        },
        deletes=[5000],
        max_share_id=1_000_000,
        age_cutoff_share_id=0,
        unaccounted_blocks=[
            {"share_id": 100000, "confirmations": -1},
        ],
    )

    ArchiveCleanup().run(_ctx(db))

    assert len(db.execute_calls) == 1
    assert db.execute_calls[0][1] == (750000, 5000)
    assert "confirmations >= 0" in db.fetchone_calls[-1][0]
    assert "through share_id 750000" in db.writes["db_prune_last_status"]


def test_archive_cleanup_uses_real_unaccounted_blocks_for_prune_safety():
    db = FakeDb(
        settings={
            "db_prune_after_days": "180",
            "db_prune_keep_recent_shares": "1000",
            "db_prune_batch_size": "5000",
            "db_prune_max_batches": "1",
        },
        deletes=[5000],
        max_share_id=1_000_000,
        age_cutoff_share_id=0,
        unaccounted_blocks=[
            {"share_id": 100000, "confirmations": -1},
            {"share_id": 300000, "confirmations": 0},
        ],
    )

    ArchiveCleanup().run(_ctx(db))

    assert len(db.execute_calls) == 1
    assert db.execute_calls[0][1] == (50000, 5000)
    assert "through share_id 50000" in db.writes["db_prune_last_status"]


def test_archive_cleanup_keeps_parent_status_visible_after_aux_slot_runs():
    db = FakeDb(
        settings={
            "db_prune_after_days": "180",
            "db_prune_batch_size": "5000",
            "db_prune_max_batches": "1",
        },
        deletes=[123, 0],
    )

    ArchiveCleanup().run(_ctx(db))
    ArchiveCleanup(slot="mm5").run(_ctx(db))

    assert db.writes["db_prune_last_deleted"] == "123"
    assert db.writes["db_prune_last_status"].startswith("parent: deleted 123")
    assert db.writes["db_prune_last_deleted_mm5"] == "0"
    assert db.writes["db_prune_last_status_mm5"].startswith("mm5: deleted 0")


def test_archive_cleanup_defaults_to_twenty_batches_for_catchup():
    db = FakeDb(
        settings={
            "db_prune_after_days": "180",
            "db_prune_batch_size": "1000",
        },
        deletes=[1000] * 20,
    )

    ArchiveCleanup().run(_ctx(db))

    assert len(db.execute_calls) == 20
    assert db.writes["db_prune_last_deleted"] == "20000"
