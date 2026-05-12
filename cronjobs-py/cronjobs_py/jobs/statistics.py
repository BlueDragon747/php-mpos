"""Port of `cronjobs/statistics.php`.

Pre-computes the four pool-wide aggregations the MPOS web UI displays
on its dashboard, and writes them to memcached under the same keys
the PHP `Statistics` class reads from. Each PHP stat method has a SQL
fall-through that recomputes on cache miss, so a degraded memcache
write doesn't break correctness — just performance.

This job does triple duty:

1. Pool-wide current hashrate (kH/s) — the headline number on the
   home page.
2. Per-user share counts (`valid` / `invalid`) — feeds the round
   progress bar and per-user totals.
3. Per-user hashrate + share counts in the recent window — feeds the
   "Top miners" leaderboard.
4. Top contributors by hashrate — same leaderboard, separate cache
   key so the UI can request just the top-N.

It also refreshes `pool_worker.shares_difficulty` so the per-worker
hashrate column on the dashboard isn't stuck at 0 (eloipool's
`ShareLogging` only writes the share row, not the rolling avg the UI
expects).
"""

from __future__ import annotations

import math
import time
from dataclasses import dataclass

from ..errors import Skip
from ..logger import get
from ..scheduler import JobContext

log = get(__name__)

STATISTICS_ALL_USER_SHARES = "STATISTICS_ALL_USER_SHARES"
STATISTICS_ALL_USER_HASHRATES = "STATISTICS_ALL_USER_HASHRATES"
TOP_CONTRIBUTORS_HASHES_15 = "getTopContributorshashes15"
# Memcache key holding the EMA running state (value + timestamp) so
# successive ticks can blend the new sample with the previous estimate.
HASHRATE_EMA_STATE = "getCurrentHashrate_ema_state"
HASHRATE_USER_EMA_STATE = "getCurrentUserHashrate_ema_state"


def _ema_step(prev_value, prev_ts, sample, now_ts, tau):
    """One step of a time-aware exponential moving average.

    `tau` is the time constant in seconds — the EMA decays toward `sample`
    with half-life ≈ 0.693 * tau. When `prev_value` is None we seed from
    the sample so the display doesn't start at zero. Time-aware alpha
    means a cron stall (large dt) catches up correctly instead of
    underweighting the recovered sample.
    """
    if prev_value is None or prev_ts is None:
        return float(sample)
    dt = max(1.0, float(now_ts) - float(prev_ts))
    alpha = 1.0 - math.exp(-dt / max(1.0, float(tau)))
    return alpha * float(sample) + (1.0 - alpha) * float(prev_value)


