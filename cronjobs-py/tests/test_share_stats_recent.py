from .conftest import insert_account, insert_block, insert_share


def test_share_stats_recent_refresh_is_incremental(fresh_db):
    insert_account(fresh_db, username="miner", account_id=1)
    fresh_db.execute(
        "INSERT INTO pool_worker (account_id, username, password) "
        "VALUES (%s, %s, %s), (%s, %s, %s)",
        (1, "miner.rig0", "x", 1, "miner.rig1", "x"),
    )
    insert_share(
        fresh_db,
        share_id=1,
        username="miner.rig0",
        difficulty=32,
        our_result="Y",
        time_offset=20,
    )
    insert_share(
        fresh_db,
        share_id=2,
        username="miner.rig0",
        difficulty=0,
        our_result="Y",
        time_offset=10,
    )
    insert_share(
        fresh_db,
        share_id=3,
        username="miner.rig1",
        difficulty=64,
        our_result="N",
        time_offset=5,
    )

    processed = fresh_db.refresh_share_stats_recent(
        difficulty_const=21,
        retain_seconds=3600,
        batch_size=1000,
        max_batches=10,
    )
    repeated = fresh_db.refresh_share_stats_recent(
        difficulty_const=21,
        retain_seconds=3600,
        batch_size=1000,
        max_batches=10,
    )

    assert processed == 3
    assert repeated == 0
    row = fresh_db.fetchone(
        "SELECT SUM(valid_count) AS valid_count, "
        "       SUM(invalid_count) AS invalid_count, "
        "       SUM(valid_diff) AS valid_diff, "
        "       SUM(worker_diff_sum) AS worker_diff_sum "
        "FROM share_stats_recent"
    )
    assert int(row["valid_count"]) == 2
    assert int(row["invalid_count"]) == 1
    assert float(row["valid_diff"]) == 64.0
    assert float(row["worker_diff_sum"]) == 33.0

    workers = {
        r["worker"]: r
        for r in fresh_db.stats_per_worker_mining(
            target_bits=32,
            difficulty_const=21,
            interval=60,
        )
    }
    assert set(workers) == {"miner.rig0"}
    assert workers["miner.rig0"]["hashrate"] > 0

    users = fresh_db.stats_per_user_mining(
        target_bits=32,
        difficulty_const=21,
        interval=60,
    )
    assert len(users) == 1
    assert users[0]["id"] == 1
    assert users[0]["account"] == "miner"
    assert users[0]["sharerate"] > 0
    assert users[0]["avgsharediff"] == 32.0

    top = fresh_db.stats_top_contributors(
        target_bits=32,
        difficulty_const=21,
        interval=60,
        limit=15,
    )
    assert top[0]["account"] == "miner"
    assert top[0]["hashrate"] > 0

    assert fresh_db.stats_active_workers(interval=60) == 2
    round_rows = fresh_db.stats_per_user_shares(difficulty_const=21)
    assert len(round_rows) == 1
    assert round_rows[0]["id"] == 1
    assert round_rows[0]["username"] == "miner"
    assert round_rows[0]["valid"] == 2.0
    assert round_rows[0]["invalid"] == 2.0

    updated = fresh_db.update_pool_worker_difficulty(interval=60)
    assert updated == 1
    difficulty = fresh_db.fetchone(
        "SELECT difficulty FROM pool_worker WHERE username = %s",
        ("miner.rig0",),
    )
    assert float(difficulty["difficulty"]) == 16.5


