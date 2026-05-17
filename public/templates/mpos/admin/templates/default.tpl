<div id="bsx-v2-shell" class="admin-templates-v2">

  <!-- LEFT — Select Page (file tree). Width is fixed via CSS grid below. -->
  <article class="bsx-card tpl-tree-card">
    <header>
      <h3>Select Page</h3>
      <span class="tpl-hint">Bold = Active override</span>
    </header>
    <div class="bsx-card-body">
      <div class="templates-tree" id="templates-tree">
        {include file="admin/templates/tree.tpl" files=$TEMPLATES prefix=""}
      </div>
    </div>
  </article>

  <!-- RIGHT — Edit form. Active toggle, Override content, Original (readonly). -->
  <article class="bsx-card tpl-edit-card">
    <header>
      <h3>Edit Template</h3>
      <code class="tpl-current">{$CURRENT_TEMPLATE|escape}</code>
    </header>
    <form method="POST" action="{$smarty.server.SCRIPT_NAME}">
      <input type="hidden" name="page"     value="{$smarty.request.page|escape}">
      <input type="hidden" name="action"   value="{$smarty.request.action|escape}">
      <input type="hidden" name="template" value="{$CURRENT_TEMPLATE|escape}">
      <input type="hidden" name="do"       value="save">
      <input type="hidden" name="ctoken"   value="{$CTOKEN|escape|default:""}">
      {* Hidden 0 keeps the form posting active=0 when the box is
         unchecked — HTML omits unchecked checkboxes from POST. *}
      <input type="hidden" name="active"   value="0">

      <div class="bsx-card-body tpl-edit-body">
        <div class="tpl-active-row">
          <label class="bsx-toggle-wrap" for="tpl-active">
            <input type="checkbox" id="tpl-active" name="active" value="1"
                   {nocache}{if $DATABASE_TEMPLATE.active}checked{/if}{/nocache}>
            <span class="bsx-toggle"><span class="bsx-toggle-knob"></span></span>
            <span class="bsx-toggle-label">Active — load DB override instead of file</span>
          </label>
        </div>

        <div class="tpl-pane">
          <div class="tpl-pane-head">
            <span class="tpl-pane-title">Override (loaded when Active)</span>
            <span class="tpl-pane-meta">{nocache}{if $DATABASE_TEMPLATE.modified_at}saved {$DATABASE_TEMPLATE.modified_at}{else}no override saved yet{/if}{/nocache}</span>
          </div>
          <textarea class="tpl-textarea" name="content" rows="18" spellcheck="false" required>{nocache}{$DATABASE_TEMPLATE.content nofilter}{/nocache}</textarea>
        </div>

        <div class="tpl-pane">
          <div class="tpl-pane-head">
            <span class="tpl-pane-title">Original (on-disk file, read-only reference)</span>
          </div>
          <textarea class="tpl-textarea" rows="18" readonly spellcheck="false">{nocache}{$ORIGINAL_TEMPLATE nofilter}{/nocache}</textarea>
        </div>

        <div class="form-actions">
          <button type="submit" class="bsx-btn bsx-btn-primary bsx-btn-small">Save</button>
        </div>
      </div>
    </form>
  </article>

</div>

<!-- Dynatree assets — kept exactly as the legacy page wired them so the
     tree behaviour (persist via cookie, click navigation, bold for
     active overrides) is unchanged. The CSS at the bottom of this file
     overrides the jQuery UI theme so the tree blends into v2 chrome. -->
