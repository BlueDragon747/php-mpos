"""Memcached client compatible with MPOS's PHP `memcached` extension.

MPOS PHP stores cache values via the `memcached` extension with
`memcached.serializer = php`, which writes PHP-native `serialize()`
bytes and tags the entry with a flag indicating "PHP-serialized".

Python clients have to match both the byte format AND the flag bits
to be read back correctly by the PHP side.

This module wraps `pymemcache` with `phpserialize` as the serializer
so cronjobs-py can pre-compute stats and store them in the same cache
the MPOS web UI reads from. If the write doesn't go through (memcached
down, network blip, version mismatch), no harm — every PHP stat
method has a SQL fall-through that runs the same query on-demand and
re-populates the cache itself.

Key naming follows MPOS's `StatsCache::setStaticCache`:
    final_key = config.memcache.keyprefix + key

Operators set `keyprefix` to namespace per-deploy (e.g. `mpos_`).
"""

from __future__ import annotations

import logging
from typing import Any

import phpserialize
from pymemcache.client.base import Client as MemcacheClient

from .errors import Transient

log = logging.getLogger(__name__)

# PHP `memcached` extension flag bits (php-memcached, NOT legacy
# php-memcache — different conventions). From php-memcached's
# php_memcached.h:
#   MEMC_VAL_IS_STRING     0
#   MEMC_VAL_IS_LONG       1
#   MEMC_VAL_IS_DOUBLE     2
#   MEMC_VAL_IS_BOOL       3
#   MEMC_VAL_IS_SERIALIZED 4   <-- this one for PHP serialize()
#   MEMC_VAL_IS_IGBINARY   5
#   MEMC_VAL_IS_JSON       6
#   MEMC_VAL_IS_MSGPACK    7
# A wrong flag (e.g. 1 = LONG) makes PHP parse our phpserialize bytes
# via strtol, get 0, treat the entry as a cache miss, and rewrite the
# slot with its own SQL fall-through — clobbering pre-computed values.
PHP_MEMCACHED_FLAG_SERIALIZED = 4


def _php_serialize(key: bytes, value: Any) -> tuple[bytes, int]:
    """Serializer hook for pymemcache that emits PHP-compatible bytes.

    pymemcache calls this with `(key, value)` — key is unused here.
    Returns `(serialized_bytes, flags)`. The flag bit tells the PHP
    memcached extension on read that the payload is PHP-serialized.
    """
    payload = phpserialize.dumps(value)
    return payload, PHP_MEMCACHED_FLAG_SERIALIZED


def _php_deserialize(key: bytes, value: bytes, flags: int) -> Any:
    """Deserializer hook. If flags mark the value as PHP-serialized,
    decode with phpserialize; else hand back raw bytes."""
    if flags & PHP_MEMCACHED_FLAG_SERIALIZED:
        try:
            return phpserialize.loads(value, decode_strings=True)
        except Exception:
            return value
    return value


class Cache:
    """Wraps pymemcache with the same key-prefix + PHP-serialize shape
    MPOS expects."""

    def __init__(self, host: str, port: int, key_prefix: str = "mpos_",
                 timeout: float = 2.0, default_ttl: int = 300) -> None:
        self.host = host
        self.port = port
        self.key_prefix = key_prefix
        self.default_ttl = default_ttl
        self._client = MemcacheClient(
            (host, port),
            connect_timeout=timeout,
            timeout=timeout,
            serializer=_php_serialize,
            deserializer=_php_deserialize,
        )

    def _key(self, key: str) -> str:
        return f"{self.key_prefix}{key}"

    def _round_key(self, key: str, round_id: int = 0, flag: int = 0) -> str:
        return f"{round_id}_{flag}{self.key_prefix}{key}"

    def set_static(self, key: str, value: Any,
                   expire: int | None = None) -> bool:
        """`StatsCache::setStaticCache` equivalent — write under the
        prefixed key with default TTL unless overridden."""
        if expire is None:
            expire = self.default_ttl
        try:
            return bool(self._client.set(self._key(key), value, expire=expire))
        except Exception as exc:
            log.warning("memcache set %s failed: %s", self._key(key), exc)
            return False

    def set_round(self, key: str, value: Any, *, round_id: int = 0,
                  flag: int = 0, expire: int | None = None) -> bool:
        """`StatsCache::setCache` equivalent for round-scoped keys."""
        if expire is None:
            expire = self.default_ttl
        final_key = self._round_key(key, round_id=round_id, flag=flag)
        try:
            return bool(self._client.set(final_key, value, expire=expire))
        except Exception as exc:
            log.warning("memcache set %s failed: %s", final_key, exc)
            return False

    def get_static(self, key: str) -> Any:
        try:
            return self._client.get(self._key(key))
        except Exception as exc:
            log.warning("memcache get %s failed: %s", self._key(key), exc)
            return None