def test_share_stats_recent_refresh_rolls_forward_new_share_only(fresh_db):
    insert_account(fresh_db, username="miner", account_id=1)
    insert_share(
        fresh_db,
        share_id=10,
        username="miner.rig0",
        difficulty=32,
        our_result="Y",
        time_offset=30,
    )
    assert fresh_db.refresh_share_stats_recent(
        difficulty_const=21,
        retain_seconds=3600,
        batch_size=1000,
        max_batches=10,
    ) == 10

    insert_share(
        fresh_db,
        share_id=11,
        username="miner.rig0",
        difficulty=32,
        our_result="Y",
        time_offset=1,
    )
    assert fresh_db.refresh_share_stats_recent(
        difficulty_const=21,
        retain_seconds=3600,
        batch_size=1000,
        max_batches=10,
    ) == 1

    row = fresh_db.fetchone(
        "SELECT SUM(valid_count) AS valid_count, "
        "       MAX(max_share_id) AS max_share_id "
        "FROM share_stats_recent"
    )
    assert int(row["valid_count"]) == 2
    assert int(row["max_share_id"]) == 11


def test_share_stats_recent_refresh_keeps_cache_when_live_table_archived(fresh_db):
    insert_share(
        fresh_db,
        share_id=1,
        username="miner.rig0",
        difficulty=32,
        our_result="Y",
        time_offset=10,
    )
    assert fresh_db.refresh_share_stats_recent(
        difficulty_const=21,
        retain_seconds=3600,
        batch_size=1000,
        max_batches=10,
    ) == 1
    fresh_db.execute("DELETE FROM shares")

    assert fresh_db.refresh_share_stats_recent(
        difficulty_const=21,
        retain_seconds=3600,
        batch_size=1000,
        max_batches=10,
    ) == 0

    row = fresh_db.fetchone(
        "SELECT COUNT(*) AS rows_seen, "
        "       SUM(valid_count) AS valid_count, "
        "       MAX(max_share_id) AS max_share_id "
        "FROM share_stats_recent"
    )
    assert int(row["rows_seen"]) == 1
    assert int(row["valid_count"]) == 1
    assert int(row["max_share_id"]) == 1


def test_stats_helpers_use_summary_during_catchup(fresh_db):
    insert_share(
        fresh_db,
        share_id=1,
        username="miner.rig0",
        difficulty=32,
        our_result="Y",
        time_offset=10,
    )
    assert fresh_db.refresh_share_stats_recent(
        difficulty_const=21,
        retain_seconds=3600,
        batch_size=1000,
        max_batches=10,
    ) == 1
    fresh_db.set_setting("share_stats_recent_caught_up", "0")
    insert_share(
        fresh_db,
        share_id=2,
        username="miner.rig0",
        difficulty=32,
        our_result="Y",
        time_offset=5,
    )

    cache_value = fresh_db.stats_current_hashrate(
        target_bits=32,
        difficulty_const=21,
        interval=60,
    )
    summary_only_floor = round(32 * (2 ** 32) / 60 / 1000)

    assert cache_value == summary_only_floor


def test_stats_helpers_do_not_fallback_when_summary_window_is_empty(fresh_db):
    insert_account(fresh_db, username="miner", account_id=1)
    insert_share(
        fresh_db,
        share_id=1,
        username="miner.rig0",
        difficulty=32,
        our_result="Y",
        time_offset=120,
    )
    assert fresh_db.refresh_share_stats_recent(
        difficulty_const=21,
        retain_seconds=3600,
        batch_size=1000,
        max_batches=10,
    ) == 1
    fresh_db.set_setting("share_stats_recent_caught_up", "0")
    insert_block(
        fresh_db,
        block_id=1,
        height=100,
        blockhash="block-100",
        amount=50.0,
        share_id=1,
    )
    fresh_db.execute("UPDATE blocks SET time = UNIX_TIMESTAMP() - 60")
    insert_share(
        fresh_db,
        share_id=2,
        username="miner.rig0",
        difficulty=512,
        our_result="Y",
        time_offset=1,
    )

    assert fresh_db.stats_current_hashrate(
        target_bits=32,
        difficulty_const=21,
        interval=30,
    ) == 0.0
    assert fresh_db.stats_active_workers(interval=30) == 0
    assert fresh_db.stats_top_contributors(
        target_bits=32,
        difficulty_const=21,
        interval=30,
    ) == []
    assert fresh_db.stats_per_worker_mining(
        target_bits=32,
        difficulty_const=21,
        interval=30,
    ) == []
    assert fresh_db.stats_per_user_mining(
        target_bits=32,
        difficulty_const=21,
        interval=30,
    ) == []
    assert fresh_db.stats_per_user_shares(difficulty_const=21) == []


