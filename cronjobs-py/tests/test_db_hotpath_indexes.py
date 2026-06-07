from .conftest import insert_share, insert_shares_archive_row
from cronjobs_py.db import Db


def _index_columns(db, table: str, key_name: str) -> tuple[str, ...]:
    rows = db.fetchall(
        "SELECT COLUMN_NAME "
        "FROM information_schema.STATISTICS "
        "WHERE TABLE_SCHEMA = DATABASE() "
        "  AND TABLE_NAME = %s "
        "  AND INDEX_NAME = %s "
        "ORDER BY SEQ_IN_INDEX",
        (table, key_name),
    )
    return tuple(str(row["COLUMN_NAME"]) for row in rows)


def test_share_hotpath_indexes_are_present(fresh_db):
    assert _index_columns(
        fresh_db, "shares", "idx_username_base_result_time",
    ) == ("username_base", "our_result", "time")
    assert _index_columns(
        fresh_db, "shares_archive", "idx_username_base_result_time",
    ) == ("username_base", "our_result", "time")
    assert _index_columns(
        fresh_db, "shares", "result_time_user_diff",
    ) == ("our_result", "time", "username", "difficulty")
    assert _index_columns(
        fresh_db, "shares_archive", "result_time_user_diff",
    ) == ("our_result", "time", "username", "difficulty", "share_id")
    assert _index_columns(
        fresh_db, "shares", "upstream_time_id",
    ) == ("upstream_result", "time", "id")
    assert _index_columns(
        fresh_db, "shares_archive", "upstream_time_share",
    ) == ("upstream_result", "time", "share_id")


def test_accounting_hotpath_indexes_are_present(fresh_db):
    assert _index_columns(
        fresh_db, "blocks", "block_accounted_share",
    ) == ("accounted", "share_id", "id")
    assert _index_columns(
        fresh_db, "transactions", "account_archived_id",
    ) == ("account_id", "archived", "id")
    assert _index_columns(
        fresh_db, "transactions_mm", "archived_account_id",
    ) == ("archived", "account_id", "id")
    assert _index_columns(
        fresh_db, "payouts_mm", "account_completed",
    ) == ("account_id", "completed")


def test_share_stats_recent_cache_schema_is_present(fresh_db):
    assert _index_columns(
        fresh_db, "share_stats_recent", "PRIMARY",
    ) == ("bucket_ts", "username")
    assert _index_columns(
        fresh_db, "share_stats_recent", "username_bucket",
    ) == ("username", "bucket_ts")
    assert _index_columns(
        fresh_db, "share_stats_recent", "username_last_share_time",
    ) == ("username", "last_share_time")
    assert _index_columns(
        fresh_db, "share_stats_recent", "username_base_last_share_time",
    ) == ("username_base", "last_share_time")
    assert _index_columns(
        fresh_db, "share_stats_recent", "last_share_time",
    ) == ("last_share_time",)
    assert _index_columns(
        fresh_db, "share_stats_recent", "max_share_id",
    ) == ("max_share_id",)


def test_advisory_lock_is_cross_connection_single_flight(fresh_db):
    other = Db(fresh_db.cfg)
    try:
        assert fresh_db.try_advisory_lock("job:statistics", timeout=0)
        assert not other.try_advisory_lock("job:statistics", timeout=0)
        assert fresh_db.release_advisory_lock("job:statistics")
        assert other.try_advisory_lock("job:statistics", timeout=0)
    finally:
        other.release_advisory_lock("job:statistics")
        other.close()


def test_find_upstream_share_time_window_matches_live_and_archive(fresh_db):
    now_ts = int(fresh_db.fetchone("SELECT UNIX_TIMESTAMP() AS ts")["ts"])
    insert_share(
        fresh_db,
        share_id=10,
        username="miner.rig1",
        upstream_result="Y",
        time_offset=30,
    )
    insert_shares_archive_row(
        fresh_db,
        share_id=20,
        username="miner.rig2",
        upstream_result="Y",
        time_offset=30,
    )

    live = fresh_db.find_upstream_share(
        blockhash="unused",
        prev_share_id=0,
        block_time=now_ts,
        exclude_ids=[20],
    )
    archived = fresh_db.find_upstream_share(
        blockhash="unused",
        prev_share_id=0,
        block_time=now_ts,
        exclude_ids=[10],
    )

    assert live is not None
    assert int(live["id"]) == 10
    assert archived is not None
    assert int(archived["id"]) == 20


def test_find_upstream_share_aux_path_uses_valid_parent_share(fresh_db):
    now_ts = int(fresh_db.fetchone("SELECT UNIX_TIMESTAMP() AS ts")["ts"])
    insert_share(
        fresh_db,
        share_id=30,
        username="miner.rig1",
        our_result="Y",
        upstream_result="N",
        time_offset=20,
    )
    insert_shares_archive_row(
        fresh_db,
        share_id=25,
        username="miner.rig2",
        our_result="Y",
        upstream_result="N",
        time_offset=20,
    )

    parent = fresh_db.find_upstream_share(
        blockhash="unused",
        prev_share_id=0,
        block_time=now_ts,
        require_upstream=True,
    )
    aux = fresh_db.find_upstream_share(
        blockhash="unused",
        prev_share_id=0,
        block_time=now_ts,
        require_upstream=False,
    )

    assert parent is None
    assert aux is not None
    assert int(aux["id"]) == 25
