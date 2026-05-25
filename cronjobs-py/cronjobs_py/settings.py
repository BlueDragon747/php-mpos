"""Bridge to MPOS's PHP `$config` array.

Rather than maintain two configs, we shell out to `php -r` and dump the
existing `$config` as JSON. The Python side gets a typed view of the same
values the PHP cronjobs / web UI use. MPOS loads `global.inc.dist.php`
first, then lets `global.inc.php` override private deploy values; cronjobs-py
must do the same or PPLNS silently falls back to hard-coded defaults.
"""

from __future__ import annotations

import json
import os
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .rpc import Endpoint


@dataclass(frozen=True)
class DbConfig:
    host: str
    port: int
    user: str
    password: str
    database: str


@dataclass(frozen=True)
class CoinConfig:
    """One coin's RPC + display info.

    `slot` is the MPOS config-key suffix: "" for the parent ($config['wallet']),
    "mm", "mm1", ..., "mm6" for the aux slots.
    """
    slot: str
    endpoint: Endpoint
    payout_system: str = "pplns"


@dataclass(frozen=True)
class Settings:
    php_config_path: Path
    db: DbConfig
    coins: list[CoinConfig]
    reward: float
    reward_type: str
    block_bonus: float
    # Wave 1: per-job kill switch. Operator pre-disables specific job
    # names (e.g. "findblock-parent", "pplns-parent", "payouts-parent")
    # via the CRONJOBS_PY_DISABLED_JOBS env var. The scheduler skips
    # the named jobs every tick. Use this for cutover gating: until
    # Waves 1..4 prove cronjobs-py is mainnet-grade for coin-moving work,
    # leave findblock/pplns/payouts/liquid_payout in this set so they
    # don't run alongside the PHP cron.
    disabled_jobs: frozenset[str] = field(default_factory=frozenset)
    # Wave 5: shadow mode for the soak window. When True, cronjobs-py
    # PREDICTS the PPLNS / Bonus credit/fee/donation rows but does NOT
    # write the corresponding `transactions_<slot>` rows or flip
    # `blocks.accounted = 1`. PHP cron stays authoritative; cronjobs-py
    # writes guard rows tagged `mode='shadow'` so the drift-check CLI
    # can compare predictions against PHP's authoritative writes.
    # Payouts (manual + auto + liquid) refuse to run in shadow mode
    # because there is no shadow-able on-chain operation. Set via the
    # `CRONJOBS_PY_SHADOW_MODE=1` env var.
    shadow_mode: bool = False
    raw: dict[str, Any] = field(default_factory=dict)

    def parent(self) -> CoinConfig:
        for c in self.coins:
            if c.slot == "":
                return c
        raise RuntimeError("no parent wallet (slot='') configured")


def _php_dump_config(config_path: Path) -> dict[str, Any]:
    """Run `php -r` to evaluate the MPOS config and emit it as JSON.

    We require config files directly (not `shared.inc.php`) because the
    latter pulls in DB and class wiring that needs a running MariaDB.
    Match `public/include/bootstrap.php`: load `global.inc.dist.php` from
    the same directory first when present, then load the operator override.
    """
    if not config_path.exists():
        raise FileNotFoundError(config_path)
    if "'" in str(config_path):
        raise ValueError(f"single-quoted path not supported: {config_path}")
    dist_path = config_path.with_name("global.inc.dist.php")
    require_dist = (
        dist_path.exists()
        and dist_path.resolve() != config_path.resolve()
    )
    if require_dist and "'" in str(dist_path):
        raise ValueError(f"single-quoted path not supported: {dist_path}")
    requires = ""
    if require_dist:
        requires += f"require_once '{dist_path}'; "
    requires += f"require_once '{config_path}'; "
    # `require_once` needs a PHP string literal, not a shell-quoted path.
    # MPOS config files open with `cfip()` web-access guards; stub it so
    # the require succeeds in CLI context.
    snippet = (
        "function cfip() { return true; } "
        "$config = []; "
        f"{requires}"
        "echo json_encode($config, JSON_UNESCAPED_SLASHES);"
    )
    out = subprocess.run(
        ["php", "-r", snippet],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(out.stdout)


def _coin_from_slot(slot: str, raw: dict[str, Any]) -> CoinConfig | None:
    key = "wallet" if slot == "" else f"wallet_{slot}"
    w = raw.get(key)
    if not isinstance(w, dict) or not w.get("host"):
        return None
    host = str(w["host"]).strip().rstrip("/")
    url = host if host.startswith(("http://", "https://")) else f"http://{host}"
    payout_key = "payout_system" if slot == "" else f"payout_system_{slot}"
    return CoinConfig(
        slot=slot,
        endpoint=Endpoint(
            url=url,
            user=w.get("username", ""),
            password=w.get("password", ""),
            label=key,
        ),
        payout_system=str(raw.get(payout_key, "pplns")),
    )


def load(config_path: str | os.PathLike[str] | None = None) -> Settings:
    """Load settings from the MPOS PHP config.

    Path resolution order:
    1. `config_path` argument
    2. `MPOS_CONFIG` env var
    3. `<repo-root>/public/include/config/global.inc.php`
    """
    if config_path is None:
        config_path = os.environ.get("MPOS_CONFIG")
    if config_path is None:
        # repo root is two levels up from this file: cronjobs-py/cronjobs_py/settings.py
        here = Path(__file__).resolve()
        config_path = (
            here.parent.parent.parent
            / "public"
            / "include"
            / "config"
            / "global.inc.php"
        )
    config_path = Path(config_path)
    raw = _php_dump_config(config_path)

    db_raw = raw.get("db", {})
    db = DbConfig(
        host=db_raw.get("host", "localhost"),
        port=int(db_raw.get("port", 3306)),
        user=db_raw.get("user", "mpos"),
        password=db_raw.get("pass", ""),
        database=db_raw.get("name", "mpos"),
    )

    # MPOS legacy code defines wallet_mm2 and wallet_mm6 slot keys, but the
    # live BlakeStream runtime (bitcoinwrapper.class.php / statscache.class.php)
    # only instantiates 6 BitcoinWrapper / StatsCache instances:
    # parent + mm/mm1/mm3/mm4/mm5. The mm2 and mm6 slots are legacy
    # placeholders ("tba1"/"tba2") with `password = 'x'` in the dist config
    # and are never read at runtime, so we don't surface them either.
    active_slots = ("", "mm", "mm1", "mm3", "mm4", "mm5")
    coins: list[CoinConfig] = []
    for slot in active_slots:
        c = _coin_from_slot(slot, raw)
        if c is not None:
            coins.append(c)

    # Operator-controlled per-job kill list. Comma-separated env var so
    # an operator can flip cronjobs-py to safe-subset-only without
    # editing code or the systemd unit body.
    disabled_env = os.environ.get("CRONJOBS_PY_DISABLED_JOBS", "").strip()
    disabled_jobs = frozenset(
        n.strip() for n in disabled_env.split(",") if n.strip()
    ) if disabled_env else frozenset()

    # Wave 5 shadow-mode flag.
    shadow_mode = os.environ.get("CRONJOBS_PY_SHADOW_MODE", "0") == "1"

    return Settings(
        php_config_path=config_path,
        db=db,
        coins=coins,
        reward=float(raw.get("reward", 0)),
        reward_type=str(raw.get("reward_type", "block")),
        block_bonus=float(raw.get("block_bonus", 0)),
        disabled_jobs=disabled_jobs,
        shadow_mode=shadow_mode,
        raw=raw,
    )