def test_stats_helpers_do_not_fallback_when_summary_started_but_pruned(fresh_db):
    insert_account(fresh_db, username="miner", account_id=1)
    insert_share(
        fresh_db,
        share_id=1,
        username="miner.rig0",
        difficulty=32,
        our_result="Y",
        time_offset=7200,
    )
    assert fresh_db.refresh_share_stats_recent(
        difficulty_const=21,
        retain_seconds=60,
        batch_size=1000,
        max_batches=10,
    ) == 1
    assert int(fresh_db.get_setting("share_stats_recent_last_share_id") or 0) == 1
    assert int(
        fresh_db.fetchone("SELECT COUNT(*) AS n FROM share_stats_recent")["n"]
    ) == 0
    fresh_db.set_setting("share_stats_recent_caught_up", "0")
    insert_block(
        fresh_db,
        block_id=1,
        height=100,
        blockhash="block-100",
        amount=50.0,
        share_id=1,
    )
    fresh_db.execute("UPDATE blocks SET time = UNIX_TIMESTAMP() - 60")
    insert_share(
        fresh_db,
        share_id=2,
        username="miner.rig0",
        difficulty=512,
        our_result="Y",
        time_offset=1,
    )

    assert fresh_db.stats_current_hashrate(
        target_bits=32,
        difficulty_const=21,
        interval=30,
    ) == 0.0
    assert fresh_db.stats_active_workers(interval=30) == 0
    assert fresh_db.stats_top_contributors(
        target_bits=32,
        difficulty_const=21,
        interval=30,
    ) == []
    assert fresh_db.stats_per_worker_mining(
        target_bits=32,
        difficulty_const=21,
        interval=30,
    ) == []
    assert fresh_db.stats_per_user_mining(
        target_bits=32,
        difficulty_const=21,
        interval=30,
    ) == []
    assert fresh_db.stats_per_user_shares(difficulty_const=21) == []


def test_pool_worker_difficulty_zeroes_stale_by_id_range(fresh_db):
    insert_account(fresh_db, username="miner", account_id=1)
    with fresh_db.cursor() as cur:
        cur.executemany(
            "INSERT INTO pool_worker "
            "(account_id, username, password, difficulty) "
            "VALUES (%s, %s, %s, %s)",
            [
                (1, "miner.rig0", "x", 1),
                *[
                    (1, f"miner.stale{i:03d}", "x", 7)
                    for i in range(1, 206)
                ],
            ],
        )
    insert_share(
        fresh_db,
        share_id=1,
        username="miner.rig0",
        difficulty=32,
        our_result="Y",
        time_offset=5,
    )
    fresh_db.refresh_share_stats_recent(
        difficulty_const=21,
        retain_seconds=3600,
        batch_size=1000,
        max_batches=10,
    )

    assert fresh_db.update_pool_worker_difficulty(
        interval=60,
        stale_batch_size=100,
    ) == 100
    assert fresh_db.get_setting_int(
        "pool_worker_difficulty_zero_cursor",
        default=0,
        floor=0,
    ) == 100

    assert fresh_db.update_pool_worker_difficulty(
        interval=60,
        stale_batch_size=100,
    ) == 100
    assert fresh_db.get_setting_int(
        "pool_worker_difficulty_zero_cursor",
        default=0,
        floor=0,
    ) == 200

    assert fresh_db.update_pool_worker_difficulty(
        interval=60,
        stale_batch_size=100,
    ) == 6
    assert fresh_db.get_setting_int(
        "pool_worker_difficulty_zero_cursor",
        default=0,
        floor=0,
    ) == 0

    rows = fresh_db.fetchall(
        "SELECT username, difficulty FROM pool_worker ORDER BY id"
    )
    assert float(rows[0]["difficulty"]) == 32.0
    assert all(float(row["difficulty"]) == 0.0 for row in rows[1:])


