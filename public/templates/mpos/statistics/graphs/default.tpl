<div id="bsx-v2-shell" class="stats-graphs-v2">
  <article class="bsx-card graphs-card">
    <header>
      {* h3.tabs_involved is the marker custom.js uses to initialise the
         tab strip — keep the class but visually hide the text since
         the tabs themselves carry the labels. *}
      <h3 class="tabs_involved sr-only">Stats</h3>
      <ul class="tabs">
        <li><a href="#mine">Mine</a></li>
        <li><a href="#pool">Pool</a></li>
        <li><a href="#both">Both</a></li>
      </ul>
    </header>
    <div class="bsx-card-body tab_container">
{include file="{$smarty.request.page|escape}/{$smarty.request.action|escape}/mine.tpl"}
{include file="{$smarty.request.page|escape}/{$smarty.request.action|escape}/pool.tpl"}
{include file="{$smarty.request.page|escape}/{$smarty.request.action|escape}/both.tpl"}
    </div>
  </article>
</div>

<style>
  .stats-graphs-v2 {
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
  .stats-graphs-v2 .bsx-card {
    background: rgba(255,255,255,.03);
    border: 1px solid rgba(255,255,255,.06);
    border-radius: 6px;
    overflow: hidden;
  }
  .stats-graphs-v2 .bsx-card header {
    background: rgba(255,255,255,.05);
    padding: 6px 14px;
    border-bottom: 1px solid rgba(255,255,255,.06);
    display: flex;
    align-items: center;
    gap: 12px;
  }
  /* sr-only */
  .stats-graphs-v2 .sr-only {
    position: absolute;
    width: 1px; height: 1px;
    padding: 0; margin: -1px;
    overflow: hidden;
    clip: rect(0 0 0 0);
    white-space: nowrap;
    border: 0;
  }

  /* Tabs strip */
  .stats-graphs-v2 ul.tabs,
  .stats-graphs-v2 ul.tabs.ui-widget-header,
  .stats-graphs-v2 ul.tabs.ui-tabs-nav,
  .stats-graphs-v2 ul.tabs.ui-corner-all {
    display: flex !important;
    gap: 4px !important;
    margin: 0 !important;
    padding: 0 !important;
    list-style: none;
    border: 0 !important;
    border-radius: 0 !important;
    background: transparent !important;
    background-image: none !important;
    box-shadow: none !important;
  }
  .stats-graphs-v2 ul.tabs li,
  .stats-graphs-v2 ul.tabs li.ui-state-default,
  .stats-graphs-v2 ul.tabs li.ui-tabs-active,
  .stats-graphs-v2 ul.tabs li.ui-state-active {
    list-style: none;
    border: 0 !important;
    background: transparent !important;
    background-image: none !important;
    margin: 0 !important;
    padding: 0 !important;
    float: none !important;
  }
  .stats-graphs-v2 ul.tabs li a {
    display: inline-block !important;
    padding: 4px 10px !important;
    color: #cdd !important;
    font-size: 12px !important;
    font-weight: 700 !important;
    letter-spacing: 0.06em !important;
    text-transform: uppercase;
    text-decoration: none !important;
    border-radius: 3px !important;
    border: 1px solid transparent !important;
    background: transparent !important;
    transition: background 150ms ease, color 150ms ease, border-color 150ms ease;
  }
  .stats-graphs-v2 ul.tabs li a:hover {
    color: #4fc3f7 !important;
    background: rgba(79, 195, 247, 0.08) !important;
  }
  .stats-graphs-v2 ul.tabs li.ui-tabs-active a,
  .stats-graphs-v2 ul.tabs li.ui-state-active a,
  .stats-graphs-v2 ul.tabs li.active a {
    color: #4fc3f7 !important;
    background: transparent !important;
    border-bottom-color: #4fc3f7 !important;
    box-shadow: 0 1px 0 0 #4fc3f7 inset;
  }

  /* Tab content padding + fallback empty state */
  .stats-graphs-v2 .tab_container { padding: 14px 18px; min-height: 260px; }
  .stats-graphs-v2 .tab_content { padding: 0; }
  .stats-graphs-v2 .tab_content table.visualize { caption-side: top; }
  .stats-graphs-v2 .tab_content table.visualize caption {
    text-align: left;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: #aab2bd;
    padding: 0 0 8px;
    font-weight: 700;
  }

  /* Light mode */
  [data-theme="light"] .stats-graphs-v2 .bsx-card {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] .stats-graphs-v2 .bsx-card header {
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] .stats-graphs-v2 ul.tabs li a { color: #1f2933 !important; }
  [data-theme="light"] .stats-graphs-v2 ul.tabs li a:hover {
    color: #1565c0 !important;
    background: rgba(25, 118, 210, 0.08) !important;
  }
  [data-theme="light"] .stats-graphs-v2 ul.tabs li.ui-tabs-active a,
  [data-theme="light"] .stats-graphs-v2 ul.tabs li.ui-state-active a {
    color: #1565c0 !important;
    border-bottom-color: #1565c0 !important;
    box-shadow: 0 1px 0 0 #1565c0 inset;
  }
  [data-theme="light"] .stats-graphs-v2 .tab_content table.visualize caption { color: #4a5568; }
</style>
