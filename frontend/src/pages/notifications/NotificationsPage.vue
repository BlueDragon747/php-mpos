<script setup lang="ts">
import { ref, onMounted } from 'vue';
import type { NotificationsInitial, PopupMessage } from './types';

// Replaces the legacy notifications/default.tpl (which was a 595-line
// copy-paste of the Edit Account form). This page only does what its
// name says: configure WHICH events email the user, and show a small
// history of past notifications.
//
// Submit posts (form-encoded) to ?page=account&action=notifications
// with `do=save` + `data[<type>]=1` for each enabled toggle. The
// legacy controller calls $notification->updateSettings() with that
// shape, so we don't need a v2 write API.

const props = defineProps<{
  initial: NotificationsInitial;
}>();

const i = props.initial;

// Local copy of the toggle state — bound to v-model on each toggle so
// the user can flip them before saving. The form's data-bound hidden
// inputs reflect the truthy values into POST.
const settings = ref(i.settings.map((s) => ({ ...s })));

// Pop-ups (auto-fade after 4 s, mirrors the Workers page pattern).
const popups = ref<(PopupMessage & { _id: number; _fading: boolean })[]>([]);
let popupSeq = 0;
function pushPopup(content: string, type: PopupMessage['type'] = 'info') {
  const id = popupSeq++;
  popups.value.push({ content, type, _id: id, _fading: false });
  setTimeout(() => {
    const item = popups.value.find((x) => x._id === id);
    if (item) item._fading = true;
    setTimeout(() => {
      const idx = popups.value.findIndex((x) => x._id === id);
      if (idx !== -1) popups.value.splice(idx, 1);
    }, 400);
  }, 4000);
}
onMounted(() => {
  for (const p of i.popups || []) pushPopup(p.content, p.type);
});

// Format the history row's time — already YYYY-MM-DD HH:MM:SS from
// server, just pass through. Wrapped here in case we want to localise
// later.
function fmtTime(t: string): string {
  return t;
}
</script>

<template>
  <div class="notifications-v2">
    <div class="notifications-grid">
    <!-- SETTINGS card: 5 toggles + Save in header. -->
    <form
      :action="i.formAction"
      method="post"
      class="bsx-form notifications-form"
    >
      <input type="hidden" name="do" value="save">
      <input type="hidden" name="ctoken" :value="i.csrfToken">

      <article class="bsx-card">
        <header>
          <h3>Notification Settings</h3>
          <!-- Pop-ups (fade-out) — centered between title and Save. -->
          <div class="bsx-head-popups" aria-live="polite">
            <span
              v-for="p in popups"
              :key="p._id"
              :class="['bsx-head-popup', `bsx-head-popup-${p.type}`, { 'is-fading': p._fading }]"
              v-text="p.content"
            ></span>
          </div>
          <div class="bsx-card-actions">
            <button type="submit" class="bsx-btn bsx-btn-primary bsx-btn-small">
              Save
            </button>
          </div>
        </header>
        <div class="bsx-card-body settings-list">
          <div
            v-for="s in settings"
            :key="s.type"
            class="setting-row"
          >
            <label class="bsx-toggle-wrap" :for="`n-${s.type}`">
              <!-- Active checkbox: when checked, posts data[<type>]=1.
                   Unchecked checkboxes are omitted from POST, which
                   is what $notification->updateSettings() expects
                   (missing key = inactive). -->
              <input
                :id="`n-${s.type}`"
                type="checkbox"
                :name="`data[${s.type}]`"
                value="1"
                v-model="s.active"
              >
              <span class="bsx-toggle" aria-hidden="true"></span>
            </label>
            <span class="setting-label">{{ s.label }}</span>
          </div>
        </div>
      </article>
    </form>

    <!-- HISTORY card: read-only list of past notifications. -->
    <article class="bsx-card">
      <header><h3>Notification History</h3></header>
      <div class="bsx-card-body history-table-wrap">
        <table class="history-table">
          <thead>
            <tr>
              <th class="th-id">ID</th>
              <th class="th-time">Time</th>
              <th class="th-type">Type</th>
              <th class="th-active">Sent</th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="i.history.length === 0">
              <td colspan="4" class="empty-row">No notifications yet.</td>
            </tr>
            <tr v-for="row in i.history" :key="row.id">
              <td class="td-id">{{ row.id }}</td>
              <td class="td-time">{{ fmtTime(row.time) }}</td>
              <td class="td-type">{{ row.label }}</td>
              <td class="td-active">
                <span :class="['active-dot', row.active ? 'is-yes' : 'is-no']"
                      :title="row.active ? 'Sent' : 'Skipped'"
                      aria-hidden="true"></span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </article>
    </div><!-- /.notifications-grid -->
  </div>
</template>

