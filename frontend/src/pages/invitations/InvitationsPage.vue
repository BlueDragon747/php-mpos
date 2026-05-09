<script setup lang="ts">
import { ref, onMounted } from 'vue';
import type { InvitationsInitial, PopupMessage } from './types';

// Replaces account/invitations/default.tpl. Submit posts (form-encoded)
// to ?page=account&action=invitations with `do=sendInvitation` +
// `data[email]` / `data[message]` so $invitation->sendInvitation()
// accepts the request unchanged. Page reloads on submit; popups + the
// fresh invitations list come back through the initial JSON.

const props = defineProps<{
  initial: InvitationsInitial;
}>();

const i = props.initial;

// Form state. Reset to the default suggested message on first paint.
const email = ref('');
const message = ref(i.defaultMessage || '');

// Pop-ups (auto-fade after 4 s — same pattern as Workers / Notifications).
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

function fmtTime(t: string): string {
  return t;
}
</script>

<template>
  <div class="invitations-v2">
    <div class="invitations-grid">

      <!-- LEFT: Send-invitation form. -->
      <form
        :action="i.formAction"
        method="post"
        class="bsx-form"
      >
        <input type="hidden" name="do" value="sendInvitation">
        <input type="hidden" name="ctoken" :value="i.csrfToken">

        <article class="bsx-card">
          <header>
            <h3>Send Invitation</h3>
            <!-- Pop-ups (auto-fade) — centered between title and Send. -->
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
                type="submit"
                class="bsx-btn bsx-btn-primary bsx-btn-small"
                :disabled="i.limitHit || i.invitationsDisabled"
              >
                Send
              </button>
            </div>
          </header>
          <div class="bsx-card-body invite-form-body">
            <div class="kv">
              <label for="invite-email">E-Mail</label>
              <input
                id="invite-email"
                type="email"
                name="data[email]"
                v-model="email"
                maxlength="255"
                required
                placeholder="friend@example.com"
                :disabled="i.limitHit || i.invitationsDisabled"
              >
            </div>
            <div class="kv kv-textarea">
              <label for="invite-message">Message</label>
              <textarea
                id="invite-message"
                name="data[message]"
                v-model="message"
                rows="5"
                :disabled="i.limitHit || i.invitationsDisabled"
              ></textarea>
            </div>
            <p v-if="i.maxCount > 0" class="invite-count">
              <strong>{{ i.sentCount }}</strong>
              <span class="muted">/ {{ i.maxCount }} invitations sent</span>
            </p>
          </div>
        </article>
      </form>

      <!-- RIGHT: Past invitations list. -->
      <article class="bsx-card">
        <header><h3>Past Invitations</h3></header>
        <div class="bsx-card-body invite-table-wrap">
          <table class="invite-table">
            <thead>
              <tr>
                <th class="th-email">E-Mail</th>
                <th class="th-time">Sent</th>
                <th class="th-activated">Activated</th>
              </tr>
            </thead>
            <tbody>
              <tr v-if="i.invitations.length === 0">
                <td colspan="3" class="empty-row">No invitations sent yet.</td>
              </tr>
              <tr v-for="(row, idx) in i.invitations" :key="idx">
                <td class="td-email">{{ row.email }}</td>
                <td class="td-time">{{ fmtTime(row.time) }}</td>
                <td class="td-activated">
                  <span :class="['active-dot', row.isActivated ? 'is-yes' : 'is-no']"
                        :title="row.isActivated ? 'Activated' : 'Pending'"
                        aria-hidden="true"></span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </article>

    </div><!-- /.invitations-grid -->
  </div>
</template>

<style scoped>
.invitations-v2 {
  padding: 1em;
  color: var(--text-primary, #cdd);
  font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
}

/* Two-column layout: form (narrow left) + history table (wide right).
   Same shape as the Workers / Notifications pages. */
.invitations-grid {
  display: grid;
  grid-template-columns: minmax(260px, 1fr) minmax(0, 2fr);
  gap: 16px;
  align-items: start;
}
@media (max-width: 900px) {
  .invitations-grid { grid-template-columns: 1fr; }
}

/* Forms become layout-transparent so their child article reads as a
   direct grid child. */
.bsx-form { display: contents; }

/* Card chrome — same as the rest of v2. */
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

/* Form rows. .kv is label/input pair (label above input on the form
   side since the column is narrow). .kv-textarea has a larger input
   area for the message. */
.invite-form-body { display: flex; flex-direction: column; gap: 12px; }
.kv {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.kv > label {
  font-size: 12px;
  color: #cdd;
  font-weight: 600;
  letter-spacing: 0.02em;
}
.kv input[type=email],
.kv input[type=text] {
  font: inherit;
  font-size: 13px;
  padding: 6px 8px;
  background: rgba(255,255,255,.04);
  border: 1px solid rgba(255,255,255,.10);
  border-radius: 4px;
  color: #f0f0f0;
  width: 100%;
  box-sizing: border-box;
}
.kv textarea {
  font: inherit;
  font-size: 13px;
  padding: 6px 8px;
  background: rgba(255,255,255,.04);
  border: 1px solid rgba(255,255,255,.10);
  border-radius: 4px;
  color: #f0f0f0;
  width: 100%;
  resize: vertical;
  min-height: 100px;
  box-sizing: border-box;
}
.kv input[disabled],
.kv textarea[disabled] {
  opacity: 0.55;
  cursor: not-allowed;
}

.invite-count {
  margin: 4px 0 0;
  font-size: 12px;
  color: #cdd;
  font-variant-numeric: tabular-nums;
}
.invite-count strong { color: #4fc3f7; }
.invite-count .muted { opacity: 0.55; margin-left: 4px; }

/* Inline header pop-ups — same pattern as Workers / Notifications. */
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
.invite-table-wrap { overflow-x: auto; }
.invite-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 12px;
}
.invite-table th,
.invite-table td {
  padding: 6px 10px;
  text-align: left;
  border-bottom: 1px solid rgba(255,255,255,.05);
  white-space: nowrap;
}
.invite-table thead th {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: #99a;
  font-weight: 700;
  background: rgba(255,255,255,0.02);
  border-bottom-color: rgba(255,255,255,0.10);
}
.invite-table tbody tr:nth-child(even) td {
  background: rgba(255,255,255,0.015);
}
.invite-table tbody tr:last-child td { border-bottom: 0; }
.invite-table .empty-row {
  text-align: center;
  opacity: 0.6;
  padding: 14px 0;
}
.td-email {
  font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
}
.td-time {
  font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
  font-variant-numeric: tabular-nums;
}
.th-activated, .td-activated { width: 100px; text-align: center; }
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
.bsx-btn[disabled] { opacity: 0.45; cursor: not-allowed; }
.bsx-btn-primary {
  background: rgba(79, 195, 247, 0.16);
  border-color: rgba(79, 195, 247, 0.45);
  color: #e0f0fa;
}
.bsx-btn-small { padding: 4px 10px; font-size: 12px; }
</style>
