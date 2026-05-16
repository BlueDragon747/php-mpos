<div id="bsx-v2-shell" class="stats-round-v2">

  <!-- ROW 1: Round Statistics (merged block + pplns details + search) -->
  <article class="bsx-card round-stats-card">
    <header>
      <h3>{if $GLOBAL.config.payout_system == 'pplns'}Round Statistics{else}Block Statistics{/if}</h3>
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
      {else if $ROUND_COIN|default:""}
        <span class="chain-pill chain-{$ROUND_COIN|escape|lower}">{$ROUND_COIN|escape}</span>
      {/if}
      <form action="{$smarty.server.SCRIPT_NAME}" method="POST" class="round-search-form">
        <input type="hidden" name="page"   value="{$smarty.request.page|escape}">
        <input type="hidden" name="action" value="{$smarty.request.action|escape}">
        <input type="hidden" name="coin"   value="{$ROUND_COIN|default:''|escape}">
        <input type="text" class="round-search-input" name="search"
               value="{$smarty.request.height|default:""|escape}"
               placeholder="Search height…" autocomplete="off" spellcheck="false"
               aria-label="Search by block height">
        <button type="submit" class="bsx-btn bsx-btn-small">Search</button>
      </form>
      <div class="round-pager">
        <a class="bsx-btn bsx-btn-small"
           href="{$smarty.server.SCRIPT_NAME}?page={$smarty.request.page|escape}&action={$smarty.request.action|escape}&coin={$ROUND_COIN|default:''|escape}&height={$BLOCKDETAILS.height}&prev=1"
           data-tooltip="Older block">‹ Older</a>
        <a class="bsx-btn bsx-btn-small"
           href="{$smarty.server.SCRIPT_NAME}?page={$smarty.request.page|escape}&action={$smarty.request.action|escape}&coin={$ROUND_COIN|default:''|escape}&height={$BLOCKDETAILS.height}&next=1"
           data-tooltip="Newer block">Newer ›</a>
      </div>
    </header>
    <div class="bsx-card-body">
      <dl class="round-kv">
        <dt>ID</dt>
        <dd>{$BLOCKDETAILS.id|number_format:"0"|default:"0"}</dd>

        <dt>Height</dt>
        <dd>
        {* Open the BlakeStream Explorer's per-coin DASHBOARD page with the
           specific block deep-linked via the ?block=<HEIGHT> query param.
           The explorer's public/js/explorer.js:818-836 reads the query,
           HTMX-loads /<coin>/block/<HEIGHT> into the .dash-content panel,
           and replaceState's the URL back to /<coin> — so the operator
           sees the coin-branded chrome (logo, stats bar, Latest Blocks
           tab, etc.) AND the specific block details, with a clean URL
           after load.

           Coin segment is lowercase (verified: /blc 200, /BLC 404).
           ROUND_COIN stays uppercase for the chain pill; |lower applies
           only to the URL. *}
        {if $ROUND_COIN|default:"" && $BLOCKDETAILS.height}
          <a href="https://explorer.blakestream.io/{$ROUND_COIN|escape|lower}?block={$BLOCKDETAILS.height}"
             target="_blank" rel="noopener"
             data-tooltip="View block {$BLOCKDETAILS.height} on the BlakeStream Explorer dashboard (new tab)">{$BLOCKDETAILS.height|number_format:"0"|default:"0"}</a>
        {else if ! $GLOBAL.website.blockexplorer.disabled}
          <a href="{$GLOBAL.website.blockexplorer.url}{$BLOCKDETAILS.blockhash}" target="_blank" rel="noopener">{$BLOCKDETAILS.height|number_format:"0"|default:"0"}</a>
        {else}
          {$BLOCKDETAILS.height|number_format:"0"|default:"0"}
        {/if}
        </dd>

        <dt>Amount</dt>
        <dd>{$BLOCKDETAILS.amount|number_format|default:"0"}</dd>

        <dt>Confirmations</dt>
        <dd>
        {if $BLOCKDETAILS.confirmations >= $GLOBAL.confirmations}
          <span class="status-pill ok">Confirmed</span>
        {else if $BLOCKDETAILS.confirmations == -1}
          <span class="status-pill bad">Orphan</span>
        {else if $BLOCKDETAILS.confirmations == 0}
          <span class="status-pill pending">0</span>
        {else}
          <span class="status-pill pending">{($GLOBAL.confirmations - $BLOCKDETAILS.confirmations)|default:"0"} left</span>
        {/if}
        </dd>

        <dt>Difficulty</dt>
        <dd>{$BLOCKDETAILS.difficulty|default:"0"}</dd>

        <dt>Time</dt>
        <dd>{$BLOCKDETAILS.time|default:"0"}</dd>

        <dt>Shares</dt>
        <dd>{$BLOCKDETAILS.shares|number_format:"0"|default:"0"}</dd>

        <dt>Finder</dt>
        <dd>{$BLOCKDETAILS.finder|default:"unknown"|escape}</dd>

        {if $GLOBAL.config.payout_system == 'pplns'}
        <dt>Estimated Shares</dt>
        <dd>{$BLOCKDETAILS.estshares|number_format|default:"0"}</dd>

        <dt>PPLNS Shares</dt>
        <dd>{$PPLNSSHARES|number_format:"0"|default:"0"}</dd>

        <dt>Target Variance</dt>
        <dd>
{assign var=variance value=0}
{if $PPLNSSHARES > 0}{math assign=variance equation=(($BLOCKDETAILS.estshares / $PPLNSSHARES) * 100)}{/if}
          <span class="pct {if $variance >= 100}is-good{else}is-bad{/if}">{$variance|number_format:"2"}%</span>
        </dd>

        {if $BLOCKAVERAGE|default:0 > 0}
        <dt>Block Avg ({$BLOCKAVGCOUNT})</dt>
        <dd>{$BLOCKAVERAGE|number_format:"0"}</dd>
        {/if}
        {/if}
      </dl>
    </div>
  </article>

  {if $GLOBAL.config.payout_system != 'pps'}
  <!-- ROW 2: Round Transactions -->
  <article class="bsx-card round-tx-card">
    <header>
      <h3>Round Transactions</h3>
      <span class="card-meta">{$ROUNDTRANSACTIONS|@count|default:0} shown</span>
    </header>
    <div class="bsx-card-body round-table-wrap">
      <table class="bsx-table round-table">
        <thead>
          <tr>
            <th>User</th>
            {if $GLOBAL.config.payout_system != 'pplns'}<th class="center">Type</th>{/if}
            <th class="right">Round Shares</th>
            <th class="right">Round %</th>
            {if $GLOBAL.config.payout_system == 'pplns'}
              <th class="right">PPLNS Shares</th>
              <th class="right">PPLNS %</th>
              <th class="right">Variance</th>
            {/if}
            <th class="right">Amount</th>
          </tr>
        </thead>
        <tbody>
{section name=txs loop=$ROUNDTRANSACTIONS}
          <tr{if $GLOBAL.userdata.username|default:"" == $ROUNDTRANSACTIONS[txs].username} class="is-me"{/if}>
            <td class="td-name">{if $ROUNDTRANSACTIONS[txs].is_anonymous|default:"0" == 1 && $GLOBAL.userdata.is_admin|default:"0" == 0}<span class="anon">anonymous</span>{else}{$ROUNDTRANSACTIONS[txs].username|default:"unknown"|escape}{/if}</td>
            {if $GLOBAL.config.payout_system != 'pplns'}<td class="center">{$ROUNDTRANSACTIONS[txs].type|default:""|escape}</td>{/if}
            <td class="right num">{$ROUNDSHARES[$ROUNDTRANSACTIONS[txs].uid].valid|number_format}</td>
            <td class="right num">{if $ROUNDSHARES[$ROUNDTRANSACTIONS[txs].uid].valid > 0 && $BLOCKDETAILS.shares > 0}{((100 / $BLOCKDETAILS.shares) * $ROUNDSHARES[$ROUNDTRANSACTIONS[txs].uid].valid)|number_format:"2"}{else}0.00{/if}</td>
            {if $GLOBAL.config.payout_system == 'pplns'}
              <td class="right num">{$PPLNSROUNDSHARES[txs].pplns_valid|number_format|default:"0"}</td>
              <td class="right num">{if $PPLNSROUNDSHARES[txs].pplns_valid > 0 && $PPLNSSHARES > 0}{((100 / $PPLNSSHARES) * $PPLNSROUNDSHARES[txs].pplns_valid)|number_format:"2"}{else}0.00{/if}</td>
              <td class="right num">
{assign var=variance1 value=0}
{if $ROUNDSHARES[$ROUNDTRANSACTIONS[txs].uid].valid > 0 && $PPLNSROUNDSHARES[txs].pplns_valid > 0 && $BLOCKDETAILS.shares > 0 && $PPLNSSHARES > 0}{math assign=variance1 equation=(100 / (((100 / $BLOCKDETAILS.shares) * $ROUNDSHARES[$ROUNDTRANSACTIONS[txs].uid].valid) / ((100 / $PPLNSSHARES) * $PPLNSROUNDSHARES[txs].pplns_valid)))}{else if $PPLNSROUNDSHARES[txs].pplns_valid == 0}{assign var=variance1 value=0}{else}{assign var=variance1 value=100}{/if}
                <span class="pct {if $variance1 >= 100}is-good{else}is-bad{/if}">{$variance1|number_format:"2"}</span>
              </td>
            {/if}
            <td class="right num">{$ROUNDTRANSACTIONS[txs].amount|default:"0"|number_format:"8"}</td>
          </tr>
{sectionelse}
          <tr><td colspan="9" class="round-empty">No transactions for this round.</td></tr>
{/section}
        </tbody>
      </table>
    </div>
  </article>
  {/if}

  <!-- ROW 3: Round Shares (left) + PPLNS Round Shares (right, pplns only) -->
  <div class="round-shares-row">
    <article class="bsx-card round-shares-card">
      <header>
        <h3>Round Shares</h3>
        <span class="card-meta">{$ROUNDSHARES|@count|default:0} contributors</span>
      </header>
      <div class="bsx-card-body round-table-wrap">
        <table class="bsx-table round-table">
          <thead>
            <tr>
              <th class="th-rank">Rank</th>
              <th>User</th>
              <th class="right">Valid</th>
              <th class="right">Invalid</th>
              <th class="right">Invalid %</th>
            </tr>
          </thead>
          <tbody>
{assign var=rank value=1}
{foreach key=id item=data from=$ROUNDSHARES}
            <tr{if $GLOBAL.userdata.username|default:"" == $data.username} class="is-me"{/if}>
              <td class="td-rank">{$rank++}</td>
              <td class="td-name">{if $data.is_anonymous|default:"0" == 1 && $GLOBAL.userdata.is_admin|default:"0" == 0}<span class="anon">anonymous</span>{else}{$data.username|default:"unknown"|escape}{/if}</td>
              <td class="right num">{$data.valid|number_format}</td>
              <td class="right num">{$data.invalid|number_format}</td>
              <td class="right num">{if $data.invalid > 0 && $data.valid > 0}{($data.invalid / $data.valid * 100)|number_format:"2"}{else}0.00{/if}</td>
            </tr>
{foreachelse}
            <tr><td colspan="5" class="round-empty">No round shares yet.</td></tr>
{/foreach}
          </tbody>
        </table>
      </div>
    </article>

    {if $GLOBAL.config.payout_system == 'pplns'}
    <article class="bsx-card round-pplns-card">
      <header>
        <h3>PPLNS Round Shares</h3>
        <span class="card-meta">{$PPLNSROUNDSHARES|@count|default:0} contributors</span>
      </header>
      <div class="bsx-card-body round-table-wrap">
        <table class="bsx-table round-table">
          <thead>
            <tr>
              <th class="th-rank">Rank</th>
              <th>User</th>
              <th class="right">Valid</th>
              <th class="right">Invalid</th>
              <th class="right">Invalid %</th>
            </tr>
          </thead>
          <tbody>
{assign var=rank value=1}
{section name=contrib loop=$PPLNSROUNDSHARES}
            <tr{if $GLOBAL.userdata.username|default:"" == $PPLNSROUNDSHARES[contrib].username} class="is-me"{/if}>
              <td class="td-rank">{$rank++}</td>
              <td class="td-name">{if $PPLNSROUNDSHARES[contrib].is_anonymous|default:"0" == 1 && $GLOBAL.userdata.is_admin|default:"0" == 0}<span class="anon">anonymous</span>{else}{$PPLNSROUNDSHARES[contrib].username|default:"unknown"|escape}{/if}</td>
              <td class="right num">{$PPLNSROUNDSHARES[contrib].pplns_valid|number_format}</td>
              <td class="right num">{$PPLNSROUNDSHARES[contrib].pplns_invalid|number_format}</td>
              <td class="right num">{if $PPLNSROUNDSHARES[contrib].pplns_invalid > 0 && $PPLNSROUNDSHARES[contrib].pplns_valid > 0}{($PPLNSROUNDSHARES[contrib].pplns_invalid / $PPLNSROUNDSHARES[contrib].pplns_valid * 100)|number_format:"2"}{else}0.00{/if}</td>
            </tr>
{sectionelse}
            <tr><td colspan="5" class="round-empty">No PPLNS shares yet.</td></tr>
{/section}
          </tbody>
        </table>
      </div>
    </article>
    {/if}
  </div>

