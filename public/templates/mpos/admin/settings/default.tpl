<style>
  /* Settings page only — header padding so SETTINGS title indents
     like the other v2 admin pages, and a punchier tab strip with a
     readable colour. .ui-tabs-active is the class jQuery UI flips on
     the currently active <li>; .ui-state-active is the older fallback. */
  /* Match the other admin pages' left spacing — Monitoring/User/etc.
     have ~24 px of indent from the card edge to the title text. */
  .settings-page > header { padding: 8px 24px !important; }
  .settings-page > header > h3.tabs_involved { font-size: 14px; }
  /* Kill the framing box around the tab strip in EVERY form jQuery
     UI's theme exposes it: the .tabs class itself, plus the
     ui-widget-header / ui-tabs-nav / ui-corner-all classes that get
     added at init time, and any background-image gradient. */
  .settings-page ul.tabs,
  .settings-page ul.tabs.ui-widget-header,
  .settings-page ul.tabs.ui-tabs-nav,
  .settings-page ul.tabs.ui-corner-all {
    display: flex !important;
    gap: 4px !important;
    border: 0 !important;
    border-radius: 0 !important;
    outline: 0 !important;
    background: transparent !important;
    background-color: transparent !important;
    background-image: none !important;
    padding: 0 !important;
    margin: 0 !important;
    box-shadow: none !important;
  }
  .settings-page ul.tabs li,
  .settings-page ul.tabs li.ui-state-default,
  .settings-page ul.tabs li.ui-tabs-active,
  .settings-page ul.tabs li.ui-state-active {
    list-style: none;
    border: 0 !important;
    background: transparent !important;
    background-image: none !important;
    margin: 0 !important;
    padding: 0 !important;
    float: none !important;
  }
  /* !important is unfortunately required — MPOS's bundled jQuery UI
     theme styles `.ui-tabs-anchor` and the inherited link styles
     have higher specificity than these scoped selectors. We accept
     the !important to keep hover/active visible on this page. */
  article.settings-page > form > header > ul.tabs li a {
    display: inline-block !important;
    padding: 4px !important;
    color: #f0f5fa !important;
    font-size: 12px !important;
    font-weight: 700 !important;
    letter-spacing: 0.06em !important;
    text-decoration: none !important;
    border-radius: 4px !important;
    border: 1px solid transparent !important;
    background: transparent !important;
    transition: background 150ms ease, color 150ms ease, border-color 150ms ease;
  }
  /* Hover: the text takes on the per-tab accent (no pill / box). */
  article.settings-page > form > header > ul.tabs li a:hover {
    color: var(--tab-accent, #4fc3f7) !important;
    background: transparent !important;
    border-color: transparent !important;
  }
  /* Active tab: accent-coloured text, brighter weight, no background.
     Bottom-border accent line indicates the selected tab. */
  article.settings-page > form > header > ul.tabs li.ui-tabs-active a,
  article.settings-page > form > header > ul.tabs li.ui-state-active a,
  article.settings-page > form > header > ul.tabs li.active a {
    color: var(--tab-accent, #4fc3f7) !important;
    background: transparent !important;
    border-color: transparent !important;
    border-bottom-color: var(--tab-accent, #4fc3f7) !important;
    box-shadow: none !important;
  }
  /* Per-tab accent palette — each <li> picks a colour by position so
     each section has a distinct identity when hovered / active. Solid
     hex so the text reads at full opacity. */
  .settings-page > header > ul.tabs li:nth-child(9n+1) { --tab-accent: #4fc3f7; }
  .settings-page > header > ul.tabs li:nth-child(9n+2) { --tab-accent: #f0a050; }
  .settings-page > header > ul.tabs li:nth-child(9n+3) { --tab-accent: #b5e7a0; }
  .settings-page > header > ul.tabs li:nth-child(9n+4) { --tab-accent: #c896f0; }
  .settings-page > header > ul.tabs li:nth-child(9n+5) { --tab-accent: #e57373; }
  .settings-page > header > ul.tabs li:nth-child(9n+6) { --tab-accent: #ffd66e; }
  .settings-page > header > ul.tabs li:nth-child(9n+7) { --tab-accent: #f48fb1; }
  .settings-page > header > ul.tabs li:nth-child(9n+8) { --tab-accent: #80cbc4; }
  .settings-page > header > ul.tabs li:nth-child(9n+0) { --tab-accent: #90caf9; }
  /* Light mode — only the inactive-tab text needs overriding. Hover
     and active rules above already use var(--tab-accent) which reads
     on either background, so we let those cascade through.
     !important is required because the dark-mode rule ships !important
     and would otherwise win the cascade regardless of specificity,
     leaving inactive text near-white on white (invisible). */
  [data-theme="light"] article.settings-page > form > header > ul.tabs li a {
    color: #1f2933 !important;
  }

  /* Inline secondary toggles: render to the right of the parent row's
     tooltip, NOT on their own row. Pointer events stay on the
     toggle's <select> so clicking the surrounding row doesn't
     activate it. The text reads as part of the row description
     (small italic, same as the row's tooltip span) so the inline
     toggle blends in with the parent row's explanation. */
  .settings-page .settings-inline-toggle {
    margin-left: auto;
    display: inline-flex;
    align-items: center;
    gap: 4px;                    /* tight gap between select and label */
    pointer-events: none;        /* <- only children with pointer-events:auto are clickable */
  }
  /* Vertical-pipe separator on the LEFT of the inline toggle, so the
     row's parent tooltip and the inline toggle don't visually run
     together. */
  .settings-page .settings-inline-toggle::before {
    content: '|';
    color: #6c7686;
    margin-right: 10px;
    font-style: normal;
    pointer-events: none;
  }
  .settings-page .settings-inline-toggle .settings-inline-toggle-text {
    font-size: 10px;
    color: #aab2bd;
    font-style: italic;
    pointer-events: none;
    white-space: nowrap;
  }
  .settings-page .settings-inline-toggle select {
    pointer-events: auto;        /* <- the only clickable thing on the inline rail */
    font: inherit;
    font-size: 12px;
    padding: 3px 22px 3px 10px;
    background: rgba(79, 195, 247, 0.10);
    border: 1px solid rgba(79, 195, 247, 0.40);
    border-radius: 4px;
    color: #4fc3f7;
    cursor: pointer;
    appearance: none;
    -webkit-appearance: none;
    background-image: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='10' height='6' viewBox='0 0 10 6'><path fill='%234fc3f7' d='M0 0l5 6 5-6z'/></svg>");
    background-repeat: no-repeat;
    background-position: right 6px center;
  }
  [data-theme="light"] .settings-page .settings-inline-toggle .settings-inline-toggle-text { color: #4a5568; }
  [data-theme="light"] .settings-page .settings-inline-toggle select {
    background-color: rgba(25, 118, 210, 0.08);
    border-color: rgba(25, 118, 210, 0.40);
    color: #1565c0;
    background-image: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='10' height='6' viewBox='0 0 10 6'><path fill='%231565c0' d='M0 0l5 6 5-6z'/></svg>");
  }
</style>

<article class="module width_full settings-page">
  <form method="POST">
    <input type="hidden" name="page" value="{$smarty.request.page|escape}" />
    <input type="hidden" name="action" value="{$smarty.request.action|escape}" />
    <input type="hidden" name="do" value="save" />
    <input type="hidden" name="ctoken" value="{$CTOKEN|escape|default:""}" />
    <header style="display: flex; align-items: center; justify-content: center;">
      {* h3.tabs_involved kept (visually hidden) so MPOS's bundled
         jQuery UI script still binds and activates the tabs below.
         Removing the element entirely would break tab activation. *}
      <h3 class="tabs_involved" style="position:absolute; width:1px; height:1px; padding:0; margin:-1px; overflow:hidden; clip:rect(0 0 0 0); white-space:nowrap; border:0;">Settings</h3>
      <ul style="margin: 0; padding: 0;" class="tabs">
{foreach item=TAB from=array_keys($SETTINGS)}
        <li><a href="#{$TAB}">{$TAB|capitalize}</a></li>
{/foreach}
      </ul>
    </header>
    <div class="tab_container">
{foreach item=TAB from=array_keys($SETTINGS)}
      <div class="tab_content module_content" id="{$TAB}">
      <br />
{section name=setting loop=$SETTINGS.$TAB}
{* Settings flagged with `inline_with` are not rendered as their own
   row — they're injected into the right side of the row whose `name`
   matches their `inline_with` value (see the inner foreach below). *}
{if !$SETTINGS.$TAB[setting].inline_with|default:""}
        <fieldset>
          <label>{$SETTINGS.$TAB[setting].display}</label>
          {if $SETTINGS.$TAB[setting].tooltip|default}<span style="font-size: 10px;">{$SETTINGS.$TAB[setting].tooltip}</span>{/if}
          {* Render any inline-attached toggles to the right of this row's tooltip.
             The {display} text is rendered in the same italic-description style
             the parent row uses, so the toggle reads as part of the row's
             explanation rather than as a separate labelled control. *}
          {foreach from=$SETTINGS.$TAB item="_inline"}
            {if $_inline.inline_with|default:"" == $SETTINGS.$TAB[setting].name}
              <span class="settings-inline-toggle">
                {if $_inline.value|strlen}
                  {html_options name="data[`$_inline.name`]" options=$_inline.options selected=$_inline.value}
                {else}
                  {html_options name="data[`$_inline.name`]" options=$_inline.options selected=$_inline.default}
                {/if}
                <span class="settings-inline-toggle-text">{$_inline.display}</span>
              </span>
            {/if}
          {/foreach}
          {if $SETTINGS.$TAB[setting].type == 'select'}
            {if $SETTINGS.$TAB[setting].value|strlen}
              {html_options name="data[{$SETTINGS.$TAB[setting].name}]" options=$SETTINGS.$TAB[setting].options selected=$SETTINGS.$TAB[setting].value}
            {else}
              {html_options name="data[{$SETTINGS.$TAB[setting].name}]" options=$SETTINGS.$TAB[setting].options selected=$SETTINGS.$TAB[setting].default}
            {/if}
          {else if $SETTINGS.$TAB[setting].type == 'text'}
            <input type="text" size="{$SETTINGS.$TAB[setting].size}" name="data[{$SETTINGS.$TAB[setting].name}]" value="{$SETTINGS.$TAB[setting].value|default:$SETTINGS.$TAB[setting].default|escape:"html"}" />
          {else if $SETTINGS.$TAB[setting].type == 'password'}
            <input type="password" size="{$SETTINGS.$TAB[setting].size}" name="data[{$SETTINGS.$TAB[setting].name}]" value="{$SETTINGS.$TAB[setting].value|default:$SETTINGS.$TAB[setting].default|escape:"html"}" />
          {else if $SETTINGS.$TAB[setting].type == 'textarea'}
          	<textarea name="data[{$SETTINGS.$TAB[setting].name}]" cols="{$SETTINGS.$TAB[setting].size|default:"1"}" rows="{$SETTINGS.$TAB[setting].height|default:"1"}">{$SETTINGS.$TAB[setting].value|default:$SETTINGS.$TAB[setting].default}</textarea>
          {else}
            Unknown option type: {$SETTINGS.$TAB[setting].type}
          {/if}
        </fieldset>
{/if}
{/section}
      </div>
{/foreach}
    </div>
    <footer>
      <div class="submit_link">
        <input type="submit" value="Save" class="alt_btn">
      </div>
    </footer>
  </form>
</article>
