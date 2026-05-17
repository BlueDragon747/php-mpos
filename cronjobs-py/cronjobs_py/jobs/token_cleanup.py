"""Port of `cronjobs/token_cleanup.php`.

Deletes expired auth/recovery tokens from `mpos.tokens`. Token types
that carry an `expiration` (in seconds) — password resets, signup
verification, API session tokens — should not linger in the DB
indefinitely.

The MPOS schema:

    tokens(id, account_id, token, type, time)
    token_types(id, name, expiration)

Cleanup rule: for any token whose `type` references a token_types
row with `expiration > 0`, delete it if `time + expiration < NOW()`.
Token types with NULL/0 expiration (e.g. permanent API keys) are
left alone.

This is a no-slot job — the tokens table isn't per-slot in MPOS.
"""

from __future__ import annotations

from dataclasses import dataclass

from ..errors import Skip
from ..logger import get
from ..scheduler import JobContext

log = get(__name__)


@dataclass
class TokenCleanup:
    name: str = "token_cleanup"
    interval_seconds: int = 3600  # hourly
    slot: str = ""  # unused; tokens table is shared

    def run(self, ctx: JobContext) -> None:
        # Only run for the parent slot — tokens table is global, no
        # need for the scheduler to fire 6 times per hour.
        if self.slot != "":
            return

        db = ctx.db
        sql = (
            "DELETE t FROM tokens t "
            "JOIN token_types tt ON tt.id = t.type "
            "WHERE tt.expiration IS NOT NULL "
            "  AND tt.expiration > 0 "
            "  AND t.time < DATE_SUB(NOW(), INTERVAL tt.expiration SECOND)"
        )
        try:
            deleted = db.execute(sql)
        except Exception as exc:
            raise Skip(f"token cleanup query failed: {exc}")

        if deleted:
            log.info("[%s] deleted %d expired tokens", self.name, deleted)
        else:
            log.debug("[%s] no expired tokens", self.name)
