# ops/eloipool-authentication-mpos.py
#
# Install as <eloipool_tree>/authentication/mpos.py and enable with:
#   Authentication = ({'module': 'mpos'},)
# in the eloipool config (see ops/eloipool-mainnet.config.py.example).
#
# Validates stratum worker credentials against MPOS's `pool_worker` table.
# Safer than `allowall`: arbitrary strangers can't submit work under an
# existing user's username. Safer than `usemysql`: parameterised query
# closes the SQL-injection hole in the reference usemysql backend.
#
# Copyright (C) 2026  Blakestream.
# Apache License 2.0 (matching php-mpos upstream licence).

import logging
import traceback

import config
import cymysql

_logger = logging.getLogger('authentication.mpos')


class mpos:
    """Stratum authenticator backed by the MPOS `pool_worker` table.

    MPOS allows workers to register on the web UI with or without a
    password. A blank password is MPOS's "accept anything" escape hatch
    (i.e. the user trusts any miner who knows the worker name). We
    preserve that semantics:

      - Worker exists, non-empty password: plaintext equality check.
      - Worker exists, blank/NULL password: accept any password.
      - Worker does not exist: reject. This is the production-relevant
        change relative to `allowall`.

    Stratum usernames come in as "account[.workername]"; MPOS's convention
    is for `pool_worker.username` to be the full "account.worker" string,
    so we match that literally first. If a bare account name arrives (no
    dot), we also try looking it up as a username, so a pool can accept
    miners that configure `-u <account-name>` without a subworker.
    """

    def __init__(self, **kwargs):
        # Pull DB creds from the first SQL ShareLogging block so there's
        # one source of truth. Operators should have the MPOS DB wired
        # there already (see ops/eloipool-mainnet.config.py.example).
        sql_cfgs = [c for c in getattr(config, 'ShareLogging', [])
                    if isinstance(c, dict) and c.get('type') == 'sql']
        if not sql_cfgs:
            raise RuntimeError(
                "authentication.mpos requires a ShareLogging sql entry "
                "to learn MPOS DB credentials. None found in config."
            )
        self.dbopts = sql_cfgs[0]['dbopts']
        self._conn = None
        self._cur = None
        self._reconnect()

    def _reconnect(self):
        """Open (or reopen) the MySQL connection + cursor."""
        if self._conn is not None:
            try:
                self._conn.close()
            except Exception:
                pass
        self._conn = cymysql.connect(
            host=self.dbopts.get('host', '127.0.0.1'),
            port=int(self.dbopts.get('port', 3306)),
            user=self.dbopts['user'],
            passwd=self.dbopts.get('passwd', self.dbopts.get('password', '')),
            db=self.dbopts['db'],
        )
        self._cur = self._conn.cursor()
        _logger.info('mpos auth: connected to %s/%s',
                     self.dbopts.get('host'), self.dbopts.get('db'))

    def _lookup(self, username):
        """Return stored pool_worker.password for `username`, or None."""
        sql = "SELECT password FROM pool_worker WHERE username = %s LIMIT 1"
        for attempt in (1, 2):
            try:
                self._cur.execute(sql, (username,))
                row = self._cur.fetchone()
                # End the implicit txn so the next lookup sees fresh DB
                # state (MySQL default REPEATABLE READ would otherwise
                # snapshot the pool_worker rows at first SELECT).
                self._conn.rollback()
                return row[0] if row else None
            except Exception:
                _logger.warning(
                    'mpos auth: DB error, reconnecting (attempt %d)', attempt,
                    exc_info=True)
                try:
                    self._reconnect()
                except Exception:
                    traceback.print_exc()
                    return None
        return None

    def checkAuthentication(self, user, password):
        """Stratum / RPC auth hook — return True to accept.

        Eloipool calls this for BOTH stratum miner authorize and the
        internal JSON-RPC (where merged-mine-proxy authenticates with
        eloipool's `SecretUser` / `SecretPass`). The MPOS pool_worker
        table only knows about real miners, so without an explicit
        SecretUser short-circuit MMP would fail every getwork call
        and the merge-mine pipeline would silently halt.
        """
        if not user:
            return False

        # MMP (and any other internal client) authenticate as
        # config.SecretUser / config.SecretPass. Accept that pair
        # without a pool_worker lookup.
        secret_user = getattr(config, 'SecretUser', None)
        secret_pass = getattr(config, 'SecretPass', None)
        if secret_user and user == secret_user:
            if secret_pass and password == secret_pass:
                return True
            _logger.info('mpos auth: reject %s (SecretUser password mismatch)', user)
            return False

        stored = self._lookup(user)
        # Fall back to the bare account name if user passed "acct.worker"
        # and only the account is registered — some pools use "the main
        # account password works for every worker".
        if stored is None and '.' in user:
            account = user.split('.', 1)[0]
            stored = self._lookup(account)

        if stored is None:
            _logger.info('mpos auth: reject %s (no pool_worker row)', user)
            return False

        if not stored:
            # Blank/NULL stored password = MPOS-style "accept any miner
            # who knows the worker name". This is the historic behaviour.
            return True

        if password == stored:
            return True

        _logger.info('mpos auth: reject %s (password mismatch)', user)
        return False
