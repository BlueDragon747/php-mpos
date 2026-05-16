<div id="bsx-v2-shell" class="admin-wallet-v2">
  <div class="wallet-grid">

    <!-- LEFT: Balance Summary. -->
    <article class="bsx-card balance-card">
      <header class="balance-head">
        <h3>Balance Summary</h3>
        <span class="coin-name">{$COIN_NAME|default:""}</span>
        <span class="head-spacer" aria-hidden="true"></span>
      </header>
      <div class="bsx-card-body">
        <table class="bsx-table balance-table">
          <tbody>
            <tr>
              <td class="label">Wallet Balance</td>
              <td class="num">{$BALANCE|default:0|number_format:"8"}</td>
            </tr>
            <tr>
              <td class="label">Locked for users</td>
              <td class="num">{$LOCKED|default:0|number_format:"8"}</td>
            </tr>
            <tr>
              <td class="label">Unconfirmed</td>
              <td class="num">{$UNCONFIRMED|default:0|number_format:"8"}</td>
            </tr>
            <tr>
              <td class="label">Liquid Assets</td>
              <td class="num strong">{($BALANCE|default:0 - $LOCKED|default:0)|number_format:"8"}</td>
            </tr>
            {if $NEWMINT|default:-1 >= 0}
            <tr>
              <td class="label">PoS New Mint</td>
              <td class="num">{$NEWMINT|number_format:"8"}</td>
            </tr>
            {/if}
          </tbody>
        </table>
      </div>
    </article>

    <!-- RIGHT: Wallet Information. -->
    <article class="bsx-card">
      <header><h3>Wallet Information</h3></header>
      <div class="bsx-card-body">
        <table class="bsx-table info-table">
          <thead>
            <tr>
              <th class="center">Version</th>
              <th class="center">Protocol Version</th>
              <th class="center">Wallet Version</th>
              <th class="center">Connections</th>
              <th class="center">Rules</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td class="center num">{$COININFO.version|default:""}</td>
              <td class="center num">{$COININFO.protocolversion|default:""}</td>
              <td class="center num">{$COININFO.walletversion|default:""}</td>
              <td class="center num">{$COININFO.connections|default:""}</td>
              <td class="center">
                {if $COIN_RULE_STATUS}
                  <span class="status-pill {$COIN_RULE_STATUS.class|default:"ok"|escape}"
                        title="{$COIN_RULE_STATUS.detail|default:""|escape}">
                    {$COIN_RULE_STATUS.label|default:"OK"|escape}
                  </span>
                  {if $COIN_RULE_STATUS.raw_warning|default:"" && !$COIN_RULE_STATUS.warning_explained}
                    <div class="wallet-rule-note">{$COIN_RULE_STATUS.raw_warning|escape}</div>
                  {/if}
                {elseif $COININFO.errors|default:""}
                  <span class="status-pill err">{$COININFO.errors|escape}</span>
                {else}
                  <span class="status-pill ok">OK</span>
                {/if}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </article>

  </div>
</div>

