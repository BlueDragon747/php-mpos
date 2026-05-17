<div id="bsx-v2-shell" class="admin-poolworkers-v2">
  <article class="bsx-card">
    <header class="pw-header">
      <h3>Active Pool Workers</h3>
      <div class="pw-search-wrap">
        <input type="search" id="pw-search" class="pw-search"
               placeholder="Search workers…" autocomplete="off" spellcheck="false"
               aria-label="Filter workers by name">
      </div>
      <span class="pw-count" id="pw-count">
        <span id="pw-count-shown">{$WORKERS|@count|default:0}</span>
        of {$WORKERS|@count|default:0} ·
        <span id="pw-count-active">{$GLOBAL.workers|default:0}</span> active
      </span>
    </header>
    <div class="bsx-card-body pw-body">
      <table class="bsx-table pw-table" id="pw-table">
        <thead>
          <tr>
            <th class="th-name sortable" data-sort="name">Worker Name<span class="sort-arrow"></span></th>
            <th class="th-pass">Password</th>
            <th class="th-active sortable" data-sort="active">Active<span class="sort-arrow"></span></th>
            {if $GLOBAL.config.disable_notifications != 1}<th class="th-monitor sortable" data-sort="monitor">Monitor<span class="sort-arrow"></span></th>{/if}
            <th class="right sortable" data-sort="hashrate">KH/s<span class="sort-arrow"></span></th>
            <th class="right sortable" data-sort="difficulty">Difficulty<span class="sort-arrow"></span></th>
            <th class="right sortable" data-sort="avg">Avg Difficulty<span class="sort-arrow"></span></th>
          </tr>
        </thead>
        <tbody>
        {nocache}
        {section name=worker loop=$WORKERS}
          <tr
            data-name="{$WORKERS[worker].username|escape}"
            data-active="{if $WORKERS[worker].hashrate > 0}1{else}0{/if}"
            data-monitor="{if $WORKERS[worker].monitor}1{else}0{/if}"
            data-hashrate="{$WORKERS[worker].hashrate|default:0}"
            data-difficulty="{if $WORKERS[worker].hashrate > 0}{$WORKERS[worker].difficulty|default:0}{else}0{/if}"
            data-avg="{if $WORKERS[worker].hashrate > 0}{$WORKERS[worker].avg_difficulty|default:0}{else}0{/if}">
            <td class="td-name">{$WORKERS[worker].username|escape}</td>
            <td class="td-pass">{$WORKERS[worker].password|escape}</td>
            <td class="center">
              {if $WORKERS[worker].hashrate > 0}
                <span class="status-dot ok" title="Active"></span>
              {else}
                <span class="status-dot off" title="Inactive"></span>
              {/if}
            </td>
            {if $GLOBAL.config.disable_notifications != 1}
            <td class="center">
              {if $WORKERS[worker].monitor}
                <span class="status-dot ok" title="Monitored"></span>
              {else}
                <span class="status-dot off" title="Not monitored"></span>
              {/if}
            </td>
            {/if}
            <td class="right num">{$WORKERS[worker].hashrate|number_format|default:"0"}</td>
            <td class="right num">{if $WORKERS[worker].hashrate > 0}{$WORKERS[worker].difficulty|number_format:"2"|default:"0"}{else}0{/if}</td>
            <td class="right num">{if $WORKERS[worker].hashrate > 0}{$WORKERS[worker].avg_difficulty|number_format:"2"|default:"0"}{else}0{/if}</td>
          </tr>
        {sectionelse}
          <tr>
            <td colspan="7" class="pw-empty">No active workers right now.</td>
          </tr>
        {/section}
        {/nocache}
        </tbody>
      </table>
    </div>
  </article>
</div>

