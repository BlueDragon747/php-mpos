<div id="bsx-v2-shell" class="stats-pool-v2">

  <!-- ROW 1: Combined Contributors (left) + Last Found Blocks (right) -->
  <article class="bsx-card pool-contrib-card">
    <header><h3>Top Contributors</h3><span class="card-meta">top {$CONTRIBUTORS|@count|default:0}</span></header>
    <div class="bsx-card-body pool-table-wrap">
      <table class="bsx-table pool-table">
        <thead>
          <tr>
            <th class="th-rank">Rank</th>
            <th class="th-icon"></th>
            <th>User</th>
            <th class="right">Shares</th>
            <th class="right">KH/s</th>
            <th class="right">{$GLOBAL.config.currency}/Day</th>
            {if $GLOBAL.config.price.currency}<th class="right">{$GLOBAL.config.price.currency}/Day</th>{/if}
          </tr>
        </thead>
        <tbody>
{assign var=rank value=1}
{assign var=listed value=0}
{section name=contrib loop=$CONTRIBUTORS}
          {if $CONTRIBUTORS[contrib].hashrate|default:0 > 0}
            {math assign="estday" equation="round(reward / ( diff * pow(2,32) / ( hashrate * 1000 ) / 3600 / 24), 3)" diff=$DIFFICULTY reward=$REWARD hashrate=$CONTRIBUTORS[contrib].hashrate}
          {else}
            {assign var=estday value=0}
          {/if}
          <tr{if $GLOBAL.userdata.username|default:""|lower == $CONTRIBUTORS[contrib].account|lower}{assign var=listed value=1} class="is-me"{/if}>
            <td class="td-rank">{$rank++}</td>
            <td class="td-icon">{if $CONTRIBUTORS[contrib].donate_percent > 0}<span class="donor" data-tooltip="Donor">★</span>{/if}</td>
            <td class="td-name">{if $CONTRIBUTORS[contrib].is_anonymous|default:"0" == 1 && $GLOBAL.userdata.is_admin|default:"0" == 0}<span class="anon">anonymous</span>{else}{$CONTRIBUTORS[contrib].account|escape}{/if}</td>
            <td class="right num">{$CONTRIBUTORS[contrib].shares|default:0|number_format}</td>
            <td class="right num">{$CONTRIBUTORS[contrib].hashrate|default:0|number_format}</td>
            <td class="right num">{$estday|number_format:"3"}</td>
            {if $GLOBAL.config.price.currency}<td class="right num">{($estday * $GLOBAL.price)|default:"n/a"|number_format:"4"}</td>{/if}
          </tr>
{/section}
{if $listed != 1 && $GLOBAL.userdata.username|default:"" && ($GLOBAL.userdata.rawhashrate|default:"0" > 0 || $GLOBAL.userdata.shares.valid|default:"0" > 0)}
          {if $GLOBAL.userdata.rawhashrate|default:0 > 0}
            {math assign="myestday" equation="round(reward / ( diff * pow(2,32) / ( hashrate * 1000 ) / 3600 / 24), 3)" diff=$DIFFICULTY reward=$REWARD hashrate=$GLOBAL.userdata.rawhashrate}
          {else}
            {assign var=myestday value=0}
          {/if}
          <tr class="is-me">
            <td class="td-rank">n/a</td>
            <td class="td-icon">{if $GLOBAL.userdata.donate_percent > 0}<span class="donor" data-tooltip="Donor">★</span>{/if}</td>
            <td class="td-name">{$GLOBAL.userdata.username|escape}</td>
            <td class="right num">{$GLOBAL.userdata.shares.valid|default:0|number_format}</td>
            <td class="right num">{$GLOBAL.userdata.rawhashrate|default:0|number_format}</td>
            <td class="right num">{$myestday|number_format:"3"|default:"n/a"}</td>
            {if $GLOBAL.config.price.currency}<td class="right num">{($myestday * $GLOBAL.price)|default:"n/a"|number_format:"4"}</td>{/if}
          </tr>
{/if}
        </tbody>
      </table>
    </div>
  </article>

  <!-- ROW 1 (right): Last Found Blocks -->
  <article class="bsx-card pool-blocks-card">
    <header><h3>Last Found Blocks</h3><span class="card-meta">{$BLOCKSFOUND|@count|default:0} shown</span></header>
    <div class="bsx-card-body pool-table-wrap">
      <table class="bsx-table pool-table">
        <thead>
          <tr>
            <th class="th-rank">Block</th>
            <th class="center">Coin</th>
            <th>Finder</th>
            <th class="center">Time</th>
            <th class="right">Actual Shares</th>
          </tr>
        </thead>
        <tbody>
{section name=block loop=$BLOCKSFOUND}
          <tr>
            <td class="td-rank">
              <a href="https://explorer.blakestream.io/{$BLOCKSFOUND[block].chain|default:""|escape|lower}?block={$BLOCKSFOUND[block].height}"
                 target="_blank" rel="noopener"
                 data-tooltip="View block {$BLOCKSFOUND[block].height} on the BlakeStream Explorer (new tab)">{$BLOCKSFOUND[block].height}</a>
            </td>
            <td class="center"><span class="chain-pill chain-{$BLOCKSFOUND[block].chain|default:""|escape|lower}" data-tooltip="{$COIN_NAMES[$BLOCKSFOUND[block].chain]|default:$BLOCKSFOUND[block].chain|escape}">{$BLOCKSFOUND[block].chain|default:""|escape}</span></td>
            <td class="td-name">{if $BLOCKSFOUND[block].is_anonymous|default:"0" == 1 && $GLOBAL.userdata.is_admin|default:"0" == 0}<span class="anon">anonymous</span>{else}{$BLOCKSFOUND[block].finder|default:"unknown"|escape}{/if}</td>
            <td class="center num">{$BLOCKSFOUND[block].time|date_format:"%d/%m %H:%M:%S"}</td>
            <td class="right num">{$BLOCKSFOUND[block].shares|number_format}</td>
          </tr>
{sectionelse}
          <tr><td colspan="5" class="pool-empty">No blocks found yet.</td></tr>
{/section}
        </tbody>
      </table>
    </div>
{if $GLOBAL.config.payout_system != 'pps'}
    <footer class="pool-card-footer">
      Round Earnings credited after <strong>{$GLOBAL.confirmations}</strong> confirmations.
    </footer>
{/if}
  </article>

  <!-- ROW 2 (full width): General Statistics —
       Pool-wide stats (Hash Rate, Efficiency, Active Workers) are
       constant across coins because the pool is merge-mined; per-coin
       stats (difficulty, last block, etc.) live in tabbed panels. The
       chain pill in Last Found Blocks acts as a shortcut that selects
       the matching tab. -->
  <article class="bsx-card pool-stats-card" data-active-coin="{$GLOBAL.config.currency|escape}">
    <header class="pool-stats-head">
      <h3>General Statistics</h3>
      <nav class="pool-coin-tabs" role="tablist" aria-label="Per-coin statistics">
{foreach from=$COIN_TICKERS item=tk}
        <button type="button"
                class="pool-coin-tab chain-pill chain-{$tk|escape|lower}"
                role="tab"
                data-coin="{$tk|escape}">{$tk|escape}</button>
{/foreach}
      </nav>
    </header>
    <div class="bsx-card-body pool-stats-body">
      <!-- Pool-wide block: identical regardless of selected coin. -->
      <dl class="pool-kv pool-kv-shared">
        <dt>Pool Hash Rate</dt>
        <dd><span id="b-hashrate">{$GLOBAL.hashrate|number_format:"3"}</span> {$GLOBAL.hashunits.pool}</dd>

        <dt>Pool Efficiency</dt>
        <dd>{if $GLOBAL.roundshares.valid > 0}{($GLOBAL.roundshares.valid / ($GLOBAL.roundshares.valid + $GLOBAL.roundshares.invalid) * 100)|number_format:"2"}%{else}0%{/if}</dd>

        <dt>Active Workers</dt>
        <dd id="b-workers">{$GLOBAL.workers|default:0}</dd>
      </dl>

      <!-- Per-coin panels: one rendered per active slot, only the panel
           matching .pool-stats-card[data-active-coin] is visible. -->
{foreach from=$COIN_TICKERS item=tk}
{assign var="cs" value=$STATS_BY_COIN[$tk]}
      <dl class="pool-kv pool-kv-percoin" data-coin="{$tk|escape}">
        <dt>Difficulty</dt>
        <dd><span class="b-diff-{$tk|escape|lower}">{$cs.difficulty}</span></dd>

        <dt>Est. Next Difficulty</dt>
        <dd>{$cs.EstNextDifficulty} <span class="dim">(in {$cs.BlocksUntilDiffChange} blocks)</span></dd>

        <dt>Avg. Time / Round (Network)</dt>
        <dd>{$cs.EstTimePerBlock|seconds_to_words}</dd>

        <dt>Avg. Time / Round (Pool)</dt>
        <dd>{$cs.AvgPoolTime|seconds_to_words}</dd>

        <dt>Last Block Found</dt>
        <dd>
        {if $cs.LastBlock > 0}
          <a href="https://explorer.blakestream.io/{$tk|escape|lower}?block={$cs.LastBlock}"
             target="_blank" rel="noopener"
             data-tooltip="View block {$cs.LastBlock} on the BlakeStream Explorer (new tab)">{$cs.LastBlock}</a>
        {else}
          0
        {/if}
        </dd>

        <dt>Est. Shares this Round</dt>
        <dd>{$cs.EstShares} <span class="dim">(done: {$cs.EstPercent}%)</span></dd>

        <dt>Next Network Block</dt>
        <dd>{$cs.CurrentBlock + 1} <span class="dim">(current:
        {if $cs.CurrentBlock > 0}
          <a href="https://explorer.blakestream.io/{$tk|escape|lower}?block={$cs.CurrentBlock}"
             target="_blank" rel="noopener"
             data-tooltip="View block {$cs.CurrentBlock} on the BlakeStream Explorer (new tab)">{$cs.CurrentBlock}</a>
        {else}
          {$cs.CurrentBlock}
        {/if}
        )</span></dd>

        <dt>Time Since Last Block</dt>
        <dd>{if $cs.TimeSinceLast > 0}{$cs.TimeSinceLast|seconds_to_words}{else}—{/if}</dd>
      </dl>
{/foreach}
    </div>
{if !$GLOBAL.website.api.disabled}
    <footer class="pool-card-footer">
      JSON: <a href="{$smarty.server.SCRIPT_NAME}?page=api&action=getpoolstatus&api_key={$GLOBAL.userdata.api_key|default:""}">getpoolstatus</a>
    </footer>
{/if}
  </article>

