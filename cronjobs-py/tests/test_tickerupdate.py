from __future__ import annotations

import pytest

from cronjobs_py.jobs.tickerupdate import TickerUpdate
from cronjobs_py.scheduler import JobContext
from cronjobs_py.settings import DbConfig, Settings


class _Db:
    def set_setting(self, name: str, value: str) -> None:
        raise AssertionError("ticker update should not write settings")


def _ctx(raw: dict) -> JobContext:
    settings = Settings(
        php_config_path="/dev/null",  # type: ignore[arg-type]
        db=DbConfig("", 0, "", "", ""),
        coins=[],
        reward=0.0,
        reward_type="block",
        block_bonus=0.0,
        raw=raw,
    )
    return JobContext(settings=settings, db=_Db(), rpc_by_slot={}, cache=None)


@pytest.mark.parametrize(
    "url",
    [
        "",
        "https://btc-e.com",
        "https://btc-e.com/api/2/ltc_usd/ticker",
        "https://www.btce.com/api/2/ltc_usd/ticker",
    ],
)
def test_tickerupdate_skips_disabled_or_legacy_price_urls(monkeypatch, url: str) -> None:
    def fail_get(*args, **kwargs):
        raise AssertionError("legacy or disabled price URL should not be fetched")

    monkeypatch.setattr("cronjobs_py.jobs.tickerupdate.requests.get", fail_get)

    TickerUpdate().run(_ctx({"price": {"url": url}}))
