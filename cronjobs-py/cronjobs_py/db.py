"""Thin DB layer over PyMySQL with the queries our jobs actually need.

We stay close to the SQL the PHP cronjobs run. Goal is parity, not a new
ORM. Each query gets one method so jobs read like the PHP they're
replacing — with retries and connection pooling moved here.
"""

from __future__ import annotations

import logging
import time
from contextlib import contextmanager
from typing import Any, Iterator

import pymysql
from pymysql.constants import CLIENT

from .errors import Transient
from .settings import DbConfig

log = logging.getLogger(__name__)


class Db:
    def __init__(
        self,
        cfg: DbConfig,
        *,
        max_attempts: int = 3,
        backoff_base: float = 0.5,
    ) -> None:
        self.cfg = cfg
        self.max_attempts = max_attempts
        self.backoff_base = backoff_base
        self._conn: pymysql.connections.Connection | None = None

    def close(self) -> None:
        if self._conn is not None:
            try:
                self._conn.close()
            except Exception:
                pass
            self._conn = None

    def __enter__(self) -> "Db":
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()

    def _connect(self) -> pymysql.connections.Connection:
        if self._conn is not None and self._conn.open:
            try:
                self._conn.ping(reconnect=True)
                return self._conn
            except Exception:
                self.close()
        self._conn = pymysql.connect(
            host=self.cfg.host,
            port=self.cfg.port,
            user=self.cfg.user,
            password=self.cfg.password,
            database=self.cfg.database,
            charset="utf8mb4",
            cursorclass=pymysql.cursors.DictCursor,
            autocommit=True,
            connect_timeout=10,
            read_timeout=30,
            write_timeout=30,
            # CLIENT.FOUND_ROWS makes UPDATE rowcount report MATCHED rows
            # rather than CHANGED rows. Several helpers (e.g.
            # set_block_shares, set_block_finder) treat rowcount=0 as
            # "row doesn't exist" and log ERROR. Without this flag, an
            # idempotent UPDATE setting a column to its existing value
            # returns rowcount=0 too, producing false-positive ERRORs.
            # FOUND_ROWS makes rowcount unambiguously mean "WHERE matched".
            client_flag=CLIENT.FOUND_ROWS,
        )
        return self._conn

    @contextmanager
    def cursor(self) -> Iterator[pymysql.cursors.DictCursor]:
        """Cursor with retry on transient connection errors only.

        Schema-level errors (DataError, ProgrammingError) bubble up
        immediately so the caller can decide. Connection errors retry
        with exponential backoff and reopen the connection.
        """
        last_exc: Exception | None = None
        for attempt in range(1, self.max_attempts + 1):
            try:
                conn = self._connect()
                with conn.cursor() as cur:
                    yield cur
                return
            except (
                pymysql.err.OperationalError,
                pymysql.err.InterfaceError,
            ) as exc:
                # Treat as a connection-level transient and retry.
                last_exc = exc
                self.close()
                if attempt < self.max_attempts:
                    delay = self.backoff_base * (2 ** (attempt - 1))
                    log.warning(
                        "db transient error %s on attempt %d/%d, retrying in %.1fs",
                        exc, attempt, self.max_attempts, delay,
                    )
                    time.sleep(delay)
                continue
            except (
                pymysql.err.ProgrammingError,
                pymysql.err.DataError,
                pymysql.err.IntegrityError,
                pymysql.err.NotSupportedError,
            ):
                # Schema/data bugs — caller's job to handle. Don't retry.
                raise
        raise Transient(f"db unavailable after {self.max_attempts} attempts: {last_exc}")

    # ---- query helpers used by jobs ----

    def fetchone(self, sql: str, params: tuple[Any, ...] = ()) -> dict | None:
        with self.cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchone()

    def fetchall(self, sql: str, params: tuple[Any, ...] = ()) -> list[dict]:
        with self.cursor() as cur:
            cur.execute(sql, params)
            return list(cur.fetchall())

    def execute(self, sql: str, params: tuple[Any, ...] = ()) -> int:
        with self.cursor() as cur:
            cur.execute(sql, params)
            return cur.rowcount

    def get_setting_int(self, name: str, *, default: int, floor: int = 0) -> int:
        """Read an integer-valued row from the MPOS `settings` table.

        Used by cron jobs that need to react in real time to admin
        edits on the Settings page — the row is queried fresh every
        call, no caching. Returns `default` if the row is missing or
        the stored value isn't a positive integer; clamps the result
        to at least `floor` so an admin typo (e.g. `1`) can't crater
        a SQL window divisor.
        """
        try:
            row = self.fetchone(
                "SELECT value FROM settings WHERE name = %s LIMIT 1",
                (name,),
            )
            if row and row.get("value") is not None:
                v = int(row["value"])
                if v > 0:
                    return max(floor, v)
        except Exception:
            pass
        return max(floor, default)

    @contextmanager
    def transaction(self) -> Iterator[pymysql.cursors.DictCursor]:
        """Multi-statement transaction with autocommit toggled off.

        Yields a cursor inside `BEGIN ... COMMIT`. On any exception the
        connection is rolled back and the original exception re-raised.
        Restores autocommit on exit so subsequent single-statement helpers
        keep their existing semantics.

        Connection-level transient errors are NOT auto-retried inside a
        transaction — the application would have to re-derive its state
        for a clean retry, which is the caller's responsibility, not ours.
        Schema/data errors raise immediately.

        Used by pplns_payout to wrap the `insert guard row + write
        Credit + write Fee + archive shares + UPDATE block accounted=1`
        sequence into a single atomic step. If any sub-step fails, the
        whole block stays unaccounted on disk and the next tick can try
        again from a clean state.
        """
        conn = self._connect()
        # PyMySQL's begin()/commit()/rollback() are NOPs while autocommit
        # is on, so we have to flip the connection-level setting first.
        conn.autocommit(False)
        try:
            with conn.cursor() as cur:
                yield cur
            conn.commit()
        except Exception:
            try:
                conn.rollback()
            except Exception:
                # Connection died mid-transaction. Force a reconnect on
                # next use; pymysql leaves the connection in a partial
                # state otherwise.
                self.close()
            raise
        finally:
            try:
                if conn.open:
                    conn.autocommit(True)
            except Exception:
                pass

    # ---- per-slot table name helpers ----
    # MPOS uses one base table per category for the parent chain (`blocks`,
    # `shares`, `shares_archive`, `transactions`) and a `_<slot>` suffix
    # for each aux chain. The parent slot is the empty string `""`; aux
    # slots are `mm`, `mm1`, `mm3`, `mm4`, `mm5` (and `mm2`/`mm6` reserved).

    _ALLOWED_SLOTS = ("", "mm", "mm1", "mm2", "mm3", "mm4", "mm5", "mm6")

    @classmethod
    def _suffixed(cls, base: str, slot: str) -> str:
        if slot == "":
            return base
        if slot not in cls._ALLOWED_SLOTS:
            raise ValueError(f"unknown coin slot: {slot!r}")
        return f"{base}_{slot}"

    def _blocks_table(self, slot: str) -> str:
        return self._suffixed("blocks", slot)

    def _transactions_table(self, slot: str) -> str:
        return self._suffixed("transactions", slot)

    def _shares_archive_table(self, slot: str) -> str:
        return self._suffixed("shares_archive", slot)

    def get_last_block(self, slot: str = "") -> dict | None:
        return self.fetchone(
            f"SELECT * FROM {self._blocks_table(slot)} ORDER BY height DESC LIMIT 1"
        )

    def get_blocks_without_share_id(self, slot: str = "") -> list[dict]:
        return self.fetchall(
            f"SELECT * FROM {self._blocks_table(slot)} "
            f"WHERE share_id IS NULL ORDER BY height ASC"
        )

    def add_block(self, slot: str, *, blockhash: str, height: int,
                  amount: float, confirmations: int, difficulty: float,
                  time_: int) -> bool:
        # MPOS schema declares `time` as `int(11)` (unix seconds), not
        # DATETIME. Pass the raw integer through.
        rows = self.execute(
            f"INSERT INTO {self._blocks_table(slot)} "
            f"(blockhash, height, amount, confirmations, difficulty, time) "
            f"VALUES (%s, %s, %s, %s, %s, %s)",
            (blockhash, height, amount, confirmations, difficulty, time_),
        )
        return rows > 0

    def set_block_share_id(self, slot: str, block_id: int, share_id: int | None) -> bool:
        return self.execute(
            f"UPDATE {self._blocks_table(slot)} SET share_id=%s WHERE id=%s",
            (share_id, block_id),
        ) > 0

    def set_block_finder(self, slot: str, block_id: int, account_id: int | None) -> bool:
        return self.execute(
            f"UPDATE {self._blocks_table(slot)} SET account_id=%s WHERE id=%s",
            (account_id, block_id),
        ) > 0

    def set_block_finding_worker(self, slot: str, block_id: int, worker: str | None) -> bool:
        return self.execute(
            f"UPDATE {self._blocks_table(slot)} SET worker_name=%s WHERE id=%s",
            (worker, block_id),
        ) > 0

    def set_block_shares(self, slot: str, block_id: int, shares: int | None) -> bool:
        return self.execute(
            f"UPDATE {self._blocks_table(slot)} SET shares=%s WHERE id=%s",
            (shares, block_id),
        ) > 0

    def get_blocks_below_threshold_confirmations(self, slot: str, threshold: int) -> list[dict]:
        """Blocks whose recorded `confirmations` is below `threshold` and
        is not already marked orphaned (-1). These are the rows the
        confirmation-tracking job should refresh from the daemon."""
        return self.fetchall(
            f"SELECT id, height, blockhash, confirmations FROM {self._blocks_table(slot)} "
            f"WHERE confirmations >= 0 AND confirmations < %s "
            f"ORDER BY height ASC",
            (threshold,),
        )

    def set_block_confirmations(self, slot: str, block_id: int, confirmations: int) -> bool:
        return self.execute(
            f"UPDATE {self._blocks_table(slot)} SET confirmations = %s WHERE id = %s",
            (confirmations, block_id),
        ) > 0

    # ---- share table helpers (parent only for now) ----

    def get_last_share_id(self, slot: str = "") -> int:
        # The last *accounted* block in this slot — i.e., the most
        # recent one with share_id already set. `get_last_block`
        # returns the highest-height row regardless of share_id,
        # which means as soon as the next unaccounted block is
        # inserted (still NULL share_id) this would return 0 and the
        # caller would count round-shares against "since pool start"
        # instead of "since the previous block".
        row = self.fetchone(
            f"SELECT share_id FROM {self._blocks_table(slot)} "
            f"WHERE share_id IS NOT NULL ORDER BY share_id DESC LIMIT 1"
        )
        return int(row["share_id"]) if row and row.get("share_id") is not None else 0

    def find_upstream_share(self, *, blockhash: str, prev_share_id: int,
                            block_time: int | None = None,
                            exclude_ids: list[int] | None = None,
                            require_upstream: bool = True) -> dict | None:
        """Find the parent-stream pool share that produced this block.

        MPOS's PHP findUpstreamShare tries four strategies; the
        time-window one (`id > last AND time within ±60s of block.time`)
        is what matches for our pool. We implement that against a UNION
        of the live `shares` table and the `shares_archive` table —
        aux findblock often runs against blocks whose parent shares
        were already archived by an earlier pplns_payout tick.

        `require_upstream` controls the row filter:
          - True  → `upstream_result='Y'`. Right for the parent (BLC)
            slot: only BLC-winning shares can BE the BLC block.
          - False → `our_result='Y'`. Right for aux slots: an aux block
            can be produced by ANY valid pool share carrying the aux
            merkle commitment, regardless of whether that share also
            happened to win the parent chain.

        Returns the share row dict, or None if no match.
        """
        if block_time is None:
            return None
        result_col = "upstream_result" if require_upstream else "our_result"
        params: list[Any] = [
            prev_share_id, block_time, block_time,
            prev_share_id, block_time, block_time,
        ]
        sql = (
            "SELECT id, username, our_result, upstream_result FROM ("
            "  SELECT id, username, our_result, upstream_result, time "
            "  FROM shares "
            f"  WHERE {result_col} = 'Y' AND id > %s "
            "    AND UNIX_TIMESTAMP(time) >= %s - 60 "
            "    AND UNIX_TIMESTAMP(time) <= %s + 60"
            "  UNION ALL "
            "  SELECT share_id AS id, username, our_result, upstream_result, time "
            "  FROM shares_archive "
            f"  WHERE {result_col} = 'Y' AND share_id > %s "
            "    AND UNIX_TIMESTAMP(time) >= %s - 60 "
            "    AND UNIX_TIMESTAMP(time) <= %s + 60"
            ") u"
        )
        if exclude_ids:
            placeholders = ",".join(["%s"] * len(exclude_ids))
            sql += f" WHERE u.id NOT IN ({placeholders})"
            params.extend(exclude_ids)
        sql += " ORDER BY u.id ASC LIMIT 1"
        return self.fetchone(sql, tuple(params))

    def get_round_shares(self, prev_share_id: int, current_share_id: int) -> int:
        row = self.fetchone(
            "SELECT COUNT(*) AS n FROM shares "
            "WHERE id > %s AND id <= %s AND our_result = 'Y'",
            (prev_share_id, current_share_id),
        )
        return int(row["n"]) if row else 0

    def get_user_id(self, username: str) -> int | None:
        # Strip worker suffix `user.worker` → `user`
        username = username.split(".", 1)[0] if username else username
        row = self.fetchone(
            "SELECT id FROM accounts WHERE username = %s LIMIT 1",
            (username,),
        )
        return int(row["id"]) if row else None

    # ---- pplns_payout helpers ---------------------------------------------

    def get_unaccounted_blocks(self, slot: str = "") -> list[dict]:
        """Blocks ready for credit accounting: accounted=0, share_id set,
        and not orphaned.

        Ordered by `share_id ASC`, NOT `id ASC` or `height ASC`. The
        round-share window pplns_payout uses is `(prev.share_id, cur.share_id]`,
        so iterating in share_id order makes the windows naturally compound
        and avoids the out-of-order trap that fires when blocks are inserted
        in confirmation order but credited in id order.

        Orphaned blocks (`confirmations = -1`, set by `blockupdate` when the
        coinbase transaction's category goes to `orphan`) are excluded —
        we never credit them in the first place. If a block is credited
        and LATER goes orphan, the balance-sum SQL in
        `get_accounts_above_threshold` drops it from the user's confirmed
        balance automatically; no reversal Debit row needed.
        """
        return self.fetchall(
            f"SELECT * FROM {self._blocks_table(slot)} "
            f"WHERE accounted = 0 AND share_id IS NOT NULL "
            f"  AND confirmations >= 0 "
            f"ORDER BY share_id ASC, id ASC"
        )

    def set_block_accounted(self, slot: str, block_id: int) -> bool:
        return self.execute(
            f"UPDATE {self._blocks_table(slot)} SET accounted = 1 WHERE id = %s",
            (block_id,),
        ) > 0

    def get_setting(self, name: str) -> str | None:
        row = self.fetchone(
            "SELECT value FROM settings WHERE name = %s",
            (name,),
        )
        return row["value"] if row else None

    def set_setting(self, name: str, value: str) -> None:
        self.execute(
            "INSERT INTO settings (name, value) VALUES (%s, %s) "
            "ON DUPLICATE KEY UPDATE value = VALUES(value)",
            (name, value),
        )

    def get_block_by_id(self, slot: str, block_id: int) -> dict | None:
        return self.fetchone(
            f"SELECT * FROM {self._blocks_table(slot)} WHERE id = %s",
            (block_id,),
        )

    def get_minimum_share_id(self, *, target: float, current_upstream: int,
                             difficulty_const: int) -> int:
        """Mirror of PHP `Share::getMinimumShareId(iCount, current_upstream)`.

        When the round (window `(prev_share_id, current_share_id]`) has
        more diff-normalized valid shares than the configured PPLNS
        target, PHP narrows the credited window to just the most-recent
        N shares whose diff-normalized sum equals the target. This
        helper returns the minimum share id `b` such that the sum of
        diff-normalized valid shares in `[b, current_upstream]` is
        approximately `target` (cumulative-sum-from-the-top approach).

        Algorithm (faithful to PHP `share.class.php:404`):

            target_norm = target * 2^(difficulty_const - 16)
            running_sum = 0
            for share in shares ORDER BY id DESC:
                if id > current_upstream: skip
                if running_sum >= target_norm: break
                running_sum += (difficulty if difficulty != 0
                                 else 2^(difficulty_const - 16))
            return MIN(id) over all visited where total <= target_norm

        Returns 0 if there are no qualifying shares (caller falls back
        to the previous share id, matching PHP's behaviour of treating
        a missing minimum as "use everything").

        Wave 2 fix (was Wave 1 single-table): UNION over live `shares`
        AND `shares_archive` so an aux PPLNS job that runs after parent
        archived its window-shares can still find the right minimum-id.
        Without this, aux PPLNS's `current_upstream` could land in the
        archive range, the live-only lookup returns nothing, and the
        narrowing step is skipped — distributing rewards across too many
        shares.
        """
        baseline = 2.0 ** (difficulty_const - 16)
        target_norm = float(target) * baseline
        # MariaDB-compatible running-total over the UNION of live
        # `shares` + `shares_archive`. Inner UNION ALL gathers
        # candidates from both tables (id <= current_upstream filter
        # pushed down to each); outer ordering + running-total picks
        # off the most-recent shares until @total crosses target_norm.
        # `shares_archive.id` is only the archive row PK; the original
        # upstream share id is `shares_archive.share_id`.
        sql = (
            "SELECT MIN(b.id) AS id FROM ("
            "  SELECT id, "
            "         @total := @total + IF(difficulty=0, %s, difficulty) AS total "
            "  FROM ("
            "    SELECT id, difficulty FROM shares "
            "      WHERE our_result = 'Y' AND id <= %s "
            "    UNION ALL "
            "    SELECT share_id AS id, difficulty FROM shares_archive "
            "      WHERE our_result = 'Y' AND share_id <= %s "
            "  ) AS u, (SELECT @total := 0) AS a "
            "  WHERE @total < %s "
            "  ORDER BY id DESC"
            ") AS b "
            "WHERE total <= %s"
        )
        row = self.fetchone(sql, (baseline,
                                  current_upstream, current_upstream,
                                  target_norm, target_norm))
        if not row or row.get("id") is None:
            return 0
        return int(row["id"])

    def round_share_breakdown_diff(self, prev_share_id: int,
                                   current_share_id: int, *,
                                   difficulty_const: int) -> list[dict]:
        """Diff-normalized counterpart of `round_share_breakdown`.

        Each share contributes `difficulty / 2^(difficulty_const - 16)`
        to its account's `valid` (or `invalid`) count, instead of `1`.
        This is what PHP's `Share::getSharesForAccounts` returns and
        what PPLNS proportional payout actually expects — a vardiff
        miner submitting one share at diff=1024 contributes 1024× more
        than a fixed-diff miner at diff=1.

        Output rows: {account_id, username, valid, invalid}, where
        `valid` and `invalid` are floats (diff-normalized counts).
        """
        baseline = 2.0 ** (difficulty_const - 16)
        sql = (
            "SELECT a.id AS account_id, a.username AS username, "
            "  ROUND(IFNULL(SUM(IF(u.our_result='Y', "
            "        IF(u.difficulty=0, %s, u.difficulty), 0)), 0) / %s, 8) AS valid, "
            "  ROUND(IFNULL(SUM(IF(u.our_result='N', "
            "        IF(u.difficulty=0, %s, u.difficulty), 0)), 0) / %s, 8) AS invalid "
            "FROM ("
            "  SELECT id, username, our_result, difficulty FROM shares "
            "  WHERE id > %s AND id <= %s "
            "  UNION ALL "
            "  SELECT share_id AS id, username, our_result, difficulty FROM shares_archive "
            "  WHERE share_id > %s AND share_id <= %s"
            ") u "
            "LEFT JOIN accounts a "
            "  ON a.username = SUBSTRING_INDEX(u.username, '.', 1) "
            "GROUP BY a.id, a.username"
        )
        rows = self.fetchall(sql, (
            baseline, baseline, baseline, baseline,
            prev_share_id, current_share_id,
            prev_share_id, current_share_id,
        ))
        for r in rows:
            r["valid"] = float(r.get("valid") or 0.0)
            r["invalid"] = float(r.get("invalid") or 0.0)
        return rows

    def archive_share_breakdown_diff(self, *, target_extra: float,
                                     exclude_above_id: int,
                                     difficulty_const: int) -> list[dict]:
        """Diff-normalized archive fill-up.

        When the current round's diff-normalized valid sum is below the
        PPLNS target, the PPLNS rule is to fold in the most-recent
        archived shares whose diff-normalized sum makes up the difference.
        PHP's `Share::getArchiveShares($target_extra)` selects the most
        recent rows from `shares_archive` where the running diff-sum is
        <= `target_extra`. We reproduce that with the same
        running-total trick used in `get_minimum_share_id`.

        Returns rows {account_id, username, valid, invalid} as floats.
        """
        if target_extra <= 0:
            return []
        baseline = 2.0 ** (difficulty_const - 16)
        target_extra_norm = float(target_extra) * baseline
        sql = (
            "SELECT a.id AS account_id, a.username AS username, "
            "  ROUND(IFNULL(SUM(IF(b.our_result='Y', "
            "        IF(b.difficulty=0, %s, b.difficulty), 0)), 0) / %s, 8) AS valid, "
            "  ROUND(IFNULL(SUM(IF(b.our_result='N', "
            "        IF(b.difficulty=0, %s, b.difficulty), 0)), 0) / %s, 8) AS invalid "
            "FROM ("
            "  SELECT share_id, username, our_result, difficulty, "
            "         @atotal := @atotal + IF(difficulty=0, %s, difficulty) AS total "
            "  FROM shares_archive, (SELECT @atotal := 0) AS x "
            "  WHERE share_id < %s AND @atotal < %s "
            "  ORDER BY share_id DESC"
            ") AS b "
            "LEFT JOIN accounts a "
            "  ON a.username = SUBSTRING_INDEX(b.username, '.', 1) "
            "WHERE b.total <= %s "
            "GROUP BY a.id, a.username"
        )
        rows = self.fetchall(sql, (
            baseline, baseline, baseline, baseline, baseline,
            exclude_above_id, target_extra_norm, target_extra_norm,
        ))
        for r in rows:
            r["valid"] = float(r.get("valid") or 0.0)
            r["invalid"] = float(r.get("invalid") or 0.0)
        return rows

    def get_round_shares_diff(self, prev_share_id: int,
                              current_share_id: int, *,
                              difficulty_const: int) -> float:
        """Diff-normalized total valid shares in (prev, current].
        Mirrors PHP `Share::getRoundShares`.
        """
        baseline = 2.0 ** (difficulty_const - 16)
        row = self.fetchone(
            "SELECT ROUND(IFNULL(SUM(IF(u.our_result='Y', "
            "    IF(u.difficulty=0, %s, u.difficulty), 0)), 0) / %s, 8) AS total "
            "FROM ("
            "  SELECT id, our_result, difficulty FROM shares "
            "  WHERE id > %s AND id <= %s "
            "  UNION ALL "
            "  SELECT share_id AS id, our_result, difficulty FROM shares_archive "
            "  WHERE share_id > %s AND share_id <= %s"
            ") u",
            (baseline, baseline,
             prev_share_id, current_share_id,
             prev_share_id, current_share_id),
        )
        return float(row["total"] or 0.0) if row else 0.0

    # ---- Wave 2: manual payout queue ------------------------------------

    def get_manual_payout_queue(self, slot: str = "",
                                min_confirmations: int = 100,
                                txfee_manual: float = 0.0) -> list[dict]:
        """Manual payouts the operator has queued via the web UI.

        Mirrors PHP `Transaction::getMPQueue` (transaction.class.php:435):
        the `payouts` table only stores `(id, account_id, time, completed)`
        — there is NO amount column. The "amount" for a manual payout
        is the user's confirmed balance computed at process time, the
        same way auto-payouts work.

        Returns rows {payout_id, account_id, username, payout_address,
        amount}. `amount` is the confirmed balance per the canonical
        balance SQL.
        """
        payouts_table = self._suffixed("payouts", slot)
        coin_addr_col = "coin_address" if slot == "" else f"coin_address_{slot}"
        txn_table = self._transactions_table(slot)
        block_table = self._blocks_table(slot)
        confirmed = self._confirmed_balance_sql(
            txn_table=txn_table, block_table=block_table,
        )
        sql = (
            f"SELECT p.id AS payout_id, p.account_id, "
            f"       a.username, a.{coin_addr_col} AS payout_address, "
            f"       {confirmed} AS amount "
            f"FROM {payouts_table} p "
            f"JOIN accounts a ON a.id = p.account_id "
            f"JOIN {txn_table} t ON t.account_id = p.account_id "
            f"LEFT JOIN {block_table} b ON b.id = t.block_id "
            f"WHERE p.completed = 0 "
            f"  AND t.archived = 0 "
            f"  AND a.{coin_addr_col} IS NOT NULL "
            f"  AND a.{coin_addr_col} <> '' "
            f"GROUP BY t.account_id, p.id "
            f"HAVING amount > %s "
            f"ORDER BY p.id ASC"
        )
        try:
            return self.fetchall(sql, (
                min_confirmations, min_confirmations, txfee_manual,
            ))
        except pymysql.err.ProgrammingError as exc:
            # 1146 = ER_NO_SUCH_TABLE — aux slots don't have their own
            # payouts table in many deploys; fall back to empty.
            if exc.args and exc.args[0] == 1146:
                return []
            raise

    def mark_manual_payout_complete(self, slot: str, payout_id: int,
                                    *, cur: pymysql.cursors.DictCursor) -> bool:
        payouts_table = self._suffixed("payouts", slot)
        cur.execute(
            f"UPDATE {payouts_table} SET completed = 1 WHERE id = %s",
            (payout_id,),
        )
        return cur.rowcount > 0

    # ---- Wave 2: archive-in-payout-cycle (createPayoutDebitRecord) ------

    def set_account_transactions_archived(self, *,
                                          cur: pymysql.cursors.DictCursor,
                                          account_id: int,
                                          insert_id_max: int,
                                          slot: str = "") -> int:
        """Mark all of `account_id`'s currently-unarchived transactions
        with id <= `insert_id_max` as `archived = 1`.

        Mirrors PHP `Transaction::setArchived`. Called inside the
        payout transaction right after the Debit_AP / TXFee rows have
        been inserted, so a future tick of the same account doesn't
        re-net the same Credit / Fee rows into the auto-payout queue
        candidate set. The Debit_AP itself is NOT archived (since the
        cron-cycle re-uses the row to compute future balances).

        PHP archives Credit / Bonus / Fee / Donation rows whose
        block_id is confirmed, plus Credit_PPS / Donation_PPS / Fee_PPS
        / TXFee unconditionally. The new Debit_AP / Debit_MP rows are
        NOT archived because they remain in the live ledger as the
        "pending balance offset". Match that exactly:
        """
        txn_table = self._transactions_table(slot)
        block_table = self._blocks_table(slot)
        cur.execute(
            f"UPDATE {txn_table} t "
            f"LEFT JOIN {block_table} b ON b.id = t.block_id "
            f"SET t.archived = 1 "
            f"WHERE t.account_id = %s "
            f"  AND t.archived = 0 "
            f"  AND t.id <= %s "
            f"  AND ( "
            f"    (t.type IN ('Credit','Bonus','Fee','Donation') "
            f"      AND b.confirmations >= 0) "
            f"    OR t.type IN ('Credit_PPS','Donation_PPS','Fee_PPS','TXFee') "
            f"  )",
            (account_id, insert_id_max),
        )
        return cur.rowcount

    # ---- Wave 2: per-account fee / donation / lock helpers --------------

    def get_account_fee_meta(self, account_id: int) -> dict:
        """Per-account fee/donation/lock state. Mirrors the columns
        PHP looks up via User::getNoFee, User::getDonatePercent,
        User::isLocked.

        Returns {no_fees: bool, donate_percent: float, is_locked: int}.
        Caller (pplns_payout) uses this to decide whether to charge
        the pool's `fees` percent and how much of the post-fee credit
        to redirect as a Donation row.
        """
        row = self.fetchone(
            "SELECT no_fees, donate_percent, is_locked FROM accounts "
            "WHERE id = %s",
            (account_id,),
        )
        if not row:
            # Unknown account — caller treats as "no fees, no donation,
            # not locked" rather than failing. (The same shares would
            # have been credited under PHP because PHP's join is LEFT.)
            return {"no_fees": False, "donate_percent": 0.0, "is_locked": 0}
        return {
            "no_fees": bool(row["no_fees"]),
            "donate_percent": float(row["donate_percent"] or 0.0),
            "is_locked": int(row["is_locked"] or 0),
        }

    def round_share_breakdown(self, prev_share_id: int,
                              current_share_id: int) -> list[dict]:
        """Per-account valid/invalid share counts in the round window.

        Always reads from the PARENT share stream (`shares` + `shares_archive`)
        because in our merge-mined setup eloipool writes shares to a single
        table — every aux block is attributed against the same per-miner
        work the parent block is. Aux slot-specific share tables
        (`shares_mm`, `shares_mm1` …) stay empty in this deployment;
        they're a relic of the era when each aux chain ran its own pool.

        UNION over `shares` (live) + `shares_archive` (already moved by
        parent's pplns) — handles the race where parent's pplns ran for
        a window first and archived the rows before the aux slot's pplns
        gets to them.

        Output rows: {account_id, username, valid, invalid}.
        """
        sql = (
            "SELECT a.id AS account_id, a.username AS username, "
            "  SUM(u.our_result = 'Y') AS valid, "
            "  SUM(u.our_result = 'N') AS invalid "
            "FROM ("
            "  SELECT id, username, our_result FROM shares "
            "  WHERE id > %s AND id <= %s"
            "  UNION ALL "
            "  SELECT share_id AS id, username, our_result FROM shares_archive "
            "  WHERE share_id > %s AND share_id <= %s"
            ") u "
            "LEFT JOIN accounts a "
            "  ON a.username = SUBSTRING_INDEX(u.username, '.', 1) "
            "GROUP BY a.id, a.username"
        )
        rows = self.fetchall(sql, (prev_share_id, current_share_id,
                                   prev_share_id, current_share_id))
        for r in rows:
            r["valid"] = int(r.get("valid") or 0)
            r["invalid"] = int(r.get("invalid") or 0)
        return rows

    def get_avg_block_shares(self, slot: str, height: int,
                             limit: int) -> float:
        """Average `shares` of the last `limit` blocks at or below `height`.

        Mirrors `BlockClass::getAvgBlockShares` in MPOS PHP — used to
        compute the PPLNS target in `blockavg` and `dynamic` modes.
        Returns 0.0 if there are no blocks yet.
        """
        row = self.fetchone(
            f"SELECT AVG(x.shares) AS average FROM ("
            f"  SELECT shares FROM {self._blocks_table(slot)} "
            f"  WHERE height <= %s AND shares IS NOT NULL "
            f"  ORDER BY height DESC LIMIT %s) AS x",
            (height, limit),
        )
        return float(row["average"] or 0.0) if row else 0.0

    def archive_share_breakdown(self, *, target_extra: int,
                                exclude_above_id: int) -> list[dict]:
        """Per-account valid/invalid counts pulled from `shares_archive`.

        Pulls the `target_extra` most-recent rows whose share_id is
        strictly less than `exclude_above_id` (so we don't re-count
        anything already in the current round window). Returns the same
        shape as `round_share_breakdown`.

        Used by pplns_payout's archive fill-up step: when the current
        round has fewer valid shares than the PPLNS target, fold in
        recent archived shares so the block reward stays fully
        distributed across miners who recently contributed work.
        """
        if target_extra <= 0:
            return []
        # First fetch the most-recent N archived share_ids that meet our
        # filter, then aggregate by account. Two-step is simpler than
        # window functions and keeps compatibility with older MariaDB.
        rows = self.fetchall(
            "SELECT a.id AS account_id, a.username AS username, "
            "  SUM(sa.our_result = 'Y') AS valid, "
            "  SUM(sa.our_result = 'N') AS invalid "
            "FROM (SELECT * FROM shares_archive "
            "      WHERE share_id < %s "
            "      ORDER BY id DESC LIMIT %s) sa "
            "LEFT JOIN accounts a "
            "  ON a.username = SUBSTRING_INDEX(sa.username, '.', 1) "
            "GROUP BY a.id, a.username",
            (exclude_above_id, target_extra),
        )
        for r in rows:
            r["valid"] = int(r.get("valid") or 0)
            r["invalid"] = int(r.get("invalid") or 0)
        return rows

    def add_transaction(self, *, account_id: int, amount: float,
                        kind: str, block_id: int | None,
                        coin_address: str | None = None,
                        txid: str | None = None,
                        slot: str = "") -> int:
        """Insert a row into the per-slot transactions table.

        Each slot keeps its own ledger so credits/payouts in different
        coins don't mix amounts. Returns the new transaction id.

        Uses an autocommitted cursor — fine for one-shot inserts (e.g.
        Debit_AP after a successful sendtoaddress). For multi-statement
        atomic work (pplns_payout's credit/fee/archive/accounted batch)
        use `add_transaction_in_tx` and pass the open transaction
        cursor instead.
        """
        table = self._transactions_table(slot)
        with self.cursor() as cur:
            cur.execute(
                f"INSERT INTO {table} "
                f"(account_id, amount, type, block_id, coin_address, txid, timestamp) "
                f"VALUES (%s, %s, %s, %s, %s, %s, NOW())",
                (account_id, amount, kind, block_id, coin_address, txid),
            )
            return int(cur.lastrowid)

    def add_transaction_in_tx(self, *, cur: pymysql.cursors.DictCursor,
                              account_id: int, amount: float,
                              kind: str, block_id: int | None,
                              coin_address: str | None = None,
                              txid: str | None = None,
                              slot: str = "") -> int:
        """Same as `add_transaction`, but writes through the caller's
        already-open cursor so the INSERT participates in the caller's
        transaction. Returns the new transaction id.
        """
        table = self._transactions_table(slot)
        cur.execute(
            f"INSERT INTO {table} "
            f"(account_id, amount, type, block_id, coin_address, txid, timestamp) "
            f"VALUES (%s, %s, %s, %s, %s, %s, NOW())",
            (account_id, amount, kind, block_id, coin_address, txid),
        )
        return int(cur.lastrowid)

    def set_block_accounted_in_tx(self, *,
                                  cur: pymysql.cursors.DictCursor,
                                  slot: str, block_id: int) -> bool:
        cur.execute(
            f"UPDATE {self._blocks_table(slot)} SET accounted = 1 "
            f"WHERE id = %s",
            (block_id,),
        )
        return cur.rowcount > 0

    def insert_pplns_shares_in_tx(self, *,
                                  cur: pymysql.cursors.DictCursor,
                                  slot: str,
                                  block_id: int,
                                  per_account: dict[int, dict]) -> int:
        """Persist the per-account difficulty-normalized PPLNS breakdown
        for one accounted block. Replaces the legacy PHP write into
        `statistics_shares` (parent-only, schema can't represent aux);
        the new `pplns_shares` table carries a `slot` column so aux
        coins get their own breakdown.

        Idempotent via the UNIQUE (slot, block_id, account_id) key:
        re-runs of the same payout INSERT…ON DUPLICATE KEY UPDATE the
        row in place rather than aborting.

        Returns the number of rows written.
        """
        if not per_account:
            return 0
        rows = [
            (slot, block_id, int(aid),
             float(r.get("valid", 0.0)),
             float(r.get("invalid", 0.0)))
            for aid, r in per_account.items()
            if int(aid) > 0
        ]
        if not rows:
            return 0
        cur.executemany(
            "INSERT INTO pplns_shares "
            "  (slot, block_id, account_id, pplns_valid, pplns_invalid) "
            "VALUES (%s, %s, %s, %s, %s) "
            "ON DUPLICATE KEY UPDATE "
            "  pplns_valid = VALUES(pplns_valid), "
            "  pplns_invalid = VALUES(pplns_invalid)",
            rows,
        )
        return cur.rowcount

    def archive_and_delete_shares_in_tx(self, *,
                                        cur: pymysql.cursors.DictCursor,
                                        prev_share_id: int,
                                        current_share_id: int,
                                        block_id: int,
                                        slot: str = "") -> tuple[int, int]:
        """Same as `archive_and_delete_shares`, but writes through the
        caller's open cursor so it participates in the caller's
        transaction. Aux slots (slot != "") still no-op since they
        share the parent share stream.
        """
        if slot != "":
            return (0, 0)
        cur.execute(
            "INSERT INTO shares_archive "
            "(share_id, username, our_result, upstream_result, "
            " block_id, difficulty, time) "
            "SELECT id, username, our_result, upstream_result, "
            "       %s, difficulty, time "
            "FROM shares WHERE id > %s AND id <= %s",
            (block_id, prev_share_id, current_share_id),
        )
        archived = cur.rowcount
        cur.execute(
            "DELETE FROM shares WHERE id > %s AND id <= %s",
            (prev_share_id, current_share_id),
        )
        deleted = cur.rowcount
        return archived, deleted

    def archive_and_delete_shares(self, prev_share_id: int,
                                  current_share_id: int,
                                  block_id: int,
                                  slot: str = "") -> tuple[int, int]:
        """Mirror MPOS's `moveArchive` + `deleteAccountedShares`.

        Only acts when `slot == ""` (the parent slot). Aux slots share
        the parent's share stream — if every slot's pplns deleted the
        shares, the FIRST slot to tick would erase them and every later
        slot's round would come up empty. Aux ticks are no-ops here:
        their `round_share_breakdown` reads via UNION over `shares` and
        `shares_archive`, so they see the rows whether or not the parent
        has archived them yet.

        Returns (archived, deleted) for the parent slot, or `(0, 0)` for
        aux slots.
        """
        if slot != "":
            return (0, 0)
        with self.cursor() as cur:
            cur.execute(
                "INSERT INTO shares_archive "
                "(share_id, username, our_result, upstream_result, "
                " block_id, difficulty, time) "
                "SELECT id, username, our_result, upstream_result, "
                "       %s, difficulty, time "
                "FROM shares WHERE id > %s AND id <= %s",
                (block_id, prev_share_id, current_share_id),
            )
            archived = cur.rowcount
            cur.execute(
                "DELETE FROM shares WHERE id > %s AND id <= %s",
                (prev_share_id, current_share_id),
            )
            deleted = cur.rowcount
        return archived, deleted

    # ---- payouts helpers --------------------------------------------------

    # ---- statistics queries (used by the statistics job) -----------------

    def stats_current_hashrate(self, *, target_bits: int, difficulty_const: int,
                               interval: int = 180) -> float:
        """kH/s over the last `interval` seconds across `shares` + `shares_archive`.

        Mirrors `Statistics::getCurrentHashrate` in MPOS PHP. The
        `target_bits` value comes from MPOS config (`config.target_bits`,
        usually 32 for SHA-256-style chains, see global.inc.dist.php).
        `difficulty_const` is `config.difficulty` (32 by default).
        """
        # The SQL is identical to PHP's: sum(diff or POW(2, diff_const-16))
        # times POW(2, target_bits) divided by interval, divided by 1000
        # to get kH/s.
        sql = (
            f"SELECT ("
            f"  (SELECT IFNULL(ROUND(SUM(IF(difficulty=0, "
            f"          POW(2, ({difficulty_const} - 16)), difficulty)) "
            f"          * POW(2, {target_bits}) / %s / 1000), 0) "
            f"   FROM shares "
            f"   WHERE time > DATE_SUB(NOW(), INTERVAL %s SECOND) "
            f"     AND our_result = 'Y') "
            f" + "
            f"  (SELECT IFNULL(ROUND(SUM(IF(difficulty=0, "
            f"          POW(2, ({difficulty_const} - 16)), difficulty)) "
            f"          * POW(2, {target_bits}) / %s / 1000), 0) "
            f"   FROM shares_archive "
            f"   WHERE time > DATE_SUB(NOW(), INTERVAL %s SECOND) "
            f"     AND our_result = 'Y')"
            f") AS hashrate"
        )
        row = self.fetchone(sql, (interval, interval, interval, interval))
        return float(row["hashrate"] or 0.0) if row else 0.0

    def stats_current_round_id(self) -> int:
        row = self.fetchone(
            "SELECT IFNULL(id, 0) AS id FROM blocks ORDER BY height DESC LIMIT 1"
        )
        return int(row["id"] or 0) if row else 0

    def stats_max_share_id(self) -> int:
        row = self.fetchone("SELECT IFNULL(MAX(id), 0) AS id FROM shares")
        return int(row["id"] or 0) if row else 0

    def stats_per_user_shares(self, *, difficulty_const: int) -> list[dict]:
        """Per-user valid/invalid share totals for the current round.

        Mirrors `Statistics::getAllUserShares` and writes the same row
        shape PHP expects under `STATISTICS_ALL_USER_SHARES`.
        """
        sql = (
            "SELECT "
            f"  ROUND(IFNULL(SUM(IF(s.our_result='Y', IF(s.difficulty=0, POW(2, ({difficulty_const} - 16)), s.difficulty), 0)), 0) / POW(2, ({difficulty_const} - 16)), 0) AS valid, "
            f"  ROUND(IFNULL(SUM(IF(s.our_result='N', IF(s.difficulty=0, POW(2, ({difficulty_const} - 16)), s.difficulty), 0)), 0) / POW(2, ({difficulty_const} - 16)), 0) AS invalid, "
            "  u.id AS id, "
            "  u.donate_percent AS donate_percent, "
            "  u.is_anonymous AS is_anonymous, "
            "  u.username AS username "
            "FROM shares AS s, accounts AS u "
            "WHERE u.username = SUBSTRING_INDEX(s.username, '.', 1) "
            "  AND UNIX_TIMESTAMP(s.time) > IFNULL((SELECT MAX(b.time) FROM blocks AS b), 0) "
            "GROUP BY u.id"
        )
        rows = self.fetchall(sql)
        for r in rows:
            r["id"] = int(r.get("id") or 0)
            r["valid"] = float(r.get("valid") or 0)
            r["invalid"] = float(r.get("invalid") or 0)
            r["donate_percent"] = float(r.get("donate_percent") or 0)
            r["is_anonymous"] = int(r.get("is_anonymous") or 0)
        return rows

    def stats_top_contributors(self, *, target_bits: int, difficulty_const: int,
                               interval: int = 600, limit: int = 15) -> list[dict]:
        """Top miners by hashrate over the last `interval` seconds."""
        sql = (
            f"SELECT a.username AS account, "
            f"       a.donate_percent AS donate_percent, "
            f"       a.is_anonymous AS is_anonymous, "
            f"       IFNULL(ROUND(SUM(u.difficulty) * POW(2, {target_bits}) / %s / 1000, 2), 0) AS hashrate "
            f"FROM ("
            f"  SELECT id, IFNULL(IF(difficulty=0, POW(2, ({difficulty_const} - 16)), difficulty), 0) AS difficulty, username "
            f"  FROM shares WHERE time > DATE_SUB(NOW(), INTERVAL %s SECOND) AND our_result = 'Y' "
            f"  UNION "
            f"  SELECT share_id, IFNULL(IF(difficulty=0, POW(2, ({difficulty_const} - 16)), difficulty), 0) AS difficulty, username "
            f"  FROM shares_archive WHERE time > DATE_SUB(NOW(), INTERVAL %s SECOND) AND our_result = 'Y'"
            f") u "
            f"LEFT JOIN accounts a "
            f"  ON a.username = SUBSTRING_INDEX(u.username, '.', 1) "
            f"GROUP BY account "
            f"ORDER BY hashrate DESC "
            f"LIMIT %s"
        )
        rows = self.fetchall(sql, (interval, interval, interval, limit))
        for r in rows:
            r["hashrate"] = float(r.get("hashrate") or 0.0)
            r["donate_percent"] = float(r.get("donate_percent") or 0)
            r["is_anonymous"] = int(r.get("is_anonymous") or 0)
        return rows

    def stats_per_worker_mining(self, *, target_bits: int, difficulty_const: int,
                                interval: int = 180) -> list[dict]:
        """Per-WORKER hashrate (keyed by full `account.workername`).

        Returns one row per worker that has at least one share in the
        window, with `hashrate` (kH/s sampled over the window) and
        `last_share_age_sec` (seconds since their most recent share).
        The age field lets the cron detect "going dormant" workers —
        ones whose shares are still inside the window but who stopped
        submitting recently — so their EMA can be decayed aggressively
        instead of waiting for the window to drain.
        """
        sql = (
            f"SELECT u.username AS worker, "
            f"       IFNULL(ROUND(SUM(u.difficulty) * POW(2, {target_bits}) / %s / 1000, 2), 0) AS hashrate, "
            f"       TIMESTAMPDIFF(SECOND, MAX(u.time), NOW()) AS last_share_age_sec "
            f"FROM ("
            f"  SELECT id, IF(difficulty = 0, POW(2, ({difficulty_const} - 16)), difficulty) AS difficulty, username, time "
            f"  FROM shares "
            f"  WHERE time > DATE_SUB(NOW(), INTERVAL %s SECOND) AND our_result = 'Y' "
            f"  UNION ALL "
            f"  SELECT share_id, IF(difficulty = 0, POW(2, ({difficulty_const} - 16)), difficulty) AS difficulty, username, time "
            f"  FROM shares_archive "
            f"  WHERE time > DATE_SUB(NOW(), INTERVAL %s SECOND) AND our_result = 'Y'"
            f") u "
            f"GROUP BY u.username"
        )
        rows = self.fetchall(sql, (interval, interval, interval))
        out = []
        for r in rows:
            out.append({
                "worker": str(r.get("worker") or ""),
                "hashrate": float(r.get("hashrate") or 0.0),
                "last_share_age_sec": int(r.get("last_share_age_sec") or 0),
            })
        return out

    def stats_per_user_mining(self, *, target_bits: int, difficulty_const: int,
                              interval: int = 180) -> list[dict]:
        """Per-user hashrate, sharerate and average difficulty."""
        sql = (
            f"SELECT a.id AS id, "
            f"       a.username AS account, "
            f"       IFNULL(ROUND(SUM(u.difficulty) * POW(2, {target_bits}) / %s / 1000, 2), 0) AS hashrate, "
            f"       ROUND(COUNT(u.id) / %s, 2) AS sharerate, "
            f"       IFNULL(AVG(IF(u.difficulty=0, POW(2, ({difficulty_const} - 16)), u.difficulty)), 0) AS avgsharediff "
            f"FROM ("
            f"  SELECT id, IF(difficulty = 0, POW(2, ({difficulty_const} - 16)), difficulty) AS difficulty, username "
            f"  FROM shares "
            f"  WHERE time > DATE_SUB(NOW(), INTERVAL %s SECOND) AND our_result = 'Y' "
            f"  UNION "
            f"  SELECT share_id, IF(difficulty = 0, POW(2, ({difficulty_const} - 16)), difficulty) AS difficulty, username "
            f"  FROM shares_archive "
            f"  WHERE time > DATE_SUB(NOW(), INTERVAL %s SECOND) AND our_result = 'Y'"
            f") u "
            f"LEFT JOIN accounts a "
            f"  ON a.username = SUBSTRING_INDEX(u.username, '.', 1) "
            f"WHERE a.id IS NOT NULL "
            f"GROUP BY account "
            f"ORDER BY hashrate DESC"
        )
        rows = self.fetchall(sql, (interval, interval, interval, interval))
        for r in rows:
            r["id"] = int(r.get("id") or 0)
            r["hashrate"] = float(r.get("hashrate") or 0.0)
            r["sharerate"] = float(r.get("sharerate") or 0.0)
            r["avgsharediff"] = float(r.get("avgsharediff") or 0.0)
        return rows

    def update_pool_worker_difficulty(self, *, interval: int = 180) -> int:
        """Refresh `pool_worker.difficulty` from recent shares.

        The MPOS web UI reads `pool_worker.difficulty` to display
        per-worker live hashrate (combined with target_bits via the
        same kH/s formula as `getCurrentHashrate`). Eloipool doesn't
        write to this column — it only writes share rows — so without
        this update the UI shows 0 H/s per worker.

        Updates the rolling-average difficulty across both `shares` and
        `shares_archive` over the recent window. Returns the number of
        pool_worker rows whose difficulty value changed.
        """
        sql = (
            "UPDATE pool_worker pw "
            "LEFT JOIN ("
            "  SELECT username, "
            "         AVG(IF(difficulty=0, 1, difficulty)) AS avg_diff "
            "  FROM ("
            "    SELECT username, difficulty FROM shares "
            "    WHERE time > DATE_SUB(NOW(), INTERVAL %s SECOND) "
            "      AND our_result='Y' "
            "    UNION ALL "
            "    SELECT username, difficulty FROM shares_archive "
            "    WHERE time > DATE_SUB(NOW(), INTERVAL %s SECOND) "
            "      AND our_result='Y'"
            "  ) u GROUP BY username "
            ") s ON s.username = pw.username "
            "SET pw.difficulty = COALESCE(s.avg_diff, 0)"
        )
        return self.execute(sql, (interval, interval))

    def get_locked_balance(self, slot: str = "",
                           min_confirmations: int = 100) -> float:
        """Confirmed-only locked balance summed across all accounts.

        PHP-parity: only confirmed credits count. An aux-block reorg that
        would orphan a credit shouldn't reserve hot-wallet balance for
        a payout that's no longer payable.

        Wave 2 changed from Wave 1: respects `archived = 0` filter,
        includes Credit_PPS / Donation_PPS / Fee_PPS / TXFee, gates
        Credit/Bonus + Donation/Fee on `b.confirmations >= min_confs`.
        """
        txn_table = self._transactions_table(slot)
        block_table = self._blocks_table(slot)
        confirmed = self._confirmed_balance_sql(
            txn_table=txn_table, block_table=block_table,
        )
        row = self.fetchone(
            f"SELECT {confirmed} AS locked "
            f"FROM {txn_table} t "
            f"LEFT JOIN {block_table} b ON b.id = t.block_id "
            f"WHERE t.archived = 0",
            (min_confirmations, min_confirmations),
        )
        return float(row["locked"] or 0.0) if row else 0.0

    # ---- Wave 1: poison flag (cronjobs_py_disabled) ---------------------

    def get_disabled_flag(self, scope: str) -> dict | None:
        """Return the disable row for `scope`, or None if the scope is
        not currently disabled. Scope formats: "", "slot:{slot}",
        "job:{name}". Caller decides which scope(s) to check.
        """
        return self.fetchone(
            "SELECT scope, reason, set_by, set_at "
            "FROM cronjobs_py_disabled WHERE scope = %s",
            (scope,),
        )

    def set_disabled_flag(self, scope: str, reason: str,
                          set_by: str = "cronjobs-py") -> None:
        """Idempotently mark `scope` as disabled. ON DUPLICATE KEY refresh
        keeps the latest reason/set_at so the operator sees the most
        recent failure when they investigate.
        """
        self.execute(
            "INSERT INTO cronjobs_py_disabled (scope, reason, set_by) "
            "VALUES (%s, %s, %s) "
            "ON DUPLICATE KEY UPDATE reason = VALUES(reason), "
            "                        set_by = VALUES(set_by), "
            "                        set_at = CURRENT_TIMESTAMP",
            (scope, reason, set_by),
        )

    def clear_disabled_flag(self, scope: str) -> bool:
        return self.execute(
            "DELETE FROM cronjobs_py_disabled WHERE scope = %s",
            (scope,),
        ) > 0

    # ---- Legacy MPOS monitoring table ------------------------------------

    def set_monitoring_status(self, name: str, type_: str, value: object) -> None:
        """Update MPOS's legacy `monitoring` table.

        The PHP web UI still reads this table for Admin -> Monitoring and
        dashboard cron-error counts. cronjobs-py is authoritative for the
        work now, so it must also keep these rows fresh.
        """
        self.execute(
            "INSERT INTO monitoring (name, type, value) "
            "VALUES (%s, %s, %s) "
            "ON DUPLICATE KEY UPDATE type = VALUES(type), value = VALUES(value)",
            (name, type_, str(value)),
        )

    # ---- Wave 1: accounting guard (cronjobs_py_accounting) --------------

    def insert_accounting_guard(self, *, slot: str, block_id: int,
                                account_id: int, tx_type: str,
                                amount: float, txn_id: int | None,
                                cur: pymysql.cursors.DictCursor,
                                mode: str = "live") -> bool:
        """Insert a guard row for (slot, block_id, account_id, tx_type).

        Returns True on success, False if the UNIQUE key fired (the
        same accounting work was already recorded by a previous run —
        caller should treat this as "already credited, skip").

        MUST be called from within `transaction()` so the guard row and
        the corresponding `transactions_<slot>` row commit or roll back
        together. Caller passes the open cursor so the INSERT runs in
        the same transaction.

        `mode='shadow'` (Wave 5) marks this row as a soak-window
        prediction — caller did NOT write the corresponding
        transactions_<slot> row; PHP cron is the authoritative writer.
        The drift-check CLI compares shadow rows against PHP's writes.
        """
        try:
            cur.execute(
                "INSERT INTO cronjobs_py_accounting "
                "(slot, block_id, account_id, tx_type, mode, amount, txn_id) "
                "VALUES (%s, %s, %s, %s, %s, %s, %s)",
                (slot, block_id, account_id, tx_type, mode, amount, txn_id),
            )
            return True
        except pymysql.err.IntegrityError as exc:
            # 1062 = ER_DUP_ENTRY — the guard fired. Anything else is
            # a real schema/data bug.
            if exc.args and exc.args[0] == 1062:
                # Shadow-to-live cutover: a shadow prediction row is not a
                # real credit. The first live run may claim that guard in the
                # same transaction, then write the matching transactions row.
                if mode == "live":
                    cur.execute(
                        "UPDATE cronjobs_py_accounting "
                        "SET mode = 'live', amount = %s, txn_id = %s "
                        "WHERE slot = %s AND block_id = %s "
                        "  AND account_id = %s AND tx_type = %s "
                        "  AND mode = 'shadow' AND txn_id IS NULL",
                        (amount, txn_id, slot, block_id, account_id, tx_type),
                    )
                    if cur.rowcount > 0:
                        return True
                return False
            raise

    def is_block_already_credited(self, slot: str, block_id: int,
                                  mode: str | None = None) -> bool:
        """Quick read-side check used by pplns_payout's pre-flight to
        skip a block whose accounting was already recorded (e.g. a
        retried tick where the previous attempt committed but the
        scheduler marked the run as Failed). Cheap; the authoritative
        check is the UNIQUE in `insert_accounting_guard`.

        When `mode='live'`, shadow-only predictions are ignored so a
        post-soak cutover can promote them into real credits.
        """
        mode_clause = ""
        params: tuple = (slot, block_id)
        if mode is not None:
            mode_clause = " AND mode = %s"
            params = (slot, block_id, mode)
        row = self.fetchone(
            "SELECT 1 FROM cronjobs_py_accounting "
            f"WHERE slot = %s AND block_id = %s{mode_clause} LIMIT 1",
            params,
        )
        return row is not None

    # ---- Wave 1: SELECT FOR UPDATE on a block row ----------------------

    def lock_block_for_update(self, slot: str, block_id: int,
                              cur: pymysql.cursors.DictCursor) -> dict | None:
        """Acquire a row lock on a block for the duration of the open
        transaction. Returns the row, or None if the block is gone.

        Used by pplns_payout to prevent two ticks of the same job
        crediting the same block. The lock is released on COMMIT or
        ROLLBACK of the surrounding transaction.

        MUST be called from within `transaction()` — calling it on an
        autocommit connection is a no-op (the row lock is released
        immediately when the SELECT returns).
        """
        cur.execute(
            f"SELECT * FROM {self._blocks_table(slot)} WHERE id = %s "
            f"FOR UPDATE",
            (block_id,),
        )
        return cur.fetchone()

    # ---- Wave 1: outbox state machine -----------------------------------

    def insert_outbox_pending(self, *, slot: str, account_id: int,
                              coin_address: str, amount: float,
                              wallet_comment: str) -> int:
        """Reserve an outbox slot before the wallet send is issued.

        wallet_comment is the idempotency anchor: the value is written
        here, then passed verbatim to `sendtoaddress` as its `comment`
        param so a later reconciliation pass can match the wallet's
        listtransactions output back to this row.

        Returns the new outbox id.
        """
        with self.cursor() as cur:
            cur.execute(
                "INSERT INTO transactions_outbox "
                "(slot, account_id, coin_address, amount, wallet_comment, status) "
                "VALUES (%s, %s, %s, %s, %s, 'pending')",
                (slot, account_id, coin_address, amount, wallet_comment),
            )
            return int(cur.lastrowid)

    def mark_outbox_broadcast(self, outbox_id: int, txid: str) -> None:
        self.execute(
            "UPDATE transactions_outbox "
            "SET status = 'broadcast', txid = %s, rpc_error = NULL "
            "WHERE id = %s AND status IN ('pending','indeterminate')",
            (txid, outbox_id),
        )

    def mark_outbox_indeterminate(self, outbox_id: int,
                                  rpc_error: str) -> None:
        """The wallet send returned a timeout / connection error after
        the request was submitted. The transaction may or may not have
        been broadcast. We park the row here for a Wave 2 reconciliation
        pass to resolve via wallet listtransactions matching wallet_comment.
        """
        self.execute(
            "UPDATE transactions_outbox "
            "SET status = 'indeterminate', rpc_error = %s "
            "WHERE id = %s AND status = 'pending'",
            (rpc_error, outbox_id),
        )

    def mark_outbox_abandoned(self, outbox_id: int, reason: str) -> None:
        """The wallet send failed pre-broadcast (auth error, malformed
        address, etc.) — the daemon never accepted it, so it's safe to
        mark abandoned without reconciliation. Does NOT credit the
        Debit_AP row; the user's balance stays unchanged.
        """
        self.execute(
            "UPDATE transactions_outbox "
            "SET status = 'abandoned', rpc_error = %s "
            "WHERE id = %s AND status = 'pending'",
            (reason, outbox_id),
        )

    def list_outbox_indeterminate(self, slot: str) -> list[dict]:
        return self.fetchall(
            "SELECT * FROM transactions_outbox "
            "WHERE slot = %s AND status = 'indeterminate' "
            "ORDER BY id ASC",
            (slot,),
        )

    def list_outbox_broadcast(self, slot: str) -> list[dict]:
        """Wave 2: broadcast outbox rows awaiting on-chain reconciliation.

        Returned rows still hold the user's `Debit_AP` / `Debit_MP` /
        `TXFee` as `archived=0`, so the dashboard balance reads as
        negative until the reconciler archives them.
        """
        return self.fetchall(
            "SELECT * FROM transactions_outbox "
            "WHERE slot = %s AND status = 'broadcast' "
            "ORDER BY id ASC",
            (slot,),
        )

    def reconcile_outbox_in_tx(
        self, *, cur: "pymysql.cursors.DictCursor",
        outbox_id: int, slot: str, txid: str,
    ) -> int:
        """Wave 2: archive the Debit + TXFee transactions tied to a
        broadcast outbox row, then advance the outbox to 'reconciled'.

        The matching txns are linked by (account_id, slot's
        transactions_<slot> table, txid) — payouts.py records the same
        txid on the Debit_AP/Debit_MP and TXFee rows it inserts when
        broadcast lands. Returns the number of transaction rows
        archived (0–2 normally: one Debit + one optional TXFee).
        """
        txn_table = self._transactions_table(slot)
        cur.execute(
            f"UPDATE {txn_table} SET archived = 1 "
            "WHERE txid = %s AND archived = 0 "
            "AND type IN ('Debit_AP','Debit_MP','TXFee')",
            (txid,),
        )
        archived = int(cur.rowcount)
        cur.execute(
            "UPDATE transactions_outbox "
            "SET status = 'reconciled' "
            "WHERE id = %s AND status = 'broadcast'",
            (outbox_id,),
        )
        return archived

    # ---- Wave 2: canonical balance SQL (PHP `transaction.class.php` parity)
    #
    # The PHP `Transaction::getBalance` is the source of truth for what
    # an account's confirmed/unconfirmed/orphaned balance looks like.
    # Three call sites read it:
    #   1. The web UI's per-account balance card.
    #   2. The auto-payout queue (`getAPQueue`).
    #   3. The cold-wallet sweep's locked-balance figure (`liquid_payout`).
    #
    # All three need to compute it the same way. The Wave 1 helper
    # `get_accounts_above_threshold` had a bespoke SQL that DIDN'T
    # filter `archived = 0` and DIDN'T include the Credit_PPS /
    # Donation_PPS / Fee_PPS / TXFee transaction types; that meant
    # already-paid users could re-trigger and TXFees weren't being
    # netted against credit. Wave 2 centralises the SQL here.

    @staticmethod
    def _confirmed_balance_sql(*, txn_table: str, block_table: str) -> str:
        """Return the canonical balance-SQL fragment used by every
        confirmed-balance call site. Yields one column `confirmed`.

        Matches PHP `Transaction::getBalance` (transaction.class.php:258)
        and `Transaction::getAPQueue` (transaction.class.php:291) which
        use identical math.
        """
        return (
            "IFNULL(ROUND(("
            "  SUM(IF((t.type IN ('Credit','Bonus') "
            "          AND b.confirmations >= %s) "
            "        OR t.type = 'Credit_PPS', t.amount, 0)) "
            " -SUM(IF(t.type IN ('Debit_MP','Debit_AP'), t.amount, 0)) "
            " -SUM(IF((t.type IN ('Donation','Fee') "
            "          AND b.confirmations >= %s) "
            "        OR (t.type IN ('Donation_PPS','Fee_PPS','TXFee')), "
            "        t.amount, 0))"
            "), 8), 0)"
        )

    def compute_balance(self, account_id: int, *, slot: str = "",
                        min_confirmations: int = 100) -> dict:
        """Return {confirmed, unconfirmed, orphaned, inflight} for one account.

        PHP-parity (transaction.class.php:258). `archived = 0` filter
        applied; includes Credit_PPS / Donation_PPS / Fee_PPS / TXFee.
        Orphaned blocks (confirmations = -1) drop out of confirmed but
        are surfaced separately so the UI can show "this much was
        orphaned after credit".

        `inflight` is the absolute amount of `Debit_AP/Debit_MP/TXFee`
        rows whose matching `transactions_outbox.status='broadcast'` —
        i.e. the payout has been broadcast on chain but hasn't yet hit
        `reconcile_min_confirmations` so reconcile_payouts hasn't
        archived the debit. Those rows are EXCLUDED from `confirmed`
        and surfaced separately so the dashboard can show
        `confirmed: 0 / inflight: X` instead of a confusing negative.

        NOTE: this differs from the legacy `_confirmed_balance_sql()`
        used by the AP queue (`get_accounts_above_threshold`). The AP
        queue must keep subtracting in-flight debits from confirmed —
        that's the conservative behaviour that keeps a user from
        re-triggering AP while a previous one is mid-broadcast.
        """
        txn_table = self._transactions_table(slot)
        block_table = self._blocks_table(slot)
        sql = (
            f"SELECT "
            f"  IFNULL(ROUND(("
            f"    SUM(IF((t.type IN ('Credit','Bonus') "
            f"            AND b.confirmations >= %s) "
            f"          OR t.type = 'Credit_PPS', t.amount, 0)) "
            f"   -SUM(IF(t.type IN ('Debit_MP','Debit_AP') "
            f"           AND (o.status IS NULL OR o.status <> 'broadcast'), "
            f"           t.amount, 0)) "
            f"   -SUM(IF((t.type IN ('Donation','Fee') "
            f"            AND b.confirmations >= %s) "
            f"          OR t.type IN ('Donation_PPS','Fee_PPS') "
            f"          OR (t.type = 'TXFee' "
            f"              AND (o.status IS NULL OR o.status <> 'broadcast')), "
            f"           t.amount, 0))"
            f"  ), 8), 0) AS confirmed, "
            f"  IFNULL(ROUND(("
            f"    SUM(IF(t.type IN ('Debit_MP','Debit_AP','TXFee') "
            f"           AND o.status = 'broadcast', t.amount, 0))"
            f"  ), 8), 0) AS inflight, "
            f"  IFNULL(ROUND(("
            f"    SUM(IF(t.type IN ('Credit','Bonus') "
            f"           AND b.confirmations < %s "
            f"           AND b.confirmations >= 0, t.amount, 0)) "
            f"   -SUM(IF(t.type IN ('Donation','Fee') "
            f"           AND b.confirmations < %s "
            f"           AND b.confirmations >= 0, t.amount, 0))"
            f"  ), 8), 0) AS unconfirmed, "
            f"  IFNULL(ROUND(("
            f"    SUM(IF(t.type IN ('Credit','Bonus') "
            f"           AND b.confirmations = -1, t.amount, 0)) "
            f"   -SUM(IF(t.type IN ('Donation','Fee') "
            f"           AND b.confirmations = -1, t.amount, 0))"
            f"  ), 8), 0) AS orphaned "
            f"FROM {txn_table} t "
            f"LEFT JOIN {block_table} b ON b.id = t.block_id "
            f"LEFT JOIN transactions_outbox o "
            f"  ON t.txid = o.txid AND o.slot = %s "
            f"WHERE t.account_id = %s AND t.archived = 0"
        )
        row = self.fetchone(sql, (
            min_confirmations, min_confirmations,  # confirmed
            min_confirmations, min_confirmations,  # unconfirmed
            slot,                                   # outbox JOIN
            account_id,
        ))
        if not row:
            return {"confirmed": 0.0, "unconfirmed": 0.0,
                    "orphaned": 0.0, "inflight": 0.0}
        return {
            "confirmed": float(row.get("confirmed") or 0.0),
            "unconfirmed": float(row.get("unconfirmed") or 0.0),
            "orphaned": float(row.get("orphaned") or 0.0),
            "inflight": float(row.get("inflight") or 0.0),
        }

    def get_accounts_above_threshold(self, slot: str = "",
                                     min_confirmations: int = 100,
                                     txfee_auto: float = 0.0) -> list[dict]:
        """Auto-payout queue. Mirror of PHP `Transaction::getAPQueue`.

        Returns accounts whose confirmed balance for this slot exceeds
        BOTH the per-account `ap_threshold` AND the operator-configured
        `txfee_auto` (so we never schedule a payout the daemon's tx fee
        would consume entirely).

        Wave 2 fixes vs Wave 1:
          - filters `t.archived = 0` (already-paid txns excluded —
            Wave 1 would have re-triggered already-paid users).
          - includes `Credit_PPS` on the credit side (PPS payouts get
            counted unconditionally regardless of block confirmations).
          - includes `Donation_PPS`, `Fee_PPS`, `TXFee` on the debit
            side (PHP nets these against credit; Wave 1 didn't).
          - HAVING uses strict `> ap_threshold` (PHP semantics).
          - HAVING also requires `confirmed > txfee_auto` so the
            daemon's mandatory tx fee can be deducted without leaving
            the user with a negative balance.
          - Drops the `is_locked = 0` filter we added in Wave 1; PHP
            getAPQueue doesn't filter on is_locked. Lock semantics are
            enforced separately by the web UI when the user tries to
            change their address.

        Note: per-slot column names (`coin_address_<slot>`,
        `ap_threshold_<slot>`) keep working since the parent slot uses
        `coin_address`/`ap_threshold` and aux slots have suffixed cols.
        """
        coin_addr_col = "coin_address" if slot == "" else f"coin_address_{slot}"
        threshold_col = "ap_threshold" if slot == "" else f"ap_threshold_{slot}"
        txn_table = self._transactions_table(slot)
        block_table = self._blocks_table(slot)
        confirmed = self._confirmed_balance_sql(
            txn_table=txn_table, block_table=block_table,
        )
        sql = (
            f"SELECT a.id, a.username, "
            f"       a.{coin_addr_col} AS payout_address, "
            f"       a.{threshold_col} AS threshold, "
            f"       {confirmed} AS balance "
            f"FROM {txn_table} t "
            f"LEFT JOIN {block_table} b ON b.id = t.block_id "
            f"LEFT JOIN accounts a ON a.id = t.account_id "
            f"WHERE t.archived = 0 "
            f"  AND a.{threshold_col} > 0 "
            f"  AND a.{coin_addr_col} IS NOT NULL "
            f"  AND a.{coin_addr_col} <> '' "
            f"GROUP BY t.account_id "
            f"HAVING balance > a.{threshold_col} "
            f"   AND balance > %s"
        )
        return self.fetchall(sql, (
            min_confirmations, min_confirmations, txfee_auto,
        ))
