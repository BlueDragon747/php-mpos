<article class="module module width_3_quarter">
  <header><h3>Overview / Pool Workers: <span id="b-dworkers">{$GLOBAL.workers}</span></h3></header>
  <div class="module_content">
    {* bsx-row: flexbox primitive with uniform 6px gap. Replaces the
       legacy `display:inline-block` columns whose gaps depended on
       HTML inline-whitespace and varied across browsers / DPI scales. *}
    <div class="bsx-row bsx-row-center">
      <div class="bsx-col">
        <div id="poolhashrate" style="width:240px; height:180px;"></div>
        <div id="sharerate" style="width:120px; height:90px; margin: 0 auto;"></div>
      </div>
      <div class="bsx-col">
        <div id="hashrate" style="width:440px; height:360px;"></div>
      </div>
      <div class="bsx-col">
        <div id="nethashrate" style="width:240px; height:180px;"></div>
        <div id="querytime" style="width:120px; height:90px; margin: 0 auto;"></div>
      </div>
    </div>
    <div id="shareinfograph" style="width:100%; height:210px;"></div>
    {if !$DISABLED_DASHBOARD and !$DISABLED_DASHBOARD_API}
      <div id="hashrategraph" style="height: 240px; width: 100%;"></div>
    {/if}
  </div>
  <footer>
    <p style="margin-left: 25px">Refresh interval: {$GLOBAL.config.statistics_ajax_refresh_interval|default:"10"} seconds. Hashrate based on shares submitted in the past {$INTERVAL|default:"5"} minutes.</p>
  </footer>
</article>
