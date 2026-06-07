from __future__ import annotations

from types import SimpleNamespace

from cronjobs_py.jobs.archive_cleanup import ArchiveCleanup


class FakeDb:
    def __init__(self, settings=None, deletes=None):
        self.settings = dict(settings or {})
        self.deletes = list(deletes or [])
        self.execute_calls = []
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
            "db_prune_batch_size": "1000",
            "db_prune_max_batches": "3",
        },
        deletes=[1000, 1000, 1000],
    )

    ArchiveCleanup().run(_ctx(db))

    assert len(db.execute_calls) == 3
    for sql, params in db.execute_calls:
        assert "DELETE FROM shares_archive" in sql
        assert "ORDER BY time ASC" in sql
        assert "LIMIT %s" in sql
        assert params == (90, 25, 1000)
    assert db.writes["db_prune_last_deleted"] == "3000"
    assert db.writes["db_prune_last_status"] == "parent: deleted 3000 older than 90d"


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
    assert db.writes["db_prune_last_status"] == "mm3: deleted 5042 older than 180d"
