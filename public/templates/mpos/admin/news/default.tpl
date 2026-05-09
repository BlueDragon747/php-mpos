{if $NEWS_CSS}
  {foreach from=$NEWS_CSS item=cssPath}
    <link rel="stylesheet" href="{$cssPath}">
  {/foreach}
{/if}
<div id="bsx-v2-shell">
  <div id="app-news"
       data-initial='{$NEWS_INITIAL_JSON nofilter}'></div>
</div>
{if $NEWS_JS}
  <script type="module" src="{$NEWS_JS}"></script>
{else}
  <p style="color:#e57373; padding: 1em;">
    v2 build not deployed. From a checkout of this repo, run
    <code>cd frontend &amp;&amp; bun install &amp;&amp; bun run build</code>
    and rsync <code>public/v2/</code> to the host.
  </p>
{/if}
<style>
  #bsx-v2-shell { margin: 0 16px 6px 16px; }
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
</style>