</div>

{if !$GLOBAL.website.api.disabled && !$GLOBAL.config.disable_navbar && !$GLOBAL.config.disable_navbar_api}
{include file="statistics/js.tpl"}
{/if}

<script>
  // Per-coin General Statistics tab switcher. The card's data-active-coin
  // attribute drives which dl.pool-kv-percoin is visible (CSS handles the
  // show/hide). Two trigger surfaces: (1) the explicit tab buttons in the
  // card header, (2) clicking a chain-pill in the Last Found Blocks list.
  (function () {
    const card = document.querySelector('.pool-stats-card');
    if (!card) return;
    function setCoin(c) {
      if (!c) return;
      const upper = c.toUpperCase();
      card.setAttribute('data-active-coin', upper);
      card.querySelectorAll('.pool-coin-tab').forEach(function (t) {
        t.classList.toggle('is-active', t.getAttribute('data-coin') === upper);
      });
    }
    // Initial active-tab highlight.
    setCoin(card.getAttribute('data-active-coin') || '');
    // Tab buttons.
    card.querySelectorAll('.pool-coin-tab').forEach(function (t) {
      t.addEventListener('click', function () { setCoin(t.getAttribute('data-coin')); });
    });
    // Last Found Blocks chain pills — click switches the tab. We keep
    // the block-number link separate so the explorer deep-link is
    // unaffected. The pills sit in the .pool-blocks-card table.
    document.querySelectorAll('.pool-blocks-card .chain-pill').forEach(function (p) {
      p.style.cursor = 'pointer';
      p.title = 'Show ' + (p.textContent || '').trim() + ' statistics';
      p.addEventListener('click', function () {
        setCoin((p.textContent || '').trim());
        // Scroll the General Statistics card into view so the user
        // sees the switched panel after clicking.
        card.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
      });
    });
  })();
