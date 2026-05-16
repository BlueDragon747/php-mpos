<script setup lang="ts">
import { ref, onMounted } from 'vue';
import type { WorkersInitial, PopupMessage } from './types';

// Re-implementation of templates/mpos/account/workers/default.tpl.
// Submit path is unchanged — the form posts (form-encoded) to
// `?page=account&action=workers` and include/pages/account/workers.inc.php
// handles add / update / delete via the `do=` switch. Page reloads,
// pop-ups come back via $_SESSION['POPUP'].

const props = defineProps<{
  initial: WorkersInitial;
}>();

const i = props.initial;

// Local mutable copy of workers — bound to the per-row form inputs so
// the user can edit subname / password and toggle Monitor. The "Update
// All Workers" submit walks this list and posts data[id][...] fields.
const workers = ref(
  i.workers.map((w) => ({
    ...w,
  })),
);

// Add-worker form state. POST to `do=add` reloads the page; on success
// the new row appears in the workers list.
const newSubname = ref('');
const newPassword = ref('');

// kH/s formatter (legacy used `number_format` which adds thousands
// separators with no decimals).
function fmtHashrate(khs: number): string {
  if (!Number.isFinite(khs) || khs <= 0) return '0';
  return Math.round(khs).toLocaleString('en-US');
}
function fmtDifficulty(d: number): string {
  if (!Number.isFinite(d)) return '0.00';
  return d.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

// `data[<id>][monitor]` is omitted from POST when the checkbox is
// unchecked. The legacy template handles this by always rendering
// the checkbox; updateWorkers() reads each row, defaulting monitor=0
// if the key is missing. To keep behaviour identical we don't add
// hidden zero-fields — unchecked = absent = 0 server-side.

// Pop-ups: a local list with auto-fade. Each entry fades out 4 s after
// being pushed (CSS .is-fading transition runs for 380 ms, then the
// item is spliced from the array).
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

// AJAX form submit. The controller's `_ajax=1` branch returns the
// fresh hydration JSON instead of rendering HTML, so we can update
// state in-place without the browser reloading. See workers.inc.php.
async function postFormJson(form: HTMLFormElement): Promise<WorkersInitial | null> {
  const fd = new FormData(form);
  fd.append('_ajax', '1');
  try {
    const res = await fetch(form.action, {
      method: 'POST',
      body: fd,
      credentials: 'same-origin',
    });
    if (!res.ok) {
      pushPopup(`Server error (HTTP ${res.status})`, 'errormsg');
      return null;
    }
    return (await res.json()) as WorkersInitial;
  } catch (err) {
    pushPopup(`Network error: ${(err as Error).message}`, 'errormsg');
    return null;
  }
}

function applyServerState(state: WorkersInitial) {
  workers.value = state.workers.map((w) => ({ ...w }));
  for (const p of state.popups || []) pushPopup(p.content, p.type);
}

async function onAddWorker(e: Event) {
  e.preventDefault();
  const form = e.currentTarget as HTMLFormElement;
  const state = await postFormJson(form);
  if (!state) return;
  applyServerState(state);
  // Clear add-form inputs so the user can add another worker quickly
  // without manually erasing the previous values.
  newSubname.value = '';
  newPassword.value = '';
}

async function onUpdateWorkers(e: Event) {
  e.preventDefault();
  const form = e.currentTarget as HTMLFormElement;
  const state = await postFormJson(form);
  if (!state) return;
  applyServerState(state);
}

// Inline "Are you sure?" state — id of the worker whose delete-X is
// currently in confirm mode (or null when nothing is pending). Only
// one row can be confirming at a time; clicking X on a different row
// just moves the prompt.
const pendingDeleteId = ref<number | null>(null);

function onDeleteClick(e: MouseEvent, id: number) {
  e.preventDefault();
  pendingDeleteId.value = id;
}
function cancelDelete() {
  pendingDeleteId.value = null;
}

// Delete: legacy controller reads $_GET['id'], so we keep this on
// the GET path. The inline "Are you sure?" widget has already been
// confirmed by the time we get here; fetch with _ajax=1 to skip the
// HTML render.
async function onDeleteWorker(id: number) {
  pendingDeleteId.value = null;
  const url = `${i.formAction}&do=delete&id=${id}&_ajax=1`;
  try {
    const res = await fetch(url, { credentials: 'same-origin' });
    if (!res.ok) {
      pushPopup(`Server error (HTTP ${res.status})`, 'errormsg');
      return;
    }
    applyServerState((await res.json()) as WorkersInitial);
  } catch (err) {
    pushPopup(`Network error: ${(err as Error).message}`, 'errormsg');
  }
}
</script>

<template>
  <div class="workers-v2">
    <!-- Pop-ups render inside the Worker Configuration card header
         (between the title and the Update button) instead of at the
         top of the page. See the header block below. -->

    <!-- Two-column layout: Add New Worker (narrow left) + Worker
         Configuration table (wide right). Each form uses display:
         contents so its child <article> becomes a direct grid item
         of .workers-grid. Collapses to single column on narrow
         viewports. -->
    <div class="workers-grid">
      <!-- Add Worker — its own form, posts do=add. Placed first in DOM
           so on narrow viewports it stacks ABOVE the table. -->
      <form
        :action="i.formAction"
        method="post"
        class="bsx-form add-worker-form"
        @submit="onAddWorker"
      >
        <input type="hidden" name="do" value="add">
        <input type="hidden" name="ctoken" :value="i.csrfToken">

        <article class="bsx-card">
          <header>
            <h3>Add New Worker</h3>
            <div class="bsx-card-actions">
              <button type="submit" class="bsx-btn bsx-btn-secondary bsx-btn-small">
                Add
              </button>
            </div>
          </header>
          <div class="bsx-card-body add-worker-row">
            <div class="kv">
              <label for="new-worker-name">Worker Login</label>
              <div class="parent-input">
                <span class="parent-prefix">{{ i.parentUsername }}.</span>
                <input
                  id="new-worker-name"
                  type="text"
                  name="username"
                  v-model="newSubname"
                  size="10"
                  maxlength="20"
                  required
                  placeholder="rig07"
                >
              </div>
            </div>
            <div class="kv">
              <label for="new-worker-pw">Worker Password</label>
              <input
                id="new-worker-pw"
                type="text"
                name="password"
                v-model="newPassword"
                size="10"
                maxlength="20"
                required
                placeholder="x"
              >
            </div>
          </div>
        </article>
      </form>

      <!-- Update All Workers form wraps the table. Rows have
           data[<id>][...] inputs; POST handler iterates. -->
      <form
        id="workers-update-form"
        :action="i.formAction"
        method="post"
        class="bsx-form"
        @submit="onUpdateWorkers"
      >
        <input type="hidden" name="do" value="update">
        <input type="hidden" name="ctoken" :value="i.csrfToken">

        <article class="bsx-card">
          <header>
            <h3>Worker Configuration</h3>
            <!-- Pop-ups (success / error from $_SESSION['POPUP'])
                 sit centered between the title and the action button.
                 They auto-fade after 4 s; see the popups ref logic. -->
            <div class="bsx-head-popups" aria-live="polite">
              <span
                v-for="p in popups"
                :key="p._id"
                :class="['bsx-head-popup', `bsx-head-popup-${p.type}`, { 'is-fading': p._fading }]"
                v-text="p.content"
              ></span>
            </div>
            <div class="bsx-card-actions">
              <button
                form="workers-update-form"
                type="submit"
                class="bsx-btn bsx-btn-primary bsx-btn-small"
              >
                Update All Workers
              </button>
            </div>
          </header>
          <div class="bsx-card-body workers-table-wrap">
            <table class="workers-table">
              <thead>
                <tr>
                  <th class="th-status"></th>
                  <th class="th-name">Worker Login</th>
                  <th class="th-pw">Password</th>
                  <th v-if="!i.disableNotifications" class="th-monitor">Monitor</th>
                  <th class="th-hashrate">Hashrate</th>
                  <th class="th-diff">Difficulty</th>
                  <th class="th-action"></th>
                </tr>
              </thead>
              <tbody>
                <tr v-if="workers.length === 0">
                  <td :colspan="i.disableNotifications ? 6 : 7" class="empty-row">
                    No workers configured. Add one on the right.
                  </td>
                </tr>
                <tr v-for="w in workers" :key="w.id" :class="{ 'is-active': w.isActive }">
                  <td class="td-status">
                    <span :class="['status-dot', w.isActive ? 'is-up' : 'is-down']"
                          :title="w.isActive ? 'Active (shares in last 10 min)' : 'Idle / no recent shares'"
                          aria-hidden="true"></span>
                  </td>
                  <td class="td-name">
                    <span class="parent-prefix">{{ i.parentUsername }}.</span>
                    <input
                      type="text"
                      :name="`data[${w.id}][username]`"
                      v-model="w.subname"
                      maxlength="20"
                      size="10"
                      required
                    >
                  </td>
                  <td class="td-pw">
                    <input
                      type="text"
                      :name="`data[${w.id}][password]`"
                      v-model="w.password"
                      maxlength="20"
                      size="10"
                      required
                    >
                  </td>
                  <td v-if="!i.disableNotifications" class="td-monitor">
                    <label class="bsx-toggle-wrap" :for="`mon-${w.id}`">
                      <input
                        :id="`mon-${w.id}`"
                        type="checkbox"
                        :name="`data[${w.id}][monitor]`"
                        value="1"
                        v-model="w.monitor"
                      >
                      <span class="bsx-toggle" aria-hidden="true"></span>
                    </label>
                  </td>
                  <td class="td-hashrate">{{ fmtHashrate(w.hashrate) }}</td>
                  <td class="td-diff">{{ fmtDifficulty(w.difficulty) }}</td>
                  <td class="td-action">
                    <!-- Delete is a separate GET (do=delete&id=N), not
                         part of the bulk Update form. First click shows
                         an inline Are-You-Sure overlay anchored to the
                         right edge of this 32px cell so it extends left
                         without changing the table layout. -->
                    <template v-if="pendingDeleteId === w.id">
                      <div class="delete-confirm" role="alertdialog" :aria-label="`Confirm delete ${w.username}`">
                        <span class="delete-confirm-text">Are you sure?</span>
                        <button type="button" class="btn-confirm-yes"
                                @click="onDeleteWorker(w.id)">Yes</button>
                        <button type="button" class="btn-confirm-no"
                                @click="cancelDelete">No</button>
                      </div>
                    </template>
                    <a
                      v-else
                      :href="`${i.formAction}&do=delete&id=${w.id}`"
                      class="btn-icon btn-trash"
                      :title="`Delete ${w.username}`"
                      @click="(e) => onDeleteClick(e, w.id)"
                    >
                      ×
                    </a>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </article>
      </form>
    </div><!-- /.workers-grid -->
  </div>
</template>

<style scoped>
.workers-v2 {
  padding: 1em;
  color: var(--text-primary, #cdd);
  font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
  display: flex;
  flex-direction: column;
  gap: 16px;
}

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

.bsx-form { display: contents; }

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

.workers-table-wrap { overflow-x: auto; }
.workers-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
}
.workers-table th,
.workers-table td {
  padding: 6px 8px;
  text-align: left;
  border-bottom: 1px solid rgba(255,255,255,0.05);
}
.workers-table thead th {
  font-size: 13px;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: #99a;
  font-weight: 700;
  background: rgba(255,255,255,0.02);
  border-bottom-color: rgba(255,255,255,0.10);
}
.workers-table tbody tr:last-child td { border-bottom: 0; }
.workers-table tbody tr.is-active .td-name input { color: #b5e7a0; }
.workers-table .empty-row {
  text-align: center;
  opacity: 0.6;
  padding: 14px 0;
}

.th-status, .td-status { width: 24px; text-align: center; padding-left: 4px; padding-right: 0; }
.status-dot {
  display: inline-block;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: #555;
}
.status-dot.is-up   { background: #b5e7a0; box-shadow: 0 0 0 2px rgba(181,231,160,0.18); }
.status-dot.is-down { background: #555;    box-shadow: 0 0 0 2px rgba(255,255,255,0.06); }

.td-name { white-space: nowrap; }
.parent-prefix {
  color: #99a;
  font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
  font-size: 12px;
}
.td-name input,
.td-pw input {
  font: inherit;
  font-size: 12px;
  padding: 3px 6px;
  background: rgba(255,255,255,.04);
  border: 1px solid rgba(255,255,255,.10);
  border-radius: 3px;
  color: #f0f0f0;
  width: 110px;
  font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
}
.td-pw input { width: 130px; }

.th-pw, .td-pw { padding-right: 0; }
.th-monitor, .td-monitor { padding-left: 0; }
.td-pw input { width: 126px; }

.th-hashrate, .td-hashrate,
.th-diff,     .td-diff {
  text-align: right;
  font-variant-numeric: tabular-nums;
}
.td-hashrate, .td-diff {
  font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
  font-size: 12px;
  color: #cdd;
}

.th-monitor, .td-monitor { width: 56px; text-align: center; }

.bsx-toggle-wrap {
  cursor: pointer;
  display: inline-flex;
  align-items: center;
}
.bsx-toggle-wrap:has(input:disabled) { cursor: not-allowed; }
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
  width: 32px;
  height: 18px;
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
  width: 12px;
  height: 12px;
  border-radius: 50%;
  background: #cdd;
  transition: transform 180ms ease, background 180ms ease;
}
.bsx-toggle-wrap input[type=checkbox]:checked + .bsx-toggle {
  background: rgba(79, 195, 247, 0.55);
  border-color: rgba(79, 195, 247, 0.65);
}
.bsx-toggle-wrap input[type=checkbox]:checked + .bsx-toggle::after {
  transform: translateX(14px);
  background: #ffffff;
}
.bsx-toggle-wrap input[type=checkbox]:focus-visible + .bsx-toggle {
  outline: 2px solid rgba(79, 195, 247, 0.7);
  outline-offset: 2px;
}

.th-action, .td-action {
  width: 32px;
  text-align: center;
  padding-right: 4px;
  position: relative;
}
/* Row height placeholder for delete-confirm state. */
.td-action::before {
  content: '';
  display: inline-block;
  vertical-align: middle;
  height: 24px;
}
.btn-icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 22px;
  height: 22px;
  border-radius: 4px;
  border: 1px solid rgba(255, 255, 255, 0.10);
  background: rgba(255, 255, 255, 0.03);
  color: #cdd;
  text-decoration: none;
  font-size: 16px;
  line-height: 1;
  transition: background 150ms ease, border-color 150ms ease, color 150ms ease;
}
.btn-icon:hover {
  background: rgba(245, 203, 167, 0.14);
  border-color: rgba(245, 203, 167, 0.4);
  color: #f5cba7;
}
/* Delete-confirm overlay */
.delete-confirm {
  position: absolute;
  right: 4px;
  top: 50%;
  transform: translateY(-50%);
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 3px 6px;
  border: 1px solid rgba(245, 203, 167, 0.55);
  background: rgba(40, 28, 16, 0.95);
  border-radius: 4px;
  white-space: nowrap;
  font-size: 13px;
  line-height: 1;
  z-index: 4;
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.35);
}
.delete-confirm-text { color: #f5cba7; font-weight: 600; }
.delete-confirm .btn-confirm-yes,
.delete-confirm .btn-confirm-no {
  appearance: none;
  border: 1px solid rgba(255, 255, 255, 0.20);
  background: rgba(255, 255, 255, 0.04);
  color: #cdd;
  font-size: 13px;
  font-weight: 600;
  padding: 2px 8px;
  border-radius: 3px;
  cursor: pointer;
  line-height: 1;
}
.delete-confirm .btn-confirm-yes:hover {
  background: rgba(229, 115, 115, 0.20);
  border-color: rgba(229, 115, 115, 0.55);
  color: #e57373;
}
.delete-confirm .btn-confirm-no:hover {
  background: rgba(79, 195, 247, 0.16);
  border-color: rgba(79, 195, 247, 0.45);
  color: #4fc3f7;
}

.workers-grid {
  display: grid;
  grid-template-columns: minmax(220px, 1fr) minmax(0, 3fr);
  gap: 16px;
  align-items: start;
}
@media (max-width: 900px) {
  .workers-grid { grid-template-columns: 1fr; }
}

.add-worker-row {
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.add-worker-row .kv {
  display: flex;
  flex-direction: column;
  align-items: stretch;
  gap: 4px;
}
.add-worker-row .kv > label {
  text-align: left;
  justify-self: start;
}

.kv {
  display: grid;
  grid-template-columns: 130px minmax(0, 1fr);
  align-items: center;
  gap: 6px 8px;
}
.kv > label {
  font-size: 12px;
  color: #cdd;
  font-weight: 600;
  letter-spacing: 0.02em;
}
.kv input[type=text],
.kv input[type=password] {
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
.parent-input {
  display: flex;
  align-items: center;
  gap: 4px;
  min-width: 0;
}
.parent-input > input { flex: 1 1 auto; min-width: 0; }
.parent-input > .parent-prefix { flex: 0 0 auto; }

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
.bsx-btn[disabled] { opacity: 0.45; cursor: not-allowed; }
.bsx-btn-primary {
  background: rgba(79, 195, 247, 0.16);
  border-color: rgba(79, 195, 247, 0.45);
  color: #e0f0fa;
}
.bsx-btn-secondary {
  background: rgba(245, 203, 167, 0.10);
  border-color: rgba(245, 203, 167, 0.40);
  color: #f9e3d2;
}
.bsx-btn-small { padding: 4px 10px; font-size: 12px; }

.muted { opacity: 0.55; }
</style>