def test_pool_worker_difficulty_can_zero_stale_without_active_update(fresh_db):
    insert_account(fresh_db, username="miner", account_id=1)
    with fresh_db.cursor() as cur:
        cur.executemany(
            "INSERT INTO pool_worker "
            "(account_id, username, password, difficulty) "
            "VALUES (%s, %s, %s, %s)",
            [
                (1, "miner.rig0", "x", 5),
                (1, "miner.stale", "x", 7),
            ],
        )
    insert_share(
        fresh_db,
        share_id=1,
        username="miner.rig0",
        difficulty=32,
        our_result="Y",
        time_offset=5,
    )
    fresh_db.refresh_share_stats_recent(
        difficulty_const=21,
        retain_seconds=3600,
        batch_size=1000,
        max_batches=10,
    )

    assert fresh_db.update_pool_worker_difficulty(
        interval=60,
        stale_batch_size=100,
        update_active=False,
        zero_stale=True,
    ) == 1

    rows = {
        row["username"]: float(row["difficulty"])
        for row in fresh_db.fetchall(
            "SELECT username, difficulty FROM pool_worker"
        )
    }
    assert rows["miner.rig0"] == 5.0
    assert rows["miner.stale"] == 0.0


def test_pool_worker_difficulty_skips_when_summary_is_behind(fresh_db):
    insert_account(fresh_db, username="miner", account_id=1)
    fresh_db.execute(
        "INSERT INTO pool_worker "
        "(account_id, username, password, difficulty) "
        "VALUES (%s, %s, %s, %s)",
        (1, "miner.rig0", "x", 7),
    )
    insert_share(
        fresh_db,
        share_id=1,
        username="miner.rig0",
        difficulty=32,
        our_result="Y",
        time_offset=5,
    )
    fresh_db.set_setting("share_stats_recent_caught_up", "0")

    assert fresh_db.update_pool_worker_difficulty(interval=60) == 0
    row = fresh_db.fetchone(
        "SELECT difficulty FROM pool_worker WHERE username = %s",
        ("miner.rig0",),
    )
    assert float(row["difficulty"]) == 7.0


def test_pool_worker_difficulty_checks_real_summary_lag(fresh_db):
    insert_account(fresh_db, username="miner", account_id=1)
    fresh_db.execute(
        "INSERT INTO pool_worker "
        "(account_id, username, password, difficulty) "
        "VALUES (%s, %s, %s, %s)",
        (1, "miner.rig0", "x", 7),
    )
    insert_share(
        fresh_db,
        share_id=1,
        username="miner.rig0",
        difficulty=32,
        our_result="Y",
        time_offset=5,
    )
    assert fresh_db.refresh_share_stats_recent(
        difficulty_const=21,
        retain_seconds=3600,
        batch_size=1000,
        max_batches=10,
    ) == 1
    assert fresh_db.update_pool_worker_difficulty(interval=60) == 1

    fresh_db.execute(
        "UPDATE pool_worker SET difficulty = %s WHERE username = %s",
        (7, "miner.rig0"),
    )
    fresh_db.set_setting("share_stats_recent_caught_up", "1")
    fresh_db.set_setting("share_stats_recent_ready_lag_tolerance", "1000")
    insert_share(
        fresh_db,
        share_id=5002,
        username="miner.rig0",
        difficulty=512,
        our_result="Y",
        time_offset=1,
    )

    assert fresh_db.share_stats_recent_lag() == 5001
    assert fresh_db.update_pool_worker_difficulty(interval=60) == 0
    row = fresh_db.fetchone(
        "SELECT difficulty FROM pool_worker WHERE username = %s",
        ("miner.rig0",),
    )
    assert float(row["difficulty"]) == 7.0
