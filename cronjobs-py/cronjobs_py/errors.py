"""Error classification.

The PHP cronjobs collapse every failure to either logFatal-and-abort or
logError-and-continue. That binary pushes operators toward the abort path
on transient daemon hiccups (block reorg, brief RPC unavailability), which
is exactly when MPOS should be most patient.

We classify failures into three buckets:

- `Transient`: retry with backoff. Connection errors, timeouts, 5xx, and
  daemon-side codes that mean "ask again later" (-28 loading-block-index,
  -8 invalid-block-hash mid-reorg).
- `Skip`: this row/operation is unprocessable but the cronjob can keep
  going. Equivalent to the warn-and-skip pattern we already adopted for
  E0005 (non-pool block) and E0062 (block has no share_id).
- `Fatal`: data-integrity violation. The job should stop and page someone.
"""

from __future__ import annotations


class CronError(Exception):
    pass


class Transient(CronError):
    """Retryable. The scheduler will re-invoke after backoff."""


class Skip(CronError):
    """This row is unprocessable; continue the loop without aborting."""


class Fatal(CronError):
    """Data-integrity issue; abort and surface to the operator."""


class Indeterminate(CronError):
    """A non-idempotent RPC call's outcome is unknown.

    Raised when sendtoaddress (or any non-idempotent RPC) times out or
    suffers a connection error after the request was submitted but
    before we got a confirmed reply. The transaction may have been
    broadcast or it may not — we MUST NOT retry, because retry would
    risk a double-spend. Caller is expected to (a) persist the request
    in `transactions_outbox` BEFORE making the RPC call so a later
    reconciliation pass can match it via wallet comment, and (b) raise
    Fatal to set the slot-wide _disabled flag so no further coin-moving
    work happens until an operator reconciles.
    """


class Disabled(CronError):
    """A slot's coin-moving jobs have been quarantined.

    Raised when the scheduler skips a job whose slot has the
    cronjobs_py_disabled flag set. Distinct from Skip so logs/metrics
    can distinguish "row unprocessable" from "scope quarantined".
    """


# JSON-RPC error codes that are retryable. Everything else falls through
# to the caller's classification.
TRANSIENT_RPC_CODES = frozenset({
    -28,  # loading block index / verifying blocks
    -8,   # invalid block hash — common during a 1-block reorg window
    -1,   # generic transport/internal
})
