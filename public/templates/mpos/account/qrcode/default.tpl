{if !$smarty.session.AUTHENTICATED|default}
  <article class="module module width_full">
    <header><h3>QR Code</h3></header>
    <div class="module_content">
      <p>You must be logged in to view this page.</p>
    </div>
  </article>
{else}
  {if $QR_CSS}
    {foreach from=$QR_CSS item=cssPath}
      <link rel="stylesheet" href="{$cssPath}">
    {/foreach}
  {/if}
  <div id="bsx-v2-shell">
    <div id="app-qrcode"
         data-initial='{$QR_INITIAL_JSON nofilter}'></div>
  </div>
  {if $QR_JS}
    <script type="module" src="{$QR_JS}"></script>
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

  [data-theme="light"] #bsx-v2-shell .qr-canvas {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] #bsx-v2-shell .qr-help { color: #4a5568; }

  [data-theme="light"] #bsx-v2-shell .kv > label { color: #4a5568; }
  [data-theme="light"] #bsx-v2-shell .copy-value {
    background: #f8f9fa;
    border-color: rgba(0, 0, 0, 0.10);
    color: #1f2933;
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
  [data-theme="light"] #bsx-v2-shell .bsx-btn-ghost {
    background: transparent;
    border-color: rgba(0, 0, 0, 0.18);
    color: #2d3748;
  }
</style>
