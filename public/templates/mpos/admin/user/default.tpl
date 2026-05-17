<script type="text/javascript">
  var adminCtoken = "{$CTOKEN|escape:'javascript'|default:''}";
  // Inline AJAX toggles for Admin / Locked / No Fees columns.
  // Same endpoints as the legacy template (do=admin/lock/fee).
  function storeFee(id) {
    $.ajax({ type: "POST", url: "{$smarty.server.SCRIPT_NAME}",
      data: { page: "{$smarty.request.page|escape:'javascript'}", action: "{$smarty.request.action|escape:'javascript'}", do: "fee", account_id: id, ctoken: adminCtoken } });
  }
  function storeLock(id) {
    $.ajax({ type: "POST", url: "{$smarty.server.SCRIPT_NAME}",
      data: { page: "{$smarty.request.page|escape:'javascript'}", action: "{$smarty.request.action|escape:'javascript'}", do: "lock", account_id: id, ctoken: adminCtoken } });
  }
  function storeAdmin(id) {
    $.ajax({ type: "POST", url: "{$smarty.server.SCRIPT_NAME}",
      data: { page: "{$smarty.request.page|escape:'javascript'}", action: "{$smarty.request.action|escape:'javascript'}", do: "admin", account_id: id, ctoken: adminCtoken } });
  }
</script>

<div id="bsx-v2-shell" class="admin-user-v2">

  <!-- USER SEARCH -->
  <article class="bsx-card">
    <header>
      <h3>User Search</h3>
      <div class="bsx-card-actions">
        <a class="bsx-btn bsx-btn-small {if !($smarty.request.start|default:0 > 0)}is-disabled{/if}"
           {if $smarty.request.start|default:0 > 0}
           href="{$smarty.server.SCRIPT_NAME}?page={$smarty.request.page|escape}&action={$smarty.request.action|escape}&start={$smarty.request.start|escape|default:"0" - $LIMIT}{if $FILTERS|default:""}{$FILTERS}{/if}"
           {/if}
        >‹ Prev</a>
        <a class="bsx-btn bsx-btn-small"
           href="{$smarty.server.SCRIPT_NAME}?page={$smarty.request.page|escape}&action={$smarty.request.action|escape}&start={$smarty.request.start|escape|default:"0" + $LIMIT}{if $FILTERS|default:""}{$FILTERS}{/if}"
        >Next ›</a>
      </div>
    </header>
    <form action="{$smarty.server.SCRIPT_NAME}" method="get" class="user-search-form">
      <input type="hidden" name="page" value="{$smarty.request.page|escape}" />
      <input type="hidden" name="action" value="{$smarty.request.action|escape}" />
      <input type="hidden" name="do" value="query" />
      <div class="bsx-card-body">
        <div class="filter-grid">
          <div class="kv">
            <label for="f-account">Account</label>
            <input id="f-account" type="text" name="filter[account]" value="{$smarty.request.filter.account|default:""}" placeholder="alice OR ali%" />
          </div>
          <div class="kv">
            <label for="f-email">E-Mail</label>
            <input id="f-email" type="text" name="filter[email]" value="{$smarty.request.filter.email|default:""}" placeholder="@example.com" />
          </div>
          <div class="kv">
            <label for="f-admin">Is Admin</label>
            {html_options name="filter[is_admin]" id="f-admin" options=$ADMIN selected=$smarty.request.filter.is_admin|default:""}
          </div>
          <div class="kv">
            <label for="f-locked">Is Locked</label>
            {html_options name="filter[is_locked]" id="f-locked" options=$LOCKED selected=$smarty.request.filter.is_locked|default:""}
          </div>
          <div class="kv">
            <label for="f-nofees">No Fees</label>
            {html_options name="filter[no_fees]" id="f-nofees" options=$NOFEE selected=$smarty.request.filter.no_fees|default:""}
          </div>
        </div>
        <p class="search-hint">Text fields support <code>%</code> as a wildcard.</p>
        <div class="form-actions">
          <button type="submit" class="bsx-btn bsx-btn-primary bsx-btn-small">Search</button>
        </div>
      </div>
    </form>
  </article>

  <!-- USER INFORMATION -->
  <article class="bsx-card">
    <header><h3>User Information</h3></header>
    <div class="bsx-card-body user-table-wrap">
      <table class="bsx-table user-table">
        <thead>
          <tr>
            <th class="th-id">ID</th>
            <th class="th-name">Username</th>
            <th class="th-email">E-Mail</th>
            <th class="right">Shares</th>
            <th class="right">Hashrate</th>
{if $GLOBAL.config.payout_system != 'pps'}
            <th class="right">Est. Donation</th>
            <th class="right">Est. Payout</th>
{else}
            <th class="right" colspan="2">Est. 24 Hours</th>
{/if}
            <th class="right">Balance</th>
            <th class="right">Last Login</th>
            <th class="center">Admin</th>
            <th class="center">Locked</th>
            <th class="center">No Fees</th>
          </tr>
        </thead>
        <tbody>
{nocache}
{section name=user loop=$USERS|default}
          <tr>
            <td class="td-id">{$USERS[user].id}</td>
            <td class="td-name">{$USERS[user].username|escape}</td>
            <td class="td-email">{$USERS[user].email|escape}</td>
            <td class="right num">{$USERS[user].shares.valid|number_format}</td>
            <td class="right num">{$USERS[user].hashrate|number_format}</td>
{if $GLOBAL.config.payout_system != 'pps'}
            <td class="right num">{$USERS[user].estimates.donation|number_format:"8"}</td>
            <td class="right num">{$USERS[user].estimates.payout|number_format:"8"}</td>
{else}
            <td class="right num" colspan="2">{$USERS[user].estimates.hours24|number_format:"8"}</td>
{/if}
            <td class="right num">{$USERS[user].balance|number_format:"8"}</td>
            <td class="right num">
              {if $USERS[user].last_login|default:0 == 0}
                <span class="muted">never</span>
              {else}
                {$USERS[user].last_login|date_format:"%d/%m %H:%M:%S"}
              {/if}
            </td>
            <td class="center">
              <label class="bsx-toggle-wrap" for="admin-{$USERS[user].id}">
                <input type="checkbox" id="admin-{$USERS[user].id}"
                  onclick="storeAdmin({$USERS[user].id})"
                  {if $USERS[user].is_admin}checked{/if} />
                <span class="bsx-toggle" aria-hidden="true"></span>
              </label>
            </td>
            <td class="center">
              <label class="bsx-toggle-wrap" for="locked-{$USERS[user].id}">
                <input type="checkbox" id="locked-{$USERS[user].id}"
                  onclick="storeLock({$USERS[user].id})"
                  {if $USERS[user].is_locked}checked{/if} />
                <span class="bsx-toggle is-warn" aria-hidden="true"></span>
              </label>
            </td>
            <td class="center">
              <label class="bsx-toggle-wrap" for="nofee-{$USERS[user].id}">
                <input type="checkbox" id="nofee-{$USERS[user].id}"
                  onclick="storeFee({$USERS[user].id})"
                  {if $USERS[user].no_fees}checked{/if} />
                <span class="bsx-toggle" aria-hidden="true"></span>
              </label>
            </td>
          </tr>
{sectionelse}
          <tr><td colspan="12" class="empty-row">No users found. Adjust the filter and click Search.</td></tr>
{/section}
{/nocache}
        </tbody>
      </table>
    </div>
  </article>

