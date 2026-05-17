<div id="bsx-v2-shell" class="monitoring-v2">
  <article class="bsx-card">
    <header><h3>Monitoring</h3></header>
    <div class="bsx-card-body mon-table-wrap">
      <table class="bsx-table mon-table">
        <thead>
          <tr>
            <th class="th-name">Cronjob</th>
            <th class="center">Disabled</th>
            <th class="center">Exit</th>
            <th class="center">Active</th>
            <th class="center">Runtime</th>
            <th class="center">Start</th>
            <th class="center">End</th>
            <th class="th-message">Message</th>
          </tr>
        </thead>
        <tbody>
{foreach $CRONSTATUS as $cron => $data}
          <tr>
            <td class="td-name">{$cron}</td>
  {foreach $data as $name => $event}
            <td class="center">
            {if $event.type == 'okerror'}
              {if $event.value == 0}
                <span class="status-pill ok">OK</span>
              {else}
                <span class="status-pill err">ERROR</span>
              {/if}
            {else if $event.type == 'message'}
              {if $event.value|default:""|trim}
                <span class="msg" :title="{$event.value|escape}">{$event.value}</span>
              {else}
                <span class="muted">&mdash;</span>
              {/if}
            {else if $event.type == 'yesno'}
              <span class="dot {if $event.value == 1}is-yes{else}is-no{/if}"
                    title="{if $event.value == 1}Yes{else}No{/if}"></span>
            {else if $event.type == 'time'}
              {if $event.value > 120}
                <span class="time-bad">{$event.value|default:"0"|number_format:"2"}s</span>
              {else if $event.value > 60}
                <span class="time-warn">{$event.value|default:"0"|number_format:"2"}s</span>
              {else}
                <span class="time-ok">{$event.value|default:"0"|number_format:"2"}s</span>
              {/if}
            {else if $event.type == 'date'}
              {if $event.value|default:0 == 0}
                <span class="muted">&mdash;</span>
              {else if ($smarty.now - 180) > $event.value}
                <span class="time-bad">{$event.value|date_format:"%m/%d %H:%M:%S"}</span>
              {else if ($smarty.now - 120) > $event.value}
                <span class="time-warn">{$event.value|date_format:"%m/%d %H:%M:%S"}</span>
              {else}
                <span class="time-ok">{$event.value|date_format:"%m/%d %H:%M:%S"}</span>
              {/if}
            {else}
              {$event.value|default:""}
            {/if}
            </td>
  {/foreach}
          </tr>
{/foreach}
        </tbody>
      </table>
    </div>
  </article>
</div>

