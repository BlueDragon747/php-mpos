<script src="{$PATH}/js/cleditor/jquery.cleditor.min.js"></script>
<link rel="stylesheet" href="{$PATH}/js/cleditor/jquery.cleditor.css">
<script type="text/javascript">
  $(document).ready(function () { $(".cleditor").cleditor(); });
</script>

<div id="bsx-v2-shell" class="admin-news-v2">

  <!-- Add News Post — Header input + Markdown textarea + Add button. -->
  <article class="bsx-card">
    <header>
      <h3>Add News Post</h3>
      <span class="news-hint">Markdown supported</span>
    </header>
    <form method="POST" action="{$smarty.server.SCRIPT_NAME}">
      <input type="hidden" name="page" value="{$smarty.request.page|escape}">
      <input type="hidden" name="action" value="{$smarty.request.action|escape}">
      <input type="hidden" name="do" value="add">
      <input type="hidden" name="ctoken" value="{$CTOKEN|escape|default:""}">
      <div class="bsx-card-body">
        <div class="kv">
          <label for="news-header">Header</label>
          <input id="news-header" type="text" name="data[header]" placeholder="Pool maintenance Saturday" required>
        </div>
        <div class="kv kv-textarea">
          <label for="news-content">Content</label>
          <textarea id="news-content" class="cleditor" name="data[content]" rows="6"
                    placeholder="Compose with the toolbar — bold, italic, links, lists, etc." required></textarea>
        </div>
        <div class="form-actions">
          <button type="submit" class="bsx-btn bsx-btn-primary bsx-btn-small">Add Post</button>
        </div>
      </div>
    </form>
  </article>

  <!-- Existing news entries — one card per row with toggle-active /
       edit / delete actions in the header. Active state shown as a
       small pill so admins can scan the list at a glance. -->
{nocache}
{if $NEWS|default}
{section name=news loop=$NEWS}
  <article class="bsx-card news-card {if $NEWS[news].active != 1}is-inactive{/if}">
    <header>
      <h3>
        {$NEWS[news].header|escape}
        {if $NEWS[news].active == 1}
          <span class="status-pill ok">Active</span>
        {else}
          <span class="status-pill off">Inactive</span>
        {/if}
      </h3>
      <div class="bsx-card-actions">
        <span class="news-meta">
          posted {$NEWS[news].time|escape} by <strong>{$NEWS[news].author|escape}</strong>
        </span>
        <form method="POST" action="{$smarty.server.SCRIPT_NAME}" style="display:inline">
          <input type="hidden" name="page" value="{$smarty.request.page|escape}">
          <input type="hidden" name="action" value="news">
          <input type="hidden" name="do" value="toggle_active">
          <input type="hidden" name="id" value="{$NEWS[news].id}">
          <input type="hidden" name="ctoken" value="{$CTOKEN|escape|default:""}">
          <button class="bsx-btn bsx-btn-small {if $NEWS[news].active == 1}bsx-btn-secondary{else}bsx-btn-primary{/if}"
                  type="submit"
                  title="{if $NEWS[news].active == 1}Deactivate (hide from dashboard){else}Activate (show on dashboard){/if}">
            {if $NEWS[news].active == 1}Deactivate{else}Activate{/if}
          </button>
        </form>
        <a class="bsx-btn bsx-btn-small bsx-btn-ghost"
           href="{$smarty.server.SCRIPT_NAME}?page={$smarty.request.page|escape}&action=news_edit&id={$NEWS[news].id}"
           title="Edit news entry">Edit</a>
        <form method="POST" action="{$smarty.server.SCRIPT_NAME}" style="display:inline">
          <input type="hidden" name="page" value="{$smarty.request.page|escape}">
          <input type="hidden" name="action" value="news">
          <input type="hidden" name="do" value="delete">
          <input type="hidden" name="id" value="{$NEWS[news].id}">
          <input type="hidden" name="ctoken" value="{$CTOKEN|escape|default:""}">
          <button class="bsx-btn bsx-btn-small bsx-btn-ghost"
                  type="submit"
                  title="Delete news entry"
                  onclick="return confirm('Delete news entry #{$NEWS[news].id}?');">Delete</button>
        </form>
      </div>
    </header>
    <div class="bsx-card-body news-content">{$NEWS[news].content nofilter}</div>
  </article>
{/section}
{else}
  <p class="news-empty">No news posts yet — add one above.</p>
{/if}
{/nocache}