</div>

<style>
  /* Page wrapper — matches the other admin v2 pages. */
  .admin-user-v2 {
    margin: 0 16px 6px 16px;
    padding: 1em;
    color: var(--text-primary, #cdd);
    font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
    display: flex;
    flex-direction: column;
    gap: 16px;
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

  /* Card chrome. */
  .admin-user-v2 .bsx-card {
    background: rgba(255,255,255,.03);
    border: 1px solid rgba(255,255,255,.06);
    border-radius: 6px;
    overflow: hidden;
  }
  .admin-user-v2 .bsx-card header {
    background: rgba(255,255,255,.05);
    padding: 4px 8px;
    border-bottom: 1px solid rgba(255,255,255,.06);
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }
  .admin-user-v2 .bsx-card h3 {
    margin: 0;
    font-size: 13px;
    text-transform: uppercase;
    color: #cdd;
    letter-spacing: 0.04em;
  }
  .admin-user-v2 .bsx-card-actions {
    display: flex;
    align-items: center;
    gap: 6px;
    flex: 0 0 auto;
  }
  .admin-user-v2 .bsx-card-body { padding: 12px 14px; }

  /* Filter grid — 5 fields side by side, wraps to fewer on narrow. */
  .admin-user-v2 .filter-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
    gap: 10px 14px;
  }
  .admin-user-v2 .kv {
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-width: 0;
  }
  .admin-user-v2 .kv > label {
    font-size: 11px;
    color: #99a;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }
  .admin-user-v2 .kv input[type=text],
  .admin-user-v2 .kv select {
    font: inherit;
    font-size: 13px;
    padding: 5px 8px;
    background: rgba(255,255,255,.04);
    border: 1px solid rgba(255,255,255,.10);
    border-radius: 4px;
    color: #f0f0f0;
    box-sizing: border-box;
    width: 100%;
    transition: border-color 200ms ease, box-shadow 200ms ease;
  }
  .admin-user-v2 .kv input[type=text]:focus,
  .admin-user-v2 .kv select:focus {
    outline: none;
    border-color: #4fc3f7;
    box-shadow: inset 0 2px 2px rgba(0, 0, 0, 0.20), 0 0 10px rgba(79, 195, 247, 0.55);
  }
  [data-theme="light"] .admin-user-v2 .kv input[type=text]:focus,
  [data-theme="light"] .admin-user-v2 .kv select:focus {
    border-color: #1565c0;
    box-shadow: inset 0 2px 2px rgba(0, 0, 0, 0.10), 0 0 10px rgba(21, 101, 192, 0.45);
  }
  /* The dropdown popup (open <option> list) renders on a white OS-
     native background. Without an explicit color, options inherit the
     light-text color from the closed select and are unreadable.
     Force black so the entries stay legible. */
  .admin-user-v2 .kv select option {
    background: #ffffff;
    color: #000000;
  }

  .admin-user-v2 .search-hint {
    margin: 8px 0 0;
    font-size: 11px;
    opacity: 0.6;
    color: #cdd;
  }
  .admin-user-v2 .search-hint code {
    background: rgba(0,0,0,0.25);
    padding: 0 4px;
    border-radius: 2px;
    font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
  }
  .admin-user-v2 .form-actions {
    display: flex;
    justify-content: flex-end;
    margin-top: 10px;
  }

  /* User table. */
  .admin-user-v2 .user-table-wrap { overflow-x: auto; padding: 0; }
  .admin-user-v2 .bsx-card-body.user-table-wrap { padding: 0; }
  .admin-user-v2 .bsx-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 12px;
  }
  .admin-user-v2 .bsx-table th,
  .admin-user-v2 .bsx-table td {
    padding: 6px 10px;
    text-align: left;
    border-bottom: 1px solid rgba(255,255,255,0.05);
    white-space: nowrap;
  }
  .admin-user-v2 .bsx-table thead th {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: #99a;
    font-weight: 700;
    background: rgba(255,255,255,0.02);
    border-bottom-color: rgba(255,255,255,0.10);
  }
  .admin-user-v2 .bsx-table tbody tr:nth-child(even) td { background: rgba(255,255,255,0.015); }
  .admin-user-v2 .bsx-table tbody tr:last-child td { border-bottom: 0; }
  .admin-user-v2 .bsx-table .center { text-align: center; }
  .admin-user-v2 .bsx-table .right { text-align: right; }
  .admin-user-v2 .num,
  .admin-user-v2 .td-id {
    font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
    font-variant-numeric: tabular-nums;
  }
  .admin-user-v2 .td-name { font-weight: 600; color: #e0f0fa; }
  .admin-user-v2 .td-email { color: #99a; }
  .admin-user-v2 .empty-row {
    text-align: center;
    opacity: 0.6;
    padding: 14px 0;
  }
  .admin-user-v2 .muted { opacity: 0.5; }

  /* Toggle pills inline in table cells (Admin / Locked / No Fees). */
  .admin-user-v2 .bsx-toggle-wrap {
    cursor: pointer;
    display: inline-flex;
    align-items: center;
  }
  .admin-user-v2 .bsx-toggle-wrap input[type=checkbox] {
    position: absolute;
    width: 1px; height: 1px;
    margin: -1px; padding: 0;
    overflow: hidden;
    clip: rect(0 0 0 0);
    white-space: nowrap;
    border: 0;
  }
  .admin-user-v2 .bsx-toggle {
    position: relative;
    width: 32px;
    height: 18px;
    border-radius: 999px;
    background: rgba(255, 255, 255, 0.10);
    border: 1px solid rgba(255, 255, 255, 0.14);
    transition: background 180ms ease, border-color 180ms ease;
  }
  .admin-user-v2 .bsx-toggle::after {
    content: '';
    position: absolute;
    top: 2px;
    left: 2px;
    width: 12px;
    height: 12px;
    border-radius: 50%;
    background: #cdd;
    transition: transform 180ms ease, background 180ms ease;
  }
  .admin-user-v2 .bsx-toggle-wrap input[type=checkbox]:checked + .bsx-toggle {
    background: rgba(79, 195, 247, 0.55);
    border-color: rgba(79, 195, 247, 0.65);
  }
  .admin-user-v2 .bsx-toggle-wrap input[type=checkbox]:checked + .bsx-toggle::after {
    transform: translateX(14px);
    background: #ffffff;
  }
  /* Locked toggle gets a warning tint when on — highlights "this user is locked". */
  .admin-user-v2 .bsx-toggle-wrap input[type=checkbox]:checked + .bsx-toggle.is-warn {
    background: rgba(229, 115, 115, 0.55);
    border-color: rgba(229, 115, 115, 0.7);
  }

  /* Buttons (mirror the rest of v2). */
  .admin-user-v2 .bsx-btn {
    font: inherit;
    font-size: 13px;
    font-weight: 600;
    letter-spacing: 0.04em;
    padding: 6px 16px;
    border-radius: 4px;
    cursor: pointer;
    border: 1px solid transparent;
    background: rgba(79, 195, 247, 0.10);
    border-color: rgba(79, 195, 247, 0.28);
    color: #cdd;
    text-decoration: none;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    transition: background 150ms ease, border-color 150ms ease, opacity 150ms ease;
  }
  .admin-user-v2 .bsx-btn:hover:not(.is-disabled) {
    background: rgba(79, 195, 247, 0.20);
    border-color: rgba(79, 195, 247, 0.55);
  }
  .admin-user-v2 .bsx-btn.is-disabled { opacity: 0.4; cursor: not-allowed; pointer-events: none; }
  .admin-user-v2 .bsx-btn-primary {
    background: rgba(79, 195, 247, 0.16);
    border-color: rgba(79, 195, 247, 0.45);
    color: #e0f0fa;
  }
  .admin-user-v2 .bsx-btn-small { padding: 4px 10px; font-size: 12px; }

  /* Light-mode overrides — same scope/pattern as other v2 pages. */
  [data-theme="light"] .admin-user-v2 .bsx-card {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] .admin-user-v2 .bsx-card header {
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] .admin-user-v2 .bsx-card h3 { color: #1f2933; }
  [data-theme="light"] .admin-user-v2 .kv > label { color: #4a5568; }
  [data-theme="light"] .admin-user-v2 .kv input[type=text],
  [data-theme="light"] .admin-user-v2 .kv select {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.18);
    color: #1f2933;
  }
  [data-theme="light"] .admin-user-v2 .search-hint { color: #2d3748; }
  [data-theme="light"] .admin-user-v2 .search-hint code {
    background: rgba(0, 0, 0, 0.06);
    color: #1f2933;
  }
  [data-theme="light"] .admin-user-v2 .bsx-table thead th {
    color: #4a5568;
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] .admin-user-v2 .bsx-table th,
  [data-theme="light"] .admin-user-v2 .bsx-table td {
    border-bottom-color: rgba(0, 0, 0, 0.06);
    color: #2d3748;
  }
  [data-theme="light"] .admin-user-v2 .bsx-table tbody tr:nth-child(even) td {
    background: rgba(0,0,0,0.02);
  }
  [data-theme="light"] .admin-user-v2 .td-name { color: #0d47a1; }
  [data-theme="light"] .admin-user-v2 .td-email { color: #4a5568; }
  [data-theme="light"] .admin-user-v2 .bsx-toggle {
    background: rgba(0, 0, 0, 0.10);
    border-color: rgba(0, 0, 0, 0.18);
  }
  [data-theme="light"] .admin-user-v2 .bsx-toggle::after {
    background: #ffffff;
    box-shadow: 0 1px 2px rgba(0, 0, 0, 0.18);
  }
  [data-theme="light"] .admin-user-v2 .bsx-toggle-wrap input[type=checkbox]:checked + .bsx-toggle {
    background: rgba(25, 118, 210, 0.55);
    border-color: rgba(25, 118, 210, 0.65);
  }
  [data-theme="light"] .admin-user-v2 .bsx-toggle-wrap input[type=checkbox]:checked + .bsx-toggle.is-warn {
    background: rgba(198, 40, 40, 0.55);
    border-color: rgba(198, 40, 40, 0.7);
  }
  [data-theme="light"] .admin-user-v2 .bsx-btn {
    color: #1f2933;
    background: rgba(25, 118, 210, 0.08);
    border-color: rgba(25, 118, 210, 0.40);
  }
  [data-theme="light"] .admin-user-v2 .bsx-btn:hover:not(.is-disabled) {
    background: rgba(25, 118, 210, 0.18);
    border-color: rgba(25, 118, 210, 0.55);
  }
  [data-theme="light"] .admin-user-v2 .bsx-btn-primary {
    background: rgba(25, 118, 210, 0.16);
    border-color: rgba(25, 118, 210, 0.50);
    color: #0d47a1;
  }
</style>
