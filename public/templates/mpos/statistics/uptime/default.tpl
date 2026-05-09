<script type="text/javascript" src="{$GLOBALASSETS}/js/jquery.easypiechart.min.js"></script>

<div id="bsx-v2-shell" class="stats-uptime-v2">
  <article class="bsx-card uptime-card">
    <header>
      <h3>UptimeRobot Status</h3>
      <span class="card-meta">{$STATUS|@count|default:0} monitors</span>
    </header>
    <div class="bsx-card-body uptime-table-wrap">
      <table class="bsx-table uptime-table">
        <thead>
          <tr>
            <th class="center">Location</th>
            <th>Service</th>
            <th class="center">Status</th>
            <th class="center">Status Since</th>
            <th class="center">Day</th>
            <th class="center">Week</th>
            <th class="center">Month</th>
            <th class="center">All Time</th>
          </tr>
        </thead>
        <tbody>
{foreach key=key item=item from=$STATUS}
{assign var=node value="."|explode:$item.friendlyname}
          <tr>
            <td class="center td-loc">
              <img class="uptime-flag" src="{$GLOBALASSETS}/images/flags/{$node.0}.png" alt="{$node.0|escape}">
              <span class="uptime-loc-label">{$node.0|escape}</span>
            </td>
            <td class="td-name">{if $node|count > 1}{$node.1|escape}{else}—{/if}</td>
            <td class="center">
              {assign var=lower value=$CODES[$item.status]|lower}
              {if $lower == 'up'}
                <span class="status-pill ok">Up</span>
              {else if $lower == 'down'}
                <span class="status-pill bad">Down</span>
              {else if $lower == 'paused'}
                <span class="status-pill pending">Paused</span>
              {else}
                <span class="status-pill off">{$CODES[$item.status]}</span>
              {/if}
            </td>
            <td class="center num">{$item.log.1.datetime|date_format:"%b %d, %Y %H:%M"}</td>
            <td class="center"><span class="chart" data-percent="{$item.customuptimeratio.0}"><span class="percent"></span></span></td>
            <td class="center"><span class="chart" data-percent="{$item.customuptimeratio.1}"><span class="percent"></span></span></td>
            <td class="center"><span class="chart" data-percent="{$item.customuptimeratio.2}"><span class="percent"></span></span></td>
            <td class="center"><span class="chart" data-percent="{$item.alltimeuptimeratio}"><span class="percent"></span></span></td>
          </tr>
{foreachelse}
          <tr><td colspan="8" class="uptime-empty">No monitors configured.</td></tr>
{/foreach}
        </tbody>
      </table>
    </div>
    <footer class="uptime-footer">
      Last update {$UPDATED|date_format:"%b %d, %Y %H:%M"}
    </footer>
  </article>
</div>

<script>
{literal}
$(document).ready(function () {
  $('.stats-uptime-v2 .chart').each(function () {
    var $el = $(this);
    var pct = parseFloat($el.attr('data-percent')) || 0;
    // easyPieChart bar colour shifts with the percent: green for high
    // (>=99.5), amber for OK (>=95), red for trouble.
    var bar = pct >= 99.5 ? '#b5e7a0' : (pct >= 95 ? '#ffd66e' : '#ff6b6b');
    $el.easyPieChart({
      easing: 'easeOutBounce',
      size: 32,
      scaleColor: false,
      lineWidth: 4,
      lineCap: 'round',
      barColor: bar,
      trackColor: 'rgba(255,255,255,0.10)',
      animate: false,
      onStep: function (from, to, percent) {
        $el.find('.percent').text(Math.round(percent));
      }
    });
    // Make sure the inner percent label exists with the final value
    // even if onStep didn't fire (animate:false).
    $el.find('.percent').text(Math.round(pct));
  });
});
{/literal}
</script>

