{nocache}
<div id="bsx-v2-shell" class="admin-dashboard-v2">

  <!-- Column 1: Version (top) + Status (below). Wrapped so the grid
       treats them as a single column with two stacked cards. -->
  <div class="version-stack">

  <!-- MPOS VERSION -->
  <article class="bsx-card">
    <header><h3>MPOS Version Information</h3></header>
    <div class="bsx-card-body">
      <table class="bsx-table">
        <thead>
          <tr>
            <th>Component</th>
            <th class="center">Current</th>
            <th class="center">Installed</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td><strong>MPOS</strong></td>
            <td class="center"><span class="ver-current">{$VERSION['CURRENT']['CORE']}</span></td>
            <td class="center"><span class="{if $VERSION['INSTALLED']['CORE'] == $VERSION['CURRENT']['CORE']}ver-ok{else}ver-bad{/if}">{$VERSION['INSTALLED']['CORE']}</span></td>
          </tr>
          <tr>
            <td><strong>Config</strong></td>
            <td class="center"><span class="ver-current">{$VERSION['CURRENT']['CONFIG']}</span></td>
            <td class="center"><span class="{if $VERSION['INSTALLED']['CONFIG'] == $VERSION['CURRENT']['CONFIG']}ver-ok{else}ver-bad{/if}">{$VERSION['INSTALLED']['CONFIG']}</span></td>
          </tr>
          <tr>
            <td><strong>Database</strong></td>
            <td class="center"><span class="ver-current">{$VERSION['CURRENT']['DB']}</span></td>
            <td class="center"><span class="{if $VERSION['INSTALLED']['DB'] == $VERSION['CURRENT']['DB']}ver-ok{else}ver-bad{/if}">{$VERSION['INSTALLED']['DB']}</span></td>
          </tr>
        </tbody>
      </table>
    </div>
  </article>

  <!-- MPOS STATUS — second card in column 1, sits below Version. -->
  <article class="bsx-card">
    <header><h3>MPOS Status</h3></header>
    <div class="bsx-card-body">
      <table class="bsx-table bsx-stat-row">
        <thead>
          <tr>
            <th colspan="2" class="center group-head">Cronjobs</th>
            <th class="center group-head">Wallet</th>
          </tr>
          <tr>
            <th class="center">Errors</th>
            <th class="center">Disabled</th>
            <th class="center">Errors</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td class="center">
              <a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=monitoring" class="stat-link">
                {if $CRON_ERROR == 0}<span class="stat-ok">None &mdash; OK</span>{else}<span class="stat-bad">{$CRON_ERROR}</span>{/if}
              </a>
            </td>
            <td class="center">
              <a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=monitoring" class="stat-link">
                {if $CRON_DISABLED == 0}<span class="stat-ok">None &mdash; OK</span>{else}<span class="stat-warn">{$CRON_DISABLED}</span>{/if}
              </a>
            </td>
            <td class="center">
              <a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=wallet" class="stat-link">
                {if $WALLET_ERROR|default:"None" == "None"}<span class="stat-ok">None &mdash; OK</span>{else}<span class="stat-bad">{$WALLET_ERROR}</span>{/if}
              </a>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </article>

  </div><!-- /.version-stack -->

  <!-- USERS -->
  <article class="bsx-card">
    <header><h3>Users</h3></header>
    <div class="bsx-card-body">
      <table class="bsx-table bsx-stat-row">
        <thead>
          <tr>
            <th class="center">Total</th>
            <th class="center">Active</th>
            <th class="center">Locked</th>
            <th class="center">Admins</th>
            <th class="center">No Fees</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td class="center stat-num">{$USER_INFO.total}</td>
            <td class="center stat-num stat-good">{$USER_INFO.active}</td>
            <td class="center stat-num {if $USER_INFO.locked > 0}stat-warn{/if}">{$USER_INFO.locked}</td>
            <td class="center stat-num">{$USER_INFO.admins}</td>
            <td class="center stat-num">{$USER_INFO.nofees}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </article>

  <!-- INVITATIONS (only when not disabled by admin) -->
  {if $GLOBAL.config.disable_invitations|default:"0" == 0}
  <article class="bsx-card">
    <header><h3>Invitations</h3></header>
    <div class="bsx-card-body">
      <table class="bsx-table bsx-stat-row">
        <thead>
          <tr>
            <th class="center">Total</th>
            <th class="center">Activated</th>
            <th class="center">Outstanding</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td class="center stat-num">{$INVITATION_INFO.total}</td>
            <td class="center stat-num stat-good">{$INVITATION_INFO.activated}</td>
            <td class="center stat-num {if $INVITATION_INFO.outstanding > 0}stat-warn{/if}">{$INVITATION_INFO.outstanding}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </article>
  {/if}

  <!-- LOGINS -->
  <article class="bsx-card">
    <header><h3>Logins</h3></header>
    <div class="bsx-card-body">
      <table class="bsx-table bsx-stat-row">
        <thead>
          <tr>
            <th class="center">24 hours</th>
            <th class="center">7 days</th>
            <th class="center">1 month</th>
            <th class="center">6 months</th>
            <th class="center">1 year</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td class="center stat-num">{$USER_LOGINS.24hours}</td>
            <td class="center stat-num">{$USER_LOGINS.7days}</td>
            <td class="center stat-num">{$USER_LOGINS.1month}</td>
            <td class="center stat-num">{$USER_LOGINS.6month}</td>
            <td class="center stat-num">{$USER_LOGINS.1year}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </article>

</div>
{/nocache}

