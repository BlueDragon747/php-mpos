from types import SimpleNamespace

from cronjobs_py.jobs.statistics import (
    STATISTICS_ALL_USER_HASHRATES,
    STATISTICS_ALL_USER_SHARES,
    TOP_CONTRIBUTORS_HASHES_15,
    Statistics,
)


class FakeDb:
    def stats_current_hashrate(self, **_kwargs):
        return 123.0

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

    def stats_top_contributors(self, **_kwargs):
        return [{
            "account": "miner",
            "donate_percent": 0.0,
            "is_anonymous": 0,
            "hashrate": 456.0,
        }]

    def update_pool_worker_difficulty(self, **_kwargs):
        return 1


class FakeCache:
    def __init__(self):
        self.static = {}
        self.round = {}

    def set_static(self, key, value, expire=None):
        self.static[key] = (value, expire)
        return True

    def set_round(self, key, value, *, round_id=0, flag=0, expire=None):
        self.round[(key, round_id, flag)] = (value, expire)
        return True


def test_statistics_job_writes_php_cache_keys_and_shapes():
    cache = FakeCache()
    ctx = SimpleNamespace(
        settings=SimpleNamespace(raw={"target_bits": 32, "difficulty": 32}),
        db=FakeDb(),
        cache=cache,
    )

    Statistics().run(ctx)

    assert cache.static["getCurrentHashrate"] == (123.0, None)

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
