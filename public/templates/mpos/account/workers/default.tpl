{if !$smarty.session.AUTHENTICATED|default}
  <article class="module module width_full">
    <header><h3>Workers</h3></header>
    <div class="module_content">
      <p>You must be logged in to view this page.</p>
    </div>
  </article>
{else}
  {if $W_CSS}
    {foreach from=$W_CSS item=cssPath}
      <link rel="stylesheet" href="{$cssPath}">
    {/foreach}
  {/if}
  {* SPA mounts here directly. Same approach as dashboard / edit
     account v2 wrappers — no <article class="module"> shell so the
     legacy `.module header` banner doesn't fight the v2 layout. *}
  <div id="bsx-v2-shell">
    <div id="app-workers"
         data-initial='{$W_INITIAL_JSON nofilter}'></div>
  </div>
  {if $W_JS}
    <script type="module" src="{$W_JS}"></script>
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
     16 px gutters match the dashboard's internal grid gap so the
     sidebar→main spacing reads consistent across pages. */
  #bsx-v2-shell {
    margin: 0 16px 6px 16px;
  }
  /* Layout.css has a 20 px `.spacer` between page content and the
     footer that's too tall for our pages. Collapse it. */
  section#main > .spacer { height: 0; }

  /* Visually blend the left sidebar with the secondary_bar above it
     (same background colour, no negative top margin / top padding). */
  aside#sidebar {
    background: var(--bg-secondary);
    margin-top: 0;
    padding-top: 0;
    min-height: 0;
  }
  /* Kill the legacy sidebar_shadow.png + min-height:85% on section#main
     so the empty space below the content collapses to content height. */
  section#main {
    background: none;
    min-height: 0;
  }

  /* Light-mode overrides — scoped to [data-theme="light"] #bsx-v2-shell
     so they ONLY trigger when MPOS's sidebar Light Mode toggle is on
     (theme.js sets data-theme="light" on <html>). */
  [data-theme="light"] #bsx-v2-shell .bsx-section {
    background: rgba(0, 0, 0, 0.02);
    border-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] #bsx-v2-shell .bsx-section-head h2 { color: #1976d2; }
  [data-theme="light"] #bsx-v2-shell .bsx-section-stats { color: #2d3748; }
  [data-theme="light"] #bsx-v2-shell .bsx-card {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] #bsx-v2-shell .bsx-card header {
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] #bsx-v2-shell .bsx-card h3 { color: #1f2933; }

  [data-theme="light"] #bsx-v2-shell .workers-table thead th {
    color: #4a5568;
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] #bsx-v2-shell .workers-table th,
  [data-theme="light"] #bsx-v2-shell .workers-table td {
    border-bottom-color: rgba(0, 0, 0, 0.06);
    color: #2d3748;
  }
  [data-theme="light"] #bsx-v2-shell .workers-table tbody tr.is-active .td-name input {
    color: #2e7d32;
  }
  [data-theme="light"] #bsx-v2-shell .parent-prefix { color: #4a5568; }
  [data-theme="light"] #bsx-v2-shell .td-hashrate,
  [data-theme="light"] #bsx-v2-shell .td-diff { color: #1f2933; }
  [data-theme="light"] #bsx-v2-shell .status-dot.is-down { background: #ccc; }

  [data-theme="light"] #bsx-v2-shell .kv > label { color: #1f2933; }

  [data-theme="light"] #bsx-v2-shell .bsx-head-popup {
    background: rgba(25, 118, 210, 0.10);
    border-color: rgba(25, 118, 210, 0.45);
    color: #0d47a1;
  }
  [data-theme="light"] #bsx-v2-shell .bsx-head-popup-success {
    background: rgba(46, 125, 50, 0.14);
    border-color: rgba(46, 125, 50, 0.45);
    color: #1b5e20;
  }
  [data-theme="light"] #bsx-v2-shell .bsx-head-popup-errormsg {
    background: rgba(239, 108, 0, 0.14);
    border-color: rgba(239, 108, 0, 0.45);
    color: #b53d00;
  }
  [data-theme="light"] #bsx-v2-shell .kv input[type=text],
  [data-theme="light"] #bsx-v2-shell .kv input[type=password],
  [data-theme="light"] #bsx-v2-shell .td-name input,
  [data-theme="light"] #bsx-v2-shell .td-pw input {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.18);
    color: #1f2933;
  }

  [data-theme="light"] #bsx-v2-shell .bsx-popup            { background: rgba(25, 118, 210, 0.08); border-left-color: #1976d2; border-right-color: #1976d2; }
  [data-theme="light"] #bsx-v2-shell .bsx-popup-success    { background: rgba(46, 125, 50, 0.10); border-left-color: #2e7d32; border-right-color: #2e7d32; }
  [data-theme="light"] #bsx-v2-shell .bsx-popup-errormsg   { background: rgba(239, 108, 0, 0.10); border-left-color: #ef6c00; border-right-color: #ef6c00; }

  [data-theme="light"] #bsx-v2-shell .bsx-btn {
    color: #1f2933;
    background: rgba(25, 118, 210, 0.08);
    border-color: rgba(25, 118, 210, 0.40);
  }
  [data-theme="light"] #bsx-v2-shell .bsx-btn:hover:not([disabled]) {
    background: rgba(25, 118, 210, 0.18);
    border-color: rgba(25, 118, 210, 0.55);
  }
  [data-theme="light"] #bsx-v2-shell .bsx-btn-primary {
    background: rgba(25, 118, 210, 0.16);
    border-color: rgba(25, 118, 210, 0.50);
    color: #0d47a1;
  }
  [data-theme="light"] #bsx-v2-shell .bsx-btn-secondary {
    background: rgba(239, 108, 0, 0.10);
    border-color: rgba(239, 108, 0, 0.45);
    color: #b53d00;
  }

  [data-theme="light"] #bsx-v2-shell .bsx-toggle {
    background: rgba(0, 0, 0, 0.10);
    border-color: rgba(0, 0, 0, 0.18);
  }
  [data-theme="light"] #bsx-v2-shell .bsx-toggle::after {
    background: #ffffff;
    box-shadow: 0 1px 2px rgba(0, 0, 0, 0.18);
  }
  [data-theme="light"] #bsx-v2-shell .bsx-toggle-wrap input[type=checkbox]:checked + .bsx-toggle {
    background: rgba(25, 118, 210, 0.55);
    border-color: rgba(25, 118, 210, 0.65);
  }

  [data-theme="light"] #bsx-v2-shell .btn-icon {
    background: rgba(0, 0, 0, 0.04);
    border-color: rgba(0, 0, 0, 0.14);
    color: #4a5568;
  }
  [data-theme="light"] #bsx-v2-shell .btn-icon:hover {
    background: rgba(239, 108, 0, 0.14);
    border-color: rgba(239, 108, 0, 0.4);
    color: #b53d00;
  }
</style>
