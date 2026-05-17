"""CLI entry point.

Usage:
    cronjobs-py run-once findblock      # one tick of one job
    cronjobs-py run-once                # one tick of every job
    cronjobs-py serve                   # long-lived scheduler
"""

from __future__ import annotations

import argparse
import sys

from . import __version__
from .jobs import (
    ArchiveCleanup, BlockUpdate, FindBlock, LiquidPayout, Notifications,
    Payouts, PplnsPayout, ReconcilePayouts, Statistics, TickerUpdate,
    TokenCleanup,
)
from .logger import get, setup
from .scheduler import Scheduler
from .settings import load


def _build_scheduler() -> Scheduler:
    settings = load()
    s = Scheduler(settings)
    # Pool-wide statistics: ticks every 60s, computes 4 aggregations
    # for the web UI dashboard + refreshes pool_worker.shares_difficulty
    # so per-worker live hashrate displays. Slot-agnostic — the parent
    # `shares` table holds the merge-mining stream.
    s.register(Statistics())
    # Register findblock + pplns_payout + payouts for every coin slot the
    # config has wired up. The parent slot (`""`) is always present;
    # aux slots come from the live `wallet_<slot>` blocks. Each job has
    # a unique `name` derived from its slot so the scheduler can track
    # per-slot last-tick state.
    #
    # Within a slot the order matters at first tick: findblock attaches
    # share_ids, then pplns_payout credits accounts, then payouts sends
    # on-chain. Across slots the scheduler ticks each job at its own
    # interval; we offset the intervals slightly to avoid all slots
    # piling on the daemon RPC and the DB at the same instant.
    base_intervals = {
        "findblock": 60,
        "pplns_payout": 90,
        "payouts": 300,
        "reconcile_payouts": 300,
        "blockupdate": 120,
        "liquid_payout": 600,
    }
    for idx, coin in enumerate(settings.coins):
        slot = coin.slot
        slot_label = slot or "parent"
        # Stagger intervals by a few seconds per slot so the per-tick
        # work doesn't all stack up.
        offset = idx * 3
        s.register(FindBlock(
            name=f"findblock-{slot_label}",
            interval_seconds=base_intervals["findblock"] + offset,
            slot=slot,
        ))
        s.register(PplnsPayout(
            name=f"pplns-{slot_label}",
            interval_seconds=base_intervals["pplns_payout"] + offset,
            slot=slot,
        ))
        s.register(Payouts(
            name=f"payouts-{slot_label}",
            interval_seconds=base_intervals["payouts"] + offset,
            slot=slot,
        ))
        # Wave 2: archive Debit_AP/Debit_MP/TXFee rows tied to outbox
        # rows whose on-chain txid has cleared `confirmations`. Closes
        # the loop so the dashboard balance returns to a clean number
        # after a payout settles.
        s.register(ReconcilePayouts(
            name=f"reconcile-{slot_label}",
            interval_seconds=base_intervals["reconcile_payouts"] + offset,
            slot=slot,
        ))
        s.register(BlockUpdate(
            name=f"blockupdate-{slot_label}",
            interval_seconds=base_intervals["blockupdate"] + offset,
            slot=slot,
        ))
        s.register(LiquidPayout(
            name=f"liquid-{slot_label}",
            interval_seconds=base_intervals["liquid_payout"] + offset,
            slot=slot,
        ))
        # archive_cleanup: per-slot, hourly, trims old `shares_archive_<slot>` rows
        # so the table doesn't grow without bound.
        s.register(ArchiveCleanup(
            name=f"archive-{slot_label}",
            interval_seconds=3600 + offset,
            slot=slot,
        ))
    # token_cleanup: shared (the tokens table isn't per-slot). Hourly.
    s.register(TokenCleanup())
    # tickerupdate: optional, no-ops if `config.price.url` isn't set.
    s.register(TickerUpdate())
    # notifications: stub — bails silently unless the operator both turns
    # notifications on AND wires up SMTP. Real port is a follow-up.
    s.register(Notifications())
    return s


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="cronjobs-py")
    parser.add_argument("--log-level", default="INFO")
    parser.add_argument("--config", help="path to MPOS global.inc.php")
    sub = parser.add_subparsers(dest="cmd", required=True)

    once = sub.add_parser("run-once", help="run one tick (default: all jobs)")
    once.add_argument("job", nargs="?", help="job name (omit for all)")

    sub.add_parser("serve", help="long-lived scheduler")

    drift = sub.add_parser(
        "drift-check",
        help="Wave 5: compare shadow predictions vs PHP-cron writes",
    )
    drift.add_argument("--slot", help="restrict to one slot ('' = parent)")
    drift.add_argument("--since", help="only rows created at or after this timestamp")
    drift.add_argument("--tolerance", type=float, default=1e-8)
    drift.add_argument("--include-php-only", action="store_true")

    # SSE side-car for the live dashboard. Runs in a separate process
    # so the scheduler isn't tied to long-lived HTTP connections.
    sse_p = sub.add_parser(
        "sse",
        help="serve Server-Sent Events for the dashboard (default: 127.0.0.1:8090)",
    )
    sse_p.add_argument("--bind", default="127.0.0.1")
    sse_p.add_argument("--port", type=int, default=8090)
    sse_p.add_argument("--share-interval", type=float, default=2.0)
    sse_p.add_argument("--block-interval", type=float, default=5.0)

    sub.add_parser("version")

    args = parser.parse_args(argv)
    setup(args.log_level)
    log = get("cronjobs-py")

    if args.cmd == "version":
        print(__version__)
        return 0

    if args.config:
        import os
        os.environ["MPOS_CONFIG"] = args.config

    # SSE doesn't want a scheduler — it just needs Settings + Db.
    if args.cmd == "sse":
        from . import sse
        from .settings import load as _load_settings
        sse.serve(
            settings=_load_settings(),
            bind=args.bind, port=args.port,
            share_interval=args.share_interval,
            block_interval=args.block_interval,
        )
        return 0

    sched = _build_scheduler()
    log.info(
        "loaded settings: db=%s coins=%d", sched.settings.db.host, len(sched.settings.coins)
    )

    if args.cmd == "run-once":
        sched.run_once(args.job)
        sched.close()
        return 0
    if args.cmd == "serve":
        sched.run_forever()
        return 0
    if args.cmd == "drift-check":
        # The drift-check CLI doesn't need a scheduler — only a Db.
        # Reuse the one the scheduler already opened so we don't pay
        # the connect cost twice.
        from . import drift
        rows = drift.check_drift(
            sched.db, slot=args.slot, since=args.since,
            tolerance=args.tolerance,
        )
        php_only: list[dict] = []
        if args.include_php_only:
            slots = [args.slot] if args.slot is not None else \
                    sorted({r.slot for r in rows} | {""})
            for s in slots:
                php_only.extend(
                    {**row, "slot": s}
                    for row in drift.find_php_only(sched.db, slot=s)
                )
        print(drift.render_report(rows, php_only, args.slot))
        sched.close()
        n_diff = sum(1 for r in rows if r.verdict == "DIFF")
        return 1 if n_diff > 0 else 0

    return 1


if __name__ == "__main__":
    sys.exit(main())