<style>
  /* Page wrapper — same gutters / sidebar treatment as the other
     admin v2 pages so the spacing stays consistent. */
  .admin-wallet-v2 {
    margin: 0 16px 6px 16px;
    padding: 1em;
    color: var(--text-primary, #cdd);
    font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
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

  /* Two-column grid: Balance Summary (narrow left) + Wallet Info
     (wide right). Same shape as the other v2 split-page layouts. */
  .admin-wallet-v2 .wallet-grid {
    display: grid;
    grid-template-columns: minmax(260px, 1fr) minmax(0, 2fr);
    gap: 16px;
    align-items: start;
  }
  @media (max-width: 900px) {
    .admin-wallet-v2 .wallet-grid { grid-template-columns: 1fr; }
  }

  /* Card chrome — identical to the rest of v2. */
  .admin-wallet-v2 .bsx-card {
    background: rgba(255,255,255,.03);
    border: 1px solid rgba(255,255,255,.06);
    border-radius: 6px;
    overflow: hidden;
  }
  .admin-wallet-v2 .bsx-card header {
    background: rgba(255,255,255,.05);
    padding: 4px 8px;
    border-bottom: 1px solid rgba(255,255,255,.06);
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }
  .admin-wallet-v2 .bsx-card h3 {
    margin: 0;
    font-size: 13px;
    text-transform: uppercase;
    color: #cdd;
    letter-spacing: 0.04em;
  }
  .admin-wallet-v2 .bsx-card-body { padding: 0; }

  /* Balance card header — three columns so the coin name centers
     between the title and an empty right cell, matching the
     transactions Summary card. */
  .admin-wallet-v2 .bsx-card header.balance-head {
    display: grid;
    grid-template-columns: 1fr auto 1fr;
    align-items: center;
  }
  .admin-wallet-v2 .balance-head h3 { text-align: left; }
  .admin-wallet-v2 .coin-name {
    font-size: 13px;
    font-weight: 700;
    letter-spacing: 0.04em;
    color: #4fc3f7;
    text-align: center;
    white-space: nowrap;
  }
  .admin-wallet-v2 .head-spacer {}

  /* Tables — same row treatment as the other v2 tables. */
  .admin-wallet-v2 .bsx-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 13px;
  }
  .admin-wallet-v2 .bsx-table th,
  .admin-wallet-v2 .bsx-table td {
    padding: 8px 12px;
    text-align: left;
    border-bottom: 1px solid rgba(255,255,255,0.05);
    white-space: nowrap;
  }
  .admin-wallet-v2 .bsx-table thead th {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: #99a;
    font-weight: 700;
    background: rgba(255,255,255,0.02);
    border-bottom-color: rgba(255,255,255,0.10);
  }
  .admin-wallet-v2 .bsx-table tbody tr:last-child td { border-bottom: 0; }
  .admin-wallet-v2 .bsx-table .center { text-align: center; }
  .admin-wallet-v2 .bsx-table .num {
    font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
    font-variant-numeric: tabular-nums;
  }

  /* Balance table: 2-col label/value rows, value right-aligned. */
  .admin-wallet-v2 .balance-table .label {
    color: #cdd;
    font-weight: 600;
  }
  .admin-wallet-v2 .balance-table .num {
    text-align: right;
    color: #e0f0fa;
  }
  .admin-wallet-v2 .balance-table .num.strong {
    color: #b5e7a0;
    font-weight: 700;
  }

  /* Status pills (OK / error). */
  .admin-wallet-v2 .status-pill {
    display: inline-block;
    padding: 2px 10px;
    border-radius: 999px;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.04em;
    border: 1px solid transparent;
  }
  .admin-wallet-v2 .status-pill.ok {
    background: rgba(181, 231, 160, 0.18);
    border-color: rgba(181, 231, 160, 0.45);
    color: #b5e7a0;
  }
  .admin-wallet-v2 .status-pill.err {
    background: rgba(229, 115, 115, 0.18);
    border-color: rgba(229, 115, 115, 0.45);
    color: #e57373;
  }
  .admin-wallet-v2 .status-pill.signal {
    background: rgba(79, 195, 247, 0.16);
    border-color: rgba(79, 195, 247, 0.45);
    color: #4fc3f7;
  }
  .admin-wallet-v2 .wallet-rule-note {
    margin-top: 4px;
    color: #e57373;
    font-size: 11px;
    white-space: normal;
    max-width: 360px;
  }

  /* Light-mode overrides — scoped to [data-theme="light"]. */
  [data-theme="light"] .admin-wallet-v2 .bsx-card {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] .admin-wallet-v2 .bsx-card header {
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] .admin-wallet-v2 .bsx-card h3 { color: #1f2933; }
  [data-theme="light"] .admin-wallet-v2 .coin-name { color: #1976d2; }
  [data-theme="light"] .admin-wallet-v2 .bsx-table thead th {
    color: #4a5568;
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] .admin-wallet-v2 .bsx-table th,
  [data-theme="light"] .admin-wallet-v2 .bsx-table td {
    border-bottom-color: rgba(0, 0, 0, 0.06);
    color: #2d3748;
  }
  [data-theme="light"] .admin-wallet-v2 .balance-table .label { color: #2d3748; }
  [data-theme="light"] .admin-wallet-v2 .balance-table .num   { color: #0d47a1; }
  [data-theme="light"] .admin-wallet-v2 .balance-table .num.strong { color: #2e7d32; }
  [data-theme="light"] .admin-wallet-v2 .status-pill.ok {
    background: rgba(46, 125, 50, 0.18);
    border-color: rgba(46, 125, 50, 0.45);
    color: #1b5e20;
  }
  [data-theme="light"] .admin-wallet-v2 .status-pill.err {
    background: rgba(198, 40, 40, 0.16);
    border-color: rgba(198, 40, 40, 0.45);
    color: #b71c1c;
  }
  [data-theme="light"] .admin-wallet-v2 .status-pill.signal {
    background: rgba(2, 136, 209, 0.14);
    border-color: rgba(2, 136, 209, 0.45);
    color: #01579b;
  }
  [data-theme="light"] .admin-wallet-v2 .wallet-rule-note { color: #b71c1c; }
</style>