<link rel="stylesheet" type="text/css" href="{$PATH}/js/dynatree/skin/ui.dynatree.css">
<script type="text/javascript" src="{$PATH}/js/jquery.cookie.js"></script>
<script type="text/javascript" src="{$PATH}/js/jquery-ui.custom.min.js"></script>
<script type="text/javascript" src="{$PATH}/js/dynatree/jquery.dynatree.min.js"></script>
<script>
  $(function () {
    $("#templates-tree").each(function () {
      $(this).find("li").each(function () {
        if ($(this).find("li.dynatree-activated").length) {
          $(this).attr("data", "addClass:'dynatree-has-activated'");
        }
      });
    }).dynatree({
      minExpandLevel: 2,
      clickFolderMode: 2,
      selectMode: 1,
      persist: true,
      onPostInit: function () { this.reactivate(); },
      // AJAX swap on click — fetch the editor data for the selected
      // file and update the right-hand pane in place. Keeps the tree
      // scroll position, the editor's cursor, etc. We still pushState
      // so the URL reflects the current selection (refresh / share / back).
      onActivate: function (node) {
        if (!node.tree.isUserEvent() || !node.data.href) return;
        var href = node.data.href;
        var ajaxUrl = href + (href.indexOf('?') === -1 ? '?' : '&') + '_ajax=1';
        fetch(ajaxUrl, { credentials: 'same-origin' })
          .then(function (r) { return r.json(); })
          .then(function (j) {
            // Swap the editor card content. Selectors are scoped to the
            // edit card (.tpl-edit-card) so they don't accidentally hit
            // anything inside the tree card.
            var card    = document.querySelector('.tpl-edit-card');
            var current = card.querySelector('.tpl-current');
            var hidden  = card.querySelector('input[name=template]');
            var active  = card.querySelector('#tpl-active');
            var meta    = card.querySelector('.tpl-pane-meta');
            var override   = card.querySelector('textarea[name=content]');
            var original   = card.querySelector('textarea[readonly]');
            if (current) current.textContent = j.currentTemplate || '';
            if (hidden)  hidden.value = j.currentTemplate || '';
            if (override) override.value = j.databaseTemplate ? (j.databaseTemplate.content || '') : '';
            if (original) original.value = j.originalContent || '';
            if (active) active.checked = !!(j.databaseTemplate && Number(j.databaseTemplate.active));
            if (meta) {
              meta.textContent = (j.databaseTemplate && j.databaseTemplate.modified_at)
                ? 'saved ' + j.databaseTemplate.modified_at
                : 'no override saved yet';
            }
            // Reflect the new selection in the URL without reloading.
            try { history.pushState({ template: j.currentTemplate }, '', href); } catch (e) {}
          })
          .catch(function () {
            // Fall back to legacy navigation if the AJAX swap fails.
            location.href = href;
          });
      }
    });
  });
</script>

