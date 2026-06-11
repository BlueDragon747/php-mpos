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
  .bsx-system-page .services-card {
    overflow: visible;
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
  #system-time-toggle {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 38px;
    margin-right: 16px;
    color: #cdd;
    font-size: 11px;
    font-weight: 700;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    white-space: nowrap;
  }
  #secondary_bar #system-time-toggle {
    float: right;
  }
  #system-time-toggle .time-toggle-label {
    display: inline-flex;
    align-items: center;
    gap: 7px;
    cursor: pointer;
    user-select: none;
  }
  #system-time-toggle input[type=checkbox] {
    position: absolute;
    width: 1px;
    height: 1px;
    margin: -1px;
    overflow: hidden;
    clip: rect(0 0 0 0);
    border: 0;
  }
  #system-time-toggle .time-toggle-track {
    position: relative;
    width: 34px;
    height: 18px;
    border-radius: 999px;
    box-sizing: border-box;
    background: rgba(255, 255, 255, 0.10);
    border: 1px solid rgba(255, 255, 255, 0.14);
    transition: background 180ms, border-color 180ms;
    display: inline-block;
  }
  #system-time-toggle .time-toggle-track::after {
    content: '';
    position: absolute;
    top: 2px;
    left: 2px;
    width: 12px;
    height: 12px;
    border-radius: 50%;
    background: #cdd;
    transition: transform 180ms, background 180ms;
  }
  #system-time-toggle input:checked + .time-toggle-track {
    background: rgba(79, 195, 247, 0.55);
    border-color: rgba(79, 195, 247, 0.65);
  }
  #system-time-toggle input:checked + .time-toggle-track::after {
    transform: translateX(16px);
    background: #ffffff;
  }
  [data-theme="light"] #system-time-toggle { color: #1f2933; }
  [data-theme="light"] #system-time-toggle .time-toggle-track {
    background: rgba(0,0,0,.08);
    border-color: rgba(0,0,0,.20);
  }
  [data-theme="light"] #system-time-toggle .time-toggle-track::after { background: #ffffff; }
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
  .bsx-system-page .grid4 {
    display: grid;
    grid-template-columns:
      minmax(175px, .7fr)
      minmax(335px, 1.1fr)
      minmax(320px, 1fr)
      minmax(390px, 1.35fr);
    gap: 12px;
  }
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
  .bsx-system-page .card-stat {
    font-size: 11px;
    display: inline-flex;
    align-items: center;
    gap: 4px;
    flex: 0 0 auto;
    white-space: nowrap;
  }
  .bsx-system-page .card-stat-k {
    color: #aab;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    white-space: nowrap;
  }
  .bsx-system-page .card-stat-v {
    color: #b5e7a0; font-weight: 700;
    font-variant-numeric: tabular-nums;
    font-size: inherit;
    white-space: nowrap;
  }
  [data-theme="light"] .bsx-system-page .card-stat-k { color: #4a5568; }
  [data-theme="light"] .bsx-system-page .card-stat-v { color: #2e7d32; }

  /* CPU + Swap stack */
  .bsx-system-page .cpu-stack,
  .bsx-system-page .memory-network-stack {
    display: flex; flex-direction: column; gap: 14px;
    min-width: 0;
    height: 100%;
  }
  .bsx-system-page .cpu-stack > .bsx-card,
  .bsx-system-page .memory-network-stack > .bsx-card { margin-bottom: 0; }

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
  .bsx-system-page .db-footnote {
    line-height: 1.25;
    margin-top: 6px;
  }
  .bsx-system-page .db-total-stat {
    align-items: center;
    gap: 6px;
    min-width: max-content;
  }
  .bsx-system-page .db-total-v {
    display: inline-flex;
    align-items: baseline;
    gap: 8px;
    line-height: 1;
  }
  .bsx-system-page .db-total-v span {
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }
  .bsx-system-page .db-footnote .db-foot-meta {
    display: block;
    white-space: normal;
  }
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
    display: inline-flex; flex-direction: row; align-items: center; justify-content: flex-end; gap: 10px;
    margin: 0; padding: 0;
  }
  .bsx-system-page .backup-action-row {
    display: inline-flex;
    align-items: center;
    justify-content: flex-end;
    gap: 10px;
  }
  .bsx-system-page .backup-auto-label {
    color: #b9c8e6;
    font-size: 11px;
    font-weight: 700;
    text-transform: uppercase;
    white-space: nowrap;
  }
  .bsx-system-page .backup-run-btn {
    min-width: 88px;
    text-align: center;
  }
  .bsx-system-page .db-prune-form {
    display: flex; align-items: center; gap: 26px;
    justify-content: center;
    flex-wrap: wrap;
    min-width: 0;
    margin: 0 0 6px; padding: 0;
    font-size: 11px;
  }
  .bsx-system-page .db-prune-control {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    min-width: 0;
  }
  .bsx-system-page .db-prune-form .card-stat-k {
    white-space: nowrap;
  }
  .bsx-system-page .db-prune-form .inline-select {
    width: 92px;
    min-width: 0;
  }
  .bsx-system-page .db-prune-form select[name="db_prune_keep_recent_shares"] {
    width: 96px;
  }
  .bsx-system-page .db-prune-form .inline-select:disabled {
    opacity: .55;
    cursor: default;
  }
  .bsx-system-page .db-prune-form.is-control-locked .inline-select {
    opacity: .55;
    cursor: default;
    border-color: rgba(255,255,255,.12);
    color: #9aa;
  }
  .bsx-system-page .db-prune-toolbar {
    padding-bottom: 6px;
    border-bottom: 1px solid rgba(255,255,255,.05);
    margin-bottom: 4px;
  }
  .bsx-system-page .inline-select {
    font: inherit;
    min-height: 22px;
    padding: 1px 20px 1px 6px;
    border-radius: 3px;
    border: 1px solid rgba(255,255,255,.18);
    background: rgba(0,0,0,.20);
    color: #cdd;
  }
  .bsx-system-page .resource-io-line {
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    text-align: center;
    gap: 4px 10px;
    margin: 0 0 6px;
    font-size: 11px;
    color: #99a;
    line-height: 1.35;
  }
  .bsx-system-page .resource-io-line span + span {
    border-left: 1px solid rgba(255,255,255,.10);
    padding-left: 10px;
  }
  .bsx-system-page .resource-io-line strong {
    color: #cdd;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }
  [data-theme="light"] .bsx-system-page .resource-io-line { color: #4a5568; }
  [data-theme="light"] .bsx-system-page .resource-io-line span + span { border-left-color: rgba(0,0,0,.12); }
  [data-theme="light"] .bsx-system-page .resource-io-line strong { color: #1f2933; }
  .bsx-system-page .memory-card .resource-io-line {
    flex-wrap: nowrap;
    justify-content: center;
    gap: 0 8px;
    padding-left: 0;
    padding-right: 0;
    padding-bottom: 6px;
    white-space: nowrap;
    border-bottom: 1px solid rgba(255,255,255,.08);
  }
  .bsx-system-page .memory-card .resource-io-line span + span {
    padding-left: 8px;
  }
  .bsx-system-page .disk-card .resource-io-line {
    padding-bottom: 6px;
    border-bottom: 1px solid rgba(255,255,255,.08);
  }
  .bsx-system-page .memory-summary-table {
    margin-bottom: 0;
  }
  .bsx-system-page .memory-card .bsx-card-body {
    display: flex;
    flex-direction: column;
    min-height: 0;
  }
  [data-theme="light"] .bsx-system-page .memory-card .resource-io-line,
  [data-theme="light"] .bsx-system-page .disk-card .resource-io-line {
    border-color: rgba(0,0,0,.10);
  }
  .bsx-system-page .network-card th,
  .bsx-system-page .network-card td {
    padding-left: 4px;
    padding-right: 4px;
  }
  .bsx-system-page .network-card .bsx-card-body {
    padding-left: 10px;
    padding-right: 10px;
  }
  [data-theme="light"] .bsx-system-page .inline-select {
    border-color: rgba(0,0,0,.20);
    background: #ffffff;
    color: #1f2933;
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
    position: relative; width: 34px; height: 18px; border-radius: 999px;
    box-sizing: border-box;
    background: rgba(255, 255, 255, 0.10);
    border: 1px solid rgba(255, 255, 255, 0.14);
    transition: background 180ms, border-color 180ms;
    display: inline-block;
  }
  .bsx-system-page .backup-toggle .bsx-toggle::after {
    content: ''; position: absolute; top: 2px; left: 2px;
    width: 12px; height: 12px; border-radius: 50%; background: #cdd;
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
  .bsx-system-page .services-status-grid {
    display: grid;
    grid-template-columns: minmax(0, 1fr) minmax(260px, 320px);
    gap: 12px;
    margin-bottom: 14px;
    align-items: stretch;
  }
  .bsx-system-page .services-status-grid > .bsx-card {
    margin-bottom: 0;
  }
  .bsx-system-page .services-head {
    display: grid !important;
    grid-template-columns: 1fr auto 1fr !important;
    align-items: center;
  }
  .bsx-system-page .services-head > h3            { justify-self: start; }
  .bsx-system-page .services-head > .version-row  { justify-self: center; }
  .bsx-system-page .services-head > .services-right {
    justify-self: end;
    display: inline-flex;
    align-items: center;
    gap: 10px;
    min-width: 0;
    max-width: 100%;
    overflow: visible;
  }
  .bsx-system-page .services-scroll {
    max-height: 236px;
    overflow-y: auto;
    scrollbar-gutter: stable;
    scrollbar-width: thin;
    scrollbar-color: rgba(255, 255, 255, 0.18) transparent;
    overflow-x: hidden;
  }
  .bsx-system-page .services-scroll::-webkit-scrollbar,
  .bsx-system-page .health-detail::-webkit-scrollbar {
    width: 8px;
    height: 8px;
  }
  .bsx-system-page .services-scroll::-webkit-scrollbar-track,
  .bsx-system-page .health-detail::-webkit-scrollbar-track {
    background: transparent;
  }
  .bsx-system-page .services-scroll::-webkit-scrollbar-thumb,
  .bsx-system-page .health-detail::-webkit-scrollbar-thumb {
    background-color: rgba(255, 255, 255, 0.18);
    border-radius: 4px;
    border: 2px solid transparent;
    background-clip: padding-box;
  }
  .bsx-system-page .services-scroll::-webkit-scrollbar-thumb:hover,
  .bsx-system-page .health-detail::-webkit-scrollbar-thumb:hover {
    background-color: rgba(79, 195, 247, 0.45);
  }
  .bsx-system-page .services-scroll thead th {
    position: sticky;
    top: 0;
    z-index: 2;
    background: #202020;
  }
  .bsx-system-page .service-sort-btn {
    appearance: none;
    border: 0;
    background: transparent;
    color: inherit;
    cursor: pointer;
    font: inherit;
    letter-spacing: inherit;
    padding: 0;
    text-transform: inherit;
  }
  .bsx-system-page .service-sort-btn:hover,
  .bsx-system-page .service-sort-btn[aria-pressed="true"] {
    color: #4fc3f7;
  }
  .bsx-system-page .service-sort-btn.metric-sort-btn {
    color: #4fc3f7;
  }
  .bsx-system-page .service-sort-btn.metric-sort-btn:hover,
  .bsx-system-page .service-sort-btn.metric-sort-btn[aria-pressed="true"] {
    color: #80d6ff;
  }
  .bsx-system-page .services-table th.num,
  .bsx-system-page .services-table td.num {
    text-align: center;
  }
  .bsx-system-page .services-table tbody td {
    transition: background-color 120ms ease;
  }
  .bsx-system-page .services-table tbody tr:hover td {
    background: rgba(79, 195, 247, .055);
  }
  [data-theme="light"] .bsx-system-page .services-table tbody tr:hover td {
    background: rgba(2, 136, 209, .06);
  }
  .bsx-system-page .services-table th:nth-child(1),
  .bsx-system-page .services-table td:nth-child(1) { width: 10%; }
  .bsx-system-page .services-table th:nth-child(2),
  .bsx-system-page .services-table td:nth-child(2) { width: 20%; }
  .bsx-system-page .services-table th:nth-child(3),
  .bsx-system-page .services-table td:nth-child(3) { width: 9%; }
  .bsx-system-page .services-table th:nth-child(4),
  .bsx-system-page .services-table td:nth-child(4) { width: 8%; }
  .bsx-system-page .services-table th:nth-child(5),
  .bsx-system-page .services-table td:nth-child(5) { width: 8%; }
  .bsx-system-page .services-table th:nth-child(6),
  .bsx-system-page .services-table td:nth-child(6) { width: 29%; }
  .bsx-system-page .services-table th:nth-child(7),
  .bsx-system-page .services-table td:nth-child(7) { width: 16%; }
  .bsx-system-page .services-scroll thead [data-tooltip]::after {
    top: calc(100% + 8px);
    bottom: auto;
    z-index: 250;
  }
  .bsx-system-page .services-scroll thead [data-tooltip]::before {
    top: calc(100% + 3px);
    bottom: auto;
    border: 0;
    border-top: 1px solid rgba(79, 195, 247, 0.35);
    border-left: 1px solid rgba(79, 195, 247, 0.35);
    transform: rotate(45deg) translateY(-2px);
    z-index: 251;
  }
  .bsx-system-page .services-scroll thead #sys-services-sort-name[data-tooltip]::after,
  .bsx-system-page .services-scroll thead #sys-services-sort-state[data-tooltip]::after {
    left: 0;
    right: auto;
  }
  .bsx-system-page .services-scroll thead #sys-services-sort-name[data-tooltip]::before,
  .bsx-system-page .services-scroll thead #sys-services-sort-state[data-tooltip]::before {
    left: 14px;
    right: auto;
  }
  .bsx-system-page .services-scroll thead [data-tooltip]:hover::after,
  .bsx-system-page .services-scroll thead [data-tooltip]:focus-visible::after {
    transform: translateY(0);
  }
  .bsx-system-page .services-scroll thead [data-tooltip]:hover::before,
  .bsx-system-page .services-scroll thead [data-tooltip]:focus-visible::before {
    transform: rotate(45deg) translateY(0);
  }
  [data-theme="light"] .bsx-system-page .services-scroll thead th {
    background: #ffffff;
  }

  /* MPOS version chip rail */
  .bsx-system-page .version-row {
    display: inline-flex; flex-wrap: wrap; gap: 25px;
    font-size: 12px;
    line-height: 1.2;
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
    font-size: inherit;
  }
  [data-theme="light"] .bsx-system-page .version-tag-k { color: #4a5568; }
  [data-theme="light"] .bsx-system-page .version-tag-v.is-ok  { color: #2e7d32; }
  [data-theme="light"] .bsx-system-page .version-tag-v.is-bad { color: #c62828; }
  [data-theme="light"] .bsx-system-page .version-tag-expected { color: #b53d00; }

  .bsx-system-page .health-row {
    display: flex;
    align-items: center;
    justify-content: center;
    flex-wrap: wrap;
    gap: 5px;
    min-width: 0;
    margin-bottom: 8px;
    overflow: visible;
  }
  .bsx-system-page .health-chip {
    appearance: none;
    display: inline-flex;
    align-items: baseline;
    gap: 3px;
    flex: 0 0 auto;
    padding: 1px 7px;
    border-radius: 999px;
    border: 1px solid rgba(181,231,160,.35);
    background: rgba(181,231,160,.08);
    color: #cdd;
    cursor: pointer;
    font: inherit;
    font-size: 10px;
    line-height: 14px;
    font-variant-numeric: tabular-nums;
  }
  .bsx-system-page .health-chip:hover,
  .bsx-system-page .health-chip.is-selected {
    border-color: rgba(79,195,247,.65);
    background: rgba(79,195,247,.10);
  }
  .bsx-system-page .health-chip-k {
    color: #aab;
    text-transform: uppercase;
    letter-spacing: .05em;
    font-weight: 700;
  }
  .bsx-system-page .health-chip.is-warn {
    border-color: rgba(255,214,110,.42);
    background: rgba(255,214,110,.08);
  }
  .bsx-system-page .health-chip.is-bad {
    border-color: rgba(229,115,115,.45);
    background: rgba(229,115,115,.10);
  }
  [data-theme="light"] .bsx-system-page .health-chip {
    border-color: rgba(46,125,50,.45);
    background: rgba(46,125,50,.10);
    color: #1f2933;
  }
  [data-theme="light"] .bsx-system-page .health-chip-k { color: #4a5568; }
  [data-theme="light"] .bsx-system-page .health-chip.is-warn {
    border-color: rgba(245,124,0,.45);
    background: rgba(245,124,0,.12);
  }
  [data-theme="light"] .bsx-system-page .health-chip.is-bad {
    border-color: rgba(198,40,40,.45);
    background: rgba(198,40,40,.10);
  }
  .bsx-system-page .health-card {
    overflow: visible;
  }
  .bsx-system-page .health-card .bsx-card-body {
    height: 236px;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    min-height: 0;
  }
  .bsx-system-page .health-detail {
    flex: 1 1 auto;
    min-height: 0;
    overflow-y: auto;
    border: 1px solid rgba(255,255,255,.08);
    background: rgba(0,0,0,.13);
    border-radius: 4px;
    padding: 8px 10px;
    color: #cdd;
    scrollbar-gutter: stable;
    scrollbar-width: thin;
    scrollbar-color: rgba(255, 255, 255, 0.18) transparent;
  }
  .bsx-system-page .health-detail-title {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 8px;
    margin-bottom: 6px;
    padding-bottom: 6px;
    border-bottom: 1px solid rgba(255,255,255,.07);
    color: #aab;
    font-size: 11px;
    font-weight: 700;
    letter-spacing: .06em;
    text-transform: uppercase;
  }
  .bsx-system-page .health-detail-value {
    color: #b5e7a0;
    font-variant-numeric: tabular-nums;
  }
  .bsx-system-page .health-detail.is-warn .health-detail-value { color: #ffd66e; }
  .bsx-system-page .health-detail.is-bad .health-detail-value { color: #e57373; }
  .bsx-system-page .health-detail-body {
    margin: 0;
    font-size: 12px;
    line-height: 1.4;
    overflow-wrap: anywhere;
    white-space: normal;
  }
  .bsx-system-page .health-detail-list {
    display: grid;
    gap: 5px;
  }
  .bsx-system-page .health-detail-row {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    gap: 8px;
    align-items: baseline;
    padding-bottom: 5px;
    border-bottom: 1px solid rgba(255,255,255,.06);
  }
  .bsx-system-page .health-detail-row:last-child {
    border-bottom: 0;
    padding-bottom: 0;
  }
  .bsx-system-page .health-detail-row-k {
    min-width: 0;
    color: #cdd;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .bsx-system-page .health-detail-row-v {
    color: #b5e7a0;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }
  .bsx-system-page .health-detail-row.is-warn .health-detail-row-v { color: #ffd66e; }
  .bsx-system-page .health-detail-row.is-bad .health-detail-row-v { color: #e57373; }
  .bsx-system-page .health-detail-row-meta {
    grid-column: 1 / -1;
    color: #99a;
    font-size: 11px;
    line-height: 1.25;
  }
  [data-theme="light"] .bsx-system-page .health-detail {
    border-color: rgba(0,0,0,.12);
    background: rgba(0,0,0,.03);
    color: #1f2933;
  }
  [data-theme="light"] .bsx-system-page .health-detail-title { color: #4a5568; }
  [data-theme="light"] .bsx-system-page .health-detail-value { color: #2e7d32; }
  [data-theme="light"] .bsx-system-page .health-detail.is-warn .health-detail-value { color: #b53d00; }
  [data-theme="light"] .bsx-system-page .health-detail.is-bad .health-detail-value { color: #c62828; }
  [data-theme="light"] .bsx-system-page .health-detail-row-k { color: #1f2933; }
  [data-theme="light"] .bsx-system-page .health-detail-row-v { color: #2e7d32; }
  [data-theme="light"] .bsx-system-page .health-detail-row.is-warn .health-detail-row-v { color: #b53d00; }
  [data-theme="light"] .bsx-system-page .health-detail-row.is-bad .health-detail-row-v { color: #c62828; }
  [data-theme="light"] .bsx-system-page .health-detail-row-meta { color: #4a5568; }
  @media (max-width: 1100px) {
    .bsx-system-page .services-status-grid {
      grid-template-columns: 1fr;
    }
  }
  @media (max-width: 1500px) {
    .bsx-system-page .health-card .bsx-card-body {
      height: auto;
      max-height: 236px;
    }
  }

  .bsx-system-page .live-indicator {
    display: inline-flex; align-items: center; gap: 6px;
    flex: 0 0 auto;
    font-size: 12px; line-height: 1.2; color: #99a; font-style: italic; letter-spacing: 0.04em;
  }
  .bsx-system-page .live-indicator.is-warming {
    color: #cdd;
    font-weight: 700;
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

<div id="system-time-toggle" role="group" aria-label="System Status timestamp display">
  <label class="time-toggle-label" for="system-time-local-toggle">
    <input id="system-time-local-toggle" type="checkbox" autocomplete="off">
    <span class="time-toggle-track" aria-hidden="true"></span>
    <span id="system-time-mode-label">UTC</span>
  </label>
</div>

{* ===== Backups (full-width top section, with inline settings) ===== *}
<article class="bsx-card backup-card">
  <header>
    <h3>Backups</h3>
    <form id="backup-settings-form" method="POST" action="?page=admin&action=system" class="backup-form"
          data-status-ready="{if $SYS_STATUS_CACHE.state|default:"" == "fresh"}1{else}0{/if}"
          onsubmit="submitBackupSettingsForm(this); return false;">
      <input type="hidden" name="page"   value="admin">
      <input type="hidden" name="action" value="system">
      <input type="hidden" name="do"     value="update_backup_settings">
      <input type="hidden" name="ctoken" value="{$CTOKEN|escape|default:""}">
      <button type="submit" id="backup-save-btn" class="bsx-btn-sm backup-save-btn" hidden>Save</button>
      <span class="backup-auto-label">Auto Backup</span>
      <label class="backup-toggle">
        <input id="backup-enabled-input" type="checkbox" name="backups_enabled" value="1"
               {if $SYS_BACKUP.enabled}checked{/if}
               onchange="submitBackupSettingsForm(this.form)">
        <span class="bsx-toggle" aria-hidden="true"></span>
        <span id="backup-toggle-text" class="backup-toggle-text">{if $SYS_BACKUP.enabled}Enabled{else}Disabled{/if}</span>
      </label>
      <button type="button" id="backup-run-btn" class="bsx-btn-sm backup-run-btn"
              onclick="runManualBackup(this.form)">Backup Now</button>
      <noscript><button type="submit" class="bsx-btn-sm">Save</button></noscript>
    </form>
  </header>
  <div class="bsx-card-body backup-body">
    <dl class="backup-meta">
      <dt>Last run:</dt>
      <dd id="sys-backup-last-run"
          data-utc-epoch="{if $SYS_BACKUP.last_mtime}{$SYS_BACKUP.last_mtime|escape}{/if}"
          data-time-format="minute">{if $SYS_BACKUP.last_mtime}{$SYS_BACKUP.last_mtime|date_format:"%Y-%m-%d %H:%M UTC"}{else}<em>never</em>{/if}</dd>

      <dt>Size:</dt>
      <dd id="sys-backup-size">{if $SYS_BACKUP.last_size}{($SYS_BACKUP.last_size / 1024 / 1024)|string_format:"%.1f"} MB{else}—{/if}</dd>
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
          <span id="sys-backup-next-time"
                data-utc-text="{$SYS_BACKUP.next_run|escape}"
                data-time-format="minute"
                data-utc-original="UTC{if $SYS_BACKUP.next_day_label} ({$SYS_BACKUP.next_day_label|escape}){/if}">UTC <span class="muted">({$SYS_BACKUP.next_day_label|escape})</span></span>
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

{* ===== Services + pool health ===== *}
<div class="services-status-grid">
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
    <div class="services-right">
      <span class="live-indicator{if $SYS_STATUS_CACHE.state|default:"" != "fresh"} is-stale{/if}{if $SYS_STATUS_CACHE.state|default:"" == "warming"} is-warming{/if}" id="sys-live">
        {if $SYS_STATUS_CACHE.state|default:"" == "warming"}
          warming up
        {elseif $SYS_STATUS_CACHE.state|default:"" == "stale"}
          stale · {$SYS_STATUS_CACHE.age|default:0|escape}s old
        {else}
          live · cached
        {/if}
      </span>
    </div>
  </header>
  <div class="bsx-card-body">
    <div class="services-scroll">
      <table class="services-table">
        <thead><tr><th><button type="button" id="sys-services-sort-state" class="service-sort-btn" aria-pressed="false" data-tooltip="Sort by state">State</button></th><th><button type="button" id="sys-services-sort-name" class="service-sort-btn" aria-pressed="true" data-tooltip="Sort alphabetically">Service</button></th><th class="num">PID</th><th class="num"><button type="button" id="sys-services-sort-cpu" class="service-sort-btn metric-sort-btn" aria-pressed="false" data-tooltip="Sort by highest per-core CPU">Core %</button></th><th class="num"><button type="button" id="sys-services-sort-mb" class="service-sort-btn metric-sort-btn" aria-pressed="false" data-tooltip="Sort by highest RAM">RAM</button></th><th><button type="button" id="sys-services-sort-duration" class="service-sort-btn" aria-pressed="false" data-tooltip="Sort by longest runtime">Duration</button></th><th><button type="button" id="sys-services-sort-since" class="service-sort-btn" aria-pressed="false" data-tooltip="Sort by longest runtime">Up since</button></th></tr></thead>
        <tbody id="sys-tbody-services">
        {section name=s loop=$SYS_SERVICES}
          <tr>
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
            <td>{$SYS_SERVICES[s].label|escape}</td>
            <td class="num">{if $SYS_SERVICES[s].pid}{$SYS_SERVICES[s].pid|escape}{else}—{/if}</td>
            <td class="num">{if $SYS_SERVICES[s].cpu_pct !== ""}{$SYS_SERVICES[s].cpu_pct|escape}{else}—{/if}</td>
            <td class="num">{if $SYS_SERVICES[s].rss_mb !== ""}{$SYS_SERVICES[s].rss_mb|escape}{else}—{/if}</td>
            <td>{if $SYS_SERVICES[s].duration}{$SYS_SERVICES[s].duration|escape}{else}—{/if}</td>
            <td data-utc-epoch="{if $SYS_SERVICES[s].since_ts}{$SYS_SERVICES[s].since_ts|escape}{/if}"
                data-time-format="service">{if $SYS_SERVICES[s].since}{$SYS_SERVICES[s].since|escape}{else}—{/if}</td>
          </tr>
        {/section}
        </tbody>
      </table>
    </div>
  </div>
</article>

<article class="bsx-card health-card">
  <header><h3>Pool Health</h3></header>
  <div class="bsx-card-body">
    <div class="health-row" id="sys-health-row">
      {section name=h loop=$SYS_HEALTH}
        <button type="button"
                class="health-chip health-chip-btn is-{$SYS_HEALTH[h].state|escape}{if $smarty.section.h.first} is-selected{/if}"
                data-health-index="{$smarty.section.h.index}"
                data-health-label="{$SYS_HEALTH[h].label|escape}"
                data-health-value="{$SYS_HEALTH[h].value|escape}"
                data-health-state="{$SYS_HEALTH[h].state|escape}"
                data-health-detail="{$SYS_HEALTH[h].tooltip|escape}"
                data-health-items="{$SYS_HEALTH[h].items_json|escape}">
          <span class="health-chip-k">{$SYS_HEALTH[h].label|escape}</span>
        </button>
      {/section}
    </div>
    <div class="health-detail" id="sys-health-detail">
      <div class="health-detail-title">
        <span id="sys-health-detail-title">
          {section name=h loop=$SYS_HEALTH}{if $smarty.section.h.first}{$SYS_HEALTH[h].label|escape}{/if}{/section}
        </span>
        <span class="health-detail-value" id="sys-health-detail-value">
          {section name=h loop=$SYS_HEALTH}{if $smarty.section.h.first}{$SYS_HEALTH[h].value|escape}{/if}{/section}
        </span>
      </div>
      <div class="health-detail-body" id="sys-health-detail-body"></div>
    </div>
  </div>
</article>
</div>

{* ===== Resources: CPU/Swap · Memory/Network · Disk · DB ===== *}
<div class="grid3 grid4">

  {* ===== CPU + Swap stack (one column in the 3-up resources row) ===== *}
  <div class="cpu-stack">
    <article class="bsx-card">
      <header>
        <h3>CPU</h3>
        <span class="card-stat"><span class="card-stat-k">Cores</span> <span id="sys-cpu-cores" class="card-stat-v">{$SYS_CPU_CORES|escape}</span></span>
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

  <div class="memory-network-stack">
    {* ===== Memory ===== *}
    <article class="bsx-card memory-card">
      <header>
        <h3>Memory</h3>
        <span class="card-stat"><span class="card-stat-k">Available</span> <span id="sys-mem-avail" class="card-stat-v">{$SYS_MEM_AVAIL|escape}</span></span>
      </header>
      <div class="bsx-card-body">
        <p class="resource-io-line">
          <span>R/W <strong id="sys-mem-io-rw">{$SYS_MEMORY_IO_SUMMARY.rw|escape}</strong></span>
          <span>I/O <strong id="sys-mem-io-util">{$SYS_MEMORY_IO_SUMMARY.util|escape}</strong></span>
          <span>Ops <strong id="sys-mem-io-ops">{$SYS_MEMORY_IO_SUMMARY.ops|escape}</strong></span>
        </p>
        <table class="kv-table memory-summary-table">
          <tbody id="sys-tbody-memory">
          {section name=m loop=$SYS_MEMORY}
            <tr>
              <td>{$SYS_MEMORY[m].label|escape}</td>
              <td class="num">{$SYS_MEMORY[m].value|escape}</td>
            </tr>
          {/section}
          </tbody>
        </table>
      </div>
    </article>

    {* ===== Network ===== *}
    <article class="bsx-card network-card">
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

  {* ===== Disk ===== *}
  <article class="bsx-card disk-card">
    <header>
      <h3>Disk</h3>
      <span class="card-stat"><span class="card-stat-k">Available</span> <span id="sys-disk-avail" class="card-stat-v">{$SYS_DISK_AVAIL|escape}</span></span>
    </header>
    <div class="bsx-card-body">
      <p class="resource-io-line">
        <span>R/W <strong id="sys-disk-io-rw">{$SYS_DISK_IO_SUMMARY.rw|escape}</strong></span>
        <span>I/O <strong id="sys-disk-io-util">{$SYS_DISK_IO_SUMMARY.util|escape}</strong></span>
        <span>Ops <strong id="sys-disk-io-ops">{$SYS_DISK_IO_SUMMARY.ops|escape}</strong></span>
      </p>
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

  {* ===== Database ===== *}
  <article class="bsx-card">
    <header>
      <h3>MPOS DB Status</h3>
      <span class="card-stat db-total-stat">
        <span class="card-stat-k">Total</span>
        <span class="card-stat-v db-total-v">
          <span id="sys-db-total-rows">{$SYS_DATABASE.total_rows|escape} rows</span>
          <span id="sys-db-total-size">{$SYS_DATABASE.total_size|escape}</span>
        </span>
      </span>
    </header>
    <div class="bsx-card-body">
      <form id="db-prune-form" method="POST" action="?page=admin&action=system" class="db-prune-form db-prune-toolbar"
            data-status-ready="{if $SYS_STATUS_CACHE.state|default:"" == "fresh"}1{else}0{/if}">
        <input type="hidden" name="page"   value="admin">
        <input type="hidden" name="action" value="system">
        <input type="hidden" name="do"     value="update_db_prune_settings">
        <input type="hidden" name="ctoken" value="{$CTOKEN|escape|default:""}">
        <span class="db-prune-control">
          <span class="card-stat-k">Prune</span>
          <select class="inline-select" name="db_prune_after_days" onchange="submitDbPruneForm(this.form)"{if $SYS_STATUS_CACHE.state|default:"" != "fresh"} disabled{/if}>
            {section name=c loop=$SYS_DATABASE.prune_choices}
              <option value="{$SYS_DATABASE.prune_choices[c].value|escape}"
                {if $SYS_DATABASE.prune_choices[c].value == $SYS_DATABASE.prune_after_days}selected{/if}>
                {$SYS_DATABASE.prune_choices[c].label|escape}
              </option>
            {/section}
          </select>
        </span>
        <span class="db-prune-control">
          <span class="card-stat-k">Archive cap</span>
          <select class="inline-select" name="db_prune_keep_recent_shares" onchange="submitDbPruneForm(this.form)"{if $SYS_STATUS_CACHE.state|default:"" != "fresh"} disabled{/if}>
            {section name=s loop=$SYS_DATABASE.keep_recent_share_choices}
              <option value="{$SYS_DATABASE.keep_recent_share_choices[s].value|escape}"
                {if $SYS_DATABASE.keep_recent_share_choices[s].value == $SYS_DATABASE.keep_recent_shares}selected{/if}>
                {$SYS_DATABASE.keep_recent_share_choices[s].label|escape}
              </option>
            {/section}
          </select>
        </span>
        <noscript><button type="submit" class="bsx-btn-sm">Save</button></noscript>
      </form>
      <table>
        <thead><tr><th>Area</th><th class="num">Rows</th><th class="num">Size</th></tr></thead>
        <tbody id="sys-tbody-db">
        {section name=db loop=$SYS_DATABASE.tables}
          <tr>
            <td>{$SYS_DATABASE.tables[db].label|escape}</td>
            <td class="num">{$SYS_DATABASE.tables[db].rows|escape}</td>
            <td class="num">{$SYS_DATABASE.tables[db].size|escape}</td>
          </tr>
        {/section}
        </tbody>
      </table>
      <div class="footnote db-footnote" id="sys-db-footnote">
        <span class="db-foot-meta">archive cap {$SYS_DATABASE.keep_recent_shares|escape} · oldest {$SYS_DATABASE.archive_oldest|escape} · newest {$SYS_DATABASE.archive_newest|escape} · prune {$SYS_DATABASE.prune_last_run_age|escape}{if $SYS_DATABASE.prune_last_deleted} · deleted {$SYS_DATABASE.prune_last_deleted|escape}{/if}</span>
      </div>
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
            {if $SYS_DAEMONS[d].stale|default:false}
              <span class="pill pill-warn" data-tooltip="{$SYS_DAEMONS[d].stale_detail|escape}">stale</span>
            {elseif $SYS_DAEMONS[d].synced}
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
  var POLL_MS = 60000;
  var URL = '?page=admin&action=system&_partial=1';
  var indicator = document.getElementById('sys-live');
  if (!indicator) return;
  indicator.textContent = 'live · 60s';
  var warmingRetryTimer = null;
  var activeRefreshUntil = 0;
  var tickInFlight = false;
  var localTimeMode = false;

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c];
    });
  }
  function statePill(state) {
    var s = String(state || '').trim();
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
  function normalizeHealthRow(row) {
    row = row || {};
    var state = String(row.state || 'warn');
    if (state !== 'ok' && state !== 'warn' && state !== 'bad') state = 'warn';
    var items = row.items || row.items_json || [];
    if (typeof items === 'string' && items) {
      try {
        items = JSON.parse(items);
      } catch (e) {
        items = [];
      }
    }
    if (!Array.isArray(items)) items = [];
    return {
      label: row.label || 'Health',
      value: row.value || '—',
      state: state,
      tooltip: row.tooltip || row.detail || '',
      items: items
    };
  }
  function healthChip(row, index) {
    row = normalizeHealthRow(row);
    var selected = index === currentHealthIndex ? ' is-selected' : '';
    return '<button type="button" class="health-chip health-chip-btn is-' + esc(row.state) + selected + '" data-health-index="' + esc(index) + '">' +
           '<span class="health-chip-k">' + esc(row.label || 'Health') + '</span>' +
           '</button>';
  }
  function readCurrentHealthRows() {
    var row = document.getElementById('sys-health-row');
    if (!row) return [];
    return Array.prototype.map.call(row.querySelectorAll('.health-chip-btn'), function (btn) {
      return normalizeHealthRow({
        label: btn.getAttribute('data-health-label') || '',
        value: btn.getAttribute('data-health-value') || '',
        state: btn.getAttribute('data-health-state') || '',
        tooltip: btn.getAttribute('data-health-detail') || '',
        items_json: btn.getAttribute('data-health-items') || ''
      });
    });
  }
  function healthDetailItem(item) {
    item = item || {};
    var state = String(item.state || 'ok');
    if (state !== 'ok' && state !== 'warn' && state !== 'bad') state = 'ok';
    var meta = item.meta ? '<div class="health-detail-row-meta">' + esc(item.meta) + '</div>' : '';
    return '<div class="health-detail-row is-' + esc(state) + '">' +
           '<span class="health-detail-row-k">' + esc(item.label || 'Detail') + '</span>' +
           '<span class="health-detail-row-v">' + esc(item.value || '—') + '</span>' +
           meta +
           '</div>';
  }
  function renderHealthDetail(row) {
    row = normalizeHealthRow(row);
    var detail = document.getElementById('sys-health-detail');
    var title = document.getElementById('sys-health-detail-title');
    var value = document.getElementById('sys-health-detail-value');
    var body = document.getElementById('sys-health-detail-body');
    if (detail) {
      detail.classList.remove('is-ok', 'is-warn', 'is-bad');
      detail.classList.add('is-' + row.state);
    }
    if (title) title.textContent = row.label;
    if (value) value.textContent = row.value;
    if (body) {
      if (row.items.length) {
        body.innerHTML = '<div class="health-detail-list">' + row.items.map(healthDetailItem).join('') + '</div>';
      } else {
        body.textContent = row.tooltip || 'No additional detail is available for this status.';
      }
    }
  }
  function renderHealth(rows) {
    latestHealthRows = (rows || []).map(normalizeHealthRow);
    if (currentHealthIndex >= latestHealthRows.length) currentHealthIndex = 0;
    fill('sys-health-row', latestHealthRows.map(healthChip).join(''));
    renderHealthDetail(latestHealthRows[currentHealthIndex] || {});
  }
  var currentOutboxFilter = '';
  var outboxFilterTouched = false;
  var serviceSortMode = 'name';
  var latestServiceRows = readCurrentServiceRows();
  var currentHealthIndex = 0;
  var latestHealthRows = readCurrentHealthRows();

  function readCurrentServiceRows() {
    var tbody = document.getElementById('sys-tbody-services');
    if (!tbody) return [];
    return Array.prototype.map.call(tbody.querySelectorAll('tr'), function (tr) {
      var td = tr.querySelectorAll('td');
      return {
        state: td[0] ? td[0].textContent : '',
        label: td[1] ? td[1].textContent : '',
        pid: td[2] ? td[2].textContent : '',
        cpu_pct: td[3] ? td[3].textContent : '',
        rss_mb: td[4] ? td[4].textContent : '',
        duration: td[5] ? td[5].textContent : '',
        since: td[6] ? td[6].textContent : '',
        since_ts: td[6] ? (td[6].getAttribute('data-utc-epoch') || '') : ''
      };
    });
  }

  function serviceSinceValue(row) {
    var n = parseInt(row && row.since_ts, 10);
    if (!isNaN(n) && n > 0) return n;
    var parsed = Date.parse(row && row.since ? row.since : '');
    return isNaN(parsed) ? 0 : Math.floor(parsed / 1000);
  }

  function durationCompact(seconds) {
    seconds = Math.max(0, Math.floor(seconds || 0));
    var units = [
      { label: 'y', seconds: 31536000 },
      { label: 'mo', seconds: 2592000 },
      { label: 'd', seconds: 86400 },
      { label: 'h', seconds: 3600 },
      { label: 'm', seconds: 60 }
    ];
    var parts = [];
    units.forEach(function (unit) {
      if (parts.length >= 3 || seconds < unit.seconds) return;
      var n = Math.floor(seconds / unit.seconds);
      seconds -= n * unit.seconds;
      parts.push(n + unit.label);
    });
    return parts.length ? parts.join(' ') : 'now';
  }

  function serviceDuration(row) {
    if (row && row.duration) return row.duration;
    var ts = serviceSinceValue(row);
    if (!ts) return '—';
    return durationCompact((Date.now() / 1000) - ts);
  }

  function serviceStateRank(row) {
    var s = String(row && row.state ? row.state : '').trim().toLowerCase();
    if (s === 'failed') return 0;
    if (s === 'activating') return 1;
    if (s === 'inactive') return 2;
    if (s === 'active') return 3;
    return 4;
  }

  function serviceMetricValue(row, key) {
    var n = parseFloat(row && row[key]);
    return isNaN(n) ? -1 : n;
  }

  function sortedServiceRows(rows) {
    return (rows || []).map(function (row, index) {
      return { row: row, index: index };
    }).sort(function (a, b) {
      var an = String(a.row.label || '').toLowerCase();
      var bn = String(b.row.label || '').toLowerCase();
      if (serviceSortMode === 'since_oldest') {
        var ao = serviceSinceValue(a.row) || 9007199254740991;
        var bo = serviceSinceValue(b.row) || 9007199254740991;
        if (ao !== bo) return ao - bo;
      } else if (serviceSortMode === 'since_newest') {
        var ay = serviceSinceValue(a.row) || -1;
        var by = serviceSinceValue(b.row) || -1;
        if (ay !== by) return by - ay;
      } else if (serviceSortMode === 'state') {
        var as = serviceStateRank(a.row);
        var bs = serviceStateRank(b.row);
        if (as !== bs) return as - bs;
      } else if (serviceSortMode === 'cpu_desc') {
        var ac = serviceMetricValue(a.row, 'cpu_pct');
        var bc = serviceMetricValue(b.row, 'cpu_pct');
        if (ac !== bc) return bc - ac;
      } else if (serviceSortMode === 'cpu_asc') {
        var acl = serviceMetricValue(a.row, 'cpu_pct');
        var bcl = serviceMetricValue(b.row, 'cpu_pct');
        if (acl < 0) acl = 9007199254740991;
        if (bcl < 0) bcl = 9007199254740991;
        if (acl !== bcl) return acl - bcl;
      } else if (serviceSortMode === 'rss_desc') {
        var ar = serviceMetricValue(a.row, 'rss_mb');
        var br = serviceMetricValue(b.row, 'rss_mb');
        if (ar !== br) return br - ar;
      } else if (serviceSortMode === 'rss_asc') {
        var arl = serviceMetricValue(a.row, 'rss_mb');
        var brl = serviceMetricValue(b.row, 'rss_mb');
        if (arl < 0) arl = 9007199254740991;
        if (brl < 0) brl = 9007199254740991;
        if (arl !== brl) return arl - brl;
      }
      if (an < bn) return -1;
      if (an > bn) return 1;
      return a.index - b.index;
    }).map(function (item) {
      return item.row;
    });
  }

  function updateServiceSortButtons() {
    var nameBtn = document.getElementById('sys-services-sort-name');
    var stateBtn = document.getElementById('sys-services-sort-state');
    var cpuBtn = document.getElementById('sys-services-sort-cpu');
    var mbBtn = document.getElementById('sys-services-sort-mb');
    var sinceBtn = document.getElementById('sys-services-sort-since');
    var durationBtn = document.getElementById('sys-services-sort-duration');
    if (nameBtn) nameBtn.setAttribute('aria-pressed', serviceSortMode === 'name' ? 'true' : 'false');
    if (stateBtn) stateBtn.setAttribute('aria-pressed', serviceSortMode === 'state' ? 'true' : 'false');
    if (cpuBtn) {
      var cpuSorted = serviceSortMode === 'cpu_desc' || serviceSortMode === 'cpu_asc';
      cpuBtn.setAttribute('aria-pressed', cpuSorted ? 'true' : 'false');
      cpuBtn.setAttribute('data-tooltip', serviceSortMode === 'cpu_desc' ? 'Sort by lowest per-core CPU' : 'Sort by highest per-core CPU');
    }
    if (mbBtn) {
      var rssSorted = serviceSortMode === 'rss_desc' || serviceSortMode === 'rss_asc';
      mbBtn.setAttribute('aria-pressed', rssSorted ? 'true' : 'false');
      mbBtn.setAttribute('data-tooltip', serviceSortMode === 'rss_desc' ? 'Sort by lowest RAM' : 'Sort by highest RAM');
    }
    [sinceBtn, durationBtn].forEach(function (btn) {
      if (!btn) return;
      var sinceMode = serviceSortMode === 'since_oldest' || serviceSortMode === 'since_newest';
      btn.setAttribute('aria-pressed', sinceMode ? 'true' : 'false');
      btn.setAttribute('data-tooltip', serviceSortMode === 'since_oldest' ? 'Sort by shortest runtime' : 'Sort by longest runtime');
    });
  }

  function toggleServiceRuntimeSort() {
    serviceSortMode = serviceSortMode === 'since_oldest' ? 'since_newest' : 'since_oldest';
    renderServiceRows(latestServiceRows);
  }

  function renderServiceRows(rows) {
    latestServiceRows = (rows || []).slice();
    fill('sys-tbody-services', sortedServiceRows(latestServiceRows).map(function (r) {
      var sinceTs = serviceSinceValue(r);
      var sinceText = sinceTs ? formatEpochTime(sinceTs, 'service', localTimeMode) : (r.since || '—');
      return '<tr><td>' + statePill(r.state) + '</td><td>' + esc(r.label) +
             '</td><td class="num">' + esc(r.pid || '—') +
             '</td><td class="num">' + (r.cpu_pct === '' || r.cpu_pct == null ? '—' : esc(r.cpu_pct)) +
             '</td><td class="num">' + (r.rss_mb === '' || r.rss_mb == null ? '—' : esc(r.rss_mb)) +
             '</td><td>' + esc(serviceDuration(r)) +
             '</td><td data-utc-epoch="' + (sinceTs ? esc(sinceTs) : '') + '" data-time-format="service" data-utc-original="' + esc(sinceTs ? formatEpochTime(sinceTs, 'service', false) : (r.since || '—')) + '">' +
             esc(sinceText) + '</td></tr>';
    }).join(''));
    updateServiceSortButtons();
  }

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
    if (d.stale) {
      var tip = d.stale_detail ? ' data-tooltip="' + esc(d.stale_detail) + '"' : '';
      return '<span class="pill pill-warn"' + tip + '>stale</span>';
    }
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

  function scheduleWarmRetry(delayMs, keepAliveMs) {
    if (keepAliveMs) activeRefreshUntil = Math.max(activeRefreshUntil, Date.now() + keepAliveMs);
    if (warmingRetryTimer) clearTimeout(warmingRetryTimer);
    warmingRetryTimer = setTimeout(function () {
      warmingRetryTimer = null;
      tick();
    }, delayMs || 3000);
  }

  function setDbPruneControlsReady(cache) {
    var state = cache && cache.state ? cache.state : 'fresh';
    var ready = state === 'fresh';
    var form = document.getElementById('db-prune-form');
    if (form) {
      form.setAttribute('data-status-ready', ready ? '1' : '0');
      form.setAttribute('data-status-state', state);
      form.classList.toggle('is-control-locked', !ready);
    }
    Array.prototype.forEach.call(document.querySelectorAll('#db-prune-form select'), function (select) {
      select.disabled = !ready;
      select.setAttribute('aria-disabled', ready ? 'false' : 'true');
      if (!ready && document.activeElement === select) select.blur();
    });
  }

  function setBackupControlsReady(cache) {
    var state = cache && cache.state ? cache.state : 'fresh';
    var ready = state === 'fresh';
    var form = document.getElementById('backup-settings-form');
    var enabledInput = document.getElementById('backup-enabled-input');
    var enabledText = document.getElementById('backup-toggle-text');
    if (form) form.setAttribute('data-status-ready', ready ? '1' : '0');
    if (enabledInput) enabledInput.disabled = false;
    var backupBtn = document.getElementById('backup-run-btn');
    if (backupBtn) backupBtn.disabled = false;
    if (enabledText && enabledInput) enabledText.textContent = enabledInput.checked ? 'Enabled' : 'Disabled';
  }

  function pad2(n) {
    return String(n).padStart(2, '0');
  }

  function weekdayShort(day) {
    return ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][day] || '';
  }

  function browserTimeZoneLabel(date) {
    date = date || new Date();
    try {
      var parts = new Intl.DateTimeFormat(undefined, { timeZoneName: 'short' }).formatToParts(date);
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].type === 'timeZoneName' && parts[i].value) return parts[i].value;
      }
    } catch (e) {}
    var offset = -date.getTimezoneOffset();
    var sign = offset >= 0 ? '+' : '-';
    offset = Math.abs(offset);
    return 'GMT' + sign + pad2(Math.floor(offset / 60)) + ':' + pad2(offset % 60);
  }

  function formatEpochTime(epoch, format, useLocal) {
    epoch = Number(epoch || 0);
    if (!epoch) return 'never';
    var d = new Date(epoch * 1000);
    var yyyy = useLocal ? d.getFullYear() : d.getUTCFullYear();
    var mm = pad2((useLocal ? d.getMonth() : d.getUTCMonth()) + 1);
    var dd = pad2(useLocal ? d.getDate() : d.getUTCDate());
    var hh = pad2(useLocal ? d.getHours() : d.getUTCHours());
    var mi = pad2(useLocal ? d.getMinutes() : d.getUTCMinutes());
    var ss = pad2(useLocal ? d.getSeconds() : d.getUTCSeconds());
    var zone = useLocal ? browserTimeZoneLabel(d) : 'UTC';
    if (format === 'service') {
      var day = weekdayShort(useLocal ? d.getDay() : d.getUTCDay());
      return day + ' ' + yyyy + '-' + mm + '-' + dd + ' ' + hh + ':' + mi + ':' + ss + ' ' + zone;
    }
    return yyyy + '-' + mm + '-' + dd + ' ' + hh + ':' + mi + ' ' + zone;
  }

  function parseUtcTextEpoch(text) {
    text = String(text || '').trim();
    var m = text.match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?\s+UTC$/);
    if (m) {
      return Math.floor(Date.UTC(
        parseInt(m[1], 10),
        parseInt(m[2], 10) - 1,
        parseInt(m[3], 10),
        parseInt(m[4], 10),
        parseInt(m[5], 10),
        parseInt(m[6] || '0', 10)
      ) / 1000);
    }
    var parsed = Date.parse(text);
    return isNaN(parsed) ? 0 : Math.floor(parsed / 1000);
  }

  function applyTimestampElement(el) {
    if (!el) return;
    var raw = el.getAttribute('data-utc-epoch') || '';
    var epoch = parseInt(raw, 10);
    if (!epoch) epoch = parseUtcTextEpoch(el.getAttribute('data-utc-text') || '');
    if (!epoch) {
      var original = el.getAttribute('data-utc-original');
      if (original) el.textContent = original;
      return;
    }
    if (!el.getAttribute('data-utc-original')) {
      el.setAttribute('data-utc-original', el.textContent);
    }
    if (localTimeMode) {
      el.textContent = formatEpochTime(epoch, el.getAttribute('data-time-format') || 'minute', true);
    } else {
      var utcOriginal = el.getAttribute('data-utc-original');
      el.textContent = utcOriginal || formatEpochTime(epoch, el.getAttribute('data-time-format') || 'minute', false);
    }
  }

  function refreshTimestampDisplays() {
    Array.prototype.forEach.call(document.querySelectorAll('[data-utc-epoch], [data-utc-text]'), applyTimestampElement);
  }

  function setLocalTimeMode(enabled) {
    localTimeMode = !!enabled;
    var toggle = document.getElementById('system-time-local-toggle');
    var label = document.getElementById('system-time-mode-label');
    if (toggle) toggle.checked = localTimeMode;
    if (label) label.textContent = localTimeMode ? browserTimeZoneLabel(new Date()) : 'UTC';
    refreshTimestampDisplays();
  }

  function installTimeToggle() {
    var control = document.getElementById('system-time-toggle');
    var bar = document.getElementById('secondary_bar');
    if (control && bar && control.parentNode !== bar) bar.appendChild(control);
    var toggle = document.getElementById('system-time-local-toggle');
    if (toggle) {
      toggle.addEventListener('change', function () {
        setLocalTimeMode(toggle.checked);
      });
    }
    setLocalTimeMode(false);
  }

  function formatMb(bytes) {
    bytes = Number(bytes || 0);
    if (!bytes) return '—';
    return (bytes / 1024 / 1024).toFixed(1) + ' MB';
  }

  function renderBackup(data) {
    if (!data) return;
    var enabledInput = document.getElementById('backup-enabled-input');
    var enabledText = document.getElementById('backup-toggle-text');
    var lastRun = document.getElementById('sys-backup-last-run');
    var size = document.getElementById('sys-backup-size');
    if (typeof data.enabled !== 'undefined' && enabledInput) enabledInput.checked = !!Number(data.enabled);
    if (enabledText && enabledInput) enabledText.textContent = enabledInput.checked ? 'Enabled' : 'Disabled';
    if (lastRun && typeof data.last_mtime !== 'undefined') {
      lastRun.setAttribute('data-utc-epoch', Number(data.last_mtime || 0) ? String(data.last_mtime) : '');
      lastRun.setAttribute('data-time-format', 'minute');
      lastRun.setAttribute('data-utc-original', Number(data.last_mtime || 0)
        ? formatEpochTime(data.last_mtime, 'minute', false)
        : 'never');
      applyTimestampElement(lastRun);
    }
    var nextRun = document.getElementById('sys-backup-next-time');
    if (nextRun && typeof data.next_run !== 'undefined') {
      var nextOriginal = 'UTC' + (data.next_day_label ? ' (' + data.next_day_label + ')' : '');
      nextRun.setAttribute('data-utc-text', data.next_run || '');
      nextRun.setAttribute('data-time-format', 'minute');
      nextRun.setAttribute('data-utc-original', nextOriginal);
      applyTimestampElement(nextRun);
    }
    if (size && typeof data.last_size !== 'undefined') size.textContent = formatMb(data.last_size);
    setBackupControlsReady({ state: 'fresh' });
  }

  function refreshCsrfTokens(token) {
    if (!token) return;
    Array.prototype.forEach.call(document.querySelectorAll('input[name="ctoken"]'), function (input) {
      input.value = token;
    });
  }

  function isPlaceholderPayload(data) {
    var state = data && data.cache ? data.cache.state : '';
    if (state !== 'warming' && state !== 'refreshing') return false;
    return !(data.services && data.services.length) &&
           !(data.database && data.database.tables && data.database.tables.length) &&
           !(data.disk && data.disk.length);
  }

  function fetchFreshCsrfToken() {
    return fetch(URL, { credentials: 'same-origin', cache: 'no-store' })
      .then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.json();
      })
      .then(function (data) {
        refreshCsrfTokens(data.csrf_token);
        return data;
      });
  }

  function dbPruneControlsAreReady() {
    var form = document.getElementById('db-prune-form');
    return !!form && form.getAttribute('data-status-ready') === '1';
  }

  ['pointerdown', 'mousedown', 'click', 'focusin', 'keydown'].forEach(function (eventName) {
    document.addEventListener(eventName, function (ev) {
      var select = ev.target && ev.target.closest ? ev.target.closest('#db-prune-form select') : null;
      if (!select || dbPruneControlsAreReady()) return;
      ev.preventDefault();
      ev.stopPropagation();
      select.blur();
    }, true);
  });

  function updateIndicator(cache) {
    cache = cache || {};
    setDbPruneControlsReady(cache);
    setBackupControlsReady(cache);
    if (!indicator) return;
    indicator.classList.remove('is-stale', 'is-warming');
    var state = cache.state || 'fresh';
    var age = Number(cache.age || 0);
    if (state === 'fresh') {
      activeRefreshUntil = 0;
      if (warmingRetryTimer) {
        clearTimeout(warmingRetryTimer);
        warmingRetryTimer = null;
      }
    }
    if (state === 'warming') {
      indicator.classList.add('is-stale', 'is-warming');
      indicator.textContent = cache.message || 'warming up';
      return;
    }
    if (state === 'stale') {
      indicator.classList.add('is-stale');
      indicator.textContent = 'stale · ' + age + 's old';
      return;
    }
    if (state === 'refreshing') {
      indicator.classList.add('is-stale');
      indicator.textContent = 'refreshing · ' + age + 's old';
      return;
    }
    var d = new Date();
    var hh = String(d.getHours()).padStart(2, '0');
    var mm = String(d.getMinutes()).padStart(2, '0');
    var ss = String(d.getSeconds()).padStart(2, '0');
    indicator.textContent = 'live · updated ' + hh + ':' + mm + ':' + ss;
  }

  function render(data) {
    if (!data) return;
    refreshCsrfTokens(data.csrf_token);
    if (isPlaceholderPayload(data)) {
      updateIndicator(data.cache);
      scheduleWarmRetry(3000);
      return;
    }
    if (data.cache && data.cache.state && data.cache.state !== 'fresh') {
      scheduleWarmRetry(3000);
    } else if (Date.now() < activeRefreshUntil) {
      scheduleWarmRetry(3000);
    }
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

    renderBackup(data.backup);

    renderServiceRows(data.services || []);
    renderHealth(data.health || []);

    var cpuRows = data.cpu || [];
    var cpuCores = data.cpu_cores || '—';
    cpuRows = cpuRows.filter(function (r) {
      if (String(r.label || '').toLowerCase() !== 'cores') return true;
      cpuCores = r.value || cpuCores;
      return false;
    });
    var cpuCoresEl = document.getElementById('sys-cpu-cores');
    if (cpuCoresEl) cpuCoresEl.textContent = cpuCores || '—';
    fill('sys-tbody-cpu', cpuRows.map(function (r) {
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
    if (data.memory_io_summary) {
      var memIoRw = document.getElementById('sys-mem-io-rw');
      var memIoUtil = document.getElementById('sys-mem-io-util');
      var memIoOps = document.getElementById('sys-mem-io-ops');
      if (memIoRw) memIoRw.textContent = data.memory_io_summary.rw || '— / —';
      if (memIoUtil) memIoUtil.textContent = data.memory_io_summary.util || '—';
      if (memIoOps) memIoOps.textContent = data.memory_io_summary.ops || '—';
    }
    var diskAvail = document.getElementById('sys-disk-avail');
    if (diskAvail && data.disk_available) diskAvail.textContent = data.disk_available;

    fill('sys-tbody-disk', (data.disk || []).map(function (r) {
      return '<tr><td>' + esc(r.label) +
             '<div class="td-subpath"><code>' + esc(r.path) + '</code> · ' + esc(r.fs || '') + '</div></td>' +
             '<td class="num">' + esc(r.dirsize || '—') +
             '</td><td class="num">' + esc(r.dirpct || '—') +
             '</td></tr>';
    }).join(''));
    if (data.disk_io_summary) {
      var diskIoRw = document.getElementById('sys-disk-io-rw');
      var diskIoUtil = document.getElementById('sys-disk-io-util');
      var diskIoOps = document.getElementById('sys-disk-io-ops');
      if (diskIoRw) diskIoRw.textContent = data.disk_io_summary.rw || '— / —';
      if (diskIoUtil) diskIoUtil.textContent = data.disk_io_summary.util || '—';
      if (diskIoOps) diskIoOps.textContent = data.disk_io_summary.ops || '—';
    }

    if (data.database) {
      fill('sys-tbody-db', (data.database.tables || []).map(function (r) {
        return '<tr><td>' + esc(r.label) + '</td>' +
               '<td class="num">' + esc(r.rows || '—') + '</td>' +
               '<td class="num">' + esc(r.size || '—') + '</td></tr>';
      }).join(''));
      var dbTotalRows = document.getElementById('sys-db-total-rows');
      var dbTotalSize = document.getElementById('sys-db-total-size');
      if (dbTotalRows) dbTotalRows.textContent = (data.database.total_rows || '—') + ' rows';
      if (dbTotalSize) dbTotalSize.textContent = data.database.total_size || '—';
      var dbFoot = document.getElementById('sys-db-footnote');
      if (dbFoot) {
        var deleted = parseInt(data.database.prune_last_deleted, 10);
        dbFoot.innerHTML =
          '<span class="db-foot-meta">archive cap ' + esc(data.database.keep_recent_shares || '—') +
          ' · oldest ' + esc(data.database.archive_oldest || '—') +
          ' · newest ' + esc(data.database.archive_newest || '—') +
          ' · prune ' + esc(data.database.prune_last_run_age || 'never') +
          (!isNaN(deleted) && deleted > 0 ? ' · deleted ' + esc(deleted) : '') +
          '</span>';
      }
    }

    fill('sys-tbody-network', (data.network || []).map(function (r) {
      var tip = r.tooltip ? ' data-tooltip="' + esc(r.tooltip) + '"' : '';
      return '<tr><td>' + esc(r.label) + '</td><td class="num"' + tip + '>' + esc(r.value) + '</td></tr>';
    }).join(''));
    var netMiners = document.getElementById('sys-net-miners');
    if (netMiners && data.network_miners != null) netMiners.textContent = data.network_miners;

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

    updateIndicator(data.cache);
  }

  window.submitDbPruneForm = function (form) {
    if (!form) return;
    if (form.getAttribute('data-status-ready') !== '1') return;
    var fields = new FormData(form);
    fields.set('_ajax', '1');
    setDbPruneControlsReady({ state: 'refreshing' });
    indicator.classList.add('is-pulsing');
    indicator.textContent = 'saving settings';
    fetchFreshCsrfToken()
      .then(function () {
        var ctoken = form.querySelector('input[name="ctoken"]');
        if (ctoken) fields.set('ctoken', ctoken.value);
        return fetch(form.action || '?page=admin&action=system', {
          method: 'POST',
          body: fields,
          credentials: 'same-origin',
          cache: 'no-store',
          headers: {
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest'
          }
        });
      })
      .then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.json();
      })
      .then(function (data) {
        refreshCsrfTokens(data.csrf_token);
        indicator.classList.remove('is-pulsing', 'is-stale');
        indicator.textContent = 'saved · waiting for status refresh';
        scheduleWarmRetry(1000, 30000);
      })
      .catch(function () {
        setDbPruneControlsReady({ state: 'stale' });
        indicator.classList.remove('is-pulsing');
        indicator.classList.add('is-stale');
        indicator.textContent = 'save failed · refresh and retry';
      });
  };

  window.submitBackupSettingsForm = function (form) {
    if (!form) return;
    var fields = new FormData(form);
    fields.set('do', 'update_backup_settings');
    fields.set('_ajax', '1');
    indicator.classList.add('is-pulsing');
    indicator.textContent = 'saving backup settings';
    fetchFreshCsrfToken()
      .then(function () {
        var ctoken = form.querySelector('input[name="ctoken"]');
        if (ctoken) fields.set('ctoken', ctoken.value);
        return fetch(form.action || '?page=admin&action=system', {
          method: 'POST',
          body: fields,
          credentials: 'same-origin',
          cache: 'no-store',
          headers: {
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest'
          }
        });
      })
      .then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.json();
      })
      .then(function (data) {
        refreshCsrfTokens(data.csrf_token);
        if (data.backup) renderBackup(data.backup);
        var saveBtn = document.getElementById('backup-save-btn');
        if (saveBtn) saveBtn.hidden = true;
        indicator.classList.remove('is-pulsing', 'is-stale');
        indicator.textContent = 'saved · waiting for status refresh';
        scheduleWarmRetry(1000, 30000);
      })
      .catch(function () {
        indicator.classList.remove('is-pulsing');
        indicator.classList.add('is-stale');
        indicator.textContent = 'save failed · refresh and retry';
      });
  };

  window.runManualBackup = function (form) {
    if (!form) return;
    var fields = new FormData(form);
    fields.set('do', 'run_backup_now');
    fields.set('_ajax', '1');
    indicator.classList.add('is-pulsing');
    indicator.textContent = 'queuing backup';
    fetchFreshCsrfToken()
      .then(function () {
        var ctoken = form.querySelector('input[name="ctoken"]');
        if (ctoken) fields.set('ctoken', ctoken.value);
        return fetch(form.action || '?page=admin&action=system', {
          method: 'POST',
          body: fields,
          credentials: 'same-origin',
          cache: 'no-store',
          headers: {
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest'
          }
        });
      })
      .then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.json();
      })
      .then(function (data) {
        refreshCsrfTokens(data.csrf_token);
        indicator.classList.remove('is-pulsing', 'is-stale');
        indicator.textContent = data.ok ? 'backup queued' : 'backup failed';
        scheduleWarmRetry(2000, 60000);
      })
      .catch(function () {
        indicator.classList.remove('is-pulsing');
        indicator.classList.add('is-stale');
        indicator.textContent = 'backup failed · refresh and retry';
      });
  };

  document.querySelectorAll('[data-outbox-filter]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      currentOutboxFilter = btn.getAttribute('data-outbox-filter') || 'pending';
      outboxFilterTouched = true;
      applyOutboxFilter(outboxCountsFromButtons());
    });
  });
  applyOutboxFilter(outboxCountsFromButtons());

  var healthRow = document.getElementById('sys-health-row');
  if (healthRow) {
    healthRow.addEventListener('click', function (ev) {
      var btn = ev.target && ev.target.closest ? ev.target.closest('.health-chip-btn') : null;
      if (!btn || !healthRow.contains(btn)) return;
      var idx = parseInt(btn.getAttribute('data-health-index'), 10);
      currentHealthIndex = isNaN(idx) ? 0 : idx;
      renderHealth(latestHealthRows);
    });
  }
  renderHealth(latestHealthRows);

  var serviceSortNameButton = document.getElementById('sys-services-sort-name');
  var serviceSortStateButton = document.getElementById('sys-services-sort-state');
  var serviceSortCpuButton = document.getElementById('sys-services-sort-cpu');
  var serviceSortMbButton = document.getElementById('sys-services-sort-mb');
  var serviceSortSinceButton = document.getElementById('sys-services-sort-since');
  var serviceSortDurationButton = document.getElementById('sys-services-sort-duration');
  if (serviceSortNameButton) {
    serviceSortNameButton.addEventListener('click', function () {
      serviceSortMode = 'name';
      renderServiceRows(latestServiceRows);
    });
  }
  if (serviceSortStateButton) {
    serviceSortStateButton.addEventListener('click', function () {
      serviceSortMode = 'state';
      renderServiceRows(latestServiceRows);
    });
  }
  if (serviceSortCpuButton) {
    serviceSortCpuButton.addEventListener('click', function () {
      serviceSortMode = serviceSortMode === 'cpu_desc' ? 'cpu_asc' : 'cpu_desc';
      renderServiceRows(latestServiceRows);
    });
  }
  if (serviceSortMbButton) {
    serviceSortMbButton.addEventListener('click', function () {
      serviceSortMode = serviceSortMode === 'rss_desc' ? 'rss_asc' : 'rss_desc';
      renderServiceRows(latestServiceRows);
    });
  }
  if (serviceSortSinceButton) {
    serviceSortSinceButton.addEventListener('click', toggleServiceRuntimeSort);
  }
  if (serviceSortDurationButton) {
    serviceSortDurationButton.addEventListener('click', toggleServiceRuntimeSort);
  }
  installTimeToggle();
  renderServiceRows(latestServiceRows);

  function tick() {
    if (tickInFlight) {
      scheduleWarmRetry(1500);
      return;
    }
    tickInFlight = true;
    indicator.classList.add('is-pulsing');
    fetch(URL, { credentials: 'same-origin', cache: 'no-store' })
      .then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.json();
      })
      .then(function (data) {
        tickInFlight = false;
        indicator.classList.remove('is-pulsing');
        render(data);
      })
      .catch(function () {
        tickInFlight = false;
        setDbPruneControlsReady({ state: 'stale' });
        setBackupControlsReady({ state: 'stale' });
        indicator.classList.remove('is-pulsing');
        indicator.classList.add('is-stale');
        indicator.textContent = 'stale · retrying';
        scheduleWarmRetry(5000);
      });
  }

  setInterval(tick, POLL_MS);
})();
</script>
