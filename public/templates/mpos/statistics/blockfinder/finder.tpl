<div id="bsx-v2-shell" class="stats-blockfinder-v2">

  <article class="bsx-card finder-account-card">
    <header>
      <h3>Top 25 Blockfinders</h3>
      {if $ROUND_COIN_LIST|default:false}
      <nav class="chain-pill-rail" aria-label="Switch coin">
        {foreach from=$ROUND_COIN_LIST item=t}
          {if $t == $ROUND_COIN}
            <span class="chain-pill chain-{$t|escape|lower} is-active" aria-current="page" data-tooltip="{$COIN_NAMES[$t]|default:$t|escape}">{$t|escape}</span>
          {else}
            <a class="chain-pill chain-{$t|escape|lower}"
               href="{$smarty.server.SCRIPT_NAME}?page={$smarty.request.page|escape}&action={$smarty.request.action|escape}&coin={$t|escape|lower}"
               data-tooltip="{$COIN_NAMES[$t]|default:$t|escape}">{$t|escape}</a>
          {/if}
        {/foreach}
      </nav>
      {/if}
      <span class="card-meta">{$BLOCKSSOLVEDBYACCOUNT|@count|default:0} accounts</span>
    </header>
    <div class="bsx-card-body finder-table-wrap">
      <table class="bsx-table finder-table">
        <thead>
          <tr>
            <th class="th-rank">Rank</th>
            <th>User</th>
            <th class="center">Blocks</th>
            <th class="right">Coins Generated</th>
          </tr>
        </thead>
        <tbody>
{assign var=rank value=1}
{section name=block loop=$BLOCKSSOLVEDBYACCOUNT}
          <tr{if $GLOBAL.userdata.username|default:"" == $BLOCKSSOLVEDBYACCOUNT[block].finder} class="is-me"{/if}>
            <td class="td-rank">{$rank++}</td>
            <td class="td-name">{if $BLOCKSSOLVEDBYACCOUNT[block].is_anonymous|default:"0" == 1 && $GLOBAL.userdata.is_admin|default:"0" == 0}<span class="anon">anonymous</span>{else}{$BLOCKSSOLVEDBYACCOUNT[block].finder|default:"unknown"|escape}{/if}</td>
            <td class="center num">{$BLOCKSSOLVEDBYACCOUNT[block].solvedblocks}</td>
            <td class="right num">{$BLOCKSSOLVEDBYACCOUNT[block].generatedcoins|number_format}</td>
          </tr>
{sectionelse}
          <tr><td colspan="4" class="finder-empty">No blocks found yet.</td></tr>
{/section}
        </tbody>
      </table>
    </div>
  </article>

{if $smarty.session.AUTHENTICATED|default}
  <article class="bsx-card finder-worker-card">
    <header>
      <h3>Blocks Found by Your Workers</h3>
      <span class="card-meta">{$BLOCKSSOLVEDBYWORKER|@count|default:0} workers</span>
    </header>
    <div class="bsx-card-body finder-table-wrap">
      <table class="bsx-table finder-table">
        <thead>
          <tr>
            <th class="th-rank">Rank</th>
            <th>Worker</th>
            <th class="center">Blocks</th>
            <th class="right">Coins Generated</th>
          </tr>
        </thead>
        <tbody>
{assign var=rank value=1}
{section name=block loop=$BLOCKSSOLVEDBYWORKER}
          <tr>
            <td class="td-rank">{$rank++}</td>
            <td class="td-name">{$BLOCKSSOLVEDBYWORKER[block].finder|default:"unknown/deleted"|escape}</td>
            <td class="center num">{$BLOCKSSOLVEDBYWORKER[block].solvedblocks}</td>
            <td class="right num">{$BLOCKSSOLVEDBYWORKER[block].generatedcoins|number_format}</td>
          </tr>
{sectionelse}
          <tr><td colspan="4" class="finder-empty">None of your workers have found a block yet.</td></tr>
{/section}
        </tbody>
      </table>
    </div>
  </article>
{/if}

</div>