</div>

<style>
  /* Page wrapper — same gutters / sidebar treatment as other admin v2 pages. */
  .admin-news-v2 {
    margin: 0 16px 6px 16px;
    padding: 1em;
    color: var(--text-primary, #cdd);
    font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
    display: flex;
    flex-direction: column;
    gap: 16px;
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

  /* Card chrome — identical to the rest of v2. */
  .admin-news-v2 .bsx-card {
    background: rgba(255,255,255,.03);
    border: 1px solid rgba(255,255,255,.06);
    border-radius: 6px;
    overflow: hidden;
  }
  .admin-news-v2 .bsx-card.is-inactive {
    opacity: 0.7;
    border-style: dashed;
  }
  .admin-news-v2 .bsx-card header {
    background: rgba(255,255,255,.05);
    padding: 6px 14px;
    border-bottom: 1px solid rgba(255,255,255,.06);
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    flex-wrap: wrap;
  }
  .admin-news-v2 .bsx-card h3 {
    margin: 0;
    font-size: 13px;
    color: #cdd;
    letter-spacing: 0.04em;
    display: flex;
    align-items: center;
    gap: 10px;
    flex: 1 1 auto;
    min-width: 0;
  }
  .admin-news-v2 .bsx-card-actions {
    display: flex;
    align-items: center;
    gap: 6px;
    flex: 0 0 auto;
    flex-wrap: wrap;
  }
  .admin-news-v2 .bsx-card-body { padding: 14px 18px; }
  .admin-news-v2 .news-hint {
    font-size: 11px;
    opacity: 0.65;
    color: #cdd;
    font-style: italic;
  }
  .admin-news-v2 .news-meta {
    font-size: 11px;
    opacity: 0.65;
    color: #cdd;
    font-variant-numeric: tabular-nums;
  }
  .admin-news-v2 .news-meta strong { color: #e0f0fa; font-weight: 600; }

  /* Active / Inactive status pill (in the news entry h3). */
  .admin-news-v2 .status-pill {
    display: inline-block;
    padding: 2px 8px;
    border-radius: 999px;
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    border: 1px solid transparent;
  }
  .admin-news-v2 .status-pill.ok {
    background: rgba(181, 231, 160, 0.18);
    border-color: rgba(181, 231, 160, 0.45);
    color: #b5e7a0;
  }
  .admin-news-v2 .status-pill.off {
    background: rgba(255, 255, 255, 0.06);
    border-color: rgba(255, 255, 255, 0.16);
    color: #99a;
  }

  /* Form rows for the Add card. */
  .admin-news-v2 .kv {
    display: grid;
    grid-template-columns: 110px minmax(0, 1fr);
    align-items: center;
    gap: 6px 12px;
    margin-bottom: 12px;
  }
  .admin-news-v2 .kv-textarea { align-items: start; }
  .admin-news-v2 .kv > label {
    font-size: 12px;
    color: #cdd;
    font-weight: 600;
    letter-spacing: 0.02em;
  }
  .admin-news-v2 .kv input[type=text],
  .admin-news-v2 .kv textarea {
    font: inherit;
    font-size: 13px;
    padding: 6px 8px;
    background: rgba(255,255,255,.04);
    border: 1px solid rgba(255,255,255,.10);
    border-radius: 4px;
    color: #f0f0f0;
    box-sizing: border-box;
    width: 100%;
  }
  .admin-news-v2 .kv textarea {
    font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
    font-size: 12px;
    min-height: 100px;
    resize: vertical;
  }
  .admin-news-v2 .form-actions {
    display: flex;
    justify-content: flex-end;
  }

  /* News content (rendered HTML from Markdown). */
  .admin-news-v2 .news-content {
    font-size: 13px;
    line-height: 1.5;
    color: #cdd;
  }
  .admin-news-v2 .news-content p { margin: 0 0 8px; }
  .admin-news-v2 .news-content p:last-child { margin-bottom: 0; }
  .admin-news-v2 .news-content a { color: #4fc3f7; }
  .admin-news-v2 .news-content code,
  .admin-news-v2 .news-content pre {
    background: rgba(0,0,0,0.25);
    padding: 1px 5px;
    border-radius: 2px;
    font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
    font-size: 12px;
  }
  .admin-news-v2 .news-content pre { padding: 8px 10px; overflow-x: auto; }

  .admin-news-v2 .news-empty {
    margin: 0;
    text-align: center;
    opacity: 0.55;
    padding: 16px;
  }

  /* Buttons (mirror the rest of v2). */
  .admin-news-v2 .bsx-btn {
    font: inherit;
    font-size: 13px;
    font-weight: 600;
    letter-spacing: 0.04em;
    padding: 6px 16px;
    border-radius: 4px;
    cursor: pointer;
    border: 1px solid transparent;
    background: rgba(79, 195, 247, 0.10);
    border-color: rgba(79, 195, 247, 0.28);
    color: #cdd;
    text-decoration: none;
    display: inline-flex;
    align-items: center;
    transition: background 150ms ease, border-color 150ms ease;
  }
  .admin-news-v2 .bsx-btn:hover { background: rgba(79, 195, 247, 0.20); border-color: rgba(79, 195, 247, 0.55); }
  .admin-news-v2 .bsx-btn-primary {
    background: rgba(79, 195, 247, 0.16);
    border-color: rgba(79, 195, 247, 0.45);
    color: #e0f0fa;
  }
  .admin-news-v2 .bsx-btn-secondary {
    background: rgba(245, 203, 167, 0.10);
    border-color: rgba(245, 203, 167, 0.40);
    color: #f9e3d2;
  }
  .admin-news-v2 .bsx-btn-ghost {
    background: transparent;
    border-color: rgba(255,255,255,.18);
    color: #cdd;
  }
  .admin-news-v2 .bsx-btn-small { padding: 4px 10px; font-size: 12px; }

  /* Light mode. */
  [data-theme="light"] .admin-news-v2 .bsx-card {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] .admin-news-v2 .bsx-card header {
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] .admin-news-v2 .bsx-card h3 { color: #1f2933; }
  [data-theme="light"] .admin-news-v2 .news-hint,
  [data-theme="light"] .admin-news-v2 .news-meta,
  [data-theme="light"] .admin-news-v2 .news-content,
  [data-theme="light"] .admin-news-v2 .kv > label { color: #2d3748; }
  [data-theme="light"] .admin-news-v2 .news-meta strong { color: #1f2933; }
  [data-theme="light"] .admin-news-v2 .news-content a { color: #1976d2; }
  [data-theme="light"] .admin-news-v2 .kv input[type=text],
  [data-theme="light"] .admin-news-v2 .kv textarea {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.18);
    color: #1f2933;
  }
  [data-theme="light"] .admin-news-v2 .status-pill.ok {
    background: rgba(46, 125, 50, 0.18);
    border-color: rgba(46, 125, 50, 0.45);
    color: #1b5e20;
  }
  [data-theme="light"] .admin-news-v2 .status-pill.off {
    background: rgba(0, 0, 0, 0.04);
    border-color: rgba(0, 0, 0, 0.18);
    color: #4a5568;
  }
  [data-theme="light"] .admin-news-v2 .bsx-btn {
    color: #1f2933;
    background: rgba(25, 118, 210, 0.08);
    border-color: rgba(25, 118, 210, 0.40);
  }
  [data-theme="light"] .admin-news-v2 .bsx-btn:hover {
    background: rgba(25, 118, 210, 0.18);
    border-color: rgba(25, 118, 210, 0.55);
  }
  [data-theme="light"] .admin-news-v2 .bsx-btn-primary {
    background: rgba(25, 118, 210, 0.16);
    border-color: rgba(25, 118, 210, 0.50);
    color: #0d47a1;
  }
  [data-theme="light"] .admin-news-v2 .bsx-btn-secondary {
    background: rgba(239, 108, 0, 0.10);
    border-color: rgba(239, 108, 0, 0.45);
    color: #b53d00;
  }
  [data-theme="light"] .admin-news-v2 .bsx-btn-ghost {
    background: transparent;
    border-color: rgba(0, 0, 0, 0.18);
    color: #2d3748;
  }
</style>