<style scoped>
.notifications-v2 {
  padding: 1em;
  color: var(--text-primary, #cdd);
  font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
}

/* Two-column layout: Settings (narrow left, ~1fr) + History (wide
   right, ~2fr). Each form/article uses display: contents so its child
   <article> becomes a direct grid item of .notifications-grid.
   Collapses to single column on narrow viewports. */
.notifications-grid {
  display: grid;
  grid-template-columns: minmax(260px, 1fr) minmax(0, 2fr);
  gap: 16px;
  align-items: start;
}
@media (max-width: 900px) {
  .notifications-grid { grid-template-columns: 1fr; }
}

/* Forms become layout-transparent so their child article reads as a
   direct grid child (mirrors Edit Account/Workers). */
.bsx-form { display: contents; }

/* Card chrome — same as Edit Account / Workers / Transactions. */
.bsx-card {
  background: rgba(255,255,255,.03);
  border: 1px solid rgba(255,255,255,.06);
  border-radius: 6px;
  overflow: hidden;
}
.bsx-card header {
  background: rgba(255,255,255,.05);
  padding: 4px 8px;
  border-bottom: 1px solid rgba(255,255,255,.06);
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}
.bsx-card h3 {
  margin: 0;
  font-size: 13px;
  text-transform: uppercase;
  color: #cdd;
  letter-spacing: 0.04em;
}
.bsx-card-actions {
  display: flex;
  align-items: center;
  gap: 6px;
  flex: 0 0 auto;
}
.bsx-card-body { padding: 12px 14px; }

/* Settings list — one row per notification type. Toggle on the left,
   label to its right. Compact rows; no extra borders since the toggle
   group reads naturally as a list. */
.settings-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.setting-row {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 4px 0;
}
.setting-label {
  font-size: 13px;
  color: #cdd;
  letter-spacing: 0.02em;
}

/* Toggle pill — same look as Edit Account / Workers. */
.bsx-toggle-wrap {
  cursor: pointer;
  display: inline-flex;
  align-items: center;
}
.bsx-toggle-wrap input[type=checkbox] {
  position: absolute;
  width: 1px;
  height: 1px;
  margin: -1px;
  padding: 0;
  overflow: hidden;
  clip: rect(0 0 0 0);
  white-space: nowrap;
  border: 0;
}
.bsx-toggle {
  position: relative;
  width: 36px;
  height: 20px;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.10);
  border: 1px solid rgba(255, 255, 255, 0.14);
  transition: background 180ms ease, border-color 180ms ease;
  flex-shrink: 0;
}
.bsx-toggle::after {
  content: '';
  position: absolute;
  top: 2px;
  left: 2px;
  width: 14px;
  height: 14px;
  border-radius: 50%;
  background: #cdd;
  transition: transform 180ms ease, background 180ms ease;
}
.bsx-toggle-wrap input[type=checkbox]:checked + .bsx-toggle {
  background: rgba(79, 195, 247, 0.55);
  border-color: rgba(79, 195, 247, 0.65);
}
.bsx-toggle-wrap input[type=checkbox]:checked + .bsx-toggle::after {
  transform: translateX(16px);
  background: #ffffff;
}
.bsx-toggle-wrap input[type=checkbox]:focus-visible + .bsx-toggle {
  outline: 2px solid rgba(79, 195, 247, 0.7);
  outline-offset: 2px;
}

/* Inline header pop-ups (auto-fade after 4 s). Same pattern as the
   Workers page so the visual treatment is consistent. */
.bsx-head-popups {
  flex: 1 1 auto;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  min-width: 0;
}
.bsx-head-popup {
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.02em;
  padding: 3px 10px;
  border-radius: 999px;
  background: rgba(79, 195, 247, 0.14);
  border: 1px solid rgba(79, 195, 247, 0.45);
  color: #e0f0fa;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 100%;
  transition: opacity 380ms ease, transform 380ms ease;
}
.bsx-head-popup.is-fading {
  opacity: 0;
  transform: translateY(-4px);
  pointer-events: none;
}
.bsx-head-popup-success {
  background: rgba(181, 231, 160, 0.18);
  border-color: rgba(181, 231, 160, 0.55);
  color: #d3f5b8;
}
.bsx-head-popup-errormsg {
  background: rgba(245, 203, 167, 0.18);
  border-color: rgba(245, 203, 167, 0.55);
  color: #f9e3d2;
}

/* History table. */
.history-table-wrap { overflow-x: auto; }
.history-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 12px;
}
.history-table th,
.history-table td {
  padding: 6px 10px;
  text-align: left;
  border-bottom: 1px solid rgba(255,255,255,.05);
  white-space: nowrap;
}
.history-table thead th {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: #99a;
  font-weight: 700;
  background: rgba(255,255,255,0.02);
  border-bottom-color: rgba(255,255,255,0.10);
}
.history-table tbody tr:nth-child(even) td {
  background: rgba(255,255,255,0.015);
}
.history-table tbody tr:last-child td { border-bottom: 0; }
.history-table .empty-row {
  text-align: center;
  opacity: 0.6;
  padding: 14px 0;
}
.td-id, .td-time {
  font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
  font-variant-numeric: tabular-nums;
}
.th-active, .td-active {
  width: 60px;
  text-align: center;
}
.active-dot {
  display: inline-block;
  width: 8px;
  height: 8px;
  border-radius: 50%;
}
.active-dot.is-yes { background: #b5e7a0; box-shadow: 0 0 0 2px rgba(181,231,160,0.18); }
.active-dot.is-no  { background: #555;    box-shadow: 0 0 0 2px rgba(255,255,255,0.06); }

/* Buttons — same as the rest of v2. */
.bsx-btn {
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
  transition: background 150ms ease, border-color 150ms ease;
}
.bsx-btn:hover:not([disabled]) {
  background: rgba(79, 195, 247, 0.20);
  border-color: rgba(79, 195, 247, 0.55);
}
.bsx-btn-primary {
  background: rgba(79, 195, 247, 0.16);
  border-color: rgba(79, 195, 247, 0.45);
  color: #e0f0fa;
}
.bsx-btn-small { padding: 4px 10px; font-size: 12px; }
</style>
