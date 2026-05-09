<div class="bsx-system-page">
<style>
  .bsx-system-page { padding: 1em; }
  .bsx-system-page .bsx-card {
    background: rgba(255,255,255,.03);
    border: 1px solid rgba(255,255,255,.08);
    border-radius: 6px;
    margin-bottom: 14px;
    overflow: hidden;
  }
  .bsx-system-page .bsx-card > header {
    background: rgba(255,255,255,.05);
    padding: 6px 14px;
    border-bottom: 1px solid rgba(255,255,255,.08);
    display: flex; align-items: center; justify-content: space-between; gap: 12px;
  }
  .bsx-system-page .bsx-card > header h3 {
    margin: 0; font-size: 13px; letter-spacing: 0.04em; color: #cdd; font-weight: 700;
  }
  .bsx-system-page .bsx-card-body { padding: 8px 14px 12px; }
  .bsx-system-page table { width: 100%; border-collapse: collapse; font-size: 12px; }
  .bsx-system-page th, .bsx-system-page td {
    text-align: left; padding: 4px 8px; border-bottom: 1px solid rgba(255,255,255,.05); color: #cdd;
  }
  .bsx-system-page th { color: #aab; font-weight: 600; font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em; }
  .bsx-system-page tr:last-child td { border-bottom: 0; }
  .bsx-system-page td.num { text-align: right; font-variant-numeric: tabular-nums; }
  .bsx-system-page .pill {
    display: inline-block; padding: 2px 7px; border-radius: 999px;
    font-size: 10px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase;
    border: 1px solid transparent;
  }
  .bsx-system-page .pill-active   { color: #b5e7a0; border-color: rgba(181,231,160,.45); background: rgba(181,231,160,.10); }
  .bsx-system-page .pill-inactive { color: #e57373; border-color: rgba(229,115,115,.45); background: rgba(229,115,115,.10); }
  .bsx-system-page .pill-warn     { color: #ffd66e; border-color: rgba(255,214,110,.45); background: rgba(255,214,110,.10); }
  .bsx-system-page .pill-disabled { color: #99a;    border-color: rgba(255,255,255,.20); background: rgba(255,255,255,.04); }
  .bsx-system-page .grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }
  @media (max-width: 900px) { .bsx-system-page .grid2 { grid-template-columns: 1fr; } }
  .bsx-system-page .meta-row { display: flex; gap: 16px; flex-wrap: wrap; font-size: 12px; color: #cdd; }
  .bsx-system-page .meta-row .k { color: #aab; }
  .bsx-system-page .footnote { font-size: 11px; color: #99a; margin-top: 8px; font-style: italic; }
  [data-theme="light"] .bsx-system-page .bsx-card { background: #ffffff; border-color: rgba(0,0,0,.10); }
  [data-theme="light"] .bsx-system-page .bsx-card > header { background: #f1f3f5; border-bottom-color: rgba(0,0,0,.08); }
  [data-theme="light"] .bsx-system-page .bsx-card > header h3 { color: #1f2933; }
  [data-theme="light"] .bsx-system-page td,
  [data-theme="light"] .bsx-system-page .meta-row { color: #1f2933; }
  [data-theme="light"] .bsx-system-page th,
  [data-theme="light"] .bsx-system-page .meta-row .k { color: #4a5568; }
</style>

<div class="grid2">

  {* ===== Services ===== *}
  <article class="bsx-card">
    <header>
      <h3>Services</h3>
    </header>
    <div class="bsx-card-body">
      <table>
        <thead><tr><th>Service</th><th>State</th><th>Up since</th></tr></thead>
        <tbody>
        {section name=s loop=$SYS_SERVICES}
          <tr>
            <td>{$SYS_SERVICES[s].label|escape}</td>
            <td>
              {if $SYS_SERVICES[s].state == "active"}
                <span class="pill pill-active">active</span>
              {elseif $SYS_SERVICES[s].state == "failed"}
                <span class="pill pill-inactive">failed</span>
              {elseif $SYS_SERVICES[s].state == "activating"}
                <span class="pill pill-warn">activating</span>
              {elseif $SYS_SERVICES[s].state == "inactive"}
                <span class="pill pill-disabled">inactive</span>
              {else}
                <span class="pill pill-disabled">{$SYS_SERVICES[s].state|escape|default:"—"}</span>
              {/if}
            </td>
            <td>{if $SYS_SERVICES[s].since}{$SYS_SERVICES[s].since|escape}{else}—{/if}</td>
          </tr>
        {/section}
        </tbody>
      </table>
    </div>
  </article>

  {* ===== Backups ===== *}
  <article class="bsx-card">
    <header>
      <h3>Backups</h3>
      {if $SYS_BACKUP.enabled}
        <span class="pill pill-active">enabled</span>
      {else}
        <span class="pill pill-disabled">disabled</span>
      {/if}
    </header>
    <div class="bsx-card-body">
      <div class="meta-row">
        <div><span class="k">Last run:</span>
          {if $SYS_BACKUP.last_mtime}
            {$SYS_BACKUP.last_mtime|date_format:"%Y-%m-%d %H:%M UTC"}
          {else}<em>never</em>{/if}
        </div>
        <div><span class="k">Size:</span>
          {if $SYS_BACKUP.last_size}{($SYS_BACKUP.last_size / 1024 / 1024)|string_format:"%.1f"} MB{else}—{/if}
        </div>
        <div><span class="k">Next:</span>
          {if $SYS_BACKUP.next_run}{$SYS_BACKUP.next_run|escape}{else}—{/if}
        </div>
        <div><span class="k">Retention:</span>
          {$SYS_BACKUP.retention_days|escape} days
        </div>
      </div>
      {if $SYS_BACKUP.wallets}
        <div class="meta-row" style="margin-top: 8px;">
          <div><span class="k">Wallets backed up:</span>
            {section name=w loop=$SYS_BACKUP.wallets}
              <span class="pill pill-active" style="margin-right: 4px;">{$SYS_BACKUP.wallets[w]|escape|upper}</span>
            {/section}
          </div>
        </div>
      {/if}
      <p class="footnote">
        Toggle on/off via the admin
        <a href="{$smarty.server.SCRIPT_NAME}?page=admin&action=settings#system">Settings → System</a>
        page (sets <code>backups_enabled</code>). Schedule + retention are deploy-time —
        edit <code>/etc/systemd/system/blakestream-mpos-backup.timer</code> and
        <code>/opt/blakestream-mpos/.deploy.env</code> over SSH respectively, then
        <code>systemctl daemon-reload</code>.
      </p>
    </div>
  </article>

  {* ===== Disk ===== *}
  <article class="bsx-card">
    <header>
      <h3>Disk</h3>
    </header>
    <div class="bsx-card-body">
      <table>
        <thead><tr><th>Mount</th><th>Path</th><th class="num">Size</th><th class="num">Used</th><th class="num">Avail</th><th class="num">Used %</th></tr></thead>
        <tbody>
        {section name=d loop=$SYS_DISK}
          <tr>
            <td>{$SYS_DISK[d].label|escape}</td>
            <td><code>{$SYS_DISK[d].path|escape}</code></td>
            <td class="num">{$SYS_DISK[d].size|escape}</td>
            <td class="num">{$SYS_DISK[d].used|escape}</td>
            <td class="num">{$SYS_DISK[d].avail|escape}</td>
            <td class="num">{$SYS_DISK[d].pcent|escape}</td>
          </tr>
        {/section}
        </tbody>
      </table>
    </div>
  </article>

  {* ===== Memory ===== *}
  <article class="bsx-card">
    <header>
      <h3>Memory (RSS)</h3>
    </header>
    <div class="bsx-card-body">
      <table>
        <thead><tr><th>Process</th><th class="num">PID</th><th class="num">RSS (MB)</th></tr></thead>
        <tbody>
        {section name=p loop=$SYS_PROCS}
          <tr>
            <td>{$SYS_PROCS[p].label|escape}</td>
            <td class="num">{$SYS_PROCS[p].pid|escape|default:"—"}</td>
            <td class="num">{if $SYS_PROCS[p].rss_mb !== ""}{$SYS_PROCS[p].rss_mb|escape}{else}—{/if}</td>
          </tr>
        {/section}
        </tbody>
      </table>
    </div>
  </article>

</div>

{* ===== Daemons (full width) ===== *}
<article class="bsx-card">
  <header>
    <h3>Coin daemons</h3>
  </header>
  <div class="bsx-card-body">
    <table>
      <thead><tr><th>Coin</th><th>Chain</th><th class="num">Blocks</th><th class="num">Headers</th><th>Sync</th></tr></thead>
      <tbody>
      {section name=d loop=$SYS_DAEMONS}
        <tr>
          <td>{$SYS_DAEMONS[d].sym|escape}</td>
          <td><code>{$SYS_DAEMONS[d].chain|escape}</code></td>
          <td class="num">{$SYS_DAEMONS[d].blocks|escape}</td>
          <td class="num">{$SYS_DAEMONS[d].headers|escape}</td>
          <td>
            {if $SYS_DAEMONS[d].synced}
              <span class="pill pill-active">synced</span>
            {elseif $SYS_DAEMONS[d].blocks == "—"}
              <span class="pill pill-inactive">unreachable</span>
            {else}
              <span class="pill pill-warn">syncing</span>
            {/if}
          </td>
        </tr>
      {/section}
      </tbody>
    </table>
  </div>
</article>

{* ===== Outbox (full width) ===== *}
{if $SYS_OUTBOX}
<article class="bsx-card">
  <header>
    <h3>Payout outbox</h3>
  </header>
  <div class="bsx-card-body">
    <table>
      <thead><tr><th>Slot</th><th>State</th><th class="num">Count</th><th>Latest update</th></tr></thead>
      <tbody>
      {section name=o loop=$SYS_OUTBOX}
        <tr>
          <td><code>{$SYS_OUTBOX[o].slot|escape}</code></td>
          <td>
            {if $SYS_OUTBOX[o].status == "broadcast"}
              <span class="pill pill-warn">broadcast</span>
            {elseif $SYS_OUTBOX[o].status == "reconciled"}
              <span class="pill pill-active">reconciled</span>
            {elseif $SYS_OUTBOX[o].status == "indeterminate"}
              <span class="pill pill-inactive">indeterminate</span>
            {elseif $SYS_OUTBOX[o].status == "abandoned"}
              <span class="pill pill-disabled">abandoned</span>
            {else}
              <span class="pill pill-disabled">{$SYS_OUTBOX[o].status|escape}</span>
            {/if}
          </td>
          <td class="num">{$SYS_OUTBOX[o].cnt}</td>
          <td>{$SYS_OUTBOX[o].latest|escape}</td>
        </tr>
      {/section}
      </tbody>
    </table>
    <p class="footnote">
      `broadcast` = payout sent on-chain, awaiting <code>reconcile_min_confirmations</code>.
      `reconciled` = on-chain confirmed, balance closed out.
      `indeterminate` = ambiguous RPC outcome, slot poison flag set, manual reconciliation required.
    </p>
  </div>
</article>
{/if}

</div>