<style>
  .stats-uptime-v2 {
    margin: 0 16px 6px 16px;
    padding: 1em;
    color: var(--text-primary, #cdd);
    font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
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
  .stats-uptime-v2 .bsx-card {
    background: rgba(255,255,255,.03);
    border: 1px solid rgba(255,255,255,.06);
    border-radius: 6px;
    overflow: hidden;
  }
  .stats-uptime-v2 .bsx-card header {
    background: rgba(255,255,255,.05);
    padding: 6px 14px;
    border-bottom: 1px solid rgba(255,255,255,.06);
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .stats-uptime-v2 .bsx-card h3 {
    margin: 0;
    font-size: 13px;
    color: #cdd;
    letter-spacing: 0.04em;
    text-transform: uppercase;
  }
  .stats-uptime-v2 .card-meta {
    font-size: 11px;
    opacity: 0.65;
    color: #cdd;
    font-style: italic;
    font-variant-numeric: tabular-nums;
    margin-left: auto;
  }
  .stats-uptime-v2 .bsx-card-body { padding: 0; }
  .stats-uptime-v2 .uptime-footer {
    padding: 6px 14px;
    border-top: 1px solid rgba(255,255,255,.06);
    background: rgba(255,255,255,.02);
    font-size: 11px;
    color: #cdd;
    opacity: 0.85;
  }

  /* Table */
  .stats-uptime-v2 .uptime-table-wrap {
    overflow: auto;
    max-height: 725px;
    scrollbar-width: thin;
    scrollbar-color: rgba(255, 255, 255, 0.18) transparent;
  }
  /* Sticky single-row header */
  .stats-uptime-v2 .uptime-table thead th {
    position: sticky;
    top: 0;
    z-index: 3;
    background: #1f2329;
  }
  [data-theme="light"] .stats-uptime-v2 .uptime-table thead th { background: #eef0f2; }
  .stats-uptime-v2 .uptime-table-wrap::-webkit-scrollbar { width: 8px; height: 8px; }
  .stats-uptime-v2 .uptime-table-wrap::-webkit-scrollbar-track { background: transparent; }
  .stats-uptime-v2 .uptime-table-wrap::-webkit-scrollbar-thumb {
    background-color: rgba(255, 255, 255, 0.18);
    border-radius: 4px;
    border: 2px solid transparent;
    background-clip: padding-box;
  }
  .stats-uptime-v2 .uptime-table-wrap::-webkit-scrollbar-thumb:hover {
    background-color: rgba(79, 195, 247, 0.45);
  }
  .stats-uptime-v2 .uptime-table {
    width: 100%;
    border-collapse: separate;
    border-spacing: 0;
    font-size: 12px;
    color: #cdd;
    box-sizing: border-box;
  }
  .stats-uptime-v2 .uptime-table thead th {
    border-bottom: 1px solid rgba(255,255,255,.10);
    text-align: left;
    padding: 6px 10px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    font-size: 11px;
    color: #aab2bd;
  }
  .stats-uptime-v2 .uptime-table tbody td {
    border-bottom: 1px solid rgba(255,255,255,.05);
    padding: 6px 10px;
    vertical-align: middle;
  }
  .stats-uptime-v2 .uptime-table tbody tr:last-child td { border-bottom: 0; }
  .stats-uptime-v2 .uptime-table tbody tr:nth-child(even) td { background: rgba(255,255,255,0.015); }
  .stats-uptime-v2 .uptime-table tbody tr:hover td { background: rgba(79, 195, 247, 0.06); }
  .stats-uptime-v2 .uptime-table .right  { text-align: right; }
  .stats-uptime-v2 .uptime-table .center { text-align: center; }
  .stats-uptime-v2 .uptime-table .num    { font-variant-numeric: tabular-nums; }

  .stats-uptime-v2 .td-loc { white-space: nowrap; }
  .stats-uptime-v2 .uptime-flag {
    width: 22px;
    height: auto;
    vertical-align: middle;
    border-radius: 2px;
    box-shadow: 0 0 0 1px rgba(255,255,255,.10);
  }
  .stats-uptime-v2 .uptime-loc-label {
    margin-left: 8px;
    font-variant-numeric: tabular-nums;
    color: #cdd;
    text-transform: lowercase;
    letter-spacing: 0.02em;
  }
  .stats-uptime-v2 .uptime-empty {
    text-align: center;
    padding: 16px;
    color: #888;
    opacity: 0.7;
    font-style: italic;
  }

  /* Status pills */
  .stats-uptime-v2 .status-pill {
    display: inline-block;
    padding: 2px 8px;
    border-radius: 999px;
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    border: 1px solid transparent;
  }
  .stats-uptime-v2 .status-pill.ok      { background: rgba(181, 231, 160, 0.18); border-color: rgba(181, 231, 160, 0.45); color: #b5e7a0; }
  .stats-uptime-v2 .status-pill.bad     { background: rgba(229, 115, 115, 0.18); border-color: rgba(229, 115, 115, 0.45); color: #ffb3b3; }
  .stats-uptime-v2 .status-pill.pending { background: rgba(255, 214, 110, 0.16); border-color: rgba(255, 214, 110, 0.45); color: #ffd66e; }
  .stats-uptime-v2 .status-pill.off     { background: rgba(255,255,255,.06);    border-color: rgba(255,255,255,.16);     color: #99a; }

  /* easyPieChart percent label */
  .stats-uptime-v2 .chart {
    position: relative;
    display: inline-block;
    width: 32px;
    height: 32px;
    line-height: 32px;
    text-align: center;
  }
  .stats-uptime-v2 .chart .percent {
    position: absolute;
    inset: 0;
    line-height: 32px;
    font-size: 10px;
    font-weight: 700;
    color: #e0f0fa;
    font-variant-numeric: tabular-nums;
  }
  .stats-uptime-v2 .chart .percent::after { content: '%'; margin-left: 1px; opacity: 0.6; font-weight: 400; }

  /* Light mode */
  [data-theme="light"] .stats-uptime-v2 .bsx-card {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] .stats-uptime-v2 .bsx-card header {
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] .stats-uptime-v2 .bsx-card h3 { color: #1f2933; }
  [data-theme="light"] .stats-uptime-v2 .card-meta { color: #4a5568; }
  [data-theme="light"] .stats-uptime-v2 .uptime-table { color: #1f2933; }
  [data-theme="light"] .stats-uptime-v2 .uptime-table thead th {
    background: #eef0f2;
    border-bottom-color: rgba(0, 0, 0, 0.10);
    color: #4a5568;
  }
  [data-theme="light"] .stats-uptime-v2 .uptime-table tbody td { border-bottom-color: rgba(0, 0, 0, 0.06); }
  [data-theme="light"] .stats-uptime-v2 .uptime-table tbody tr:nth-child(even) td { background: rgba(0, 0, 0, 0.025); }
  [data-theme="light"] .stats-uptime-v2 .uptime-table tbody tr:hover td { background: rgba(25, 118, 210, 0.06); }
  [data-theme="light"] .stats-uptime-v2 .uptime-loc-label { color: #1f2933; }
  [data-theme="light"] .stats-uptime-v2 .uptime-flag { box-shadow: 0 0 0 1px rgba(0,0,0,.10); }
  [data-theme="light"] .stats-uptime-v2 .uptime-footer {
    background: #f7f8fa;
    border-top-color: rgba(0, 0, 0, 0.08);
    color: #4a5568;
  }
  [data-theme="light"] .stats-uptime-v2 .status-pill.ok      { background: rgba(46, 125, 50, 0.18); border-color: rgba(46, 125, 50, 0.45); color: #1b5e20; }
  [data-theme="light"] .stats-uptime-v2 .status-pill.bad     { background: rgba(198, 40, 40, 0.12); border-color: rgba(198, 40, 40, 0.45); color: #c62828; }
  [data-theme="light"] .stats-uptime-v2 .status-pill.pending { background: rgba(239, 108, 0, 0.10); border-color: rgba(239, 108, 0, 0.45); color: #b53d00; }
  [data-theme="light"] .stats-uptime-v2 .chart .percent { color: #1f2933; }
</style>
