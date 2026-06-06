import time
from types import SimpleNamespace

from cronjobs_py.jobs.statistics import (
    STATISTICS_ALL_USER_HASHRATES,
    STATISTICS_ALL_USER_SHARES,
    TOP_CONTRIBUTORS_HASHES_15,
    Statistics,
)


class FakeDb:
    def __init__(self, settings=None):
        self.settings = dict(settings or {})
        self.worker_refresh_calls = 0
        self.worker_refresh_kwargs = []

    def get_setting_int(self, key, default=0, floor=None, ceiling=None):
        value = int(self.settings.get(key, default))
        if floor is not None:
            value = max(value, floor)
        if ceiling is not None:
            value = min(value, ceiling)
        return value

    def set_setting(self, key, value):
        self.settings[key] = str(value)

    def stats_current_hashrate(self, **_kwargs):
        return 123.0

    def refresh_share_stats_recent(self, **_kwargs):
        return 0

    def stats_per_user_shares(self, **_kwargs):
        return [{
            "id": 42,
            "username": "miner",
            "valid": 10.0,
            "invalid": 1.0,
            "donate_percent": 0.0,
            "is_anonymous": 0,
        }]

    def stats_max_share_id(self):
        return 99

    def stats_current_round_id(self):
        return 7

    def stats_per_user_mining(self, **_kwargs):
        return [{
            "id": 42,
            "account": "miner",
            "hashrate": 456.0,
            "sharerate": 1.5,
            "avgsharediff": 8.0,
        }]

    def stats_per_worker_mining(self, **_kwargs):
        return [{
            "worker": "miner.worker",
            "hashrate": 456.0,
            "last_share_age_sec": 0,
        }]

    def stats_top_contributors(self, **_kwargs):
        return [{
            "account": "miner",
            "donate_percent": 0.0,
            "is_anonymous": 0,
            "hashrate": 456.0,
        }]

    def update_pool_worker_difficulty(self, **_kwargs):
        self.worker_refresh_calls += 1
        self.worker_refresh_kwargs.append(_kwargs)
        return 1


class FakeCache:
    def __init__(self):
        self.static = {}
        self.round = {}

    def set_static(self, key, value, expire=None):
        self.static[key] = (value, expire)
        return True

    def get_static(self, key):
        value = self.static.get(key)
        if isinstance(value, tuple):
            return value[0]
        return value

    def set_round(self, key, value, *, round_id=0, flag=0, expire=None):
        self.round[(key, round_id, flag)] = (value, expire)
        return True


def test_statistics_job_writes_php_cache_keys_and_shapes():
    cache = FakeCache()
    db = FakeDb()
    ctx = SimpleNamespace(
        settings=SimpleNamespace(raw={"target_bits": 32, "difficulty": 32}),
        db=db,
        cache=cache,
    )

    Statistics().run(ctx)

    assert cache.static["getCurrentHashrate"] == (456.0, None)

    shares, shares_expire = cache.round[(STATISTICS_ALL_USER_SHARES, 7, 0)]
    assert shares_expire is None
    assert shares["share_id"] == 99
    assert shares["data"][42]["username"] == "miner"
    assert shares["data"][42]["valid"] == 10.0

    mining, mining_expire = cache.static[STATISTICS_ALL_USER_HASHRATES]
    assert mining_expire == 600
    assert mining["data"][42]["hashrate"] == 456.0
    assert mining["data"][42]["sharerate"] == 1.5
    assert mining["data"][42]["avgsharediff"] == 8.0

    top, top_expire = cache.static[TOP_CONTRIBUTORS_HASHES_15]
    assert top_expire is None
    assert top[0]["account"] == "miner"
    assert db.worker_refresh_calls == 1
    assert db.worker_refresh_kwargs[0]["update_active"] is True
    assert db.worker_refresh_kwargs[0]["zero_stale"] is True
    assert db.worker_refresh_kwargs[0]["stale_batch_size"] == 500
    assert int(db.settings["pool_worker_difficulty_last_update"]) > 0
    assert int(db.settings["pool_worker_difficulty_zero_last_update"]) > 0


def test_statistics_job_skips_worker_refresh_inside_throttle_window():
    cache = FakeCache()
    db = FakeDb({
        "pool_worker_difficulty_update_seconds": "600",
        "pool_worker_difficulty_zero_update_seconds": "600",
        "pool_worker_difficulty_last_update": str(int(time.time())),
        "pool_worker_difficulty_zero_last_update": str(int(time.time())),
    })
    ctx = SimpleNamespace(
        settings=SimpleNamespace(raw={"target_bits": 32, "difficulty": 32}),
        db=db,
        cache=cache,
    )

    Statistics().run(ctx)

    assert db.worker_refresh_calls == 0


def test_statistics_job_can_run_stale_zero_without_active_refresh():
    cache = FakeCache()
    now = int(time.time())
    db = FakeDb({
        "pool_worker_difficulty_update_seconds": "600",
        "pool_worker_difficulty_zero_update_seconds": "600",
        "pool_worker_difficulty_last_update": str(now),
        "pool_worker_difficulty_zero_last_update": "0",
    })
    ctx = SimpleNamespace(
        settings=SimpleNamespace(raw={"target_bits": 32, "difficulty": 32}),
        db=db,
        cache=cache,
    )

    Statistics().run(ctx)

    assert db.worker_refresh_calls == 1
    assert db.worker_refresh_kwargs[0]["update_active"] is False
    assert db.worker_refresh_kwargs[0]["zero_stale"] is True
    assert int(db.settings["pool_worker_difficulty_last_update"]) == now
    assert int(db.settings["pool_worker_difficulty_zero_last_update"]) > 0