</script>

<style>
  /* General Statistics tab strip — the chain-pill class above already
     paints each tab in its coin's accent. Add interaction state on top:
     dim inactive tabs, brighten on hover, full opacity on active. */
  .stats-pool-v2 .pool-stats-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    flex-wrap: wrap;
  }
  .stats-pool-v2 .pool-coin-tabs {
    display: inline-flex;
    gap: 6px;
    flex-wrap: wrap;
  }
  .stats-pool-v2 .pool-coin-tab {
    cursor: pointer;
    font-family: inherit;
    padding: 3px 10px;
    font-size: 10px;
    opacity: 0.55;
    transition: opacity 120ms ease, transform 120ms ease;
  }
  .stats-pool-v2 .pool-coin-tab:hover { opacity: 0.85; }
  .stats-pool-v2 .pool-coin-tab.is-active {
    opacity: 1;
    transform: translateY(-1px);
    box-shadow: 0 0 0 1px currentColor inset;
  }

  /* Per-coin panels: only the dl matching .pool-stats-card[data-active-coin]
     stays in the flow; the rest are hidden. Selector specificity bumped
     by including .pool-stats-card so it beats the generic .pool-kv
     `display: grid` rule below (which would otherwise un-hide every
     panel via source-order tie-break). */
  .stats-pool-v2 .pool-stats-card .pool-kv-percoin { display: none; }
{foreach from=$COIN_TICKERS item=tk}
  .stats-pool-v2 .pool-stats-card[data-active-coin="{$tk|escape}"] .pool-kv-percoin[data-coin="{$tk|escape}"] {
    display: grid;
  }
{/foreach}

  /* Chain pill — same palette as the Blocks/Round pages so all three
     pages reference coins the same way. Per-coin colour-coded background
     + border + text for quick visual identification. */
  .stats-pool-v2 .chain-pill {
    display: inline-block;
    font-size: 9px;
    font-weight: 700;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    padding: 1px 6px;
    border-radius: 999px;
    border: 1px solid transparent;
    line-height: 1.4;
  }
  .stats-pool-v2 .chain-pill.chain-bbtc { color: #ea4335; border-color: rgba(234,67,53,.40);  background: rgba(234,67,53,.10);  }
  .stats-pool-v2 .chain-pill.chain-blc  { color: #ff9800; border-color: rgba(255,152,0,.40);  background: rgba(255,152,0,.10);  }
  .stats-pool-v2 .chain-pill.chain-elt  { color: #34a853; border-color: rgba(52,168,83,.40);  background: rgba(52,168,83,.10);  }
  .stats-pool-v2 .chain-pill.chain-lit  { color: #fbbc04; border-color: rgba(251,188,4,.40);  background: rgba(251,188,4,.10);  }
  .stats-pool-v2 .chain-pill.chain-pho  { color: #4285f4; border-color: rgba(66,133,244,.40); background: rgba(66,133,244,.10); }
  .stats-pool-v2 .chain-pill.chain-umo  { color: #7b61ff; border-color: rgba(123,97,255,.40); background: rgba(123,97,255,.10); }
  /* Light-mode chip overrides — darker hex per coin (yellow→orange for
     LIT since yellow is unreadable on white), bumped saturation
     (.18 bg / .55 border) so each chip stays distinct on a white
     surface. Same identity, different intensity. */
  [data-theme="light"] .stats-pool-v2 .chain-pill.chain-bbtc { color: #c5221f; border-color: rgba(197,34,31,.55);  background: rgba(197,34,31,.18);  }
  [data-theme="light"] .stats-pool-v2 .chain-pill.chain-blc  { color: #e65100; border-color: rgba(230,81,0,.55);   background: rgba(230,81,0,.18);   }
  [data-theme="light"] .stats-pool-v2 .chain-pill.chain-elt  { color: #2e7d32; border-color: rgba(46,125,50,.55);  background: rgba(46,125,50,.18);  }
  [data-theme="light"] .stats-pool-v2 .chain-pill.chain-lit  { color: #f57c00; border-color: rgba(245,124,0,.55);  background: rgba(245,124,0,.18);  }
  [data-theme="light"] .stats-pool-v2 .chain-pill.chain-pho  { color: #1565c0; border-color: rgba(21,101,192,.55); background: rgba(21,101,192,.18); }
  [data-theme="light"] .stats-pool-v2 .chain-pill.chain-umo  { color: #5e35b1; border-color: rgba(94,53,177,.55);  background: rgba(94,53,177,.18);  }

  .stats-pool-v2 {
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
    .stats-pool-v2 { grid-template-columns: 1fr; }
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
  .stats-pool-v2 .bsx-card {
    background: rgba(255,255,255,.03);
    border: 1px solid rgba(255,255,255,.06);
    border-radius: 6px;
    overflow: hidden;
  }
  .stats-pool-v2 .bsx-card header {
    background: rgba(255,255,255,.05);
    padding: 6px 14px;
    border-bottom: 1px solid rgba(255,255,255,.06);
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    flex-wrap: wrap;
  }
  .stats-pool-v2 .bsx-card h3 {
    margin: 0;
    font-size: 13px;
    color: #cdd;
    letter-spacing: 0.04em;
    text-transform: uppercase;
  }
  .stats-pool-v2 .card-meta {
    font-size: 11px;
    opacity: 0.65;
    color: #cdd;
    font-style: italic;
    font-variant-numeric: tabular-nums;
  }
  .stats-pool-v2 .bsx-card-body { padding: 0; }
  .stats-pool-v2 .pool-card-footer {
    padding: 6px 14px;
    border-top: 1px solid rgba(255,255,255,.06);
    background: rgba(255,255,255,.02);
    font-size: 11px;
    color: #cdd;
    opacity: 0.75;
  }
  .stats-pool-v2 .pool-card-footer a { color: #4fc3f7; text-decoration: none; }
  .stats-pool-v2 .pool-card-footer a:hover { text-decoration: underline; }

  /* Tables */
  .stats-pool-v2 .pool-table-wrap { overflow-x: auto; }

  /* Contributors and Last Found Blocks scroll past ~20 rows. */
  .stats-pool-v2 .pool-contrib-card .pool-table-wrap,
  .stats-pool-v2 .pool-blocks-card  .pool-table-wrap {
    overflow: auto;
    max-height: 580px;
    scrollbar-width: thin;
    scrollbar-color: rgba(255, 255, 255, 0.18) transparent;
  }
  .stats-pool-v2 .pool-contrib-card .pool-table-wrap::-webkit-scrollbar,
  .stats-pool-v2 .pool-blocks-card  .pool-table-wrap::-webkit-scrollbar { width: 8px; height: 8px; }
  .stats-pool-v2 .pool-contrib-card .pool-table-wrap::-webkit-scrollbar-track,
  .stats-pool-v2 .pool-blocks-card  .pool-table-wrap::-webkit-scrollbar-track { background: transparent; }
  .stats-pool-v2 .pool-contrib-card .pool-table-wrap::-webkit-scrollbar-thumb,
  .stats-pool-v2 .pool-blocks-card  .pool-table-wrap::-webkit-scrollbar-thumb {
    background-color: rgba(255, 255, 255, 0.18);
    border-radius: 4px;
    border: 2px solid transparent;
    background-clip: padding-box;
  }
  .stats-pool-v2 .pool-contrib-card .pool-table-wrap::-webkit-scrollbar-thumb:hover,
  .stats-pool-v2 .pool-blocks-card  .pool-table-wrap::-webkit-scrollbar-thumb:hover {
    background-color: rgba(79, 195, 247, 0.45);
  }
  /* Sticky header */
  .stats-pool-v2 .pool-contrib-card .pool-table thead th,
  .stats-pool-v2 .pool-blocks-card  .pool-table thead th {
    position: sticky;
    top: 0;
    z-index: 2;
    background: #1f2329;
  }
  [data-theme="light"] .stats-pool-v2 .pool-contrib-card .pool-table thead th,
  [data-theme="light"] .stats-pool-v2 .pool-blocks-card  .pool-table thead th {
    background: #eef0f2;
  }
  /* General Statistics — full width, content-sized. */
  .stats-pool-v2 .pool-stats-card {
    grid-column: 1 / -1;
    align-self: start;
  }
  .stats-pool-v2 .pool-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 12px;
    color: #cdd;
  }
  .stats-pool-v2 .pool-table thead th {
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
  .stats-pool-v2 .pool-table tbody td {
    border-bottom: 1px solid rgba(255,255,255,.05);
    padding: 6px 12px;
    vertical-align: middle;
  }
  .stats-pool-v2 .pool-table tbody tr:last-child td { border-bottom: 0; }
  .stats-pool-v2 .pool-table tbody tr:nth-child(even) td {
    background: rgba(255,255,255,0.015);
  }
  .stats-pool-v2 .pool-table tbody tr:hover td { background: rgba(79, 195, 247, 0.06); }
  .stats-pool-v2 .pool-table tbody tr.is-me td {
    background: rgba(181, 231, 160, 0.10) !important;
    color: #d8efc6;
  }
  .stats-pool-v2 .pool-table tbody tr.is-me td:first-child {
    box-shadow: inset 3px 0 0 rgba(181, 231, 160, 0.65);
  }
  .stats-pool-v2 .pool-table .right  { text-align: right; }
  .stats-pool-v2 .pool-table .center { text-align: center; }
  .stats-pool-v2 .pool-table .num    { font-variant-numeric: tabular-nums; }
  .stats-pool-v2 .pool-table .th-rank,
  .stats-pool-v2 .pool-table .td-rank { text-align: center; width: 56px; color: #99a; font-variant-numeric: tabular-nums; }
  .stats-pool-v2 .pool-table .th-icon,
  .stats-pool-v2 .pool-table .td-icon { text-align: center; width: 22px; }
  .stats-pool-v2 .pool-table .donor { color: #ffd66e; font-size: 13px; }
  .stats-pool-v2 .pool-table .anon  { font-style: italic; opacity: 0.7; }
  .stats-pool-v2 .pool-empty {
    text-align: center;
    padding: 16px;
    color: #888;
    opacity: 0.7;
    font-style: italic;
  }

  /* Definition list (general stats) */
  .stats-pool-v2 .pool-kv {
    margin: 0;
    display: grid;
    grid-template-columns: minmax(0, 1fr) minmax(0, 1.4fr) minmax(0, 1fr) minmax(0, 1.4fr);
    column-gap: 14px;
  }
  @media (max-width: 1100px) {
    .stats-pool-v2 .pool-kv {
      grid-template-columns: minmax(0, 1fr) minmax(0, 1.2fr);
    }
  }
  .stats-pool-v2 .pool-kv dt,
  .stats-pool-v2 .pool-kv dd {
    margin: 0;
    padding: 7px 14px;
    font-size: 12px;
    border-bottom: 1px solid rgba(255,255,255,.05);
  }
  .stats-pool-v2 .pool-kv dt {
    color: #aab2bd;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    font-size: 11px;
    font-weight: 700;
  }
  .stats-pool-v2 .pool-kv dd {
    color: #e0f0fa;
    font-variant-numeric: tabular-nums;
  }
  .stats-pool-v2 .pool-kv dd a { color: #4fc3f7; text-decoration: none; }
  .stats-pool-v2 .pool-kv dd a:hover { text-decoration: underline; }
  .stats-pool-v2 .pool-kv dd .dim { color: #99a; font-size: 11px; font-style: italic; margin-left: 4px; }
  .stats-pool-v2 .pool-kv dt:nth-last-of-type(1),
  .stats-pool-v2 .pool-kv dd:nth-last-of-type(1) { border-bottom: 0; }

  /* Light mode */
  [data-theme="light"] .stats-pool-v2 .bsx-card {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] .stats-pool-v2 .bsx-card header {
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] .stats-pool-v2 .bsx-card h3 { color: #1f2933; }
  [data-theme="light"] .stats-pool-v2 .card-meta { color: #4a5568; }
  [data-theme="light"] .stats-pool-v2 .pool-table { color: #1f2933; }
  [data-theme="light"] .stats-pool-v2 .pool-table thead th {
    background: #eef0f2;
    border-bottom-color: rgba(0, 0, 0, 0.10);
    color: #4a5568;
  }
  [data-theme="light"] .stats-pool-v2 .pool-table tbody td {
    border-bottom-color: rgba(0, 0, 0, 0.06);
  }
  [data-theme="light"] .stats-pool-v2 .pool-table tbody tr:nth-child(even) td {
    background: rgba(0, 0, 0, 0.025);
  }
  [data-theme="light"] .stats-pool-v2 .pool-table tbody tr:hover td {
    background: rgba(25, 118, 210, 0.06);
  }
  [data-theme="light"] .stats-pool-v2 .pool-table tbody tr.is-me td {
    background: rgba(46, 125, 50, 0.10) !important;
    color: #1b5e20;
  }
  [data-theme="light"] .stats-pool-v2 .pool-table .donor { color: #ef6c00; }
  [data-theme="light"] .stats-pool-v2 .pool-kv dt,
  [data-theme="light"] .stats-pool-v2 .pool-kv dd {
    border-bottom-color: rgba(0, 0, 0, 0.06);
  }
  [data-theme="light"] .stats-pool-v2 .pool-kv dt { color: #4a5568; }
  [data-theme="light"] .stats-pool-v2 .pool-kv dd { color: #1f2933; }
  [data-theme="light"] .stats-pool-v2 .pool-kv dd a { color: #1565c0; }
  [data-theme="light"] .stats-pool-v2 .pool-kv dd .dim { color: #6c7686; }
  [data-theme="light"] .stats-pool-v2 .pool-card-footer {
    background: #f7f8fa;
    border-top-color: rgba(0, 0, 0, 0.08);
    color: #4a5568;
  }
  [data-theme="light"] .stats-pool-v2 .pool-card-footer a { color: #1565c0; }

  /* Custom tooltip — sits above the source. Mirrors the System Status pattern. */
  .stats-pool-v2 [data-tooltip] { position: relative; outline: none; }
  .stats-pool-v2 [data-tooltip]::after {
    content: attr(data-tooltip);
    position: absolute;
    bottom: calc(100% + 8px);
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
    transform: translateX(-50%) translateY(2px);
    z-index: 100;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.45);
  }
  .stats-pool-v2 [data-tooltip]::before {
    content: '';
    position: absolute;
    bottom: calc(100% + 3px);
    left: 50%;
    width: 8px;
    height: 8px;
    background: rgba(20, 23, 28, 0.96);
    border-bottom: 1px solid rgba(79, 195, 247, 0.35);
    border-right: 1px solid rgba(79, 195, 247, 0.35);
    transform: translateX(-50%) rotate(45deg) translateY(2px);
    opacity: 0;
    pointer-events: none;
    transition: opacity 150ms ease, transform 150ms ease;
    z-index: 101;
  }
  .stats-pool-v2 [data-tooltip]:hover::after,
  .stats-pool-v2 [data-tooltip]:focus-visible::after { opacity: 1; transform: translateX(-50%) translateY(0); }
  .stats-pool-v2 [data-tooltip]:hover::before,
  .stats-pool-v2 [data-tooltip]:focus-visible::before { opacity: 1; transform: translateX(-50%) rotate(45deg) translateY(0); }
  [data-theme="light"] .stats-pool-v2 [data-tooltip]::after,
  [data-theme="light"] .stats-pool-v2 [data-tooltip]::before {
    background: #ffffff;
    border-color: rgba(21, 101, 192, 0.40);
    color: #1f2933;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
  }
</style>