<style>
  /* Page wrapper — 2-column grid (tree | editor). */
  .admin-templates-v2 {
    margin: 0 16px 6px 16px;
    padding: 1em;
    color: var(--text-primary, #cdd);
    font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
    display: grid;
    grid-template-columns: 320px minmax(0, 1fr);
    gap: 16px;
    align-items: stretch;
  }
  @media (max-width: 900px) {
    .admin-templates-v2 { grid-template-columns: 1fr; }
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
  .admin-templates-v2 .bsx-card {
    background: rgba(255,255,255,.03);
    border: 1px solid rgba(255,255,255,.06);
    border-radius: 6px;
    overflow: hidden;
    min-height: calc(100vh + 35px);
    display: flex;
    flex-direction: column;
  }
  .admin-templates-v2 .bsx-card header {
    background: rgba(255,255,255,.05);
    padding: 6px 14px;
    border-bottom: 1px solid rgba(255,255,255,.06);
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    flex-wrap: wrap;
  }
  .admin-templates-v2 .bsx-card h3 {
    margin: 0;
    font-size: 13px;
    color: #cdd;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    flex: 0 0 auto;
  }
  .admin-templates-v2 .bsx-card-body { padding: 12px 14px; }
  .admin-templates-v2 .tpl-hint,
  .admin-templates-v2 .tpl-current {
    font-size: 11px;
    opacity: 0.65;
    color: #cdd;
    font-style: italic;
  }
  .admin-templates-v2 .tpl-current {
    font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
    font-style: normal;
    font-size: 13px;
    letter-spacing: 0.04em;
    color: #4fc3f7;
    background: rgba(79, 195, 247, 0.08);
    padding: 2px 8px;
    border-radius: 4px;
    border: 1px solid rgba(79, 195, 247, 0.25);
  }
  /* Center the path chip in the editor header. */
  .admin-templates-v2 .tpl-edit-card > header {
    display: grid;
    grid-template-columns: 1fr auto 1fr;
  }
  .admin-templates-v2 .tpl-edit-card > header > .tpl-current {
    justify-self: center;
  }

  /* ─── Tree column ─── */
  .admin-templates-v2 .tpl-tree-card {
    min-height: 0;
    align-self: start;
  }
  .admin-templates-v2 .tpl-tree-card .bsx-card-body {
    max-height: 995px;
    overflow-y: auto;
    padding: 8px 6px;
    scrollbar-width: thin;
    scrollbar-color: rgba(255, 255, 255, 0.18) transparent;
  }
  .admin-templates-v2 .tpl-tree-card .bsx-card-body::-webkit-scrollbar {
    width: 8px;
  }
  .admin-templates-v2 .tpl-tree-card .bsx-card-body::-webkit-scrollbar-track {
    background: transparent;
  }
  .admin-templates-v2 .tpl-tree-card .bsx-card-body::-webkit-scrollbar-thumb {
    background-color: rgba(255, 255, 255, 0.18);
    border-radius: 4px;
    border: 2px solid transparent;
    background-clip: padding-box;
  }
  .admin-templates-v2 .tpl-tree-card .bsx-card-body::-webkit-scrollbar-thumb:hover {
    background-color: rgba(79, 195, 247, 0.45);
  }
  .admin-templates-v2 .templates-tree { font-size: 12px; }

  /* Dynatree theme overrides */
  .admin-templates-v2 .templates-tree .dynatree-container {
    border: none !important;
    background: transparent !important;
  }
  .admin-templates-v2 .templates-tree ul {
    background: transparent !important;
  }
  .admin-templates-v2 .templates-tree span.dynatree-node a {
    color: #cdd !important;
    background: transparent !important;
    border: 1px solid transparent;
    text-decoration: none;
    padding: 2px 6px;
    border-radius: 3px;
    transition: background 120ms ease, color 120ms ease;
  }
  .admin-templates-v2 .templates-tree span.dynatree-node a:hover {
    background: rgba(79, 195, 247, 0.10) !important;
    color: #e0f0fa !important;
    border-color: rgba(79, 195, 247, 0.25);
  }
  .admin-templates-v2 .templates-tree span.dynatree-folder a { font-weight: 400 !important; }
  .admin-templates-v2 .templates-tree span.dynatree-active a,
  .admin-templates-v2 .templates-tree span.dynatree-has-activated a,
  .admin-templates-v2 .templates-tree span.dynatree-activated a {
    font-weight: 700 !important;
    color: #b5e7a0 !important;
  }
  .admin-templates-v2 .templates-tree span.dynatree-active a {
    background: rgba(79, 195, 247, 0.14) !important;
    color: #4fc3f7 !important;
    border-color: rgba(79, 195, 247, 0.40);
  }

  /* ─── Edit column ─── */
  .admin-templates-v2 .tpl-edit-card > form {
    display: flex;
    flex-direction: column;
    flex: 1 1 auto;
    min-height: 0;
  }
  .admin-templates-v2 .tpl-edit-body {
    display: flex;
    flex-direction: column;
    gap: 14px;
    flex: 1 1 auto;
    min-height: 0;
  }
  .admin-templates-v2 .tpl-active-row {
    display: flex;
    align-items: center;
    padding: 8px 10px;
    background: rgba(255,255,255,.02);
    border: 1px solid rgba(255,255,255,.06);
    border-radius: 4px;
  }

  /* Toggle pill */
  .admin-templates-v2 .bsx-toggle-wrap {
    display: inline-flex;
    align-items: center;
    gap: 10px;
    cursor: pointer;
    user-select: none;
  }
  .admin-templates-v2 .bsx-toggle-wrap input { display: none; }
  .admin-templates-v2 .bsx-toggle {
    width: 34px;
    height: 18px;
    background: rgba(255,255,255,.10);
    border: 1px solid rgba(255,255,255,.18);
    border-radius: 999px;
    position: relative;
    transition: background 150ms ease, border-color 150ms ease;
  }
  .admin-templates-v2 .bsx-toggle-knob {
    position: absolute;
    top: 1px;
    left: 1px;
    width: 14px;
    height: 14px;
    background: #cdd;
    border-radius: 50%;
    transition: left 150ms ease, background 150ms ease;
  }
  .admin-templates-v2 .bsx-toggle-wrap input:checked + .bsx-toggle {
    background: rgba(79, 195, 247, 0.40);
    border-color: rgba(79, 195, 247, 0.65);
  }
  .admin-templates-v2 .bsx-toggle-wrap input:checked + .bsx-toggle .bsx-toggle-knob {
    left: 17px;
    background: #e0f0fa;
  }
  .admin-templates-v2 .bsx-toggle-label { font-size: 12px; color: #cdd; }

  .admin-templates-v2 .tpl-pane {
    border: 1px solid rgba(255,255,255,.06);
    border-radius: 4px;
    overflow: hidden;
    background: rgba(255,255,255,.02);
    display: flex;
    flex-direction: column;
    flex: 1 1 0;
    min-height: 0;
  }
  .admin-templates-v2 .tpl-pane-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 6px 10px;
    background: rgba(255,255,255,.04);
    border-bottom: 1px solid rgba(255,255,255,.06);
    font-size: 11px;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    color: #aab2bd;
  }
  .admin-templates-v2 .tpl-pane-title { font-weight: 700; }
  .admin-templates-v2 .tpl-pane-meta {
    text-transform: none;
    letter-spacing: 0;
    font-style: italic;
    opacity: 0.65;
  }
  .admin-templates-v2 .tpl-textarea {
    width: 100%;
    box-sizing: border-box;
    background: rgba(0,0,0,0.25);
    color: #d8e0e6;
    border: 0;
    padding: 10px 12px;
    font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
    font-size: 12px;
    line-height: 1.5;
    resize: none;
    flex: 1 1 auto;
    min-height: 200px;
    tab-size: 2;
    scrollbar-width: thin;
    scrollbar-color: rgba(255, 255, 255, 0.18) transparent;
  }
  .admin-templates-v2 .tpl-textarea::-webkit-scrollbar { width: 8px; }
  .admin-templates-v2 .tpl-textarea::-webkit-scrollbar-track { background: transparent; }
  .admin-templates-v2 .tpl-textarea::-webkit-scrollbar-thumb {
    background-color: rgba(255, 255, 255, 0.18);
    border-radius: 4px;
    border: 2px solid transparent;
    background-clip: padding-box;
  }
  .admin-templates-v2 .tpl-textarea::-webkit-scrollbar-thumb:hover {
    background-color: rgba(79, 195, 247, 0.45);
  }
  .admin-templates-v2 .tpl-textarea:focus {
    outline: 2px solid rgba(79, 195, 247, 0.45);
    outline-offset: -2px;
  }
  .admin-templates-v2 .tpl-textarea[readonly] { opacity: 0.85; }

  .admin-templates-v2 .form-actions {
    display: flex;
    justify-content: flex-end;
  }

  /* Buttons */
  .admin-templates-v2 .bsx-btn {
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
  .admin-templates-v2 .bsx-btn:hover {
    background: rgba(79, 195, 247, 0.20);
    border-color: rgba(79, 195, 247, 0.55);
  }
  .admin-templates-v2 .bsx-btn-primary {
    background: rgba(79, 195, 247, 0.16);
    border-color: rgba(79, 195, 247, 0.45);
    color: #e0f0fa;
  }
  .admin-templates-v2 .bsx-btn-small { padding: 4px 12px; font-size: 12px; }

  /* ─── Light mode ─── */
  [data-theme="light"] .admin-templates-v2 .bsx-card {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] .admin-templates-v2 .bsx-card header {
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] .admin-templates-v2 .bsx-card h3 { color: #1f2933; }
  [data-theme="light"] .admin-templates-v2 .tpl-hint { color: #4a5568; }
  [data-theme="light"] .admin-templates-v2 .tpl-current {
    background: rgba(25, 118, 210, 0.08);
    border-color: rgba(25, 118, 210, 0.30);
    color: #1565c0;
  }
  [data-theme="light"] .admin-templates-v2 .templates-tree span.dynatree-node a { color: #1f2933 !important; }
  [data-theme="light"] .admin-templates-v2 .templates-tree span.dynatree-node a:hover {
    background: rgba(25, 118, 210, 0.08) !important;
    border-color: rgba(25, 118, 210, 0.30);
  }
  [data-theme="light"] .admin-templates-v2 .templates-tree span.dynatree-active a {
    background: rgba(25, 118, 210, 0.14) !important;
    color: #1565c0 !important;
  }
  [data-theme="light"] .admin-templates-v2 .templates-tree span.dynatree-activated a,
  [data-theme="light"] .admin-templates-v2 .templates-tree span.dynatree-has-activated a {
    color: #1b5e20 !important;
  }
  [data-theme="light"] .admin-templates-v2 .tpl-active-row {
    background: #f7f8fa;
    border-color: rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] .admin-templates-v2 .bsx-toggle {
    background: rgba(0,0,0,.10);
    border-color: rgba(0,0,0,.18);
  }
  [data-theme="light"] .admin-templates-v2 .bsx-toggle-knob { background: #ffffff; }
  [data-theme="light"] .admin-templates-v2 .bsx-toggle-label { color: #2d3748; }
  [data-theme="light"] .admin-templates-v2 .bsx-toggle-wrap input:checked + .bsx-toggle {
    background: rgba(25, 118, 210, 0.40);
    border-color: rgba(25, 118, 210, 0.65);
  }
  [data-theme="light"] .admin-templates-v2 .tpl-pane {
    background: #f7f8fa;
    border-color: rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] .admin-templates-v2 .tpl-pane-head {
    background: #eef0f2;
    border-bottom-color: rgba(0, 0, 0, 0.08);
    color: #4a5568;
  }
  [data-theme="light"] .admin-templates-v2 .tpl-textarea {
    background: #ffffff;
    color: #1f2933;
  }
  [data-theme="light"] .admin-templates-v2 .bsx-btn {
    color: #1f2933;
    background: rgba(25, 118, 210, 0.08);
    border-color: rgba(25, 118, 210, 0.40);
  }
  [data-theme="light"] .admin-templates-v2 .bsx-btn-primary {
    background: rgba(25, 118, 210, 0.16);
    border-color: rgba(25, 118, 210, 0.50);
    color: #0d47a1;
  }
</style>
