"""Port of `cronjobs/notifications.php` — email-on-event.

The PHP cron emails miners on three events:

- A worker hasn't submitted a share for `worker.idle_after` seconds
  ("IDLE worker" event).
- The same worker recovers (RESET event).
- Account hits various other thresholds.

In our deploy we don't run an SMTP relay and `disable_notifications`
is the default. Without those, all the PHP cron does is no-op the
whole loop. We mirror that — register a job that bails silently
unless the operator both turns notifications on AND wires up SMTP.

If/when an operator wants email notifications, this stub should be
replaced with a full port that:

  1. Queries `pool_worker` rows whose `last_share` is older than
     `config.worker.idle_after` and that don't already have an
     active idle_worker notification row.
  2. For each, looks up the account email and sends via
     SMTP / SendGrid / SES / etc.
  3. Records an entry in `notifications` so we don't re-mail on
     every tick.

The infrastructure (cronjobs-py scheduler, DB, settings) is already
in place — what's missing is the SMTP wiring, which is an operator
config decision, not a code gap.
"""

from __future__ import annotations

from dataclasses import dataclass

from ..logger import get
from ..scheduler import JobContext

log = get(__name__)


@dataclass
class Notifications:
    name: str = "notifications"
    interval_seconds: int = 300  # 5 minutes
    slot: str = ""

    def run(self, ctx: JobContext) -> None:
        if self.slot != "":
            return  # global, not per-slot

        cfg = ctx.settings
        db = ctx.db

        # Gate 1: operator has explicitly turned notifications off.
        disabled = (db.get_setting("disable_notifications") or "0") == "1"
        if disabled:
            log.debug("[%s] disable_notifications=1; nothing to do", self.name)
            return

        # Gate 2: SMTP transport not configured. Without it we have
        # nothing to send; bail silently rather than building idle-worker
        # state that no one will read. Operators wire `mail.smtp.host`
        # to enable.
        mail_cfg = (cfg.raw.get("mail") or {})
        smtp = (mail_cfg.get("smtp") or {})
        if not smtp.get("host"):
            log.debug("[%s] mail.smtp.host not set; nothing to send",
                      self.name)
            return

        # Real implementation would go here; see module docstring.
        log.info("[%s] SMTP configured but full notification port "
                 "is not implemented yet — this is the only stubbed job",
                 self.name)
