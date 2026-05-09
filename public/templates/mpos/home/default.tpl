<div id="bsx-v2-shell" class="home-news-v2">
{section name=news loop=$NEWS}
  <article class="bsx-card news-card">
    <header>
      <h3>{$NEWS[news].header|escape}</h3>
      <span class="news-meta">
        posted {$NEWS[news].time|date_format:"%b %e, %Y at %H:%M"}{if $HIDEAUTHOR|default:"0" == 0}
          by <strong>{$NEWS[news].author|escape}</strong>{/if}
      </span>
    </header>
    <div class="bsx-card-body news-content">{$NEWS[news].content nofilter}</div>
  </article>
{/section}
</div>

<style>
  .home-news-v2 {
    margin: 0 16px 6px 16px;
    padding: 1em;
    color: var(--text-primary, #cdd);
    font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
    display: flex;
    flex-direction: column;
    gap: 16px;
  }
  section#main > .spacer { height: 0; }
  section#main { background: none; min-height: 0; }

  .home-news-v2 .bsx-card {
    background: rgba(255,255,255,.03);
    border: 1px solid rgba(255,255,255,.06);
    border-radius: 6px;
    overflow: hidden;
  }
  .home-news-v2 .bsx-card header {
    background: rgba(255,255,255,.05);
    padding: 6px 14px;
    border-bottom: 1px solid rgba(255,255,255,.06);
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    flex-wrap: wrap;
  }
  .home-news-v2 .bsx-card h3 {
    margin: 0;
    font-size: 13px;
    color: #cdd;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    flex: 1 1 auto;
    min-width: 0;
  }
  .home-news-v2 .news-meta {
    font-size: 11px;
    opacity: 0.65;
    color: #cdd;
    font-variant-numeric: tabular-nums;
    flex: 0 0 auto;
  }
  .home-news-v2 .news-meta strong { color: #e0f0fa; font-weight: 600; }

  .home-news-v2 .bsx-card-body { padding: 14px 18px; }
  .home-news-v2 .news-content {
    font-size: 13px;
    line-height: 1.5;
    color: #cdd;
  }
  .home-news-v2 .news-content p { margin: 0 0 8px; }
  .home-news-v2 .news-content p:last-child { margin-bottom: 0; }
  .home-news-v2 .news-content a { color: #4fc3f7; }
  .home-news-v2 .news-content code,
  .home-news-v2 .news-content pre {
    background: rgba(0,0,0,0.25);
    padding: 1px 5px;
    border-radius: 2px;
    font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
    font-size: 12px;
  }
  .home-news-v2 .news-content pre { padding: 8px 10px; overflow-x: auto; }

  /* Light mode parity. */
  [data-theme="light"] .home-news-v2 .bsx-card {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] .home-news-v2 .bsx-card header {
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] .home-news-v2 .bsx-card h3 { color: #1f2933; }
  [data-theme="light"] .home-news-v2 .news-meta,
  [data-theme="light"] .home-news-v2 .news-content { color: #2d3748; }
  [data-theme="light"] .home-news-v2 .news-meta strong { color: #1f2933; }
  [data-theme="light"] .home-news-v2 .news-content a { color: #1976d2; }
</style>