@dataclass
class Statistics:
    name: str = "statistics"
    interval_seconds: int = 60
    # Pool-wide stats; the slot field is unused but kept so __main__'s
    # registration loop can hand any slot in without special-casing.
    slot: str = ""

    def run(self, ctx: JobContext) -> None:
        cfg = ctx.settings
        db = ctx.db
        cache = ctx.cache

        # MPOS config knobs that go into the hashrate math.
        target_bits = int(cfg.raw.get("target_bits", 32))
        difficulty_const = int(cfg.raw.get("difficulty", 32))
        # Sampling window for each raw hashrate read.
        interval = db.get_setting_int(
            "hashrate_window_seconds", default=900, floor=60
        )
        # EMA time constant. Half-life ≈ 0.693 * tau. Default 300s
        # (~3.5 min half-life) gives quick response to load changes
        # with most of the sample noise already smoothed out by the
        # wider 900s sampling window above.
        tau = db.get_setting_int(
            "hashrate_ema_tau_seconds", default=300, floor=60
        )

        # 1. Current pool hashrate (kH/s)
        try:
            sample = db.stats_current_hashrate(
                target_bits=target_bits,
                difficulty_const=difficulty_const,
                interval=interval,
            )
        except Exception as exc:
            raise Skip(f"current_hashrate query failed: {exc}")

        now_ts = time.time()
        prev = cache.get_static(HASHRATE_EMA_STATE) if cache else None
        prev_value = prev.get("value") if isinstance(prev, dict) else None
        prev_ts = prev.get("ts") if isinstance(prev, dict) else None
        hashrate = _ema_step(prev_value, prev_ts, sample, now_ts, tau)
        log.info(
            "[%s] pool hashrate: sample=%.0f ema=%.0f kH/s (tau=%ds)",
            self.name, sample, hashrate, tau,
        )
        if cache:
            cache.set_static(
                HASHRATE_EMA_STATE,
                {"value": float(hashrate), "ts": float(now_ts)},
            )
            cache.set_static("getCurrentHashrate", hashrate)

        # 2. Per-user share counts for the current round.
        try:
            user_shares = db.stats_per_user_shares(
                difficulty_const=difficulty_const,
            )
            max_share_id = db.stats_max_share_id()
            round_id = db.stats_current_round_id()
        except Exception as exc:
            log.warning("[%s] per_user_shares query failed: %s",
                        self.name, exc)
            user_shares = []
            max_share_id = 0
            round_id = 0
        if cache:
            cache.set_round(
                STATISTICS_ALL_USER_SHARES,
                {
                    "share_id": max_share_id,
                    "data": {int(row["id"]): row for row in user_shares},
                },
                round_id=round_id,
                flag=0,
            )
        log.info("[%s] %d users with share rows", self.name, len(user_shares))

        # 3. Per-user mining stats (recent-window hashrate). Each user's
        # hashrate is EMA-smoothed with the same tau as the pool value
        # so the dashboard reads stable for steady miners and converges
        # to the new rate over a few minutes when load actually shifts.
        try:
            user_mining = db.stats_per_user_mining(
                target_bits=target_bits,
                difficulty_const=difficulty_const,
                interval=interval,
            )
        except Exception as exc:
            log.warning("[%s] per_user_mining query failed: %s",
                        self.name, exc)
            user_mining = []
        prev_user = cache.get_static(HASHRATE_USER_EMA_STATE) if cache else None
        prev_user_map = prev_user.get("data") if isinstance(prev_user, dict) else None
        prev_user_ts = prev_user.get("ts") if isinstance(prev_user, dict) else None
        smoothed_user_map = {}
        for row in user_mining:
            uid = int(row["id"])
            sample = float(row.get("hashrate") or 0.0)
            prev_v = (prev_user_map or {}).get(uid) if prev_user_map else None
            row["hashrate"] = _ema_step(prev_v, prev_user_ts, sample, now_ts, tau)
            smoothed_user_map[uid] = row["hashrate"]
        if cache:
            cache.set_static(
                HASHRATE_USER_EMA_STATE,
                {"data": smoothed_user_map, "ts": float(now_ts)},
            )
            cache.set_static(
                STATISTICS_ALL_USER_HASHRATES,
                {"data": {int(row["id"]): row for row in user_mining}},
                expire=600,
            )

        # 4. Top contributors leaderboard (hashrate ordered)
        try:
            top = db.stats_top_contributors(
                target_bits=target_bits,
                difficulty_const=difficulty_const,
                interval=600,
                limit=15,
            )
        except Exception as exc:
            log.warning("[%s] top_contributors query failed: %s",
                        self.name, exc)
            top = []
        if cache and top:
            cache.set_static(TOP_CONTRIBUTORS_HASHES_15, top)
        if top:
            log.info("[%s] top miner: %s @ %.0f kH/s",
                     self.name, top[0]["account"], top[0]["hashrate"])

        # 5. Per-worker live-hashrate refresh (pool_worker.shares_difficulty).
        # eloipool doesn't update this column; without our refresh the UI
        # shows 0 H/s per worker. Folded into statistics so it ticks at
        # the same cadence as the other dashboard data — covers item (5)
        # in the 100% gap list.
        try:
            n = db.update_pool_worker_difficulty(interval=interval)
            log.debug("[%s] refreshed shares_difficulty on %d pool_worker rows",
                      self.name, n)
        except Exception as exc:
            log.warning("[%s] pool_worker refresh failed: %s",
                        self.name, exc)
