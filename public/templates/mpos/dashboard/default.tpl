{if !$smarty.session.AUTHENTICATED|default}
  <article class="module module width_full">
    <header><h3>Dashboard</h3></header>
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
     Left/right margin matches the dashboard's internal grid gap (16 px)
     so the sidebar→main gap looks the same as the gaps between cards.
     Bottom is 6 px — combined with the legacy `.spacer { height: 20px }`
     override below, the page footnote sits 6 px above the footer. */
  #bsx-v2-shell {
    margin: 0 16px 6px 16px;
  }
  /* Layout.css has a 20 px `.spacer` between page content and the
     footer that's too tall for the dashboard. Collapse it. */
  section#main > .spacer {
    height: 0;
  }

  #bsx-v2-shell .bsx-v2-debug {
    opacity: 0.4;
    font-size: 0.75em;
    margin-top: 1em;
    color: var(--text-primary, #cdd);
  }

  /* Light mode overrides — scoped to [data-theme="light"] #bsx-v2-shell so
     they ONLY trigger when the user clicks "Light Mode" in the sidebar
     (theme.js sets data-theme="light" on <html>). Dark mode is the
     default state from theme.js init, and never matches this selector. */
  [data-theme="light"] #bsx-v2-shell .bsx-card,
  [data-theme="light"] #bsx-v2-shell .bsx-stats-block {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] #bsx-v2-shell .bsx-card header,
  [data-theme="light"] #bsx-v2-shell .bsx-stats-block header {
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] #bsx-v2-shell .bsx-card h3,
  [data-theme="light"] #bsx-v2-shell .bsx-stats-block h3 {
    color: #1f2933;
  }
  [data-theme="light"] #bsx-v2-shell .bsx-stats-block td {
    color: #2d3748;
  }
  [data-theme="light"] #bsx-v2-shell .bsx-stats-block .section-head {
    color: #1976d2;
  }

  /* Workers table — th band + body text. */
  [data-theme="light"] #bsx-v2-shell .bsx-workers-table th {
    background: #f1f3f5;
    color: #1f2933;
  }
  [data-theme="light"] #bsx-v2-shell .bsx-workers-table th,
  [data-theme="light"] #bsx-v2-shell .bsx-workers-table td {
    border-bottom-color: rgba(0, 0, 0, 0.08);
    color: #2d3748;
  }

  /* Balance card. */
  [data-theme="light"] #bsx-v2-shell .bsx-balance-card th {
    background: #f1f3f5;
    color: #1f2933;
    border-bottom-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] #bsx-v2-shell .bsx-balance-card td.label {
    color: #2d3748;
  }
  [data-theme="light"] #bsx-v2-shell .bsx-balance-card td.confirmed   { color: #2e7d32; }
  [data-theme="light"] #bsx-v2-shell .bsx-balance-card td.unconfirmed { color: #ef6c00; }

  /* Messages chip on the Overview card header. The dark-mode tints sit
     on a near-black card; on white we need stronger fills + dark text. */
  [data-theme="light"] #bsx-v2-shell .bsx-msg-chip {
    color: #1f2933;
    background: rgba(25, 118, 210, 0.08);
    border-color: rgba(25, 118, 210, 0.40);
  }
  [data-theme="light"] #bsx-v2-shell .bsx-msg-chip:hover {
    background: rgba(25, 118, 210, 0.16);
    border-color: rgba(25, 118, 210, 0.55);
  }
  [data-theme="light"] #bsx-v2-shell .bsx-msg-chip.is-active {
    background: rgba(25, 118, 210, 0.22);
    border-color: rgba(25, 118, 210, 0.6);
  }
  [data-theme="light"] #bsx-v2-shell .bsx-msg-chip-dot {
    background: #1976d2;
    box-shadow: 0 0 0 2px rgba(25, 118, 210, 0.18);
  }
  [data-theme="light"] #bsx-v2-shell .bsx-msg-chip-dot.is-active {
    background: #2e7d32;
  }

  /* Individual message cards — translucent .06 vanishes on white, so we
     bump alpha and switch to dark text on the title chips. */
  [data-theme="light"] #bsx-v2-shell .bsx-msg {
    background: rgba(25, 118, 210, 0.06);
    border-left-color: #1976d2;
    border-right-color: #1976d2;
  }
  [data-theme="light"] #bsx-v2-shell .bsx-msg-success {
    background: rgba(46, 125, 50, 0.06);
    border-left-color: #2e7d32;
    border-right-color: #2e7d32;
  }
  [data-theme="light"] #bsx-v2-shell .bsx-msg-warning {
    background: rgba(239, 108, 0, 0.06);
    border-left-color: #ef6c00;
    border-right-color: #ef6c00;
  }
  [data-theme="light"] #bsx-v2-shell .bsx-msg h4 {
    background: rgba(25, 118, 210, 0.16);
    border-color: rgba(25, 118, 210, 0.45);
    color: #0d47a1;
  }
  [data-theme="light"] #bsx-v2-shell .bsx-msg-success h4 {
    background: rgba(46, 125, 50, 0.16);
    border-color: rgba(46, 125, 50, 0.45);
    color: #1b5e20;
  }
  [data-theme="light"] #bsx-v2-shell .bsx-msg-warning h4 {
    background: rgba(239, 108, 0, 0.16);
    border-color: rgba(239, 108, 0, 0.45);
    color: #b53d00;
  }
  [data-theme="light"] #bsx-v2-shell .bsx-msg p {
    color: #2d3748;
  }
  [data-theme="light"] #bsx-v2-shell .bsx-msg-date {
    background: rgba(0, 0, 0, 0.06);
    color: #4a5568;
  }

  /* Flip-back scrollbar (the messages-side scroll track) — on white the
     dark-mode rgba(255,255,255,.18) thumb is invisible. */
  [data-theme="light"] #bsx-v2-shell .flip-back-inner {
    scrollbar-color: rgba(0, 0, 0, 0.25) transparent;
  }
  [data-theme="light"] #bsx-v2-shell .flip-back-inner::-webkit-scrollbar-thumb {
    background-color: rgba(0, 0, 0, 0.25);
  }
  [data-theme="light"] #bsx-v2-shell .flip-back-inner::-webkit-scrollbar-thumb:hover {
    background-color: rgba(25, 118, 210, 0.45);
  }
  /* Workers-area scrollbar inside the sidebar (DashboardPage.vue’s
     account-workers wrapper uses the same dark-mode default). */
  [data-theme="light"] #bsx-v2-shell .account-workers {
    scrollbar-color: rgba(0, 0, 0, 0.25) transparent;
  }
  [data-theme="light"] #bsx-v2-shell .account-workers::-webkit-scrollbar-thumb {
    background-color: rgba(0, 0, 0, 0.25);
  }
  [data-theme="light"] #bsx-v2-shell .account-workers::-webkit-scrollbar-thumb:hover {
    background-color: rgba(25, 118, 210, 0.45);
  }

  /* Visually blend the left sidebar with the secondary_bar above it
     (the "Welcome admin" / breadcrumb strip): same background colour,
     no negative top margin, no top padding. The two sit as one
     continuous vertical column instead of two slightly off-shaded ones. */
  aside#sidebar {
    background: var(--bg-secondary);
    margin-top: 0;
    padding-top: 0;
  }

  /* Kill the legacy sidebar_shadow.png that lives as the
     `section#main` background — it adds a fat dark gradient on the
     left edge of main content, which combined with the shell margin
     makes the gap between sidebar and dashboard look much wider than
     the 16 px we set. Also override `min-height: 85%` so the empty
     dark area below the content collapses to the content height. */
  section#main {
    background: none;
    min-height: 0;
  }
  /* The legacy `aside#sidebar { min-height: 85% }` similarly forces
     the sidebar to extend to 85 % of the viewport even when the
     dashboard ends sooner. Match section#main's collapse. */
  aside#sidebar {
    min-height: 0;
  }
</style>