<style>
  .stats-blockfinder-v2 {
    margin: 0 16px 6px 16px;
    padding: 1em;
    color: var(--text-primary, #cdd);
    font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 16px;
    align-items: start;
    min-height: calc(100vh - 200px);
  }
  @media (max-width: 1100px) {
    .stats-blockfinder-v2 { grid-template-columns: 1fr; }
  }
  section#main > .spacer { height: 0; }
  aside#sidebar {
    background: var(--bg-secondary);
    margin-top: 0;
    padding-top: 0;
    min-height: 0;
  }
  section#main { background: none; min-height: 0; }

  /* Card chrome */
  .stats-blockfinder-v2 .bsx-card {
    background: rgba(255,255,255,.03);
    border: 1px solid rgba(255,255,255,.06);
    border-radius: 6px;
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }
  .stats-blockfinder-v2 .bsx-card header {
    background: rgba(255,255,255,.05);
    padding: 6px 14px;
    border-bottom: 1px solid rgba(255,255,255,.06);
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .stats-blockfinder-v2 .bsx-card h3 {
    margin: 0;
    font-size: 13px;
    color: #cdd;
    letter-spacing: 0.04em;
    text-transform: uppercase;
  }
  .stats-blockfinder-v2 .card-meta {
    font-size: 11px;
    opacity: 0.65;
    color: #cdd;
    font-style: italic;
    font-variant-numeric: tabular-nums;
    margin-left: auto;
  }
  .stats-blockfinder-v2 .bsx-card-body { padding: 0; }

  .stats-blockfinder-v2 .chain-pill-rail {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    flex-wrap: wrap;
  }
  .stats-blockfinder-v2 .chain-pill {
    display: inline-block;
    padding: 1px 7px;
    border-radius: 3px;
    font-size: 9px;
    font-weight: 700;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    border: 1px solid rgba(79, 195, 247, 0.40);
    background: rgba(79, 195, 247, 0.10);
    color: #4fc3f7;
  }
  .stats-blockfinder-v2 .chain-pill.chain-bbtc { color: #ea4335; border-color: rgba(234,67,53,.40);  background: rgba(234,67,53,.10);  }
  .stats-blockfinder-v2 .chain-pill.chain-blc  { color: #ff9800; border-color: rgba(255,152,0,.40);  background: rgba(255,152,0,.10);  }
  .stats-blockfinder-v2 .chain-pill.chain-elt  { color: #34a853; border-color: rgba(52,168,83,.40);  background: rgba(52,168,83,.10);  }
  .stats-blockfinder-v2 .chain-pill.chain-lit  { color: #fbbc04; border-color: rgba(251,188,4,.40);  background: rgba(251,188,4,.10);  }
  .stats-blockfinder-v2 .chain-pill.chain-pho  { color: #4285f4; border-color: rgba(66,133,244,.40); background: rgba(66,133,244,.10); }
  .stats-blockfinder-v2 .chain-pill.chain-umo  { color: #7b61ff; border-color: rgba(123,97,255,.40); background: rgba(123,97,255,.10); }
  [data-theme="light"] .stats-blockfinder-v2 .chain-pill.chain-bbtc { color: #c5221f; border-color: rgba(197,34,31,.55);  background: rgba(197,34,31,.18);  }
  [data-theme="light"] .stats-blockfinder-v2 .chain-pill.chain-blc  { color: #e65100; border-color: rgba(230,81,0,.55);   background: rgba(230,81,0,.18);   }
  [data-theme="light"] .stats-blockfinder-v2 .chain-pill.chain-elt  { color: #2e7d32; border-color: rgba(46,125,50,.55);  background: rgba(46,125,50,.18);  }
  [data-theme="light"] .stats-blockfinder-v2 .chain-pill.chain-lit  { color: #f57c00; border-color: rgba(245,124,0,.55);  background: rgba(245,124,0,.18);  }
  [data-theme="light"] .stats-blockfinder-v2 .chain-pill.chain-pho  { color: #1565c0; border-color: rgba(21,101,192,.55); background: rgba(21,101,192,.18); }
  [data-theme="light"] .stats-blockfinder-v2 .chain-pill.chain-umo  { color: #5e35b1; border-color: rgba(94,53,177,.55);  background: rgba(94,53,177,.18);  }
  .stats-blockfinder-v2 a.chain-pill {
    text-decoration: none;
    opacity: 0.55;
    transition: opacity 150ms ease, transform 100ms ease;
  }
  .stats-blockfinder-v2 a.chain-pill:hover {
    opacity: 1;
    transform: translateY(-1px);
  }
  .stats-blockfinder-v2 .chain-pill.is-active {
    opacity: 1;
    box-shadow: 0 0 0 1px currentColor inset;
  }

  /* Table */
  .stats-blockfinder-v2 .finder-table-wrap { overflow-x: auto; }
  .stats-blockfinder-v2 .finder-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 12px;
    color: #cdd;
  }
  .stats-blockfinder-v2 .finder-table thead th {
    background: rgba(255,255,255,.04);
    border-bottom: 1px solid rgba(255,255,255,.10);
    text-align: left;
    padding: 8px 12px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    font-size: 11px;
    color: #aab2bd;
  }
  .stats-blockfinder-v2 .finder-table tbody td {
    border-bottom: 1px solid rgba(255,255,255,.05);
    padding: 6px 12px;
    vertical-align: middle;
  }
  .stats-blockfinder-v2 .finder-table tbody tr:last-child td { border-bottom: 0; }
  .stats-blockfinder-v2 .finder-table tbody tr:nth-child(even) td { background: rgba(255,255,255,0.015); }
  .stats-blockfinder-v2 .finder-table tbody tr:hover td { background: rgba(79, 195, 247, 0.06); }
  .stats-blockfinder-v2 .finder-table tbody tr.is-me td {
    background: rgba(181, 231, 160, 0.10) !important;
    color: #d8efc6;
  }
  .stats-blockfinder-v2 .finder-table tbody tr.is-me td:first-child {
    box-shadow: inset 3px 0 0 rgba(181, 231, 160, 0.65);
  }
  .stats-blockfinder-v2 .finder-table .right  { text-align: right; }
  .stats-blockfinder-v2 .finder-table .center { text-align: center; }
  .stats-blockfinder-v2 .finder-table .num    { font-variant-numeric: tabular-nums; }
  .stats-blockfinder-v2 .finder-table .th-rank,
  .stats-blockfinder-v2 .finder-table .td-rank {
    text-align: center;
    width: 56px;
    color: #99a;
    font-variant-numeric: tabular-nums;
  }
  .stats-blockfinder-v2 .finder-table .anon { font-style: italic; opacity: 0.7; }
  .stats-blockfinder-v2 .finder-empty {
    text-align: center;
    padding: 16px;
    color: #888;
    opacity: 0.7;
    font-style: italic;
  }

  /* Light mode */
  [data-theme="light"] .stats-blockfinder-v2 .bsx-card {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] .stats-blockfinder-v2 .bsx-card header {
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] .stats-blockfinder-v2 .bsx-card h3 { color: #1f2933; }
  [data-theme="light"] .stats-blockfinder-v2 .card-meta { color: #4a5568; }
  [data-theme="light"] .stats-blockfinder-v2 .finder-table { color: #1f2933; }
  [data-theme="light"] .stats-blockfinder-v2 .finder-table thead th {
    background: #eef0f2;
    border-bottom-color: rgba(0, 0, 0, 0.10);
    color: #4a5568;
  }
  [data-theme="light"] .stats-blockfinder-v2 .finder-table tbody td { border-bottom-color: rgba(0, 0, 0, 0.06); }
  [data-theme="light"] .stats-blockfinder-v2 .finder-table tbody tr:nth-child(even) td { background: rgba(0, 0, 0, 0.025); }
  [data-theme="light"] .stats-blockfinder-v2 .finder-table tbody tr:hover td { background: rgba(25, 118, 210, 0.06); }
  [data-theme="light"] .stats-blockfinder-v2 .finder-table tbody tr.is-me td {
    background: rgba(46, 125, 50, 0.10) !important;
    color: #1b5e20;
  }

  /* Custom tooltip — sits BELOW the source (chips are at top of card). */
  .stats-blockfinder-v2 [data-tooltip] { position: relative; outline: none; }
  .stats-blockfinder-v2 [data-tooltip]::after {
    content: attr(data-tooltip);
    position: absolute;
    top: calc(100% + 8px);
    left: 50%;
    background: rgba(20, 23, 28, 0.96);
    border: 1px solid rgba(79, 195, 247, 0.35);
    color: #cdd;
    padding: 6px 10px;
    border-radius: 4px;
    font-size: 11px;
    font-weight: 400;
    letter-spacing: normal;
    text-transform: none;
    white-space: nowrap;
    opacity: 0;
    pointer-events: none;
    transition: opacity 150ms ease, transform 150ms ease;
    transform: translateX(-50%) translateY(-2px);
    z-index: 100;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.45);
  }
  .stats-blockfinder-v2 [data-tooltip]::before {
    content: '';
    position: absolute;
    top: calc(100% + 3px);
    left: 50%;
    width: 8px;
    height: 8px;
    background: rgba(20, 23, 28, 0.96);
    border-top: 1px solid rgba(79, 195, 247, 0.35);
    border-left: 1px solid rgba(79, 195, 247, 0.35);
    transform: translateX(-50%) rotate(45deg) translateY(-2px);
    opacity: 0;
    pointer-events: none;
    transition: opacity 150ms ease, transform 150ms ease;
    z-index: 101;
  }
  .stats-blockfinder-v2 [data-tooltip]:hover::after,
  .stats-blockfinder-v2 [data-tooltip]:focus-visible::after { opacity: 1; transform: translateX(-50%) translateY(0); }
  .stats-blockfinder-v2 [data-tooltip]:hover::before,
  .stats-blockfinder-v2 [data-tooltip]:focus-visible::before { opacity: 1; transform: translateX(-50%) rotate(45deg) translateY(0); }
  [data-theme="light"] .stats-blockfinder-v2 [data-tooltip]::after,
  [data-theme="light"] .stats-blockfinder-v2 [data-tooltip]::before {
    background: #ffffff;
    border-color: rgba(21, 101, 192, 0.40);
    color: #1f2933;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
  }
</style>
