{if !$smarty.session.AUTHENTICATED|default}
  <article class="module module width_full">
    <header><h3>Invitations</h3></header>
    <div class="module_content">
      <p>You must be logged in to view this page.</p>
    </div>
  </article>
{else}
  {if $INV_CSS}
    {foreach from=$INV_CSS item=cssPath}
      <link rel="stylesheet" href="{$cssPath}">
    {/foreach}
  {/if}
  <div id="bsx-v2-shell">
    <div id="app-invitations"
         data-initial='{$INV_INITIAL_JSON nofilter}'></div>
  </div>
  {if $INV_JS}
    <script type="module" src="{$INV_JS}"></script>
  {else}
    <p style="color:#e57373; padding: 1em;">
      v2 build not deployed. From a checkout of this repo, run
      <code>cd frontend &amp;&amp; bun install &amp;&amp; bun run build</code>
      and rsync <code>public/v2/</code> to the host.
    </p>
  {/if}
{/if}

<style>
  #bsx-v2-shell {
    margin: 0 16px 6px 16px;
  }
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

  /* Light-mode overrides — same scope/pattern as the other v2 pages. */
  [data-theme="light"] #bsx-v2-shell .bsx-card {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] #bsx-v2-shell .bsx-card header {
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] #bsx-v2-shell .bsx-card h3 { color: #1f2933; }
  [data-theme="light"] #bsx-v2-shell .kv > label { color: #1f2933; }
  [data-theme="light"] #bsx-v2-shell .kv input[type=email],
  [data-theme="light"] #bsx-v2-shell .kv input[type=text],
  [data-theme="light"] #bsx-v2-shell .kv textarea {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.18);
    color: #1f2933;
  }
  [data-theme="light"] #bsx-v2-shell .invite-count { color: #2d3748; }
  [data-theme="light"] #bsx-v2-shell .invite-count strong { color: #1976d2; }

  [data-theme="light"] #bsx-v2-shell .invite-table thead th {
    color: #4a5568;
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] #bsx-v2-shell .invite-table th,
  [data-theme="light"] #bsx-v2-shell .invite-table td {
    border-bottom-color: rgba(0, 0, 0, 0.06);
    color: #2d3748;
  }
  [data-theme="light"] #bsx-v2-shell .invite-table tbody tr:nth-child(even) td {
    background: rgba(0,0,0,0.02);
  }
  [data-theme="light"] #bsx-v2-shell .active-dot.is-no { background: #ccc; }

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
</style>
