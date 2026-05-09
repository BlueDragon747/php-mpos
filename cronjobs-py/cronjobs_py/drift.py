"""Wave 5 drift-check between cronjobs-py shadow predictions and PHP
cron's authoritative writes.

Usage:
    cronjobs-py drift-check
    cronjobs-py drift-check --slot mm1
    cronjobs-py drift-check --since "2026-04-25 00:00:00"
    cronjobs-py drift-check --tolerance 0.00000001

For every row in `cronjobs_py_accounting WHERE mode='shadow'` (i.e.
every prediction cronjobs-py made during the soak window), look up the
matching authoritative `transactions_<slot>` row written by PHP cron
and emit a verdict:

    MATCH      shadow.amount == authoritative.amount  (within tolerance)
    DIFF       shadow.amount != authoritative.amount  (drift)
    MISSING    no authoritative row exists for this (slot, block,
               account, type) — PHP cron didn't credit this prediction

A summary at the end reports the totals by verdict per slot. Cutover
to authoritative is safe when:
    - MATCH count is high relative to expected blocks
    - DIFF count == 0
    - MISSING count == 0

The "expected blocks" baseline is in the operator's head — typically
"every block credited during the soak window". A small MISSING tail
is usually the timing race: PHP cron credits before cronjobs-py
shadow-predicts, so cronjobs-py never wrote the guard row. Drift-check
also reports those as `PHP_ONLY` (rows in transactions_<slot> matching
the shadow window but with no shadow guard).
"""

from __future__ import annotations

import argparse
import sys
from collections import defaultdict
from dataclasses import dataclass

from .db import Db
from .logger import get, setup
from .settings import load

log = get(__name__)


@dataclass
class DriftRow:
    slot: str
    block_id: int
    account_id: int
    tx_type: str
    shadow_amount: float
    auth_amount: float | None
    verdict: str  # MATCH | DIFF | MISSING


def check_drift(db: Db, *, slot: str | None = None,
                since: str | None = None,
                tolerance: float = 1e-8) -> list[DriftRow]:
    """Walk shadow guard rows; lookup authoritative writes; classify."""
    where_clauses = ["mode = 'shadow'"]
    params: list = []
    if slot is not None:
        where_clauses.append("slot = %s")
        params.append(slot)
    if since is not None:
        where_clauses.append("created_at >= %s")
        params.append(since)

    sql = (
        "SELECT slot, block_id, account_id, tx_type, amount "
        "FROM cronjobs_py_accounting "
        f"WHERE {' AND '.join(where_clauses)} "
        "ORDER BY created_at ASC"
    )
    shadow_rows = db.fetchall(sql, tuple(params))

    rows: list[DriftRow] = []
    for s in shadow_rows:
        slot_name = s["slot"] or ""
        txn_table = db._transactions_table(slot_name)
        # Match by (account_id, type, block_id, amount-tolerance).
        # PHP-cron writes one row per (account, block, type) so this
        # is a 1:1 lookup. We don't filter on archived because the
        # archive flip happens AFTER the row is written, and we want
        # the drift check to see archived rows too (PHP may have
        # paid out and archived between shadow predict and our scan).
        auth = db.fetchone(
            f"SELECT amount FROM {txn_table} "
            f"WHERE account_id = %s AND block_id = %s AND type = %s "
            f"LIMIT 1",
            (s["account_id"], s["block_id"], s["tx_type"]),
        )
        shadow_amount = float(s["amount"])
        if auth is None:
            rows.append(DriftRow(
                slot=slot_name, block_id=int(s["block_id"]),
                account_id=int(s["account_id"]), tx_type=s["tx_type"],
                shadow_amount=shadow_amount, auth_amount=None,
                verdict="MISSING",
            ))
            continue
        auth_amount = float(auth["amount"])
        verdict = "MATCH" if abs(shadow_amount - auth_amount) <= tolerance else "DIFF"
        rows.append(DriftRow(
            slot=slot_name, block_id=int(s["block_id"]),
            account_id=int(s["account_id"]), tx_type=s["tx_type"],
            shadow_amount=shadow_amount, auth_amount=auth_amount,
            verdict=verdict,
        ))
    return rows


def find_php_only(db: Db, *, slot: str = "",
                  since_block_id: int | None = None) -> list[dict]:
    """PHP-only rows: transactions_<slot> entries that have no
    matching shadow guard. These are the soak-window blocks where
    cronjobs-py missed the prediction (timing race).
    """
    txn_table = db._transactions_table(slot)
    where = (
        "t.type IN ('Credit','Bonus','Fee','Donation') "
        "AND t.block_id IS NOT NULL "
    )
    params: list = []
    if since_block_id is not None:
        where += "AND t.block_id >= %s "
        params.append(since_block_id)
    sql = (
        f"SELECT t.id AS txn_id, t.account_id, t.block_id, t.type, t.amount "
        f"FROM {txn_table} t "
        f"LEFT JOIN cronjobs_py_accounting g "
        f"  ON g.slot = %s AND g.block_id = t.block_id "
        f" AND g.account_id = t.account_id AND g.tx_type = t.type "
        f"WHERE {where} "
        f"  AND g.id IS NULL "
        f"ORDER BY t.id ASC"
    )
    return db.fetchall(sql, (slot, *params))


