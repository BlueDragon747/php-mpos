{if !$smarty.session.AUTHENTICATED|default}
  <article class="module module width_full">
    <header><h3>Transactions</h3></header>
    <div class="module_content">
      <p>You must be logged in to view this page.</p>
    </div>
  </article>
{else}
  {if $TX_CSS}
    {foreach from=$TX_CSS item=cssPath}
      <link rel="stylesheet" href="{$cssPath}">
    {/foreach}
  {/if}
  <div id="bsx-v2-shell">
    <div id="app-transactions"
         data-initial='{$TX_INITIAL_JSON nofilter}'></div>
  </div>
  {if $TX_JS}
    <script type="module" src="{$TX_JS}"></script>
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

  /* Light-mode overrides — scoped so they only fire when MPOS's
     sidebar Light Mode toggle is active. */
  [data-theme="light"] #bsx-v2-shell .bsx-card {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] #bsx-v2-shell .bsx-card header {
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] #bsx-v2-shell .bsx-card h3 { color: #1f2933; }
  [data-theme="light"] #bsx-v2-shell .tx-summary-coin { color: #1976d2; }

  [data-theme="light"] #bsx-v2-shell .tx-filter-select {
    background-color: #ffffff;
    border-color: rgba(0, 0, 0, 0.18);
    color: #1f2933;
    /* swap the SVG arrow to a dark stroke so it's visible on white */
    background-image: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 12 12'><path d='M3 5l3 3 3-3' fill='none' stroke='%231f2933' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'/></svg>");
  }
  [data-theme="light"] #bsx-v2-shell .tx-filter-input {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.18);
    color: #1f2933;
  }
  [data-theme="light"] #bsx-v2-shell .tx-filter-input::placeholder { color: #6b7280; }

  [data-theme="light"] #bsx-v2-shell .tx-table thead th {
    color: #4a5568;
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] #bsx-v2-shell .tx-table th,
  [data-theme="light"] #bsx-v2-shell .tx-table td {
    border-bottom-color: rgba(0, 0, 0, 0.06);
    color: #2d3748;
  }
  [data-theme="light"] #bsx-v2-shell .tx-table tbody tr:nth-child(even) td {
    background: rgba(0,0,0,0.02);
  }
  [data-theme="light"] #bsx-v2-shell .td-addr a,
  [data-theme="light"] #bsx-v2-shell .td-txid a,
  [data-theme="light"] #bsx-v2-shell .td-block a { color: #1976d2; }

  [data-theme="light"] #bsx-v2-shell .tx-status-confirmed {
    background: rgba(46, 125, 50, 0.18);
    border-color: rgba(46, 125, 50, 0.45);
    color: #1b5e20;
  }
  [data-theme="light"] #bsx-v2-shell .tx-status-unconfirmed {
    background: rgba(239, 108, 0, 0.18);
    border-color: rgba(239, 108, 0, 0.45);
    color: #b53d00;
  }
  [data-theme="light"] #bsx-v2-shell .tx-status-orphan {
    background: rgba(198, 40, 40, 0.16);
    border-color: rgba(198, 40, 40, 0.45);
    color: #b71c1c;
  }
  [data-theme="light"] #bsx-v2-shell .tx-amount-credit { color: #2e7d32; }
  [data-theme="light"] #bsx-v2-shell .tx-amount-debit  { color: #c62828; }

  [data-theme="light"] #bsx-v2-shell .tx-footer {
    background: #f8f9fa;
    border-top-color: rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] #bsx-v2-shell .tx-legend { color: #2d3748; }
  [data-theme="light"] #bsx-v2-shell .tx-legend strong { color: #1976d2; }
  [data-theme="light"] #bsx-v2-shell .tx-pager-info { color: #2d3748; }

  [data-theme="light"] #bsx-v2-shell .bsx-btn {
    color: #1f2933;
    background: rgba(25, 118, 210, 0.08);
    border-color: rgba(25, 118, 210, 0.40);
  }
  [data-theme="light"] #bsx-v2-shell .bsx-btn:hover:not(.is-disabled) {
    background: rgba(25, 118, 210, 0.18);
    border-color: rgba(25, 118, 210, 0.55);
  }
  [data-theme="light"] #bsx-v2-shell .bsx-btn-primary {
    background: rgba(25, 118, 210, 0.16);
    border-color: rgba(25, 118, 210, 0.50);
    color: #0d47a1;
  }
</style>
