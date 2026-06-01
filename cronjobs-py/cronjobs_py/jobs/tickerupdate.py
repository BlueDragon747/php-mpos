"""Port of `cronjobs/tickerupdate.php` — exchange-rate poller.

Fetches the pool's coin/USD (or coin/BTC) price from an external API
and stores it in the `settings` table under key `price`. The MPOS
web UI reads `price` to render dollar values next to balance figures.

Behaviour:

- If the operator hasn't configured a price API URL (`config.price.url`),
  this job is a clean no-op. The UI shows BLC amounts only (no $ /BTC),
  which is fine.
- If the URL is set, fetch JSON and store `result.{key_path}` as a
  float price.

The PHP version also queries UptimeRobot — that's pool-monitoring
infrastructure the operator opts into separately. Skipped here; if
needed it's a 20-line follow-up.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from urllib.parse import urlparse

import requests

from ..errors import Skip
from ..logger import get
from ..scheduler import JobContext

log = get(__name__)

LEGACY_PRICE_HOSTS = {"btc-e.com", "www.btc-e.com", "btce.com", "www.btce.com"}


def _is_legacy_price_url(url: str) -> bool:
    host = (urlparse(url).hostname or "").lower()
    return host in LEGACY_PRICE_HOSTS


@dataclass
class TickerUpdate:
    name: str = "tickerupdate"
    interval_seconds: int = 600  # 10 minutes
    slot: str = ""

    def run(self, ctx: JobContext) -> None:
        # Single-firing job; only run for the parent slot.
        if self.slot != "":
            return

        cfg = ctx.settings
        db = ctx.db

        price_cfg = (cfg.raw.get("price") or {})
        url = price_cfg.get("url")
        key_path = price_cfg.get("path", "price")  # dotted path into JSON

        if not url:
            log.debug("[%s] no price.url configured; skipping", self.name)
            return
        if _is_legacy_price_url(str(url)):
            log.debug("[%s] legacy price.url configured; skipping", self.name)
            return

        try:
            resp = requests.get(url, timeout=10)
            resp.raise_for_status()
            data = resp.json()
        except Exception as exc:
            raise Skip(f"price fetch from {url} failed: {exc}")

        # Walk dotted key_path through the response JSON.
        cursor = data
        for key in key_path.split("."):
            if not isinstance(cursor, dict) or key not in cursor:
                raise Skip(
                    f"price path {key_path!r} not found in API response: {data!r}"
                )
            cursor = cursor[key]
        try:
            price = float(cursor)
        except Exception as exc:
            raise Skip(f"price value {cursor!r} not numeric: {exc}")

        db.set_setting("price", str(price))
        log.info("[%s] price updated: %.8f", self.name, price)
