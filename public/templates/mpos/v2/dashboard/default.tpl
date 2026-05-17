{if !$smarty.session.AUTHENTICATED|default}
  <article class="module module width_full">
    <header><h3>Dashboard v2</h3></header>
    <div class="module_content">
      <p>You must be logged in to view this page.</p>
    </div>
  </article>
{else}
  {if $V2_CSS}
    {foreach from=$V2_CSS item=cssPath}
      <link rel="stylesheet" href="{$cssPath}">
    {/foreach}
  {/if}
  {* SPA mounts here directly, no <article class="module"> wrapper.
     The wrapper would inject the legacy 38 px `.module header` banner
     and impose `.module_content { margin: 10px 20px }` styles that
     fight with the v2 layout. The SPA renders its own scoped cards. *}
  <div id="bsx-v2-shell">
    <div id="app-dashboard"
         data-api-key="{$V2_API_KEY}"
         data-user-id="{$V2_USER_ID}"
         data-refresh-ms="{$V2_REFRESH_MS}"
         data-long-refresh-ms="{$V2_LONG_REFRESH_MS}"
         data-payout-system="{$V2_PAYOUT_SYSTEM}"
         data-currency="{$V2_CURRENCY}"
         data-pplns-target="{$V2_PPLNS_TARGET}"
         data-balances='{$V2_BALANCES_JSON nofilter}'
         data-stats='{$V2_STATS_JSON nofilter}'
         data-messages='{$V2_MESSAGES_JSON nofilter}'
         data-session-key="{$V2_SESSION_KEY}"></div>
    <p class="bsx-v2-debug">debug: {$V2_DEBUG}</p>
  </div>
  {if $V2_JS}
    <script type="module" src="{$V2_JS}"></script>
  {else}
    <p style="color:#e57373; padding: 1em;">
      v2 build not deployed. From a checkout of this repo, run
      <code>cd frontend &amp;&amp; bun install &amp;&amp; bun run build</code>
      and rsync <code>public/v2/</code> to the host.
    </p>
  {/if}
{/if}

<style>
  /* Outer shell — sits where the legacy .module wrapper used to be.
     Provides the same outer padding so the v2 SPA isn't flush against
     the page edges (master.tpl gives no automatic gutter). */
  #bsx-v2-shell {
    margin: 16px 24px;
  }
  #bsx-v2-shell .bsx-v2-debug {
    opacity: 0.4;
    font-size: 0.75em;
    margin-top: 1em;
    color: var(--text-primary, #cdd);
  }
</style>