<script>
(function () {
  var table  = document.getElementById('pw-table');
  if (!table) return;
  var tbody  = table.querySelector('tbody');
  var search = document.getElementById('pw-search');
  var shown  = document.getElementById('pw-count-shown');

  // Snapshot the original DOM order so the 3-state cycle can revert.
  var defaultRows = Array.prototype.slice.call(tbody.querySelectorAll('tr'));
  var sortKey = null;
  var sortDir = 0; // 0 = default, 1 = primary, 2 = reversed

  // What "primary direction" means per column. Numeric columns sort
  // high→low first (most useful for hashrate / difficulty). Worker
  // Name sorts A→Z. Active sorts active-first.
  function compare(a, b, key, dir) {
    var av, bv;
    if (key === 'name') {
      av = a.dataset.name.toLowerCase();
      bv = b.dataset.name.toLowerCase();
      return (av < bv ? -1 : av > bv ? 1 : 0) * (dir === 2 ? -1 : 1);
    }
    if (key === 'active' || key === 'monitor') {
      av = +a.dataset[key];
      bv = +b.dataset[key];
      if (av !== bv) return (bv - av) * (dir === 2 ? -1 : 1); // 1st click = "yes" first
      // tie-break by name A→Z regardless of direction
      var an = a.dataset.name.toLowerCase(), bn = b.dataset.name.toLowerCase();
      return an < bn ? -1 : an > bn ? 1 : 0;
    }
    // numeric columns
    av = +a.dataset[key];
    bv = +b.dataset[key];
    if (dir === 1) {
      // high→low; zero-hashrate rows sink to the bottom in numeric mode
      if (av === 0 && bv !== 0) return 1;
      if (bv === 0 && av !== 0) return -1;
      return bv - av;
    }
    return av - bv; // dir === 2: low→high
  }

  function render() {
    var term = (search.value || '').trim().toLowerCase();
    var rows = sortKey
      ? defaultRows.slice().sort(function (a, b) { return compare(a, b, sortKey, sortDir); })
      : defaultRows.slice();

    // Detach + reattach in the new order. Rows that don't match the
    // search term get hidden via display:none — keeps them in the
    // sortable set so clearing the search restores them instantly.
    tbody.innerHTML = '';
    var visible = 0;
    rows.forEach(function (r) {
      var matches = !term || r.dataset.name.toLowerCase().indexOf(term) !== -1;
      r.style.display = matches ? '' : 'none';
      if (matches) visible++;
      tbody.appendChild(r);
    });
    if (shown) shown.textContent = visible;
  }

  // Wire sortable headers — 3-state cycle: default → 1st → reversed → default.
  table.querySelectorAll('thead th.sortable').forEach(function (th) {
    th.addEventListener('click', function () {
      var key = th.dataset.sort;
      if (sortKey !== key) { sortKey = key; sortDir = 1; }
      else if (sortDir === 1) { sortDir = 2; }
      else { sortKey = null; sortDir = 0; }
      // Visual indicator on headers.
      table.querySelectorAll('thead th.sortable').forEach(function (h) {
        h.classList.remove('is-sorted-asc', 'is-sorted-desc');
      });
      if (sortDir === 1) th.classList.add('is-sorted-desc'); // 1st click: ▾
      if (sortDir === 2) th.classList.add('is-sorted-asc');  // 2nd click: ▴
      render();
    });
  });

  search.addEventListener('input', render);
})();
</script>