<style>
  /* Same outer-shell adjustments as the user-facing v2 pages so the
     admin dashboard sits in the same gutters and visually blends with
     the secondary breadcrumb bar / sidebar. */
  .admin-dashboard-v2 {
    margin: 0 16px 6px 16px;
    padding: 1em;
    color: var(--text-primary, #cdd);
    font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
    /* Cards go across in a single row at wide viewports, wrapping
       to fewer columns as the viewport narrows. minmax(220px, 1fr)
       packs as many cards as fit while keeping each at least 220 px. */
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
    gap: 12px;
    align-items: start;
  }
  /* Column 1 holds two stacked cards (Version + Status). */
  .admin-dashboard-v2 .version-stack {
    display: flex;
    flex-direction: column;
    gap: 12px;
    min-width: 0;
  }
  section#main > .spacer { height: 0; }
  aside#sidebar {
    background: var(--bg-secondary);
    margin-top: 0;
    padding-top: 0;
    min-height: 0;
  }
  section#main {
    background: none;
    min-height: 0;
  }

  /* Card chrome — identical to the v2 user pages. */
  .admin-dashboard-v2 .bsx-card {
    background: rgba(255,255,255,.03);
    border: 1px solid rgba(255,255,255,.06);
    border-radius: 6px;
    overflow: hidden;
  }
  .admin-dashboard-v2 .bsx-card header {
    background: rgba(255,255,255,.05);
    padding: 4px 8px;
    border-bottom: 1px solid rgba(255,255,255,.06);
    display: flex;
    align-items: center;
    justify-content: space-between;
  }
  .admin-dashboard-v2 .bsx-card h3 {
    margin: 0;
    font-size: 13px;
    text-transform: uppercase;
    color: #cdd;
    letter-spacing: 0.04em;
  }
  .admin-dashboard-v2 .bsx-card-body { padding: 0; }

  /* Table rows that match the v2 transactions / workers tables. */
  .admin-dashboard-v2 .bsx-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 13px;
  }
  .admin-dashboard-v2 .bsx-table th,
  .admin-dashboard-v2 .bsx-table td {
    padding: 6px 10px;
    text-align: left;
    border-bottom: 1px solid rgba(255,255,255,0.05);
  }
  .admin-dashboard-v2 .bsx-table thead th {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: #99a;
    font-weight: 700;
    background: rgba(255,255,255,0.02);
    border-bottom-color: rgba(255,255,255,0.10);
  }
  .admin-dashboard-v2 .bsx-table tbody tr:last-child td { border-bottom: 0; }
  .admin-dashboard-v2 .bsx-table .center { text-align: center; }
  .admin-dashboard-v2 .bsx-table .group-head { color: #cdd; letter-spacing: 0.08em; }

  /* Single-row stat tables (Users / Logins / Invitations / Status):
     center the numbers, monospace + tabular for column alignment. */
  .admin-dashboard-v2 .bsx-stat-row td {
    font-size: 16px;
    padding: 10px 10px;
  }
  .admin-dashboard-v2 .stat-num {
    font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
    font-variant-numeric: tabular-nums;
    font-weight: 700;
    color: #e0f0fa;
  }
  .admin-dashboard-v2 .stat-good { color: #b5e7a0; }
  .admin-dashboard-v2 .stat-warn { color: #f5cba7; }
  .admin-dashboard-v2 .stat-bad  { color: #e57373; }
  .admin-dashboard-v2 .stat-ok   { color: #b5e7a0; font-weight: 600; }
  .admin-dashboard-v2 .stat-link { color: #4fc3f7; text-decoration: none; }
  .admin-dashboard-v2 .stat-link:hover { text-decoration: underline; }

  /* Version-table colours: green = matches current, red = mismatch. */
  .admin-dashboard-v2 .ver-current { color: #b5e7a0; font-weight: 700; font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; }
  .admin-dashboard-v2 .ver-ok      { color: #b5e7a0; font-weight: 700; font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; }
  .admin-dashboard-v2 .ver-bad     { color: #e57373; font-weight: 700; font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; }

  /* Light-mode overrides — scoped to [data-theme="light"]. */
  [data-theme="light"] .admin-dashboard-v2 .bsx-card {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] .admin-dashboard-v2 .bsx-card header {
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] .admin-dashboard-v2 .bsx-card h3 { color: #1f2933; }
  [data-theme="light"] .admin-dashboard-v2 .bsx-table thead th {
    color: #4a5568;
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] .admin-dashboard-v2 .bsx-table th,
  [data-theme="light"] .admin-dashboard-v2 .bsx-table td {
    border-bottom-color: rgba(0, 0, 0, 0.06);
    color: #2d3748;
  }
  [data-theme="light"] .admin-dashboard-v2 .stat-num   { color: #0d47a1; }
  [data-theme="light"] .admin-dashboard-v2 .stat-good  { color: #2e7d32; }
  [data-theme="light"] .admin-dashboard-v2 .stat-warn  { color: #b53d00; }
  [data-theme="light"] .admin-dashboard-v2 .stat-bad   { color: #c62828; }
  [data-theme="light"] .admin-dashboard-v2 .stat-ok    { color: #2e7d32; }
  [data-theme="light"] .admin-dashboard-v2 .stat-link  { color: #1976d2; }
  [data-theme="light"] .admin-dashboard-v2 .ver-current,
  [data-theme="light"] .admin-dashboard-v2 .ver-ok     { color: #2e7d32; }
  [data-theme="light"] .admin-dashboard-v2 .ver-bad    { color: #c62828; }
</style>
