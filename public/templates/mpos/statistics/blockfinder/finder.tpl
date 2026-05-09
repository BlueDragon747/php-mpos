<div id="bsx-v2-shell" class="stats-blockfinder-v2">

  <article class="bsx-card finder-account-card">
    <header>
      <h3>Top 25 Blockfinders</h3>
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
</style>
