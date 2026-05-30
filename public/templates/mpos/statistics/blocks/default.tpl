<div id="bsx-v2-shell" class="stats-blocks-v2">

{* The .blocks-pager and .blocks-coin-filter elements are JS-relocated
   to whichever card is the topmost expanded one — see relocateHeaderControls()
   in the script block below. Default DOM placement is in the graph
   card header (pager) and the overview card header (coin filter); when
   the graph card is collapsed both controls migrate together. *}

  <!-- SECTION 1: Block Shares graph -->
  <article class="bsx-card blocks-graph-card" data-card-id="graph">
    <header>
      <button type="button" class="bsx-collapse-toggle" aria-label="Collapse section">▾</button>
      <h3>Block Shares{if $SELECTED_COIN|default:"ALL" != "ALL"} ({$SELECTED_COIN|escape}){/if}</h3>
{if !$BLOCKS_HIDE_NAV|default:false}
      <div class="blocks-pager">
        {if $PAGER_AT_OLDEST|default:false}
          <span class="bsx-btn bsx-btn-small is-disabled" data-tooltip="Already at oldest">‹ Older</span>
        {else}
          <a class="bsx-btn bsx-btn-small"
             href="{$smarty.server.SCRIPT_NAME}?page={$smarty.request.page|escape}&action={$smarty.request.action|escape}&coin={$SELECTED_COIN|default:'ALL'|escape}&before={$PAGER_OLDER_TIME}"
             data-tooltip="Older blocks">‹ Older</a>
        {/if}
        {if $PAGER_AT_NEWEST|default:false}
          <span class="bsx-btn bsx-btn-small is-disabled" data-tooltip="Already at newest">Newer ›</span>
        {else}
          <a class="bsx-btn bsx-btn-small"
             href="{$smarty.server.SCRIPT_NAME}?page={$smarty.request.page|escape}&action={$smarty.request.action|escape}&coin={$SELECTED_COIN|default:'ALL'|escape}&after={$PAGER_NEWER_TIME}"
             data-tooltip="Newer blocks">Newer ›</a>
        {/if}
      </div>
{/if}
    </header>
    <div class="bsx-card-body blocks-graph-body">
      {* Same `table.visualize` markup the legacy page used — custom.js
         picks this up via `$('table.visualize').each(...)`, hides the
         table, and renders a canvas chart in its place. *}
      <table width="70%" class="visualize" rel="line">
        <caption>Block Shares</caption>
        <thead>
          <tr>
{section name=block loop=$BLOCKSFOUND step=-1}
            <th scope="col">{$BLOCKSFOUND[block].height}</th>
{/section}
          </tr>
        </thead>
        <tbody>
          <tr>
            <th scope="row">Expected</th>
{section name=block loop=$BLOCKSFOUND step=-1}
            <td>{$BLOCKSFOUND[block].estshares}</td>
{/section}
          </tr>
          <tr>
            <th scope="row">Actual</th>
{section name=block loop=$BLOCKSFOUND step=-1}
            <td>{$BLOCKSFOUND[block].shares|default:"0"}</td>
{/section}
          </tr>
          {if $GLOBAL.config.payout_system == 'pplns'}
          <tr>
            <th scope="row">PPLNS</th>
{section name=block loop=$BLOCKSFOUND step=-1}
            <td>{$BLOCKSFOUND[block].pplns_shares}</td>
{/section}
          </tr>
          {/if}
          {if $USEBLOCKAVERAGE}
          <tr>
            <th scope="row">Average</th>
{section name=block loop=$BLOCKSFOUND step=-1}
            <td>{$BLOCKSFOUND[block].block_avg}</td>
{/section}
          </tr>
          {/if}
        </tbody>
      </table>
    </div>
    <footer class="blocks-card-footer">
      Graph above: <strong>N</strong> shares to find a block vs.
      <strong>E</strong> shares expected, based on target and network
      difficulty (zero-variance baseline).
    </footer>
  </article>

  <!-- SECTION 2: Block Overview pivot table -->
  <article class="bsx-card blocks-overview-card" data-card-id="overview">
    <header>
      <button type="button" class="bsx-collapse-toggle" aria-label="Collapse section">▾</button>
      <h3>Block Overview{if $SELECTED_COIN|default:"ALL" != "ALL"} ({$SELECTED_COIN|escape}){/if}</h3>
{if !$BLOCKS_HIDE_NAV|default:false}
      <form method="get" action="{$smarty.server.SCRIPT_NAME}" class="blocks-coin-filter">
        <input type="hidden" name="page"   value="{$smarty.request.page|escape}">
        <input type="hidden" name="action" value="{$smarty.request.action|escape}">
        <label for="blocks-coin-select" class="blocks-coin-filter-label">Coin</label>
        <select id="blocks-coin-select" name="coin" onchange="this.form.submit()">
          <option value="ALL"{if $SELECTED_COIN|default:"ALL" == "ALL"} selected{/if}>ALL</option>
          {foreach from=$COIN_OPTIONS item=opt}
          <option value="{$opt|escape}"{if $SELECTED_COIN == $opt} selected{/if}>{$opt|escape}</option>
          {/foreach}
        </select>
      </form>
{/if}
    </header>
    <div class="bsx-card-body blocks-table-wrap">
      <table class="bsx-table blocks-table">
        <thead>
          <tr>
            <th class="th-period">Period</th>
            <th class="center">Gen Est.</th>
            <th class="center">Found</th>
            <th class="center">Valid</th>
            <th class="center">Orphan</th>
            <th class="center">Avg Diff</th>
            <th class="center">Shares Est.</th>
            <th class="center">Shares</th>
            <th class="center">Percentage</th>
            <th class="center">Amount</th>
            <th class="center">Rate Est.</th>
          </tr>
        </thead>
        <tbody>
          {* All Time *}
          <tr>
            <th class="td-period">All Time</th>
            <td class="center num">{($FIRSTBLOCKFOUND / $COINGENTIME)|number_format:"0"}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.Total}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.TotalValid}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.TotalOrphan}</td>
            <td class="center num">{if $LASTBLOCKSBYTIME.TotalValid > 0}{($LASTBLOCKSBYTIME.TotalDifficulty / $LASTBLOCKSBYTIME.TotalValid)|number_format:"4"}{else}0{/if}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.TotalEstimatedShares}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.TotalShares}</td>
            <td class="center num">
              {if $LASTBLOCKSBYTIME.TotalEstimatedShares > 0}
                {assign var="pct" value=($LASTBLOCKSBYTIME.TotalShares / $LASTBLOCKSBYTIME.TotalEstimatedShares * 100)}
                <span class="pct {if $pct <= 100}is-good{else}is-bad{/if}">{$pct|number_format:"2"}%</span>
              {else}0.00%{/if}
            </td>
            <td class="center num">{$LASTBLOCKSBYTIME.TotalAmount}</td>
            <td class="center num">{($LASTBLOCKSBYTIME.Total|default:"0.00" / ($FIRSTBLOCKFOUND / $COINGENTIME) * 100)|number_format:"2"}%</td>
          </tr>
          {* Last Hour *}
          <tr>
            <th class="td-period">Last Hour</th>
            <td class="center num">{(3600 / $COINGENTIME)|number_format:"0"}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.1HourTotal}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.1HourValid}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.1HourOrphan}</td>
            <td class="center num">{if $LASTBLOCKSBYTIME.1HourValid > 0}{($LASTBLOCKSBYTIME.1HourDifficulty / $LASTBLOCKSBYTIME.1HourValid)|number_format:"4"}{else}0{/if}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.1HourEstimatedShares}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.1HourShares}</td>
            <td class="center num">
              {if $LASTBLOCKSBYTIME.1HourEstimatedShares > 0}
                {assign var="pct" value=($LASTBLOCKSBYTIME.1HourShares / $LASTBLOCKSBYTIME.1HourEstimatedShares * 100)}
                <span class="pct {if $pct <= 100}is-good{else}is-bad{/if}">{$pct|number_format:"2"}%</span>
              {else}0.00%{/if}
            </td>
            <td class="center num">{$LASTBLOCKSBYTIME.1HourAmount}</td>
            <td class="center num">{($LASTBLOCKSBYTIME.1HourTotal|default:"0.00" / (3600 / $COINGENTIME) * 100)|number_format:"2"}%</td>
          </tr>
          {* Last 24 Hours *}
          <tr>
            <th class="td-period">Last 24 Hrs</th>
            <td class="center num">{(86400 / $COINGENTIME)|number_format:"0"}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.24HourTotal}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.24HourValid}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.24HourOrphan}</td>
            <td class="center num">{if $LASTBLOCKSBYTIME.24HourValid > 0}{($LASTBLOCKSBYTIME.24HourDifficulty / $LASTBLOCKSBYTIME.24HourValid)|number_format:"4"}{else}0{/if}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.24HourEstimatedShares}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.24HourShares}</td>
            <td class="center num">
              {if $LASTBLOCKSBYTIME.24HourEstimatedShares > 0}
                {assign var="pct" value=($LASTBLOCKSBYTIME.24HourShares / $LASTBLOCKSBYTIME.24HourEstimatedShares * 100)}
                <span class="pct {if $pct <= 100}is-good{else}is-bad{/if}">{$pct|number_format:"2"}%</span>
              {else}0.00%{/if}
            </td>
            <td class="center num">{$LASTBLOCKSBYTIME.24HourAmount}</td>
            <td class="center num">{($LASTBLOCKSBYTIME.24HourTotal|default:"0.00" / (86400 / $COINGENTIME) * 100)|number_format:"2"}%</td>
          </tr>
          {* Last 7 Days *}
          <tr>
            <th class="td-period">Last 7 Days</th>
            <td class="center num">{(604800 / $COINGENTIME)|number_format:"0"}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.7DaysTotal}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.7DaysValid}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.7DaysOrphan}</td>
            <td class="center num">{if $LASTBLOCKSBYTIME.7DaysValid > 0}{($LASTBLOCKSBYTIME.7DaysDifficulty / $LASTBLOCKSBYTIME.7DaysValid)|number_format:"4"}{else}0{/if}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.7DaysEstimatedShares}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.7DaysShares}</td>
            <td class="center num">
              {if $LASTBLOCKSBYTIME.7DaysEstimatedShares > 0}
                {assign var="pct" value=($LASTBLOCKSBYTIME.7DaysShares / $LASTBLOCKSBYTIME.7DaysEstimatedShares * 100)}
                <span class="pct {if $pct <= 100}is-good{else}is-bad{/if}">{$pct|number_format:"2"}%</span>
              {else}0.00%{/if}
            </td>
            <td class="center num">{$LASTBLOCKSBYTIME.7DaysAmount}</td>
            <td class="center num">{($LASTBLOCKSBYTIME.7DaysTotal|default:"0.00" / (604800 / $COINGENTIME) * 100)|number_format:"2"}%</td>
          </tr>
          {* Last 4 Weeks *}
          <tr>
            <th class="td-period">Last 4 Weeks</th>
            <td class="center num">{(2419200 / $COINGENTIME)|number_format:"0"}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.4WeeksTotal}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.4WeeksValid}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.4WeeksOrphan}</td>
            <td class="center num">{if $LASTBLOCKSBYTIME.4WeeksValid > 0}{($LASTBLOCKSBYTIME.4WeeksDifficulty / $LASTBLOCKSBYTIME.4WeeksValid)|number_format:"4"}{else}0{/if}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.4WeeksEstimatedShares}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.4WeeksShares}</td>
            <td class="center num">
              {if $LASTBLOCKSBYTIME.4WeeksEstimatedShares > 0}
                {assign var="pct" value=($LASTBLOCKSBYTIME.4WeeksShares / $LASTBLOCKSBYTIME.4WeeksEstimatedShares * 100)}
                <span class="pct {if $pct <= 100}is-good{else}is-bad{/if}">{$pct|number_format:"2"}%</span>
              {else}0.00%{/if}
            </td>
            <td class="center num">{$LASTBLOCKSBYTIME.4WeeksAmount}</td>
            <td class="center num">{($LASTBLOCKSBYTIME.4WeeksTotal|default:"0.00" / (2419200 / $COINGENTIME) * 100)|number_format:"2"}%</td>
          </tr>
          {* Last 12 Months *}
          <tr>
            <th class="td-period">Last 12 Mos</th>
            <td class="center num">{(29030400 / $COINGENTIME)|number_format:"0"}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.12MonthTotal}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.12MonthValid}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.12MonthOrphan}</td>
            <td class="center num">{if $LASTBLOCKSBYTIME.12MonthValid > 0}{($LASTBLOCKSBYTIME.12MonthDifficulty / $LASTBLOCKSBYTIME.12MonthValid)|number_format:"4"}{else}0{/if}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.12MonthEstimatedShares}</td>
            <td class="center num">{$LASTBLOCKSBYTIME.12MonthShares}</td>
            <td class="center num">
              {if $LASTBLOCKSBYTIME.12MonthEstimatedShares > 0}
                {assign var="pct" value=($LASTBLOCKSBYTIME.12MonthShares / $LASTBLOCKSBYTIME.12MonthEstimatedShares * 100)}
                <span class="pct {if $pct <= 100}is-good{else}is-bad{/if}">{$pct|number_format:"2"}%</span>
              {else}0.00%{/if}
            </td>
            <td class="center num">{$LASTBLOCKSBYTIME.12MonthAmount}</td>
            <td class="center num">{($LASTBLOCKSBYTIME.12MonthTotal|default:"0.00" / (29030400 / $COINGENTIME) * 100)|number_format:"2"}%</td>
          </tr>
        </tbody>
      </table>
    </div>
  </article>

  <!-- SECTION 3: Last N Blocks Found details -->
  <article class="bsx-card blocks-details-card" data-card-id="details">
    <header>
      <button type="button" class="bsx-collapse-toggle" aria-label="Collapse section">▾</button>
      <h3>Last {$BLOCKLIMIT} Blocks Found{if $SELECTED_COIN|default:"ALL" != "ALL"} ({$SELECTED_COIN|escape}){/if}</h3>
      <span class="card-meta">{$BLOCKSFOUND|@count|default:0} shown</span>
    </header>
    <div class="bsx-card-body blocks-table-wrap">
      <table class="bsx-table blocks-table">
        <thead>
          <tr>
{if $SELECTED_COIN|default:"ALL" == "ALL"}<th class="center th-chain">Chain</th>{/if}
            <th class="center">Block</th>
            <th class="center">Validity</th>
            <th>Finder</th>
            <th class="center">Time</th>
            <th class="right">Difficulty</th>
            <th class="right">Amount</th>
            <th class="right">Expected Shares</th>
{if $GLOBAL.config.payout_system == 'pplns'}<th class="right">PPLNS Shares</th>{/if}
            <th class="right">Actual Shares</th>
            <th class="right">Percentage</th>
          </tr>
        </thead>
        <tbody>
{assign var=count value=0}
{assign var=totalexpectedshares value=0}
{assign var=totalshares value=0}
{assign var=pplnsshares value=0}
{section name=block loop=$BLOCKSFOUND}
          {assign var="totalshares" value=$totalshares+$BLOCKSFOUND[block].shares}
          {assign var="count" value=$count+1}
          {if $GLOBAL.config.payout_system == 'pplns'}{assign var="pplnsshares" value=$pplnsshares+$BLOCKSFOUND[block].pplns_shares}{/if}
          {assign var="totalexpectedshares" value=$totalexpectedshares+$BLOCKSFOUND[block].estshares}
          {math assign="percentage" equation="shares / estshares * 100" shares=$BLOCKSFOUND[block].shares|default:"0" estshares=$BLOCKSFOUND[block].estshares|default:"1"}
          <tr>
{if $SELECTED_COIN|default:"ALL" == "ALL"}
            <td class="center"><span class="chain-pill chain-{$BLOCKSFOUND[block].chain|escape|lower}" data-tooltip="{$COIN_NAMES[$BLOCKSFOUND[block].chain]|default:$BLOCKSFOUND[block].chain|escape}">{$BLOCKSFOUND[block].chain|escape}</span></td>
{/if}
            <td class="center">
{if ! $GLOBAL.website.blockexplorer.disabled}
              <a href="{$smarty.server.SCRIPT_NAME}?page=statistics&action=round&coin={$BLOCKSFOUND[block].chain|escape}&height={$BLOCKSFOUND[block].height}">{$BLOCKSFOUND[block].height}</a>
{else}
              {$BLOCKSFOUND[block].height}
{/if}
            </td>
            <td class="center">
{assign var="required_confirmations" value=$BLOCKSFOUND[block].confirmations_required|default:$GLOBAL.confirmations}
{if $BLOCKSFOUND[block].confirmations >= $required_confirmations}
              <span class="status-pill ok">Confirmed</span>
{else if $BLOCKSFOUND[block].confirmations == -1}
              <span class="status-pill bad">Orphan</span>
{else}
              <span class="status-pill pending">{$required_confirmations - $BLOCKSFOUND[block].confirmations} left</span>
{/if}
            </td>
            <td class="td-name">{if $BLOCKSFOUND[block].is_anonymous|default:"0" == 1 && $GLOBAL.userdata.is_admin|default:"0" == 0}<span class="anon">anonymous</span>{else}{$BLOCKSFOUND[block].finder|default:"unknown"|escape}{/if}</td>
            <td class="center num">{$BLOCKSFOUND[block].time|date_format:"%d/%m %H:%M:%S"}</td>
            <td class="right num">{$BLOCKSFOUND[block].difficulty|number_format:"2"}</td>
            <td class="right num">{$BLOCKSFOUND[block].amount|number_format:"2"}</td>
            <td class="right num">{$BLOCKSFOUND[block].estshares|number_format}</td>
{if $GLOBAL.config.payout_system == 'pplns'}<td class="right num">{$BLOCKSFOUND[block].pplns_shares|number_format}</td>{/if}
            <td class="right num">{$BLOCKSFOUND[block].shares|number_format}</td>
            <td class="right num"><span class="pct {if $percentage <= 100}is-good{else}is-bad{/if}">{$percentage|number_format:"2"}</span></td>
          </tr>
{sectionelse}
          <tr><td colspan="{if $SELECTED_COIN|default:'ALL' == 'ALL'}11{else}10{/if}" class="blocks-empty">No blocks found yet.</td></tr>
{/section}
          <tr class="row-totals">
            <td colspan="{if $SELECTED_COIN|default:'ALL' == 'ALL'}7{else}6{/if}" class="right"><strong>Totals</strong></td>
            <td class="right num">{$totalexpectedshares|number_format}</td>
{if $GLOBAL.config.payout_system == 'pplns'}<td class="right num">{$pplnsshares|number_format}</td>{/if}
            <td class="right num">{$totalshares|number_format}</td>
            <td class="right num">
              {if $count > 0 && $totalexpectedshares > 0}
                {assign var="totpct" value=($totalshares / $totalexpectedshares * 100)}
                <span class="pct {if $totpct <= 100}is-good{else}is-bad{/if}">{$totpct|number_format:"2"}</span>
              {else}0{/if}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
{if $GLOBAL.config.payout_system != 'pps'}
    <footer class="blocks-card-footer">
{if $SELECTED_COIN|default:"ALL" == "ALL"}
      Round Earnings credited after each chain reaches its configured maturity.
{else}
      Round Earnings credited after <strong>{$SELECTED_CONFIRMATIONS|default:$GLOBAL.confirmations}</strong> confirmations.
{/if}
    </footer>
{/if}
  </article>