<style>
  /* Page wrapper — same gutter / spacer / sidebar treatment as the
     other admin v2 page. */
  .monitoring-v2 {
    margin: 0 16px 6px 16px;
    padding: 1em;
    color: var(--text-primary, #cdd);
    font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
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

  /* Card chrome — identical to the user-facing v2 pages. */
  .monitoring-v2 .bsx-card {
    background: rgba(255,255,255,.03);
    border: 1px solid rgba(255,255,255,.06);
    border-radius: 6px;
    overflow: hidden;
  }
  .monitoring-v2 .bsx-card header {
    background: rgba(255,255,255,.05);
    padding: 4px 8px;
    border-bottom: 1px solid rgba(255,255,255,.06);
    display: flex;
    align-items: center;
    justify-content: space-between;
  }
  .monitoring-v2 .bsx-card h3 {
    margin: 0;
    font-size: 13px;
    text-transform: uppercase;
    color: #cdd;
    letter-spacing: 0.04em;
  }
  .monitoring-v2 .bsx-card-body { padding: 0; }

  /* Table chrome — same as other v2 tables. */
  .monitoring-v2 .mon-table-wrap { overflow-x: auto; }
  .monitoring-v2 .bsx-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 12px;
  }
  .monitoring-v2 .bsx-table th,
  .monitoring-v2 .bsx-table td {
    padding: 6px 10px;
    text-align: left;
    border-bottom: 1px solid rgba(255,255,255,0.05);
    white-space: nowrap;
  }
  .monitoring-v2 .bsx-table thead th {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: #99a;
    font-weight: 700;
    background: rgba(255,255,255,0.02);
    border-bottom-color: rgba(255,255,255,0.10);
  }
  .monitoring-v2 .bsx-table tbody tr:nth-child(even) td {
    background: rgba(255,255,255,0.015);
  }
  .monitoring-v2 .bsx-table tbody tr:last-child td { border-bottom: 0; }
  .monitoring-v2 .bsx-table .center { text-align: center; }
  .monitoring-v2 .td-name { font-weight: 600; color: #e0f0fa; }

  /* Status pills (OK / ERROR). */
  .monitoring-v2 .status-pill {
    display: inline-block;
    padding: 2px 8px;
    border-radius: 999px;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.04em;
    border: 1px solid transparent;
  }
  .monitoring-v2 .status-pill.ok {
    background: rgba(181, 231, 160, 0.18);
    border-color: rgba(181, 231, 160, 0.45);
    color: #b5e7a0;
  }
  .monitoring-v2 .status-pill.err {
    background: rgba(229, 115, 115, 0.18);
    border-color: rgba(229, 115, 115, 0.45);
    color: #e57373;
  }

  /* Yes/No dot. */
  .monitoring-v2 .dot {
    display: inline-block;
    width: 8px;
    height: 8px;
    border-radius: 50%;
  }
  .monitoring-v2 .dot.is-yes {
    background: #b5e7a0;
    box-shadow: 0 0 0 2px rgba(181,231,160,0.18);
  }
  .monitoring-v2 .dot.is-no {
    background: #555;
    box-shadow: 0 0 0 2px rgba(255,255,255,0.06);
  }

  /* Time values colour-coded by threshold. */
  .monitoring-v2 .time-ok   { color: #b5e7a0; font-variant-numeric: tabular-nums; }
  .monitoring-v2 .time-warn { color: #f5cba7; font-variant-numeric: tabular-nums; }
  .monitoring-v2 .time-bad  { color: #e57373; font-variant-numeric: tabular-nums; }

  .monitoring-v2 .msg {
    font-style: italic;
    color: #cdd;
    /* Truncate long messages so the table stays readable; the
       title attribute still shows the full text on hover. */
    display: inline-block;
    max-width: 320px;
    overflow: hidden;
    text-overflow: ellipsis;
    vertical-align: middle;
  }
  .monitoring-v2 .muted { opacity: 0.45; }
  .monitoring-v2 .th-message,
  .monitoring-v2 .td-message { white-space: normal; }

  /* Light-mode overrides — scoped to [data-theme="light"]. */
  [data-theme="light"] .monitoring-v2 .bsx-card {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] .monitoring-v2 .bsx-card header {
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] .monitoring-v2 .bsx-card h3 { color: #1f2933; }
  [data-theme="light"] .monitoring-v2 .bsx-table thead th {
    color: #4a5568;
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] .monitoring-v2 .bsx-table th,
  [data-theme="light"] .monitoring-v2 .bsx-table td {
    border-bottom-color: rgba(0, 0, 0, 0.06);
    color: #2d3748;
  }
  [data-theme="light"] .monitoring-v2 .bsx-table tbody tr:nth-child(even) td {
    background: rgba(0,0,0,0.02);
  }
  [data-theme="light"] .monitoring-v2 .td-name { color: #0d47a1; }
  [data-theme="light"] .monitoring-v2 .status-pill.ok {
    background: rgba(46, 125, 50, 0.18);
    border-color: rgba(46, 125, 50, 0.45);
    color: #1b5e20;
  }
  [data-theme="light"] .monitoring-v2 .status-pill.err {
    background: rgba(198, 40, 40, 0.16);
    border-color: rgba(198, 40, 40, 0.45);
    color: #b71c1c;
  }
  [data-theme="light"] .monitoring-v2 .dot.is-no { background: #ccc; }
  [data-theme="light"] .monitoring-v2 .time-ok   { color: #2e7d32; }
  [data-theme="light"] .monitoring-v2 .time-warn { color: #b53d00; }
  [data-theme="light"] .monitoring-v2 .time-bad  { color: #c62828; }
  [data-theme="light"] .monitoring-v2 .msg { color: #2d3748; }
</style>