</div>

<style>
  .stats-round-v2 {
    margin: 0 16px 6px 16px;
    padding: 1em;
    color: var(--text-primary, #cdd);
    font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
    display: flex;
    flex-direction: column;
    gap: 16px;
    min-height: calc(100vh - 200px);
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
  .stats-round-v2 .bsx-card {
    background: rgba(255,255,255,.03);
    border: 1px solid rgba(255,255,255,.06);
    border-radius: 6px;
    overflow: hidden;
  }
  .stats-round-v2 .bsx-card header {
    background: rgba(255,255,255,.05);
    padding: 6px 14px;
    border-bottom: 1px solid rgba(255,255,255,.06);
    display: flex;
    align-items: center;
    gap: 12px;
    flex-wrap: wrap;
  }
  .stats-round-v2 .bsx-card h3 {
    margin: 0;
    font-size: 13px;
    color: #cdd;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    display: inline-flex;
    align-items: center;
    gap: 8px;
  }

  .stats-round-v2 .chain-pill {
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
  .stats-round-v2 .chain-pill-rail {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    flex-wrap: wrap;
  }
  .stats-round-v2 a.chain-pill {
    text-decoration: none;
    opacity: 0.55;
    transition: opacity 150ms ease, transform 100ms ease;
  }
  .stats-round-v2 a.chain-pill:hover {
    opacity: 1;
    transform: translateY(-1px);
  }
  .stats-round-v2 .chain-pill.is-active {
    opacity: 1;
    box-shadow: 0 0 0 1px currentColor inset;
  }
  .stats-round-v2 .chain-pill.chain-bbtc { color: #ea4335; border-color: rgba(234,67,53,.40);  background: rgba(234,67,53,.10);  }
  .stats-round-v2 .chain-pill.chain-blc  { color: #ff9800; border-color: rgba(255,152,0,.40);  background: rgba(255,152,0,.10);  }
  .stats-round-v2 .chain-pill.chain-elt  { color: #34a853; border-color: rgba(52,168,83,.40);  background: rgba(52,168,83,.10);  }
  .stats-round-v2 .chain-pill.chain-lit  { color: #fbbc04; border-color: rgba(251,188,4,.40);  background: rgba(251,188,4,.10);  }
  .stats-round-v2 .chain-pill.chain-pho  { color: #4285f4; border-color: rgba(66,133,244,.40); background: rgba(66,133,244,.10); }
  .stats-round-v2 .chain-pill.chain-umo  { color: #7b61ff; border-color: rgba(123,97,255,.40); background: rgba(123,97,255,.10); }
  [data-theme="light"] .stats-round-v2 .chain-pill.chain-bbtc { color: #c5221f; border-color: rgba(197,34,31,.55);  background: rgba(197,34,31,.18);  }
  [data-theme="light"] .stats-round-v2 .chain-pill.chain-blc  { color: #e65100; border-color: rgba(230,81,0,.55);   background: rgba(230,81,0,.18);   }
  [data-theme="light"] .stats-round-v2 .chain-pill.chain-elt  { color: #2e7d32; border-color: rgba(46,125,50,.55);  background: rgba(46,125,50,.18);  }
  [data-theme="light"] .stats-round-v2 .chain-pill.chain-lit  { color: #f57c00; border-color: rgba(245,124,0,.55);  background: rgba(245,124,0,.18);  }
  [data-theme="light"] .stats-round-v2 .chain-pill.chain-pho  { color: #1565c0; border-color: rgba(21,101,192,.55); background: rgba(21,101,192,.18); }
  [data-theme="light"] .stats-round-v2 .chain-pill.chain-umo  { color: #5e35b1; border-color: rgba(94,53,177,.55);  background: rgba(94,53,177,.18);  }
  .stats-round-v2 .card-meta {
    font-size: 11px;
    opacity: 0.65;
    color: #cdd;
    font-style: italic;
    font-variant-numeric: tabular-nums;
    margin-left: auto;
  }
  .stats-round-v2 .bsx-card-body { padding: 0; }

  .stats-round-v2 .round-search-form {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    margin-left: auto;
  }
  .stats-round-v2 .round-search-input {
    background: rgba(0,0,0,0.25);
    border: 1px solid rgba(255,255,255,.10);
    border-radius: 4px;
    color: #e0f0fa;
    font: inherit;
    font-size: 12px;
    padding: 4px 10px;
    width: 160px;
    transition: border-color 150ms ease, background 150ms ease;
  }
  .stats-round-v2 .round-search-input::placeholder { color: #8892a0; }
  .stats-round-v2 .round-search-input:focus {
    outline: none;
    border-color: rgba(79, 195, 247, 0.55);
    background: rgba(0,0,0,0.35);
  }
  .stats-round-v2 .round-pager { display: inline-flex; gap: 6px; }
  .stats-round-v2 .bsx-btn {
    font: inherit;
    font-size: 12px;
    font-weight: 600;
    letter-spacing: 0.04em;
    padding: 4px 10px;
    border-radius: 4px;
    cursor: pointer;
    border: 1px solid transparent;
    background: rgba(79, 195, 247, 0.10);
    border-color: rgba(79, 195, 247, 0.28);
    color: #cdd;
    text-decoration: none;
    display: inline-flex;
    align-items: center;
    transition: background 150ms ease, border-color 150ms ease;
  }
  .stats-round-v2 .bsx-btn:hover {
    background: rgba(79, 195, 247, 0.20);
    border-color: rgba(79, 195, 247, 0.55);
  }

  .stats-round-v2 .round-kv {
    margin: 0;
    display: grid;
    grid-template-columns: minmax(0, 1fr) minmax(0, 1.4fr) minmax(0, 1fr) minmax(0, 1.4fr);
    column-gap: 14px;
  }
  @media (max-width: 1100px) {
    .stats-round-v2 .round-kv { grid-template-columns: minmax(0, 1fr) minmax(0, 1.2fr); }
  }
  .stats-round-v2 .round-kv dt,
  .stats-round-v2 .round-kv dd {
    margin: 0;
    padding: 7px 14px;
    font-size: 12px;
    border-bottom: 1px solid rgba(255,255,255,.05);
  }
  .stats-round-v2 .round-kv dt {
    color: #aab2bd;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    font-size: 11px;
    font-weight: 700;
  }
  .stats-round-v2 .round-kv dd {
    color: #e0f0fa;
    font-variant-numeric: tabular-nums;
  }
  .stats-round-v2 .round-kv dd a { color: #4fc3f7; text-decoration: none; }
  .stats-round-v2 .round-kv dd a:hover { text-decoration: underline; }

  /* Tables */
  .stats-round-v2 .round-table-wrap { overflow-x: auto; }
  .stats-round-v2 .round-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 12px;
    color: #cdd;
  }
  .stats-round-v2 .round-table thead th {
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
  .stats-round-v2 .round-table tbody td {
    border-bottom: 1px solid rgba(255,255,255,.05);
    padding: 6px 12px;
    vertical-align: middle;
  }
  .stats-round-v2 .round-table tbody tr:last-child td { border-bottom: 0; }
  .stats-round-v2 .round-table tbody tr:nth-child(even) td { background: rgba(255,255,255,0.015); }
  .stats-round-v2 .round-table tbody tr:hover td { background: rgba(79, 195, 247, 0.06); }
  .stats-round-v2 .round-table tbody tr.is-me td {
    background: rgba(181, 231, 160, 0.10) !important;
    color: #d8efc6;
  }
  .stats-round-v2 .round-table tbody tr.is-me td:first-child {
    box-shadow: inset 3px 0 0 rgba(181, 231, 160, 0.65);
  }
  .stats-round-v2 .round-table .right  { text-align: right; }
  .stats-round-v2 .round-table .center { text-align: center; }
  .stats-round-v2 .round-table .num    { font-variant-numeric: tabular-nums; }
  .stats-round-v2 .round-table .th-rank,
  .stats-round-v2 .round-table .td-rank {
    text-align: center;
    width: 56px;
    color: #99a;
    font-variant-numeric: tabular-nums;
  }
  .stats-round-v2 .round-table .anon { font-style: italic; opacity: 0.7; }
  .stats-round-v2 .round-empty {
    text-align: center;
    padding: 16px;
    color: #888;
    opacity: 0.7;
    font-style: italic;
  }

  .stats-round-v2 .round-shares-row {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 16px;
    align-items: stretch;
  }
  @media (max-width: 1100px) {
    .stats-round-v2 .round-shares-row { grid-template-columns: 1fr; }
  }

  /* Status pills */
  .stats-round-v2 .status-pill {
    display: inline-block;
    padding: 2px 8px;
    border-radius: 999px;
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    border: 1px solid transparent;
  }
  .stats-round-v2 .status-pill.ok      { background: rgba(181, 231, 160, 0.18); border-color: rgba(181, 231, 160, 0.45); color: #b5e7a0; }
  .stats-round-v2 .status-pill.bad     { background: rgba(229, 115, 115, 0.18); border-color: rgba(229, 115, 115, 0.45); color: #ffb3b3; }
  .stats-round-v2 .status-pill.pending { background: rgba(255, 214, 110, 0.16); border-color: rgba(255, 214, 110, 0.45); color: #ffd66e; }

  .stats-round-v2 .pct.is-good { color: #b5e7a0; }
  .stats-round-v2 .pct.is-bad  { color: #ffb3b3; }

  /* Light mode */
  [data-theme="light"] .stats-round-v2 .bsx-card {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] .stats-round-v2 .bsx-card header {
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] .stats-round-v2 .bsx-card h3 { color: #1f2933; }
  [data-theme="light"] .stats-round-v2 .card-meta { color: #4a5568; }
  [data-theme="light"] .stats-round-v2 .round-search-input {
    background: #ffffff;
    border-color: rgba(0,0,0,0.18);
    color: #1f2933;
  }
  [data-theme="light"] .stats-round-v2 .round-search-input::placeholder { color: #6c7686; }
  [data-theme="light"] .stats-round-v2 .bsx-btn {
    color: #1f2933;
    background: rgba(25, 118, 210, 0.08);
    border-color: rgba(25, 118, 210, 0.40);
  }
  [data-theme="light"] .stats-round-v2 .round-kv dt,
  [data-theme="light"] .stats-round-v2 .round-kv dd { border-bottom-color: rgba(0, 0, 0, 0.06); }
  [data-theme="light"] .stats-round-v2 .round-kv dt { color: #4a5568; }
  [data-theme="light"] .stats-round-v2 .round-kv dd { color: #1f2933; }
  [data-theme="light"] .stats-round-v2 .round-kv dd a { color: #1565c0; }
  [data-theme="light"] .stats-round-v2 .round-table { color: #1f2933; }
  [data-theme="light"] .stats-round-v2 .round-table thead th {
    background: #eef0f2;
    border-bottom-color: rgba(0, 0, 0, 0.10);
    color: #4a5568;
  }
  [data-theme="light"] .stats-round-v2 .round-table tbody td { border-bottom-color: rgba(0, 0, 0, 0.06); }
  [data-theme="light"] .stats-round-v2 .round-table tbody tr:nth-child(even) td { background: rgba(0, 0, 0, 0.025); }
  [data-theme="light"] .stats-round-v2 .round-table tbody tr:hover td { background: rgba(25, 118, 210, 0.06); }
  [data-theme="light"] .stats-round-v2 .round-table tbody tr.is-me td {
    background: rgba(46, 125, 50, 0.10) !important;
    color: #1b5e20;
  }
  [data-theme="light"] .stats-round-v2 .status-pill.ok      { background: rgba(46, 125, 50, 0.18); border-color: rgba(46, 125, 50, 0.45); color: #1b5e20; }
  [data-theme="light"] .stats-round-v2 .status-pill.bad     { background: rgba(198, 40, 40, 0.12); border-color: rgba(198, 40, 40, 0.45); color: #c62828; }
  [data-theme="light"] .stats-round-v2 .status-pill.pending { background: rgba(239, 108, 0, 0.10); border-color: rgba(239, 108, 0, 0.45); color: #b53d00; }
  [data-theme="light"] .stats-round-v2 .pct.is-good { color: #1b5e20; }
  [data-theme="light"] .stats-round-v2 .pct.is-bad  { color: #c62828; }

  /* Custom tooltip — sits BELOW the source (pager + chain pills are
     near the top of the card, so above-positioning would clip them). */
  .stats-round-v2 [data-tooltip] { position: relative; outline: none; }
  .stats-round-v2 [data-tooltip]::after {
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
  .stats-round-v2 [data-tooltip]::before {
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
  .stats-round-v2 [data-tooltip]:hover::after,
  .stats-round-v2 [data-tooltip]:focus-visible::after { opacity: 1; transform: translateX(-50%) translateY(0); }
  .stats-round-v2 [data-tooltip]:hover::before,
  .stats-round-v2 [data-tooltip]:focus-visible::before { opacity: 1; transform: translateX(-50%) rotate(45deg) translateY(0); }
  [data-theme="light"] .stats-round-v2 [data-tooltip]::after,
  [data-theme="light"] .stats-round-v2 [data-tooltip]::before {
    background: #ffffff;
    border-color: rgba(21, 101, 192, 0.40);
    color: #1f2933;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
  }
</style>