def render_report(rows: list[DriftRow], php_only: list[dict],
                  slot_filter: str | None) -> str:
    out: list[str] = []
    out.append("=" * 78)
    out.append("cronjobs-py Wave 5 drift-check report")
    out.append("=" * 78)
    if slot_filter is not None:
        out.append(f"Slot filter: {slot_filter or '(parent)'}")
    out.append(f"Shadow rows examined: {len(rows)}")
    out.append("")

    # Group counts per slot per verdict.
    counts: dict[tuple[str, str], int] = defaultdict(int)
    diff_rows: list[DriftRow] = []
    missing_rows: list[DriftRow] = []
    for r in rows:
        counts[(r.slot, r.verdict)] += 1
        if r.verdict == "DIFF":
            diff_rows.append(r)
        elif r.verdict == "MISSING":
            missing_rows.append(r)

    slots = sorted({r.slot for r in rows})
    if slots:
        header = f"{'slot':<10} {'MATCH':>8} {'DIFF':>6} {'MISSING':>9}"
        out.append(header)
        out.append("-" * len(header))
        for s in slots:
            label = s or "(parent)"
            out.append(
                f"{label:<10} "
                f"{counts.get((s, 'MATCH'), 0):>8} "
                f"{counts.get((s, 'DIFF'), 0):>6} "
                f"{counts.get((s, 'MISSING'), 0):>9}"
            )
    else:
        out.append("(no shadow rows in scope)")

    if diff_rows:
        out.append("")
        out.append("DRIFT (shadow.amount != php.amount):")
        out.append(
            f"  {'slot':<8} {'block':>8} {'account':>8} {'type':<10} "
            f"{'shadow':>14} {'php':>14}"
        )
        for r in diff_rows[:50]:
            out.append(
                f"  {r.slot:<8} {r.block_id:>8} {r.account_id:>8} "
                f"{r.tx_type:<10} {r.shadow_amount:>14.8f} "
                f"{r.auth_amount or 0.0:>14.8f}"
            )
        if len(diff_rows) > 50:
            out.append(f"  ... ({len(diff_rows) - 50} more drift rows)")

    if missing_rows:
        out.append("")
        out.append("MISSING (shadow predicted, php didn't credit):")
        out.append(
            f"  {'slot':<8} {'block':>8} {'account':>8} {'type':<10} "
            f"{'shadow':>14}"
        )
        for r in missing_rows[:50]:
            out.append(
                f"  {r.slot:<8} {r.block_id:>8} {r.account_id:>8} "
                f"{r.tx_type:<10} {r.shadow_amount:>14.8f}"
            )
        if len(missing_rows) > 50:
            out.append(f"  ... ({len(missing_rows) - 50} more missing rows)")

    if php_only:
        out.append("")
        out.append(
            f"PHP_ONLY (php credited, no shadow guard) — typically the "
            f"timing race where PHP beat cronjobs-py to a block. "
            f"{len(php_only)} rows; first 20 shown:"
        )
        out.append(
            f"  {'slot':<8} {'block':>8} {'account':>8} {'type':<10} "
            f"{'amount':>14}"
        )
        for r in php_only[:20]:
            out.append(
                f"  {(r.get('slot') or ''):<8} {r['block_id']:>8} "
                f"{r['account_id']:>8} {r['type']:<10} "
                f"{float(r['amount']):>14.8f}"
            )

    out.append("")
    out.append("=" * 78)
    n_diff = len(diff_rows)
    n_missing = len(missing_rows)
    if n_diff == 0 and n_missing == 0:
        out.append("VERDICT: CLEAN — safe to cutover when soak duration is met.")
    elif n_diff == 0:
        out.append(
            f"VERDICT: NO DRIFT but {n_missing} MISSING. Investigate why "
            f"PHP cron didn't credit those predictions before cutover."
        )
    else:
        out.append(
            f"VERDICT: DRIFT DETECTED — {n_diff} DIFF rows, {n_missing} MISSING. "
            f"DO NOT CUTOVER until investigated and resolved."
        )
    out.append("=" * 78)
    return "\n".join(out)


def cli(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="cronjobs-py drift-check",
        description="Compare cronjobs-py shadow predictions vs PHP-cron "
                    "authoritative writes."
    )
    parser.add_argument("--config", help="path to MPOS global.inc.php")
    parser.add_argument("--log-level", default="WARN")
    parser.add_argument(
        "--slot",
        help="restrict to one slot ('' = parent, 'mm', 'mm1', ...)",
    )
    parser.add_argument(
        "--since",
        help="only look at shadow rows created at or after this timestamp "
             "('YYYY-MM-DD HH:MM:SS')",
    )
    parser.add_argument(
        "--tolerance", type=float, default=1e-8,
        help="absolute tolerance for amount comparison (default 1e-8)",
    )
    parser.add_argument(
        "--include-php-only", action="store_true",
        help="also report transactions_<slot> rows with no matching "
             "shadow guard (the timing-race population)",
    )
    args = parser.parse_args(argv)
    setup(args.log_level)

    if args.config:
        import os
        os.environ["MPOS_CONFIG"] = args.config

    settings = load()
    db = Db(settings.db)
    try:
        rows = check_drift(
            db, slot=args.slot, since=args.since, tolerance=args.tolerance,
        )
        php_only = []
        if args.include_php_only:
            slots = [args.slot] if args.slot is not None else \
                    sorted({r.slot for r in rows} | {""})
            for s in slots:
                php_only.extend(
                    {**row, "slot": s} for row in find_php_only(db, slot=s)
                )
        print(render_report(rows, php_only, args.slot))
    finally:
        db.close()

    n_diff = sum(1 for r in rows if r.verdict == "DIFF")
    return 1 if n_diff > 0 else 0


if __name__ == "__main__":
    sys.exit(cli())
