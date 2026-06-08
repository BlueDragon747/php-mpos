from __future__ import annotations

from types import SimpleNamespace

from cronjobs_py.jobs.archive_cleanup import ArchiveCleanup


class FakeDb:
    def __init__(self, settings=None, deletes=None, *,
                 max_share_id=2_000_000, age_cutoff_share_id=2_000_000,
                 min_unaccounted_share_id=None):
        self.settings = dict(settings or {})
        self.deletes = list(deletes or [])
        self.max_share_id = max_share_id
        self.age_cutoff_share_id = age_cutoff_share_id
        self.min_unaccounted_share_id = min_unaccounted_share_id
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
    assert db.writes["db_prune_last_deleted"] == "5042"
    assert db.writes["db_prune_last_status"] == (
        "mm3: deleted 5042 through share_id 2000000; "
        "target latest 250000 raw shares / 180d"
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
