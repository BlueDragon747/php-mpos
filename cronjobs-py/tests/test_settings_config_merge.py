from __future__ import annotations

import shutil

import pytest

from cronjobs_py.settings import _coin_from_slot, _php_dump_config


def test_php_config_loader_matches_mpos_dist_then_override(tmp_path):
    if shutil.which("php") is None:
        pytest.skip("php CLI not installed")

    cfg_dir = tmp_path / "include" / "config"
    cfg_dir.mkdir(parents=True)
    (cfg_dir / "global.inc.dist.php").write_text(
        """<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;
$config['difficulty'] = 21;
$config['fees'] = 1.5;
$config['pplns']['shares']['default'] = 4000000;
$config['pplns']['shares']['type'] = 'blockavg';
$config['pplns']['blockavg']['blockcount'] = 5;
$config['db']['host'] = 'localhost';
$config['db']['user'] = 'dist-user';
?>""",
        encoding="utf-8",
    )
    override = cfg_dir / "global.inc.php"
    override.write_text(
        """<?php
$defflip = (!cfip()) ? exit(header('HTTP/1.1 401 Unauthorized')) : 1;
$config['db']['user'] = 'operator-user';
$config['wallet']['host'] = '127.0.0.1:8772/wallet/pool';
?>""",
        encoding="utf-8",
    )

    raw = _php_dump_config(override)

    assert raw["difficulty"] == 21
    assert raw["fees"] == 1.5
    assert raw["pplns"]["shares"]["default"] == 4000000
    assert raw["pplns"]["shares"]["type"] == "blockavg"
    assert raw["pplns"]["blockavg"]["blockcount"] == 5
    assert raw["db"]["host"] == "localhost"
    assert raw["db"]["user"] == "operator-user"


def test_coin_config_sets_25_2_default_wallet_endpoint() -> None:
    coin = _coin_from_slot("", {
        "wallet": {
            "host": "localhost:8772",
            "username": "u",
            "password": "p",
        },
    })

    assert coin is not None
    assert coin.endpoint.url == "http://localhost:8772"
    assert coin.endpoint.wallet_url == "http://localhost:8772/wallet/"


def test_coin_config_splits_explicit_wallet_path_from_node_root() -> None:
    coin = _coin_from_slot("mm1", {
        "wallet_mm1": {
            "host": "http://localhost:8243/wallet/pool",
            "username": "u",
            "password": "p",
        },
    })

    assert coin is not None
    assert coin.endpoint.url == "http://localhost:8243"
    assert coin.endpoint.wallet_url == "http://localhost:8243/wallet/pool"
