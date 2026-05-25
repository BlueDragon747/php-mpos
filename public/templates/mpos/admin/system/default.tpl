<div class="bsx-system-page">
<style>
  .bsx-system-page { padding: 1em; }
  .bsx-system-page .bsx-card {
    background: rgba(255,255,255,.03);
    border: 1px solid rgba(255,255,255,.08);
    border-radius: 6px;
    margin-bottom: 14px;
    overflow: hidden;
  }
  .bsx-system-page .bsx-card > header {
    background: rgba(255,255,255,.05);
    padding: 6px 14px;
    border-bottom: 1px solid rgba(255,255,255,.08);
    display: flex; align-items: center; justify-content: space-between; gap: 12px;
  }
  .bsx-system-page .bsx-card > header h3 {
    margin: 0; font-size: 13px; letter-spacing: 0.04em; color: #cdd; font-weight: 700;
  }
  .bsx-system-page .bsx-card-body { padding: 8px 14px 12px; }
  .bsx-system-page table { width: 100%; border-collapse: collapse; font-size: 12px; }
  .bsx-system-page th, .bsx-system-page td {
    text-align: left; padding: 4px 8px; border-bottom: 1px solid rgba(255,255,255,.05); color: #cdd;
  }
  .bsx-system-page th { color: #aab; font-weight: 600; font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em; }
  .bsx-system-page tr:last-child td { border-bottom: 0; }
  .bsx-system-page th.num,
  .bsx-system-page td.num { text-align: right; font-variant-numeric: tabular-nums; }
  .bsx-system-page .pill {
    display: inline-block; padding: 1px 6px; border-radius: 999px;
    font-size: 10px; line-height: 13px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase;
    border: 1px solid transparent;
  }
  .bsx-system-page .pill-active   { color: #b5e7a0; border-color: rgba(181,231,160,.45); background: rgba(181,231,160,.10); }
  .bsx-system-page .pill-inactive { color: #e57373; border-color: rgba(229,115,115,.45); background: rgba(229,115,115,.10); }
  .bsx-system-page .pill-warn     { color: #ffd66e; border-color: rgba(255,214,110,.45); background: rgba(255,214,110,.10); }
  .bsx-system-page .pill-signal   { color: #4fc3f7; border-color: rgba(79,195,247,.45); background: rgba(79,195,247,.10); }
  .bsx-system-page .pill-disabled { color: #99a;    border-color: rgba(255,255,255,.20); background: rgba(255,255,255,.04); }
  /* Light-mode pill colours */
  [data-theme="light"] .bsx-system-page .pill-active   { color: #1b5e20; border-color: rgba(46,125,50,.55);  background: rgba(46,125,50,.18); }
  [data-theme="light"] .bsx-system-page .pill-inactive { color: #b71c1c; border-color: rgba(198,40,40,.55); background: rgba(198,40,40,.16); }
  [data-theme="light"] .bsx-system-page .pill-warn     { color: #b53d00; border-color: rgba(245,124,0,.55); background: rgba(245,124,0,.18); }
  [data-theme="light"] .bsx-system-page .pill-signal   { color: #01579b; border-color: rgba(2,136,209,.55); background: rgba(2,136,209,.14); }
  [data-theme="light"] .bsx-system-page .pill-disabled { color: #4a5568; border-color: rgba(0,0,0,.20);     background: rgba(0,0,0,.04); }

  /* Light-mode label darkening */
  [data-theme="light"] .bsx-system-page th,
  [data-theme="light"] .bsx-system-page .kv-table td:first-child,
  [data-theme="light"] .bsx-system-page .meta-row .k,
  [data-theme="light"] .bsx-system-page .card-stat-k,
  [data-theme="light"] .bsx-system-page .backup-meta dt,
  [data-theme="light"] .bsx-system-page .version-tag-k {
    color: #1f2933;
  }
  .bsx-system-page .grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }
  .bsx-system-page .grid3 { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 14px; }
  .bsx-system-page .grid4 { display: grid; grid-template-columns: 1fr 1fr 1fr 1fr; gap: 14px; }
  @media (max-width: 1300px) {
    .bsx-system-page .grid4 { grid-template-columns: 1fr 1fr; }
  }
  .bsx-system-page .daemon-outbox-grid {
    display: grid;
    grid-template-columns: minmax(max-content, 1.25fr) minmax(0, 1fr) minmax(0, 1fr);
    gap: 14px;
    margin-bottom: 14px;
    align-items: stretch;
  }
  @media (max-width: 1100px) {
    .bsx-system-page .daemon-outbox-grid { grid-template-columns: 1fr; }
  }
  .bsx-system-page .daemon-card {
    justify-self: stretch;
    width: auto;
    max-width: 100%;
    overflow: visible;
  }
  .bsx-system-page .daemon-outbox-grid > .bsx-card {
    margin-bottom: 0;
    display: flex;
    flex-direction: column;
    min-height: 0;
  }
  .bsx-system-page .daemon-outbox-grid > .bsx-card > .bsx-card-body {
    flex: 1 1 auto;
  }
  .bsx-system-page .wallets-table .muted { color: #99a; font-style: italic; }
  .bsx-system-page .daemon-card .bsx-card-body { overflow: visible; }
  .bsx-system-page .daemon-table {
    width: max-content;
    min-width: 100%;
  }
  .bsx-system-page .daemon-table th,
  .bsx-system-page .daemon-table td { white-space: nowrap; }
  .bsx-system-page .daemon-outbox-grid table thead tr {
    height: 26px;
  }
  .bsx-system-page .daemon-outbox-grid table tbody tr {
    height: 27px;
  }
  .bsx-system-page .daemon-outbox-grid table th,
  .bsx-system-page .daemon-outbox-grid table td {
    padding-top: 0;
    padding-bottom: 0;
    line-height: 18px;
    vertical-align: middle;
  }
  .bsx-system-page .outbox-card {
    justify-self: stretch;
    width: auto;
    max-width: 100%;
  }
  .bsx-system-page .outbox-card .bsx-card-body { overflow: visible; }
  .bsx-system-page .outbox-table {
    width: auto;
    min-width: 0;
  }
  .bsx-system-page .outbox-table th,
  .bsx-system-page .outbox-table td { white-space: nowrap; }
  .bsx-system-page .outbox-tx-link {
    color: #4fc3f7;
    font-variant-numeric: tabular-nums;
    text-decoration: none;
  }
  .bsx-system-page .outbox-tx-link:hover { text-decoration: underline; }
  .bsx-system-page .outbox-table .outbox-tx-col { display: none; }
  .bsx-system-page .outbox-table.is-broadcast-filter .outbox-tx-col { display: table-cell; }
  .bsx-system-page .outbox-table .outbox-user-col { display: none; }
  .bsx-system-page .outbox-table.is-pending-filter .outbox-user-col { display: table-cell; }
  .bsx-system-page .outbox-filter-group {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    flex-wrap: wrap;
    justify-content: flex-end;
  }
  .bsx-system-page .outbox-filter {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    min-height: 20px;
    padding: 2px 7px;
    border-radius: 4px;
    border: 1px solid rgba(255,255,255,.18);
    background: rgba(255,255,255,.04);
    color: #aab;
    font-size: 11px;
    line-height: 14px;
    cursor: pointer;
  }
  .bsx-system-page .outbox-filter:hover {
    border-color: rgba(79,195,247,.55);
    color: #cdd;
  }
  .bsx-system-page .outbox-filter.is-active {
    border-color: rgba(79,195,247,.75);
    background: rgba(79,195,247,.16);
    color: #4fc3f7;
  }
  .bsx-system-page .outbox-filter-count {
    color: #e6f7ff;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }
  .bsx-system-page .outbox-filter[hidden] { display: none !important; }
  [data-theme="light"] .bsx-system-page .outbox-filter {
    border-color: rgba(0,0,0,.18);
    background: rgba(0,0,0,.03);
    color: #4a5568;
  }
  [data-theme="light"] .bsx-system-page .outbox-filter:hover {
    border-color: rgba(2,136,209,.55);
    color: #1f2933;
  }
  [data-theme="light"] .bsx-system-page .outbox-filter.is-active {
    border-color: rgba(2,136,209,.65);
    background: rgba(2,136,209,.12);
    color: #01579b;
  }
  [data-theme="light"] .bsx-system-page .outbox-filter-count { color: #1f2933; }
  /* Grid-row bottom spacing */
  .bsx-system-page .grid2,
  .bsx-system-page .grid3 { margin-bottom: 14px; }
  @media (max-width: 900px) {
    .bsx-system-page .grid2,
    .bsx-system-page .grid3 { grid-template-columns: 1fr; }
  }
  /* Card header right-side stat */
  .bsx-system-page .card-stat { font-size: 11px; display: inline-flex; align-items: center; gap: 4px; }
  .bsx-system-page .card-stat-k { color: #aab; text-transform: uppercase; letter-spacing: 0.06em; }
  .bsx-system-page .card-stat-v {
    color: #b5e7a0; font-weight: 700;
    font-variant-numeric: tabular-nums;
  }
  [data-theme="light"] .bsx-system-page .card-stat-k { color: #4a5568; }
  [data-theme="light"] .bsx-system-page .card-stat-v { color: #2e7d32; }

  /* CPU + Swap stack */
  .bsx-system-page .cpu-stack {
    display: flex; flex-direction: column; gap: 14px;
    min-width: 0;
    height: 100%;
  }
  .bsx-system-page .cpu-stack > .bsx-card { margin-bottom: 0; }

  /* Stretch resources-row columns */
  .bsx-system-page .grid3 { align-items: stretch; }
  .bsx-system-page .grid3 > .bsx-card {
    margin-bottom: 0;
    display: flex; flex-direction: column;
  }
  .bsx-system-page .grid3 > .bsx-card > .bsx-card-body { flex: 1 1 auto; }

  /* CPU kv-table */
  .bsx-system-page .kv-table td:first-child { color: #aab; font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em; }
  .bsx-system-page .kv-table td:last-child { text-align: right; font-variant-numeric: tabular-nums; }

  /* Disk row path subtext */
  .bsx-system-page .td-subpath {
    font-size: 10px; color: #99a; margin-top: 1px;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }
  .bsx-system-page .td-subpath code { background: none; padding: 0; color: inherit; }
  [data-theme="light"] .bsx-system-page .td-subpath { color: #4a5568; }
  .bsx-system-page .meta-row { display: flex; gap: 16px; flex-wrap: wrap; font-size: 12px; color: #cdd; }
  .bsx-system-page .meta-row .k { color: #aab; }
  .bsx-system-page .footnote { font-size: 11px; color: #99a; margin-top: 8px; font-style: italic; }
  /* Empty-state message */
  .bsx-system-page .empty-state {
    margin: 6px 0 2px; padding: 8px 0;
    color: #99a; font-style: italic; font-size: 12px;
    text-align: center;
  }
  [data-theme="light"] .bsx-system-page .empty-state { color: #6c7686; }
  [data-theme="light"] .bsx-system-page .bsx-card { background: #ffffff; border-color: rgba(0,0,0,.10); }
  [data-theme="light"] .bsx-system-page .bsx-card > header { background: #f1f3f5; border-bottom-color: rgba(0,0,0,.08); }
  [data-theme="light"] .bsx-system-page .bsx-card > header h3 { color: #1f2933; }
  [data-theme="light"] .bsx-system-page td,
  [data-theme="light"] .bsx-system-page .meta-row { color: #1f2933; }
  [data-theme="light"] .bsx-system-page th,
  [data-theme="light"] .bsx-system-page .meta-row .k { color: #4a5568; }

  /* Backups card */
  .bsx-system-page .backup-card { margin-bottom: 14px; }
  .bsx-system-page .backup-form {
    display: inline-flex; align-items: center; gap: 10px;
    margin: 0; padding: 0;
  }
  .bsx-system-page .backup-toggle {
    display: inline-flex; align-items: center; gap: 8px;
    cursor: pointer; user-select: none;
  }
  .bsx-system-page .backup-toggle input[type=checkbox] {
    position: absolute; width: 1px; height: 1px; margin: -1px;
    overflow: hidden; clip: rect(0 0 0 0); border: 0;
  }
  .bsx-system-page .backup-toggle .bsx-toggle {
    position: relative; width: 36px; height: 20px; border-radius: 999px;
    background: rgba(255, 255, 255, 0.10);
    border: 1px solid rgba(255, 255, 255, 0.14);
    transition: background 180ms, border-color 180ms;
    display: inline-block;
  }
  .bsx-system-page .backup-toggle .bsx-toggle::after {
    content: ''; position: absolute; top: 2px; left: 2px;
    width: 14px; height: 14px; border-radius: 50%; background: #cdd;
    transition: transform 180ms, background 180ms;
  }
  .bsx-system-page .backup-toggle input:checked + .bsx-toggle {
    background: rgba(79, 195, 247, 0.55);
    border-color: rgba(79, 195, 247, 0.65);
  }
  .bsx-system-page .backup-toggle input:checked + .bsx-toggle::after {
    transform: translateX(16px); background: #ffffff;
  }
  .bsx-system-page .backup-toggle-text { font-size: 11px; color: #cdd; }

  /* Inline editable values */
  .bsx-system-page .inline-input {
    font: inherit;
    padding: 0 2px;
    background: transparent;
    border: none;
    border-bottom: 1px dashed rgba(255, 255, 255, 0.20);
    border-radius: 0;
    color: inherit;
    cursor: pointer;
    vertical-align: baseline;
  }
  /* Number field (no spinner) */
  .bsx-system-page .inline-input-num { width: 32px; text-align: right; }
  .bsx-system-page .inline-input-num::-webkit-inner-spin-button,
  .bsx-system-page .inline-input-num::-webkit-outer-spin-button {
    -webkit-appearance: none; margin: 0;
  }
  .bsx-system-page .inline-input-num { -moz-appearance: textfield; appearance: textfield; }
  .bsx-system-page .inline-input:hover {
    border-bottom-color: rgba(79, 195, 247, 0.65);
    background: rgba(79, 195, 247, 0.06);
  }
  .bsx-system-page .inline-input:focus {
    outline: none;
    border-bottom-style: solid;
    border-bottom-color: rgba(79, 195, 247, 0.85);
    background: rgba(0,0,0,0.22);
  }
  [data-theme="light"] .bsx-system-page .inline-input {
    border-bottom-color: rgba(0, 0, 0, 0.20);
  }
  [data-theme="light"] .bsx-system-page .inline-input:hover {
    border-bottom-color: rgba(25, 118, 210, 0.65);
    background: rgba(25, 118, 210, 0.05);
  }
  .bsx-system-page .muted { color: #99a; font-style: italic; }
  [data-theme="light"] .bsx-system-page .muted { color: #4a5568; }
  .bsx-system-page .bsx-btn-sm {
    font: inherit; font-size: 11px; font-weight: 600;
    padding: 3px 10px; border-radius: 3px; cursor: pointer;
    border: 1px solid rgba(79, 195, 247, 0.45);
    background: rgba(79, 195, 247, 0.16);
    color: #e0f0fa;
    transition: background 150ms, border-color 150ms;
  }
  .bsx-system-page .bsx-btn-sm:hover {
    background: rgba(79, 195, 247, 0.28);
    border-color: rgba(79, 195, 247, 0.65);
  }
  [data-theme="light"] .bsx-system-page .backup-toggle .bsx-toggle {
    background: rgba(0,0,0,0.08); border-color: rgba(0,0,0,0.14);
  }
  [data-theme="light"] .bsx-system-page .backup-toggle .bsx-toggle::after { background: #ffffff; }
  [data-theme="light"] .bsx-system-page .backup-toggle-text { color: #1f2933; }
  [data-theme="light"] .bsx-system-page .bsx-btn-sm {
    color: #1565c0; background: rgba(25, 118, 210, 0.08);
    border-color: rgba(25, 118, 210, 0.40);
  }
  .bsx-system-page .backup-body { padding: 10px 14px 12px; }
  .bsx-system-page .backup-body .meta-row { font-size: 14px; }
  /* Backup-meta key/value grid */
  .bsx-system-page .backup-meta {
    display: grid;
    grid-template-columns: max-content 1fr max-content 1fr;
    column-gap: 16px;
    row-gap: 6px;
    align-items: baseline;
    margin: 0;
    font-size: 14px;
  }
  .bsx-system-page .backup-meta dt { color: #aab; margin: 0; }
  .bsx-system-page .backup-meta dd { margin: 0; color: #cdd; min-width: 0; }
  .bsx-system-page .backup-meta dt.full { grid-column: 1; }
  .bsx-system-page .backup-meta dd.full { grid-column: 2 / -1; }
  @media (max-width: 900px) {
    .bsx-system-page .backup-meta { grid-template-columns: max-content 1fr; }
    .bsx-system-page .backup-meta dt.full,
    .bsx-system-page .backup-meta dd.full { grid-column: auto; }
  }
  [data-theme="light"] .bsx-system-page .backup-meta dt { color: #4a5568; }
  [data-theme="light"] .bsx-system-page .backup-meta dd { color: #1f2933; }

  /* Expand/collapse */
  .bsx-system-page .backup-extra > summary {
    list-style: none;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    margin-top: 8px;
    color: #4fc3f7;
    font-size: 12px;
    user-select: none;
  }
  .bsx-system-page .backup-extra > summary::-webkit-details-marker { display: none; }
  .bsx-system-page .backup-extra > summary::before {
    content: '';
    display: inline-block;
    width: 0; height: 0;
    border-left: 5px solid currentColor;
    border-top: 4px solid transparent;
    border-bottom: 4px solid transparent;
    transition: transform 150ms ease;
  }
  .bsx-system-page .backup-extra[open] > summary::before { transform: rotate(90deg); }
  .bsx-system-page .backup-extra[open] > summary .backup-extra-toggle::after { content: ' (hide)'; opacity: 0.65; }
  .bsx-system-page .backup-extra > summary:hover { color: #80d6ff; }
  .bsx-system-page .backup-meta-extra { margin-top: 8px; }
  [data-theme="light"] .bsx-system-page .backup-extra > summary { color: #1565c0; }
  [data-theme="light"] .bsx-system-page .backup-extra > summary:hover { color: #0d47a1; }


  /* Stat tables */
  .bsx-system-page .stat-row th,
  .bsx-system-page .stat-row td { text-align: center; }
  .bsx-system-page .stat-num {
    font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
    font-variant-numeric: tabular-nums;
    font-weight: 700;
    color: #e0f0fa;
  }
  .bsx-system-page .stat-good { color: #b5e7a0; }
  .bsx-system-page .stat-warn { color: #f5cba7; }
  [data-theme="light"] .bsx-system-page .stat-num  { color: #0d47a1; }
  [data-theme="light"] .bsx-system-page .stat-good { color: #2e7d32; }
  [data-theme="light"] .bsx-system-page .stat-warn { color: #b53d00; }

  /* Services header layout */
  .bsx-system-page .services-head {
    display: grid !important;
    grid-template-columns: 1fr auto 1fr !important;
    align-items: center;
  }
  .bsx-system-page .services-head > h3            { justify-self: start; }
  .bsx-system-page .services-head > .version-row  { justify-self: center; }
  .bsx-system-page .services-head > .live-indicator { justify-self: end; }

  /* MPOS version chip rail */
  .bsx-system-page .version-row {
    display: inline-flex; flex-wrap: wrap; gap: 25px;
    font-size: 13px;
  }
  .bsx-system-page .version-tag { display: inline-flex; align-items: center; gap: 4px; }
  .bsx-system-page .version-tag-k {
    color: #aab; text-transform: uppercase; letter-spacing: 0.04em; font-weight: 600;
  }
  .bsx-system-page .version-tag-v {
    font-weight: 700;
  }
  .bsx-system-page .version-tag-v.is-ok  { color: #b5e7a0; }
  .bsx-system-page .version-tag-v.is-bad { color: #e57373; }
  .bsx-system-page .version-tag-expected {
    color: #f5cba7;
    font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
    font-size: 10px;
  }
  [data-theme="light"] .bsx-system-page .version-tag-k { color: #4a5568; }
  [data-theme="light"] .bsx-system-page .version-tag-v.is-ok  { color: #2e7d32; }
  [data-theme="light"] .bsx-system-page .version-tag-v.is-bad { color: #c62828; }
  [data-theme="light"] .bsx-system-page .version-tag-expected { color: #b53d00; }

  .bsx-system-page .live-indicator {
    display: inline-flex; align-items: center; gap: 6px;
    font-size: 10px; color: #99a; font-style: italic; letter-spacing: 0.04em;
  }
  .bsx-system-page .live-indicator::before {
    content: ''; display: inline-block; width: 6px; height: 6px;
    border-radius: 50%; background: #b5e7a0;
    box-shadow: 0 0 0 2px rgba(181,231,160,0.18);
    transition: background 200ms, box-shadow 200ms;
  }
  .bsx-system-page .live-indicator.is-stale::before {
    background: #e57373; box-shadow: 0 0 0 2px rgba(229,115,115,0.18);
  }
  .bsx-system-page .live-indicator.is-pulsing::before {
    background: #4fc3f7; box-shadow: 0 0 0 2px rgba(79,195,247,0.18);
  }

  /* Custom tooltip — sits above the source so it never clips the card edge below. */
  .bsx-system-page [data-tooltip] { position: relative; outline: none; }
  .bsx-system-page [data-tooltip]::after {
    content: attr(data-tooltip);
    position: absolute;
    bottom: calc(100% + 8px);
    right: 0;
    width: max-content;
    max-width: min(760px, calc(100vw - 32px));
    background: rgba(20, 23, 28, 0.96);
    border: 1px solid rgba(79, 195, 247, 0.35);
    color: #cdd;
    padding: 6px 10px;
    border-radius: 4px;
    font-size: 11px;
    font-weight: 400;
    letter-spacing: normal;
    text-transform: none;
    line-height: 1.35;
    text-align: left;
    white-space: nowrap;
    overflow-wrap: normal;
    opacity: 0;
    pointer-events: none;
    transition: opacity 150ms ease, transform 150ms ease;
    transform: translateY(2px);
    z-index: 100;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.45);
  }
  .bsx-system-page [data-tooltip]::before {
    content: '';
    position: absolute;
    bottom: calc(100% + 3px);
    right: 14px;
    width: 8px;
    height: 8px;
    background: rgba(20, 23, 28, 0.96);
    border-bottom: 1px solid rgba(79, 195, 247, 0.35);
    border-right: 1px solid rgba(79, 195, 247, 0.35);
    transform: rotate(45deg) translateY(2px);
    opacity: 0;
    pointer-events: none;
    transition: opacity 150ms ease, transform 150ms ease;
    z-index: 101;
  }
  .bsx-system-page [data-tooltip]:hover::after,
  .bsx-system-page [data-tooltip]:focus-visible::after { opacity: 1; transform: translateY(0); }
  .bsx-system-page [data-tooltip]:hover::before,
  .bsx-system-page [data-tooltip]:focus-visible::before { opacity: 1; transform: rotate(45deg) translateY(0); }
  [data-theme="light"] .bsx-system-page [data-tooltip]::after,
  [data-theme="light"] .bsx-system-page [data-tooltip]::before {
    background: #ffffff;
    border-color: rgba(21, 101, 192, 0.40);
    color: #1f2933;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
  }
  .bsx-system-page .daemon-rule-note {
    margin-top: 4px;
    max-width: 360px;
    color: #e57373;
    font-size: 11px;
    line-height: 1.3;
    white-space: normal;
    overflow-wrap: anywhere;
  }
  [data-theme="light"] .bsx-system-page .daemon-rule-note { color: #b71c1c; }
</style>

{* ===== Backups (full-width top section, with inline settings) ===== *}
<article class="bsx-card backup-card">
  <header>
    <h3>Backups</h3>
    <form id="backup-settings-form" method="POST" action="?page=admin&action=system" class="backup-form">
      <input type="hidden" name="page"   value="admin">
      <input type="hidden" name="action" value="system">
      <input type="hidden" name="do"     value="update_backup_settings">
      <input type="hidden" name="ctoken" value="{$CTOKEN|escape|default:""}">
      <button type="submit" id="backup-save-btn" class="bsx-btn-sm backup-save-btn" hidden>Save</button>
      <label class="backup-toggle">
        <input type="checkbox" name="backups_enabled" value="1"
               {if $SYS_BACKUP.enabled}checked{/if}
               onchange="this.form.submit()">
        <span class="bsx-toggle" aria-hidden="true"></span>
        <span class="backup-toggle-text">{if $SYS_BACKUP.enabled}Enabled{else}Disabled{/if}</span>
      </label>
      <noscript><button type="submit" class="bsx-btn-sm">Save</button></noscript>
    </form>
  </header>
  <div class="bsx-card-body backup-body">
    <dl class="backup-meta">
      <dt>Last run:</dt>
      <dd>{if $SYS_BACKUP.last_mtime}{$SYS_BACKUP.last_mtime|date_format:"%Y-%m-%d %H:%M UTC"}{else}<em>never</em>{/if}</dd>

      <dt>Size:</dt>
      <dd>{if $SYS_BACKUP.last_size}{($SYS_BACKUP.last_size / 1024 / 1024)|string_format:"%.1f"} MB{else}—{/if}</dd>
    </dl>

    <details class="backup-extra">
      <summary><span class="backup-extra-toggle">More backup details</span></summary>
      <dl class="backup-meta backup-meta-extra">
        <dt>Next:</dt>
        <dd>
          <input type="time" form="backup-settings-form" class="inline-input backup-dirty-input"
                 name="backup_schedule_time"
                 value="{$SYS_BACKUP.schedule_time|escape}"
                 step="1800"
                 data-tooltip="Click to change daily backup time">
          UTC <span class="muted">({$SYS_BACKUP.next_day_label|escape})</span>
        </dd>

        <dt>Retention:</dt>
        <dd>
          <input type="number" form="backup-settings-form" class="inline-input inline-input-num backup-dirty-input"
                 name="backup_retention_days"
                 value="{$SYS_BACKUP.retention_days|escape}"
                 min="1" max="365" step="1"
                 data-tooltip="Days to keep old backup archives">
          days
        </dd>

        {if $SYS_BACKUP.database || $SYS_BACKUP.wallets}
        <dt>Captured:</dt>
        <dd>
          {if $SYS_BACKUP.database}
            <span class="pill pill-active" data-tooltip="MariaDB{if $SYS_BACKUP.database_size} ({($SYS_BACKUP.database_size / 1024 / 1024)|string_format:"%.1f"} MB gzipped){/if}">DB · {$SYS_BACKUP.database|escape|upper}</span>
          {/if}
          {section name=w loop=$SYS_BACKUP.wallets}
            <span class="pill pill-active" data-tooltip="wallet.dat via backupwallet RPC">{$SYS_BACKUP.wallets[w]|escape|upper}</span>
          {/section}
        </dd>

        <dt>Archive:</dt>
        <dd><code>{$SYS_BACKUP.tarball_path|escape}</code></dd>
        {else}
        <dt class="full">Archive:</dt>
        <dd class="full"><code>{$SYS_BACKUP.tarball_path|escape}</code></dd>
        {/if}
      </dl>
      <p class="footnote">
        Enabled / Time / Retention all write the <code>settings</code> table and take effect at
        the next 30-min timer tick. The systemd timer fires every 30 minutes;
        <code>backup.sh</code> checks the configured window and last-run age before doing real
        work, so the schedule lives in the DB and not in
        <code>/etc/systemd/system/</code>.
      </p>
    </details>
  </div>
</article>

<script>
// Reveal the backup Save button as soon as the time or retention
// input loses its initial value. We compare against the value PHP
// rendered, so post-save (when the page reloads with the new value)
// the button hides itself again. The Enabled toggle stays auto-save —
// no button needed for it.
(function () {
  var btn = document.getElementById('backup-save-btn');
  if (!btn) return;
  var inputs = document.querySelectorAll('.backup-dirty-input');
  var initial = {};
  inputs.forEach(function (el) { initial[el.name] = el.value; });
  function check() {
    var dirty = false;
    inputs.forEach(function (el) { if (el.value !== initial[el.name]) dirty = true; });
    btn.hidden = !dirty;
  }
  inputs.forEach(function (el) {
    el.addEventListener('input',  check);
    el.addEventListener('change', check);
  });
})();
</script>

{* ===== Users / Invitations / Logins (3-up top row) ===== *}
<div class="grid3">

  <article class="bsx-card">
    <header><h3>Users</h3></header>
    <div class="bsx-card-body">
      <table class="stat-row" id="sys-table-users">
        <thead>
          <tr>
            <th class="num">Total</th>
            <th class="num">Active</th>
            <th class="num">Locked</th>
            <th class="num">Admins</th>
            <th class="num">No Fees</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td class="num stat-num">{$SYS_USERS.total}</td>
            <td class="num stat-num stat-good">{$SYS_USERS.active}</td>
            <td class="num stat-num {if $SYS_USERS.locked > 0}stat-warn{/if}">{$SYS_USERS.locked}</td>
            <td class="num stat-num">{$SYS_USERS.admins}</td>
            <td class="num stat-num">{$SYS_USERS.nofees}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </article>

  {if $SYS_INVITATIONS}
  <article class="bsx-card">
    <header><h3>Invitations</h3></header>
    <div class="bsx-card-body">
      <table class="stat-row" id="sys-table-invitations">
        <thead>
          <tr>
            <th class="num">Total</th>
            <th class="num">Activated</th>
            <th class="num">Outstanding</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td class="num stat-num">{$SYS_INVITATIONS.total}</td>
            <td class="num stat-num stat-good">{$SYS_INVITATIONS.activated}</td>
            <td class="num stat-num {if $SYS_INVITATIONS.outstanding > 0}stat-warn{/if}">{$SYS_INVITATIONS.outstanding}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </article>
  {else}
  <article class="bsx-card">
    <header><h3>Invitations</h3></header>
    <div class="bsx-card-body" style="padding: 12px 14px; color: #99a; font-style: italic; font-size: 12px;">
      Invitations are disabled in Settings.
    </div>
  </article>
  {/if}

  <article class="bsx-card">
    <header><h3>Logins</h3></header>
    <div class="bsx-card-body">
      <table class="stat-row" id="sys-table-logins">
        <thead>
          <tr>
            <th class="num">24 h</th>
            <th class="num">7 d</th>
            <th class="num">1 mo</th>
            <th class="num">6 mo</th>
            <th class="num">1 y</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td class="num stat-num">{$SYS_LOGINS.24hours}</td>
            <td class="num stat-num">{$SYS_LOGINS.7days}</td>
            <td class="num stat-num">{$SYS_LOGINS.1month}</td>
            <td class="num stat-num">{$SYS_LOGINS.6month}</td>
            <td class="num stat-num">{$SYS_LOGINS.1year}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </article>

</div>

{* ===== Services (full width, version row + service list) ===== *}
<article class="bsx-card services-card">
  <header class="services-head">
    <h3>Services</h3>
    <div class="version-row" id="sys-version-row">
      {section name=v loop=$SYS_VERSIONS}
        <span class="version-tag">
          <span class="version-tag-k">{$SYS_VERSIONS[v].label|escape}</span>
          <span class="version-tag-v {if $SYS_VERSIONS[v].match}is-ok{else}is-bad{/if}">{$SYS_VERSIONS[v].installed|escape}</span>
          {if !$SYS_VERSIONS[v].match}
            <span class="version-tag-expected" data-tooltip="Expected">→ {$SYS_VERSIONS[v].current|escape}</span>
          {/if}
        </span>
      {/section}
    </div>
    <span class="live-indicator" id="sys-live"></span>
  </header>
  <div class="bsx-card-body">
    <table>
        <thead><tr><th>Service</th><th>State</th><th>Up since</th></tr></thead>
        <tbody id="sys-tbody-services">
        {section name=s loop=$SYS_SERVICES}
          <tr>
            <td>{$SYS_SERVICES[s].label|escape}</td>
            <td>
              {if $SYS_SERVICES[s].state == "active"}
                <span class="pill pill-active">active</span>
              {elseif $SYS_SERVICES[s].state == "failed"}
                <span class="pill pill-inactive">failed</span>
              {elseif $SYS_SERVICES[s].state == "activating"}
                <span class="pill pill-warn">activating</span>
              {elseif $SYS_SERVICES[s].state == "inactive"}
                <span class="pill pill-disabled">inactive</span>
              {else}
                <span class="pill pill-disabled">{$SYS_SERVICES[s].state|escape|default:"—"}</span>
              {/if}
            </td>
            <td>{if $SYS_SERVICES[s].since}{$SYS_SERVICES[s].since|escape}{else}—{/if}</td>
          </tr>
        {/section}
        </tbody>
      </table>
  </div>
</article>

{* ===== Resources (4-up): CPU · Memory · Disk · Network ===== *}
<div class="grid3 grid4">

  {* ===== CPU + Swap stack (one column in the 3-up resources row) ===== *}
  <div class="cpu-stack">
    <article class="bsx-card">
      <header>
        <h3>CPU</h3>
      </header>
      <div class="bsx-card-body">
        <table class="kv-table">
          <tbody id="sys-tbody-cpu">
          {section name=c loop=$SYS_CPU}
            <tr>
              <td>{$SYS_CPU[c].label|escape}</td>
              <td class="num">{$SYS_CPU[c].value|escape}</td>
            </tr>
          {/section}
          </tbody>
        </table>
      </div>
    </article>
    <article class="bsx-card">
      <header>
        <h3>Swap</h3>
        <span class="card-stat"><span class="card-stat-k">Available</span> <span id="sys-swap-avail" class="card-stat-v">{$SYS_SWAP_AVAIL|escape}</span></span>
      </header>
      <div class="bsx-card-body">
        <table class="kv-table" {if !$SYS_SWAP_OK}hidden{/if}>
          <tbody id="sys-tbody-swap">
          {section name=s loop=$SYS_SWAP}
            <tr>
              <td>{$SYS_SWAP[s].label|escape}</td>
              <td class="num">{$SYS_SWAP[s].value|escape}</td>
            </tr>
          {/section}
          </tbody>
        </table>
        <p id="sys-swap-empty" class="empty-state" {if $SYS_SWAP_OK}hidden{/if}>No swap configured</p>
      </div>
    </article>
  </div>

  {* ===== Memory ===== *}
  <article class="bsx-card">
    <header>
      <h3>Memory</h3>
      <span class="card-stat"><span class="card-stat-k">Available</span> <span id="sys-mem-avail" class="card-stat-v">{$SYS_MEM_AVAIL|escape}</span></span>
    </header>
    <div class="bsx-card-body">
      <table class="kv-table">
        <tbody id="sys-tbody-memory">
        {section name=m loop=$SYS_MEMORY}
          <tr>
            <td>{$SYS_MEMORY[m].label|escape}</td>
            <td class="num">{$SYS_MEMORY[m].value|escape}</td>
          </tr>
        {/section}
        </tbody>
      </table>
      <table>
        <thead><tr><th>Process RSS</th><th class="num">PID</th><th class="num">MB</th></tr></thead>
        <tbody id="sys-tbody-procs">
        {section name=p loop=$SYS_PROCS}
          <tr>
            <td>{$SYS_PROCS[p].label|escape}</td>
            <td class="num">{$SYS_PROCS[p].pid|escape|default:"—"}</td>
            <td class="num">{if $SYS_PROCS[p].rss_mb !== ""}{$SYS_PROCS[p].rss_mb|escape}{else}—{/if}</td>
          </tr>
        {/section}
        </tbody>
      </table>
    </div>
  </article>

  {* ===== Disk ===== *}
  <article class="bsx-card">
    <header>
      <h3>Disk</h3>
      <span class="card-stat"><span class="card-stat-k">Available</span> <span id="sys-disk-avail" class="card-stat-v">{$SYS_DISK_AVAIL|escape}</span></span>
    </header>
    <div class="bsx-card-body">
      <table>
        <thead><tr><th>Path</th><th class="num">Dir Size</th><th class="num">Dir %</th></tr></thead>
        <tbody id="sys-tbody-disk">
        {section name=d loop=$SYS_DISK}
          <tr>
            <td>{$SYS_DISK[d].label|escape}<div class="td-subpath"><code>{$SYS_DISK[d].path|escape}</code> · {$SYS_DISK[d].fs|escape}</div></td>
            <td class="num">{$SYS_DISK[d].dirsize|escape}</td>
            <td class="num">{$SYS_DISK[d].dirpct|escape}</td>
          </tr>
        {/section}
        </tbody>
      </table>
    </div>
  </article>

  {* ===== Network ===== *}
  <article class="bsx-card">
    <header>
      <h3>Network</h3>
      <span class="card-stat"><span class="card-stat-k">Miners</span> <span id="sys-net-miners" class="card-stat-v">{$SYS_NET_MINERS|escape}</span></span>
    </header>
    <div class="bsx-card-body">
      <table class="kv-table">
        <tbody id="sys-tbody-network">
        {section name=n loop=$SYS_NETWORK}
          <tr>
            <td>{$SYS_NETWORK[n].label|escape}</td>
            <td class="num"{if $SYS_NETWORK[n].tooltip|default:""} data-tooltip="{$SYS_NETWORK[n].tooltip|escape}"{/if}>{$SYS_NETWORK[n].value|escape}</td>
          </tr>
        {/section}
        </tbody>
      </table>
      <p class="footnote">Iface <code>{$SYS_NET_IFACE|escape}</code></p>
    </div>
  </article>

</div>

{* ===== Daemons + Wallets + Outbox (3-up) ===== *}
<div class="daemon-outbox-grid">

<article class="bsx-card daemon-card">
  <header>
    <h3>Coin daemons</h3>
  </header>
  <div class="bsx-card-body">
    <table class="daemon-table">
      <thead><tr><th>Coin</th><th>Chain</th><th class="num">Blocks</th><th class="num">Headers</th><th>Version</th><th>Sync</th><th>Rules</th></tr></thead>
      <tbody id="sys-tbody-daemons">
      {section name=d loop=$SYS_DAEMONS}
        <tr>
          <td>{$SYS_DAEMONS[d].sym|escape}</td>
          <td><code>{$SYS_DAEMONS[d].chain|escape}</code></td>
          <td class="num">{$SYS_DAEMONS[d].blocks|escape}</td>
          <td class="num">{$SYS_DAEMONS[d].headers|escape}</td>
          <td><code>{$SYS_DAEMONS[d].version|escape}</code></td>
          <td>
            {if $SYS_DAEMONS[d].synced}
              <span class="pill pill-active">synced</span>
            {elseif $SYS_DAEMONS[d].blocks == "—"}
              <span class="pill pill-inactive">unreachable</span>
            {else}
              <span class="pill pill-warn">syncing</span>
            {/if}
          </td>
          <td>
            {if $SYS_DAEMONS[d].rules.class == "signal"}
              <span class="pill pill-signal" data-tooltip="{$SYS_DAEMONS[d].rules.detail|escape}">{$SYS_DAEMONS[d].rules.label|escape}</span>
            {elseif $SYS_DAEMONS[d].rules.class == "err"}
              <span class="pill pill-inactive" data-tooltip="{$SYS_DAEMONS[d].rules.detail|escape}">{$SYS_DAEMONS[d].rules.label|escape}</span>
            {else}
              <span class="pill pill-active" data-tooltip="{$SYS_DAEMONS[d].rules.detail|escape}">{$SYS_DAEMONS[d].rules.label|escape|default:"OK"}</span>
            {/if}
            {if $SYS_DAEMONS[d].rules.raw_warning|default:"" && !$SYS_DAEMONS[d].rules.warning_explained}
              <div class="daemon-rule-note">{$SYS_DAEMONS[d].rules.raw_warning|escape}</div>
            {/if}
          </td>
        </tr>
      {/section}
      </tbody>
    </table>
  </div>
</article>

<article class="bsx-card">
  <header>
    <h3>Wallets</h3>
  </header>
  <div class="bsx-card-body">
    <table class="wallets-table">
      <thead><tr><th>Coin</th><th class="num">Balance</th><th class="num">Locked</th><th class="num">Unconfirmed</th></tr></thead>
      <tbody id="sys-tbody-wallets">
      {section name=w loop=$SYS_WALLETS}
        <tr>
          <td>{$SYS_WALLETS[w].sym|escape}</td>
          <td class="num{if !$SYS_WALLETS[w].reachable} muted{/if}">{$SYS_WALLETS[w].balance|escape}</td>
          <td class="num">{$SYS_WALLETS[w].locked|escape}</td>
          <td class="num">{$SYS_WALLETS[w].unconfirmed|escape}</td>
        </tr>
      {/section}
      </tbody>
    </table>
  </div>
</article>

<article class="bsx-card outbox-card">
  <header>
    <h3>Payout</h3>
    <div class="outbox-filter-group" role="group" aria-label="Payout status">
      <button type="button" class="outbox-filter" data-outbox-filter="pending">Pending <span id="sys-outbox-count-pending" class="outbox-filter-count">{$SYS_OUTBOX_COUNTS.pending|default:"0"|escape}</span></button>
      <button type="button" class="outbox-filter" data-outbox-filter="broadcast">Broadcasted <span id="sys-outbox-count-broadcast" class="outbox-filter-count">{$SYS_OUTBOX_COUNTS.broadcast|default:"0"|escape}</span></button>
      <button type="button" class="outbox-filter" data-outbox-filter="reconciled">Reconciled <span id="sys-outbox-count-reconciled" class="outbox-filter-count">{$SYS_OUTBOX_COUNTS.reconciled|default:"0"|escape}</span></button>
      <button type="button" class="outbox-filter" data-outbox-filter="other"{if !$SYS_OUTBOX_COUNTS.other} hidden{/if} data-tooltip="Abandoned or review payout states">Other <span id="sys-outbox-count-other" class="outbox-filter-count">{$SYS_OUTBOX_COUNTS.other|default:"0"|escape}</span></button>
    </div>
  </header>
  <div class="bsx-card-body">
    <table class="outbox-table">
      <thead><tr><th>Coin</th><th>State</th><th class="num">Count</th><th class="num">Amount</th><th>Age</th><th class="outbox-user-col">User</th><th class="outbox-tx-col">TX</th></tr></thead>
      <tbody id="sys-tbody-outbox">
      {section name=o loop=$SYS_OUTBOX}
        <tr data-outbox-group="{$SYS_OUTBOX[o].group|escape}">
          <td><code>{$SYS_OUTBOX[o].slot|escape}</code></td>
          <td>
            {if $SYS_OUTBOX[o].status == "pending"}
              <span class="pill pill-warn">pending</span>
            {elseif $SYS_OUTBOX[o].status == "broadcast"}
              <span class="pill pill-warn">broadcast</span>
            {elseif $SYS_OUTBOX[o].status == "reconciled"}
              <span class="pill pill-active">reconciled</span>
            {elseif $SYS_OUTBOX[o].status == "indeterminate"}
              <span class="pill pill-inactive">review</span>
            {elseif $SYS_OUTBOX[o].status == "abandoned"}
              <span class="pill pill-disabled">abandoned</span>
            {else}
              <span class="pill pill-disabled">{$SYS_OUTBOX[o].status|escape}</span>
            {/if}
          </td>
          <td class="num">{$SYS_OUTBOX[o].cnt}</td>
          <td class="num">{$SYS_OUTBOX[o].amount|escape}</td>
          <td>{$SYS_OUTBOX[o].age|escape}</td>
          <td class="outbox-user-col">{$SYS_OUTBOX[o].user|escape|default:"—"}</td>
          <td class="outbox-tx-col">
            {if $SYS_OUTBOX[o].status == "broadcast" && $SYS_OUTBOX[o].txurl && $SYS_OUTBOX[o].txid}
              <a class="outbox-tx-link" href="{$SYS_OUTBOX[o].txurl|escape}" target="_blank" rel="noopener">{$SYS_OUTBOX[o].txshort|escape}</a>
            {elseif $SYS_OUTBOX[o].status == "broadcast" && $SYS_OUTBOX[o].txid}
              <span class="outbox-tx-link" title="{$SYS_OUTBOX[o].txid|escape}">{$SYS_OUTBOX[o].txshort|escape}</span>
            {else}
              —
            {/if}
          </td>
        </tr>
      {/section}
        <tr id="sys-outbox-empty"{if $SYS_OUTBOX} hidden{/if}><td colspan="7" class="empty-state">No payouts yet.</td></tr>
      </tbody>
    </table>
  </div>
</article>

</div>{* /grid2 daemons + outbox *}

</div>{* /bsx-system-page *}

<script>
(function () {
  var POLL_MS = 10000;
  var URL = '?page=admin&action=system&_partial=1';
  var indicator = document.getElementById('sys-live');
  if (!indicator) return;
  indicator.textContent = 'live · 10s';

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c];
    });
  }
  function statePill(state) {
    var s = String(state || '');
    if (s === 'active')     return '<span class="pill pill-active">active</span>';
    if (s === 'failed')     return '<span class="pill pill-inactive">failed</span>';
    if (s === 'activating') return '<span class="pill pill-warn">activating</span>';
    if (s === 'inactive')   return '<span class="pill pill-disabled">inactive</span>';
    return '<span class="pill pill-disabled">' + esc(s || '—') + '</span>';
  }
  function outboxPill(status) {
    var s = String(status || '');
    if (s === 'pending')       return '<span class="pill pill-warn">pending</span>';
    if (s === 'broadcast')     return '<span class="pill pill-warn">broadcast</span>';
    if (s === 'reconciled')    return '<span class="pill pill-active">reconciled</span>';
    if (s === 'indeterminate') return '<span class="pill pill-inactive">review</span>';
    if (s === 'abandoned')     return '<span class="pill pill-disabled">abandoned</span>';
    return '<span class="pill pill-disabled">' + esc(s) + '</span>';
  }
  function outboxTxLink(row) {
    if (!row || row.status !== 'broadcast' || !row.txid) return '—';
    if (!row.txurl) {
      return '<span class="outbox-tx-link" title="' + esc(row.txid) + '">' +
             esc(row.txshort || row.txid) + '</span>';
    }
    return '<a class="outbox-tx-link" href="' + esc(row.txurl) + '" target="_blank" rel="noopener">' +
           esc(row.txshort || row.txid) + '</a>';
  }
  var currentOutboxFilter = '';
  var outboxFilterTouched = false;
  function outboxGroup(row) {
    var status = String((row && row.status) || '');
    var group = String((row && row.group) || '');
    if (group) return group;
    if (status === 'pending') return 'pending';
    if (status === 'broadcast') return 'broadcast';
    if (status === 'reconciled') return 'reconciled';
    return 'other';
  }
  function emptyOutboxCounts() {
    return { pending: 0, broadcast: 0, reconciled: 0, other: 0 };
  }
  function outboxCountsFromButtons() {
    var counts = emptyOutboxCounts();
    Object.keys(counts).forEach(function (key) {
      var el = document.getElementById('sys-outbox-count-' + key);
      var n = el ? parseInt(el.textContent, 10) : 0;
      counts[key] = isNaN(n) ? 0 : n;
    });
    return counts;
  }
  function outboxCountsFromRows(rows, provided) {
    var counts = emptyOutboxCounts();
    if (provided) {
      Object.keys(counts).forEach(function (key) {
        var n = parseInt(provided[key], 10);
        counts[key] = isNaN(n) ? 0 : n;
      });
      return counts;
    }
    (rows || []).forEach(function (row) {
      var group = outboxGroup(row);
      var n = parseInt(row.cnt, 10);
      counts[group] = (counts[group] || 0) + (isNaN(n) ? 0 : n);
    });
    return counts;
  }
  function chooseOutboxFilter(counts) {
    if (currentOutboxFilter) {
      if (outboxFilterTouched || (counts[currentOutboxFilter] || 0) > 0) return;
    }
    currentOutboxFilter =
      counts.pending > 0 ? 'pending' :
      counts.broadcast > 0 ? 'broadcast' :
      counts.reconciled > 0 ? 'reconciled' :
      counts.other > 0 ? 'other' :
      'pending';
  }
  function updateOutboxButtons(counts) {
    var otherBtn = document.querySelector('[data-outbox-filter="other"]');
    if (otherBtn) otherBtn.hidden = !(counts.other > 0 || currentOutboxFilter === 'other');
    document.querySelectorAll('[data-outbox-filter]').forEach(function (btn) {
      var key = btn.getAttribute('data-outbox-filter');
      btn.classList.toggle('is-active', key === currentOutboxFilter);
      btn.setAttribute('aria-pressed', key === currentOutboxFilter ? 'true' : 'false');
      var countEl = document.getElementById('sys-outbox-count-' + key);
      if (countEl) countEl.textContent = counts[key] || 0;
    });
  }
  function applyOutboxFilter(counts) {
    chooseOutboxFilter(counts);
    updateOutboxButtons(counts);
    var tbody = document.getElementById('sys-tbody-outbox');
    if (!tbody) return;
    var table = tbody.closest('table');
    if (table) {
      table.classList.toggle('is-pending-filter', currentOutboxFilter === 'pending');
      table.classList.toggle('is-broadcast-filter', currentOutboxFilter === 'broadcast');
    }
    var shown = 0;
    Array.prototype.forEach.call(tbody.querySelectorAll('tr[data-outbox-group]'), function (tr) {
      var show = tr.getAttribute('data-outbox-group') === currentOutboxFilter;
      tr.hidden = !show;
      if (show) shown++;
    });
    var empty = document.getElementById('sys-outbox-empty');
    if (empty) empty.hidden = shown > 0;
  }
  function syncPill(d) {
    if (d.synced) return '<span class="pill pill-active">synced</span>';
    if (d.blocks === '—' || d.blocks === '') return '<span class="pill pill-inactive">unreachable</span>';
    return '<span class="pill pill-warn">syncing</span>';
  }
  function rulePill(rule) {
    rule = rule || {};
    var cls = 'pill-active';
    if (rule.class === 'signal') cls = 'pill-signal';
    else if (rule.class === 'err') cls = 'pill-inactive';
    else if (rule.class === 'warn') cls = 'pill-warn';
    var title = rule.detail ? ' data-tooltip="' + esc(rule.detail) + '"' : '';
    var note = '';
    if (rule.raw_warning && !rule.warning_explained) {
      note = '<div class="daemon-rule-note">' + esc(rule.raw_warning) + '</div>';
    }
    return '<span class="pill ' + cls + '"' + title + '>' + esc(rule.label || 'OK') + '</span>' + note;
  }

  function fill(id, html) {
    var el = document.getElementById(id);
    if (el) el.innerHTML = html;
  }

  function setText(el, txt) { if (el) el.textContent = txt; }

  function render(data) {
    // Users / Invitations / Logins live in single-row tables — just
    // poke the <td> cells in place. Robust against the Invitations
    // panel being absent (when disabled in settings).
    if (data.users) {
      var u = document.querySelectorAll('#sys-table-users tbody td');
      if (u.length === 5) {
        setText(u[0], data.users.total);
        setText(u[1], data.users.active);
        setText(u[2], data.users.locked);
        setText(u[3], data.users.admins);
        setText(u[4], data.users.nofees);
        u[2].className = 'num stat-num' + (data.users.locked > 0 ? ' stat-warn' : '');
      }
    }
    if (data.invitations) {
      var iv = document.querySelectorAll('#sys-table-invitations tbody td');
      if (iv.length === 3) {
        setText(iv[0], data.invitations.total);
        setText(iv[1], data.invitations.activated);
        setText(iv[2], data.invitations.outstanding);
        iv[2].className = 'num stat-num' + (data.invitations.outstanding > 0 ? ' stat-warn' : '');
      }
    }
    if (data.logins) {
      var lg = document.querySelectorAll('#sys-table-logins tbody td');
      if (lg.length === 5) {
        setText(lg[0], data.logins['24hours']);
        setText(lg[1], data.logins['7days']);
        setText(lg[2], data.logins['1month']);
        setText(lg[3], data.logins['6month']);
        setText(lg[4], data.logins['1year']);
      }
    }
    if (data.versions) {
      var vr = document.getElementById('sys-version-row');
      if (vr) {
        vr.innerHTML = data.versions.map(function (v) {
          var cls = v.match ? 'is-ok' : 'is-bad';
          var expected = v.match ? '' : '<span class="version-tag-expected" data-tooltip="Expected">→ ' + esc(v.current) + '</span>';
          return '<span class="version-tag"><span class="version-tag-k">' + esc(v.label) +
                 '</span><span class="version-tag-v ' + cls + '">' + esc(v.installed) +
                 '</span>' + expected + '</span>';
        }).join('');
      }
    }

    fill('sys-tbody-services', (data.services || []).map(function (r) {
      return '<tr><td>' + esc(r.label) + '</td><td>' + statePill(r.state) +
             '</td><td>' + (r.since ? esc(r.since) : '—') + '</td></tr>';
    }).join(''));

    fill('sys-tbody-cpu', (data.cpu || []).map(function (r) {
      return '<tr><td>' + esc(r.label) + '</td><td class="num">' + esc(r.value) + '</td></tr>';
    }).join(''));

    fill('sys-tbody-swap', (data.swap || []).map(function (r) {
      return '<tr><td>' + esc(r.label) + '</td><td class="num">' + esc(r.value) + '</td></tr>';
    }).join(''));
    var swapAvail = document.getElementById('sys-swap-avail');
    if (swapAvail && data.swap_available) swapAvail.textContent = data.swap_available;
    var swapTbl = document.querySelector('#sys-tbody-swap')
                  && document.querySelector('#sys-tbody-swap').closest('table');
    var swapEmpty = document.getElementById('sys-swap-empty');
    if (swapTbl && swapEmpty) {
      var ok = !!data.swap_configured;
      swapTbl.hidden   = !ok;
      swapEmpty.hidden = ok;
    }

    fill('sys-tbody-memory', (data.memory || []).map(function (r) {
      return '<tr><td>' + esc(r.label) + '</td><td class="num">' + esc(r.value) + '</td></tr>';
    }).join(''));
    var memAvail = document.getElementById('sys-mem-avail');
    if (memAvail && data.memory_available) memAvail.textContent = data.memory_available;
    var diskAvail = document.getElementById('sys-disk-avail');
    if (diskAvail && data.disk_available) diskAvail.textContent = data.disk_available;

    fill('sys-tbody-disk', (data.disk || []).map(function (r) {
      return '<tr><td>' + esc(r.label) +
             '<div class="td-subpath"><code>' + esc(r.path) + '</code> · ' + esc(r.fs || '') + '</div></td>' +
             '<td class="num">' + esc(r.dirsize || '—') +
             '</td><td class="num">' + esc(r.dirpct || '—') +
             '</td></tr>';
    }).join(''));

    fill('sys-tbody-network', (data.network || []).map(function (r) {
      var tip = r.tooltip ? ' data-tooltip="' + esc(r.tooltip) + '"' : '';
      return '<tr><td>' + esc(r.label) + '</td><td class="num"' + tip + '>' + esc(r.value) + '</td></tr>';
    }).join(''));
    var netMiners = document.getElementById('sys-net-miners');
    if (netMiners && data.network_miners != null) netMiners.textContent = data.network_miners;

    fill('sys-tbody-procs', (data.procs || []).map(function (r) {
      return '<tr><td>' + esc(r.label) + '</td><td class="num">' + esc(r.pid || '—') +
             '</td><td class="num">' + (r.rss_mb === '' || r.rss_mb == null ? '—' : esc(r.rss_mb)) +
             '</td></tr>';
    }).join(''));

    fill('sys-tbody-daemons', (data.daemons || []).map(function (r) {
      return '<tr><td>' + esc(r.sym) + '</td><td><code>' + esc(r.chain) +
             '</code></td><td class="num">' + esc(r.blocks) +
             '</td><td class="num">' + esc(r.headers) +
             '</td><td><code>' + esc(r.version) + '</code></td>' +
             '<td>' + syncPill(r) + '</td><td>' + rulePill(r.rules) + '</td></tr>';
    }).join(''));

    fill('sys-tbody-wallets', (data.wallets || []).map(function (r) {
      var balCls = 'num' + (r.reachable ? '' : ' muted');
      return '<tr><td>' + esc(r.sym) + '</td>' +
             '<td class="' + balCls + '">' + esc(r.balance) + '</td>' +
             '<td class="num">' + esc(r.locked) + '</td>' +
             '<td class="num">' + esc(r.unconfirmed) + '</td></tr>';
    }).join(''));

    var outboxTbody = document.getElementById('sys-tbody-outbox');
    if (outboxTbody) {
      var outboxRows = data.outbox || [];
      var outboxCounts = outboxCountsFromRows(outboxRows, data.outbox_counts);
      fill('sys-tbody-outbox', outboxRows.map(function (r) {
        return '<tr data-outbox-group="' + esc(outboxGroup(r)) + '"><td><code>' + esc(r.slot) + '</code></td><td>' + outboxPill(r.status) +
               '</td><td class="num">' + esc(r.cnt) + '</td><td class="num">' + esc(r.amount || '—') +
               '</td><td>' + esc(r.age || '—') + '</td><td class="outbox-user-col">' + esc(r.user || '—') +
               '</td><td class="outbox-tx-col">' + outboxTxLink(r) + '</td></tr>';
      }).join('') + '<tr id="sys-outbox-empty" hidden><td colspan="7" class="empty-state">No payouts in this state.</td></tr>');
      applyOutboxFilter(outboxCounts);
    }

    indicator.classList.remove('is-stale');
    var d = new Date();
    var hh = String(d.getHours()).padStart(2, '0');
    var mm = String(d.getMinutes()).padStart(2, '0');
    var ss = String(d.getSeconds()).padStart(2, '0');
    indicator.textContent = 'live · updated ' + hh + ':' + mm + ':' + ss;
  }

  document.querySelectorAll('[data-outbox-filter]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      currentOutboxFilter = btn.getAttribute('data-outbox-filter') || 'pending';
      outboxFilterTouched = true;
      applyOutboxFilter(outboxCountsFromButtons());
    });
  });
  applyOutboxFilter(outboxCountsFromButtons());

  function tick() {
    indicator.classList.add('is-pulsing');
    fetch(URL, { credentials: 'same-origin', cache: 'no-store' })
      .then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.json();
      })
      .then(function (data) {
        indicator.classList.remove('is-pulsing');
        render(data);
      })
      .catch(function () {
        indicator.classList.remove('is-pulsing');
        indicator.classList.add('is-stale');
        indicator.textContent = 'stale · retrying';
      });
  }

  setInterval(tick, POLL_MS);
})();
</script>