<style>
  .admin-poolworkers-v2 {
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
  section#main { background: none; min-height: 0; }

  /* Card chrome */
  .admin-poolworkers-v2 .bsx-card {
    background: rgba(255,255,255,.03);
    border: 1px solid rgba(255,255,255,.06);
    border-radius: 6px;
    overflow: hidden;
  }
  .admin-poolworkers-v2 .bsx-card header {
    background: rgba(255,255,255,.05);
    padding: 6px 14px;
    border-bottom: 1px solid rgba(255,255,255,.06);
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    flex-wrap: wrap;
  }
  .admin-poolworkers-v2 .bsx-card h3 {
    margin: 0;
    font-size: 13px;
    color: #cdd;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    flex: 1 1 auto;
    min-width: 0;
  }
  /* Header layout */
  .admin-poolworkers-v2 .pw-header {
    display: grid !important;
    grid-template-columns: 1fr minmax(220px, 360px) 1fr;
    align-items: center;
    gap: 12px;
  }
  .admin-poolworkers-v2 .pw-search-wrap {
    justify-self: center;
    width: 100%;
  }
  .admin-poolworkers-v2 .pw-search {
    width: 100%;
    box-sizing: border-box;
    background: rgba(0,0,0,0.25);
    border: 1px solid rgba(255,255,255,.10);
    border-radius: 4px;
    color: #e0f0fa;
    font: inherit;
    font-size: 12px;
    padding: 5px 10px;
    transition: border-color 150ms ease, background 150ms ease;
  }
  .admin-poolworkers-v2 .pw-search::placeholder { color: #8892a0; }
  .admin-poolworkers-v2 .pw-search:focus {
    outline: none;
    border-color: rgba(79, 195, 247, 0.55);
    background: rgba(0,0,0,0.35);
  }
  .admin-poolworkers-v2 .pw-count {
    font-size: 11px;
    opacity: 0.65;
    color: #cdd;
    font-variant-numeric: tabular-nums;
    letter-spacing: 0.02em;
    justify-self: end;
    white-space: nowrap;
  }

  /* Sortable headers */
  .admin-poolworkers-v2 .pw-table thead th.sortable {
    cursor: pointer;
    user-select: none;
    transition: color 120ms ease;
  }
  .admin-poolworkers-v2 .pw-table thead th.sortable:hover { color: #4fc3f7; }
  .admin-poolworkers-v2 .pw-table thead th .sort-arrow {
    display: inline-block;
    width: 10px;
    margin-left: 4px;
    color: #4fc3f7;
    font-size: 10px;
  }
  .admin-poolworkers-v2 .pw-table thead th.is-sorted-asc  .sort-arrow::before { content: "▴"; }
  .admin-poolworkers-v2 .pw-table thead th.is-sorted-desc .sort-arrow::before { content: "▾"; }
  .admin-poolworkers-v2 .pw-table thead th.is-sorted-asc,
  .admin-poolworkers-v2 .pw-table thead th.is-sorted-desc { color: #4fc3f7; }
  .admin-poolworkers-v2 .bsx-card-body { padding: 0; }

  /* Buttons */
  .admin-poolworkers-v2 .bsx-btn {
    font: inherit;
    font-size: 12px;
    font-weight: 600;
    letter-spacing: 0.04em;
    padding: 4px 10px;
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
  .admin-poolworkers-v2 .bsx-btn:hover { background: rgba(79, 195, 247, 0.20); border-color: rgba(79, 195, 247, 0.55); }
  .admin-poolworkers-v2 .bsx-btn-ghost {
    background: transparent;
    border-color: rgba(255,255,255,.18);
    color: #cdd;
  }
  .admin-poolworkers-v2 .bsx-btn.is-disabled {
    opacity: 0.4;
    pointer-events: none;
    cursor: default;
  }

  /* Table */
  .admin-poolworkers-v2 .pw-body {
    overflow: auto;
    max-height: 1000px;
    scrollbar-width: thin;
    scrollbar-color: rgba(255, 255, 255, 0.18) transparent;
  }
  .admin-poolworkers-v2 .pw-body::-webkit-scrollbar { width: 8px; height: 8px; }
  .admin-poolworkers-v2 .pw-body::-webkit-scrollbar-track { background: transparent; }
  .admin-poolworkers-v2 .pw-body::-webkit-scrollbar-thumb {
    background-color: rgba(255, 255, 255, 0.18);
    border-radius: 4px;
    border: 2px solid transparent;
    background-clip: padding-box;
  }
  .admin-poolworkers-v2 .pw-body::-webkit-scrollbar-thumb:hover {
    background-color: rgba(79, 195, 247, 0.45);
  }
  /* Sticky thead */
  .admin-poolworkers-v2 .pw-table thead th {
    position: sticky;
    top: 0;
    z-index: 1;
  }
  .admin-poolworkers-v2 .pw-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 12px;
    color: #cdd;
  }
  .admin-poolworkers-v2 .pw-table thead th {
    background: rgba(255,255,255,.04);
    border-bottom: 1px solid rgba(255,255,255,.10);
    text-align: left;
    padding: 8px 12px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    font-size: 11px;
    color: #aab2bd;
  }
  .admin-poolworkers-v2 .pw-table tbody td {
    border-bottom: 1px solid rgba(255,255,255,.05);
    padding: 6px 12px;
    vertical-align: middle;
  }
  .admin-poolworkers-v2 .pw-table tbody tr:last-child td { border-bottom: 0; }
  .admin-poolworkers-v2 .pw-table tbody tr:nth-child(even) td {
    background: rgba(255,255,255,0.015);
  }
  .admin-poolworkers-v2 .pw-table tbody tr:hover td { background: rgba(79, 195, 247, 0.06); }
  .admin-poolworkers-v2 .pw-table .right  { text-align: right; }
  .admin-poolworkers-v2 .pw-table .center { text-align: center; }
  .admin-poolworkers-v2 .pw-table .num    { font-variant-numeric: tabular-nums; }
  .admin-poolworkers-v2 .pw-table .td-pass { font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; opacity: 0.7; }
  .admin-poolworkers-v2 .pw-empty {
    text-align: center;
    padding: 16px;
    color: #888;
    opacity: 0.7;
    font-style: italic;
  }

  /* Status dots */
  .admin-poolworkers-v2 .status-dot {
    display: inline-block;
    width: 9px;
    height: 9px;
    border-radius: 50%;
    background: #555;
    border: 1px solid rgba(255,255,255,.10);
  }
  .admin-poolworkers-v2 .status-dot.ok {
    background: #b5e7a0;
    border-color: rgba(181, 231, 160, 0.55);
    box-shadow: 0 0 6px rgba(181, 231, 160, 0.45);
  }
  .admin-poolworkers-v2 .status-dot.off {
    background: rgba(255,255,255,.10);
    border-color: rgba(255,255,255,.20);
  }

  /* Light mode */
  [data-theme="light"] .admin-poolworkers-v2 .bsx-card {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] .admin-poolworkers-v2 .bsx-card header {
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] .admin-poolworkers-v2 .bsx-card h3 { color: #1f2933; }
  [data-theme="light"] .admin-poolworkers-v2 .pw-count { color: #2d3748; }
  [data-theme="light"] .admin-poolworkers-v2 .pw-search {
    background: #ffffff;
    border-color: rgba(0,0,0,0.18);
    color: #1f2933;
  }
  [data-theme="light"] .admin-poolworkers-v2 .pw-search::placeholder { color: #6c7686; }
  [data-theme="light"] .admin-poolworkers-v2 .pw-search:focus {
    border-color: rgba(25, 118, 210, 0.55);
    background: #ffffff;
  }
  [data-theme="light"] .admin-poolworkers-v2 .pw-table thead th.sortable:hover,
  [data-theme="light"] .admin-poolworkers-v2 .pw-table thead th.is-sorted-asc,
  [data-theme="light"] .admin-poolworkers-v2 .pw-table thead th.is-sorted-desc { color: #1565c0; }
  [data-theme="light"] .admin-poolworkers-v2 .pw-table thead th .sort-arrow { color: #1565c0; }
  [data-theme="light"] .admin-poolworkers-v2 .pw-table { color: #1f2933; }
  [data-theme="light"] .admin-poolworkers-v2 .pw-table thead th {
    background: #eef0f2;
    border-bottom-color: rgba(0, 0, 0, 0.10);
    color: #4a5568;
  }
  [data-theme="light"] .admin-poolworkers-v2 .pw-table tbody td {
    border-bottom-color: rgba(0, 0, 0, 0.06);
  }
  [data-theme="light"] .admin-poolworkers-v2 .pw-table tbody tr:nth-child(even) td {
    background: rgba(0, 0, 0, 0.025);
  }
  [data-theme="light"] .admin-poolworkers-v2 .pw-table tbody tr:hover td {
    background: rgba(25, 118, 210, 0.06);
  }
  [data-theme="light"] .admin-poolworkers-v2 .pw-table .td-pass { opacity: 0.6; }
  [data-theme="light"] .admin-poolworkers-v2 .bsx-btn {
    color: #1f2933;
    background: rgba(25, 118, 210, 0.08);
    border-color: rgba(25, 118, 210, 0.40);
  }
  [data-theme="light"] .admin-poolworkers-v2 .bsx-btn-ghost {
    background: transparent;
    border-color: rgba(0, 0, 0, 0.18);
    color: #2d3748;
  }
  [data-theme="light"] .admin-poolworkers-v2 .status-dot.ok {
    background: #2e7d32;
    border-color: rgba(46, 125, 50, 0.55);
    box-shadow: 0 0 6px rgba(46, 125, 50, 0.30);
  }
  [data-theme="light"] .admin-poolworkers-v2 .status-dot.off {
    background: rgba(0, 0, 0, 0.10);
    border-color: rgba(0, 0, 0, 0.20);
  }
</style>