</div>

<script>
{literal}
(function () {
  // ─── Collapse state ──────────────────────────────────────────
  var STORAGE_KEY = 'bsx-blocks-collapsed-v1';
  var collapsed = {};
  try { collapsed = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}') || {}; } catch (e) {}
  var ORDER = ['graph', 'overview', 'details'];

  function applyCollapseState() {
    document.querySelectorAll('.stats-blocks-v2 .bsx-card').forEach(function (c) {
      var id = c.dataset.cardId;
      if (!id) return;
      if (collapsed[id]) c.classList.add('is-collapsed');
      else c.classList.remove('is-collapsed');
    });
  }

  // Right-aligned header controls (.blocks-coin-filter, .blocks-pager)
  // only ever exist in one place at a time — the first expanded card's
  // header. JS moves them from their current parent into that header
  // whenever the collapse state changes. Both ride the same
  // `margin-left: auto` rail so they sit together on the right.
  //
  // Order matters: array order = visual order in the header, because
  // appendChild puts each at the end. Coin filter is first so it sits
  // to the LEFT of the Older/Newer pager — matches the operator's
  // chosen layout: [COIN dropdown][Older][Newer].
  var HEADER_CONTROLS = ['.blocks-coin-filter', '.blocks-pager'];
  function relocateHeaderControls() {
    var firstId = ORDER.find(function (id) { return !collapsed[id]; });
    var controls = HEADER_CONTROLS
      .map(function (s) { return document.querySelector('.stats-blocks-v2 ' + s); })
      .filter(Boolean);
    if (!firstId) {
      controls.forEach(function (el) { el.style.display = 'none'; });
      return;
    }
    var card = document.querySelector('.stats-blocks-v2 .bsx-card[data-card-id="' + firstId + '"]');
    if (!card) return;
    var header = card.querySelector('header');
    if (!header) return;
    // Always appendChild — even if the element is already in this
    // header, this re-orders it to the end, enforcing the array order.
    controls.forEach(function (el) {
      el.style.display = '';
      header.appendChild(el);
    });
  }
  // Back-compat alias for any code that still calls relocatePager().
  var relocatePager = relocateHeaderControls;

  function wireCollapse() {
    document.querySelectorAll('.stats-blocks-v2 .bsx-card .bsx-collapse-toggle').forEach(function (btn) {
      if (btn.dataset.bsxWired) return;
      btn.dataset.bsxWired = '1';
      btn.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        var card = btn.closest('.bsx-card');
        if (!card) return;
        var id = card.dataset.cardId;
        if (collapsed[id]) delete collapsed[id];
        else               collapsed[id] = 1;
        try { localStorage.setItem(STORAGE_KEY, JSON.stringify(collapsed)); } catch (e2) {}
        applyCollapseState();
        relocatePager();
      });
    });
  }

  // ─── No-flash pager swap ─────────────────────────────────────
  function reinitVisualize() {
    if (!window.jQuery || !jQuery.fn.visualize) return;
    var width = jQuery(document).width() - 500;
    jQuery('.stats-blocks-v2 table.visualize').each(function () {
      if (jQuery(this).next('.visualize-frame, .visualize-line, .visualize-area, .visualize-bar, .visualize-pie').length) return;
      var rel = jQuery(this).attr('rel') || 'area';
      var opts = {
        type: rel,
        width: width,
        height: '240px',
        colors: ['#6fb9e8', '#ec8526', '#9dc453', '#ddd74c']
      };
      if (rel === 'line' || rel === 'pie') {
        opts.lineDots = 'double';
        opts.interaction = true;
        opts.multiHover = 5;
        opts.tooltip = true;
      }
      jQuery(this).hide().visualize(opts);
    });
  }

  function swap(href) {
    fetch(href, { credentials: 'same-origin' })
      .then(function (r) { return r.text(); })
      .then(function (html) {
        var doc = new DOMParser().parseFromString(html, 'text/html');
        var fresh = doc.querySelector('.stats-blocks-v2');
        var current = document.querySelector('.stats-blocks-v2');
        if (!fresh || !current) { location.href = href; return; }
        current.replaceWith(fresh);
        try { history.pushState({ blocks: 1 }, '', href); } catch (e) {}
        // Fresh DOM — re-bind everything.
        applyCollapseState();
        relocatePager();
        wireCollapse();
        wirePager();
        reinitVisualize();
      })
      .catch(function () { location.href = href; });
  }

  function wirePager() {
    document.querySelectorAll('.stats-blocks-v2 .blocks-pager a.bsx-btn').forEach(function (a) {
      if (a.dataset.bsxWired) return;
      a.dataset.bsxWired = '1';
      a.addEventListener('click', function (e) {
        e.preventDefault();
        swap(a.getAttribute('href'));
      });
    });
  }

  function init() {
    applyCollapseState();
    relocatePager();
    wireCollapse();
    wirePager();
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
{/literal}
</script>

<style>
  .stats-blocks-v2 {
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
  .stats-blocks-v2 .bsx-card {
    background: rgba(255,255,255,.03);
    border: 1px solid rgba(255,255,255,.06);
    border-radius: 6px;
    overflow: hidden;
  }
  .stats-blocks-v2 .bsx-card header {
    background: rgba(255,255,255,.05);
    padding: 6px 14px;
    border-bottom: 1px solid rgba(255,255,255,.06);
    display: flex;
    align-items: center;
    gap: 10px;
    flex-wrap: wrap;
  }
  /* Right-aligned chrome inside the card header. */
  .stats-blocks-v2 .bsx-card header > .blocks-pager,
  .stats-blocks-v2 .bsx-card header > .card-meta,
  .stats-blocks-v2 .bsx-card header > .blocks-coin-filter {
    margin-left: auto;
  }
  .stats-blocks-v2 .bsx-card header > .blocks-pager ~ .card-meta,
  .stats-blocks-v2 .bsx-card header > .blocks-pager ~ .blocks-coin-filter,
  .stats-blocks-v2 .bsx-card header > .card-meta   ~ .blocks-pager,
  .stats-blocks-v2 .bsx-card header > .card-meta   ~ .blocks-coin-filter,
  .stats-blocks-v2 .bsx-card header > .blocks-coin-filter ~ .blocks-pager,
  .stats-blocks-v2 .bsx-card header > .blocks-coin-filter ~ .card-meta {
    margin-left: 0;
  }

  /* Coin filter dropdown */
  .stats-blocks-v2 .blocks-coin-filter {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    margin: 0;
  }
  .stats-blocks-v2 .blocks-coin-filter-label {
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: #aab2bd;
    font-weight: 700;
  }
  .stats-blocks-v2 .blocks-coin-filter select {
    font: inherit;
    font-size: 11px;
    padding: 3px 22px 3px 10px;
    background: rgba(79, 195, 247, 0.10);
    border: 1px solid rgba(79, 195, 247, 0.40);
    border-radius: 4px;
    color: #4fc3f7;
    cursor: pointer;
    appearance: none;
    -webkit-appearance: none;
    background-image: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='10' height='6' viewBox='0 0 10 6'><path fill='%234fc3f7' d='M0 0l5 6 5-6z'/></svg>");
    background-repeat: no-repeat;
    background-position: right 6px center;
  }
  .stats-blocks-v2 .blocks-coin-filter select:hover {
    background-color: rgba(79, 195, 247, 0.18);
    border-color: rgba(79, 195, 247, 0.55);
  }
  .stats-blocks-v2 .blocks-coin-filter select option {
    background: #1f2937;
    color: #cdd;
  }
  [data-theme="light"] .stats-blocks-v2 .blocks-coin-filter-label { color: #4a5568; }
  [data-theme="light"] .stats-blocks-v2 .blocks-coin-filter select {
    background-color: rgba(25, 118, 210, 0.08);
    border-color: rgba(25, 118, 210, 0.40);
    color: #1565c0;
    background-image: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='10' height='6' viewBox='0 0 10 6'><path fill='%231565c0' d='M0 0l5 6 5-6z'/></svg>");
  }
  [data-theme="light"] .stats-blocks-v2 .blocks-coin-filter select option {
    background: #ffffff;
    color: #1f2933;
  }

  /* Chain pill in the multi-coin Last N Blocks list */
  .stats-blocks-v2 .chain-pill {
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
  .stats-blocks-v2 .chain-pill.chain-bbtc { color: #ea4335; border-color: rgba(234,67,53,.40);  background: rgba(234,67,53,.10);  }
  .stats-blocks-v2 .chain-pill.chain-blc  { color: #ff9800; border-color: rgba(255,152,0,.40);  background: rgba(255,152,0,.10);  }
  .stats-blocks-v2 .chain-pill.chain-elt  { color: #34a853; border-color: rgba(52,168,83,.40);  background: rgba(52,168,83,.10);  }
  .stats-blocks-v2 .chain-pill.chain-lit  { color: #fbbc04; border-color: rgba(251,188,4,.40);  background: rgba(251,188,4,.10);  }
  .stats-blocks-v2 .chain-pill.chain-pho  { color: #4285f4; border-color: rgba(66,133,244,.40); background: rgba(66,133,244,.10); }
  .stats-blocks-v2 .chain-pill.chain-umo  { color: #7b61ff; border-color: rgba(123,97,255,.40); background: rgba(123,97,255,.10); }
  /* Light-mode chip overrides — darker hex + bumped saturation so
     each coin's chip reads on a white surface. */
  [data-theme="light"] .stats-blocks-v2 .chain-pill.chain-bbtc { color: #c5221f; border-color: rgba(197,34,31,.55);  background: rgba(197,34,31,.18);  }
  [data-theme="light"] .stats-blocks-v2 .chain-pill.chain-blc  { color: #e65100; border-color: rgba(230,81,0,.55);   background: rgba(230,81,0,.18);   }
  [data-theme="light"] .stats-blocks-v2 .chain-pill.chain-elt  { color: #2e7d32; border-color: rgba(46,125,50,.55);  background: rgba(46,125,50,.18);  }
  [data-theme="light"] .stats-blocks-v2 .chain-pill.chain-lit  { color: #f57c00; border-color: rgba(245,124,0,.55);  background: rgba(245,124,0,.18);  }
  [data-theme="light"] .stats-blocks-v2 .chain-pill.chain-pho  { color: #1565c0; border-color: rgba(21,101,192,.55); background: rgba(21,101,192,.18); }
  [data-theme="light"] .stats-blocks-v2 .chain-pill.chain-umo  { color: #5e35b1; border-color: rgba(94,53,177,.55);  background: rgba(94,53,177,.18);  }
  .stats-blocks-v2 .bsx-card h3 {
    margin: 0;
    font-size: 13px;
    color: #cdd;
    letter-spacing: 0.04em;
    text-transform: uppercase;
  }
  .stats-blocks-v2 .card-meta {
    font-size: 11px;
    opacity: 0.65;
    color: #cdd;
    font-style: italic;
    font-variant-numeric: tabular-nums;
  }
  .stats-blocks-v2 .bsx-card-body { padding: 0; }
  .stats-blocks-v2 .blocks-card-footer {
    padding: 6px 14px;
    border-top: 1px solid rgba(255,255,255,.06);
    background: rgba(255,255,255,.02);
    font-size: 11px;
    color: #cdd;
    opacity: 0.85;
  }
  .stats-blocks-v2 .blocks-card-footer strong { color: #ffd66e; }

  /* Collapse toggle */
  .stats-blocks-v2 .bsx-collapse-toggle {
    background: transparent;
    border: 0;
    color: #cdd;
    font-size: 14px;
    line-height: 1;
    cursor: pointer;
    padding: 4px 6px;
    margin-right: 2px;
    border-radius: 3px;
    transition: transform 200ms ease, color 150ms ease, background 150ms ease;
  }
  .stats-blocks-v2 .bsx-collapse-toggle:hover {
    color: #4fc3f7;
    background: rgba(79, 195, 247, 0.10);
  }
  .stats-blocks-v2 .bsx-card.is-collapsed .bsx-collapse-toggle { transform: rotate(-90deg); }
  .stats-blocks-v2 .bsx-card.is-collapsed .bsx-card-body,
  .stats-blocks-v2 .bsx-card.is-collapsed .blocks-card-footer { display: none; }
  .stats-blocks-v2 .bsx-card header { user-select: none; }

  /* Pager buttons */
  .stats-blocks-v2 .blocks-pager { display: inline-flex; gap: 6px; }
  .stats-blocks-v2 .bsx-btn {
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
  .stats-blocks-v2 .bsx-btn:hover {
    background: rgba(79, 195, 247, 0.20);
    border-color: rgba(79, 195, 247, 0.55);
  }
  .stats-blocks-v2 .bsx-btn.is-disabled {
    opacity: 0.4;
    pointer-events: none;
    cursor: default;
  }

  /* Graph card body — leaves room for the visualize canvas. */
  .stats-blocks-v2 .blocks-graph-body { padding: 14px 18px; min-height: 220px; }

  /* Tables */
  .stats-blocks-v2 .blocks-table-wrap { overflow-x: auto; }
  .stats-blocks-v2 .blocks-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 12px;
    color: #cdd;
  }
  .stats-blocks-v2 .blocks-table thead th {
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
  .stats-blocks-v2 .blocks-table tbody td,
  .stats-blocks-v2 .blocks-table tbody th {
    border-bottom: 1px solid rgba(255,255,255,.05);
    padding: 6px 12px;
    vertical-align: middle;
  }
  .stats-blocks-v2 .blocks-table tbody tr:last-child td,
  .stats-blocks-v2 .blocks-table tbody tr:last-child th { border-bottom: 0; }
  .stats-blocks-v2 .blocks-table tbody tr:nth-child(even) td,
  .stats-blocks-v2 .blocks-table tbody tr:nth-child(even) th { background: rgba(255,255,255,0.015); }
  .stats-blocks-v2 .blocks-table tbody tr:hover td,
  .stats-blocks-v2 .blocks-table tbody tr:hover th { background: rgba(79, 195, 247, 0.06); }
  .stats-blocks-v2 .blocks-table .right  { text-align: right; }
  .stats-blocks-v2 .blocks-table .center { text-align: center; }
  .stats-blocks-v2 .blocks-table .num    { font-variant-numeric: tabular-nums; }
  .stats-blocks-v2 .blocks-table .td-period,
  .stats-blocks-v2 .blocks-table .th-period {
    text-align: left;
    padding-left: 18px;
    font-weight: 700;
    color: #cdd;
    text-transform: none;
    letter-spacing: 0;
    font-size: 12px;
    background: rgba(255,255,255,.02);
  }
  .stats-blocks-v2 .blocks-table tr.row-totals td,
  .stats-blocks-v2 .blocks-table tr.row-totals th {
    background: rgba(255,255,255,.04) !important;
    font-weight: 700;
    color: #e0f0fa;
  }
  .stats-blocks-v2 .blocks-table .anon { font-style: italic; opacity: 0.7; }
  .stats-blocks-v2 .blocks-table a { color: #4fc3f7; text-decoration: none; }
  .stats-blocks-v2 .blocks-table a:hover { text-decoration: underline; }
  .stats-blocks-v2 .blocks-empty {
    text-align: center;
    padding: 16px;
    color: #888;
    opacity: 0.7;
    font-style: italic;
  }

  /* Status pills */
  .stats-blocks-v2 .status-pill {
    display: inline-block;
    padding: 2px 8px;
    border-radius: 999px;
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    border: 1px solid transparent;
  }
  .stats-blocks-v2 .status-pill.ok {
    background: rgba(181, 231, 160, 0.18);
    border-color: rgba(181, 231, 160, 0.45);
    color: #b5e7a0;
  }
  .stats-blocks-v2 .status-pill.bad {
    background: rgba(229, 115, 115, 0.18);
    border-color: rgba(229, 115, 115, 0.45);
    color: #ffb3b3;
  }
  .stats-blocks-v2 .status-pill.pending {
    background: rgba(255, 214, 110, 0.16);
    border-color: rgba(255, 214, 110, 0.45);
    color: #ffd66e;
  }

  /* Percentage cells */
  .stats-blocks-v2 .pct.is-good { color: #b5e7a0; }
  .stats-blocks-v2 .pct.is-bad  { color: #ffb3b3; }

  /* Light mode */
  [data-theme="light"] .stats-blocks-v2 .bsx-card {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] .stats-blocks-v2 .bsx-card header {
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] .stats-blocks-v2 .bsx-card h3 { color: #1f2933; }
  [data-theme="light"] .stats-blocks-v2 .card-meta { color: #4a5568; }
  [data-theme="light"] .stats-blocks-v2 .blocks-table { color: #1f2933; }
  [data-theme="light"] .stats-blocks-v2 .blocks-table thead th {
    background: #eef0f2;
    border-bottom-color: rgba(0, 0, 0, 0.10);
    color: #4a5568;
  }
  [data-theme="light"] .stats-blocks-v2 .blocks-table tbody td,
  [data-theme="light"] .stats-blocks-v2 .blocks-table tbody th {
    border-bottom-color: rgba(0, 0, 0, 0.06);
  }
  [data-theme="light"] .stats-blocks-v2 .blocks-table tbody tr:nth-child(even) td,
  [data-theme="light"] .stats-blocks-v2 .blocks-table tbody tr:nth-child(even) th { background: rgba(0, 0, 0, 0.025); }
  [data-theme="light"] .stats-blocks-v2 .blocks-table tbody tr:hover td,
  [data-theme="light"] .stats-blocks-v2 .blocks-table tbody tr:hover th { background: rgba(25, 118, 210, 0.06); }
  [data-theme="light"] .stats-blocks-v2 .blocks-table .td-period,
  [data-theme="light"] .stats-blocks-v2 .blocks-table .th-period {
    color: #1f2933;
    background: rgba(0, 0, 0, 0.02);
  }
  [data-theme="light"] .stats-blocks-v2 .blocks-table tr.row-totals td,
  [data-theme="light"] .stats-blocks-v2 .blocks-table tr.row-totals th {
    background: rgba(0, 0, 0, 0.04) !important;
    color: #1f2933;
  }
  [data-theme="light"] .stats-blocks-v2 .blocks-table a { color: #1565c0; }
  [data-theme="light"] .stats-blocks-v2 .bsx-btn {
    color: #1f2933;
    background: rgba(25, 118, 210, 0.08);
    border-color: rgba(25, 118, 210, 0.40);
  }
  [data-theme="light"] .stats-blocks-v2 .blocks-card-footer {
    background: #f7f8fa;
    border-top-color: rgba(0, 0, 0, 0.08);
    color: #4a5568;
  }
  [data-theme="light"] .stats-blocks-v2 .blocks-card-footer strong { color: #ef6c00; }
  [data-theme="light"] .stats-blocks-v2 .status-pill.ok {
    background: rgba(46, 125, 50, 0.18);
    border-color: rgba(46, 125, 50, 0.45);
    color: #1b5e20;
  }
  [data-theme="light"] .stats-blocks-v2 .status-pill.bad {
    background: rgba(198, 40, 40, 0.12);
    border-color: rgba(198, 40, 40, 0.45);
    color: #c62828;
  }
  [data-theme="light"] .stats-blocks-v2 .status-pill.pending {
    background: rgba(239, 108, 0, 0.10);
    border-color: rgba(239, 108, 0, 0.45);
    color: #b53d00;
  }
  [data-theme="light"] .stats-blocks-v2 .pct.is-good { color: #1b5e20; }
  [data-theme="light"] .stats-blocks-v2 .pct.is-bad  { color: #c62828; }

  /* Custom tooltip — sits BELOW the source (pager + chain pills are
     near the top of the card, so above-positioning would clip them). */
  .stats-blocks-v2 [data-tooltip] { position: relative; outline: none; }
  .stats-blocks-v2 [data-tooltip]::after {
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
  .stats-blocks-v2 [data-tooltip]::before {
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
  .stats-blocks-v2 [data-tooltip]:hover::after,
  .stats-blocks-v2 [data-tooltip]:focus-visible::after { opacity: 1; transform: translateX(-50%) translateY(0); }
  .stats-blocks-v2 [data-tooltip]:hover::before,
  .stats-blocks-v2 [data-tooltip]:focus-visible::before { opacity: 1; transform: translateX(-50%) rotate(45deg) translateY(0); }

  /* First-column chain pills sit close to the card's left overflow boundary. */
  .stats-blocks-v2 .blocks-details-card tbody td:first-child [data-tooltip]::after {
    left: 0;
    transform: translateY(-2px);
  }
  .stats-blocks-v2 .blocks-details-card tbody td:first-child [data-tooltip]::before {
    left: 12px;
    transform: rotate(45deg) translateY(-2px);
  }
  .stats-blocks-v2 .blocks-details-card tbody td:first-child [data-tooltip]:hover::after,
  .stats-blocks-v2 .blocks-details-card tbody td:first-child [data-tooltip]:focus-visible::after {
    transform: translateY(0);
  }
  .stats-blocks-v2 .blocks-details-card tbody td:first-child [data-tooltip]:hover::before,
  .stats-blocks-v2 .blocks-details-card tbody td:first-child [data-tooltip]:focus-visible::before {
    transform: rotate(45deg) translateY(0);
  }
  [data-theme="light"] .stats-blocks-v2 [data-tooltip]::after,
  [data-theme="light"] .stats-blocks-v2 [data-tooltip]::before {
    background: #ffffff;
    border-color: rgba(21, 101, 192, 0.40);
    color: #1f2933;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
  }
</style>
