<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import type { CoinSlotState, EditAccountInitial, PopupMessage } from './types';

// Re-implementation of legacy templates/mpos/account/edit/default.tpl as a
// Vue 3 + TS component. The submit path is unchanged — every form posts
// (form-encoded) to the same `?page=account&action=edit` URL the legacy
// page uses, so include/pages/account/edit.inc.php handles validation,
// CSRF check, 2FA gating, and User->update*() exactly as before. The
// page reloads on submit; the controller writes pop-ups to $_SESSION,
// then default.tpl re-renders with the updated $GLOBAL.userdata which
// the v2 wrapper hydrates back into us via data-initial.

const props = defineProps<{
  initial: EditAccountInitial;
}>();

const i = props.initial;

// Cached computed gates (cleaner than inlining the 2FA conditional in
// every disabled binding).
const detailsLocked = computed(() =>
  i.twoFactor.enabled && i.twoFactor.details && !i.twoFactor.detailsUnlocked,
);
const passwordLocked = computed(() =>
  i.twoFactor.enabled && i.twoFactor.changepw && !i.twoFactor.changepwUnlocked,
);
const withdrawLocked = computed(() =>
  i.twoFactor.enabled && i.twoFactor.withdraw && !i.twoFactor.withdrawUnlocked,
);

// Donation % UI lower bound. The pool config ships a
// `donate_threshold.min` (historically used to prevent users from
// disabling donations); we explicitly allow 0 so users can opt out.
// PHP still validates the saved value against config on submit.
const donateMin = computed(() => 0);

// Address-type classifier — mirrors Eliopool's _classify_addr_string
// (deploy-bundle/dashboard/dashboard.py:342-363). Shape-based, so it
// works without per-coin version-byte decoding. Empty input returns
// '' so the pill hides; anything else returns one of the four kinds.
type AddrKind = 'bech32' | 'p2sh' | 'legacy' | 'none' | '';
function classifyAddress(addr: string): AddrKind {
  const a = (addr || '').trim();
  if (!a) return '';
  if (a === a.toLowerCase() && a.includes('1')) {
    const idx = a.indexOf('1');
    const hrp = a.slice(0, idx);
    const rest = a.slice(idx + 1);
    const charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
    if (hrp.length >= 1 && rest.length >= 6 &&
        [...rest].every(c => charset.includes(c))) {
      return 'bech32';
    }
  }
  if (a.length < 26 || a.length > 62) return 'none';
  if (a.startsWith('3') || a.startsWith('q')) return 'p2sh';
  return 'legacy';
}
const ADDR_TYPE_TOOLTIP: Record<AddrKind, string> = {
  bech32: 'Native SegWit (BIP173)',
  p2sh:   'Wrapped SegWit (P2SH-P2WPKH)',
  legacy: 'Legacy Base58 with version byte',
  none:   'Address not recognised',
  '':     '',
};

function handleCoinIconError(event: Event, fallbackUrl: string): void {
  const img = event.target as HTMLImageElement | null;
  if (!img) return;
  if (fallbackUrl && img.dataset.fallbackApplied !== '1') {
    img.dataset.fallbackApplied = '1';
    img.src = fallbackUrl;
    return;
  }
  img.style.display = 'none';
}

// Form models. We seed from initial state but let the user edit freely.
const form = ref({
  email: i.email,
  donatePercent: String(i.donatePercent),
  isAnonymous: i.isAnonymous,
  // Per-coin maps keyed by slot.key for v-model on the inputs.
  coinAddress: Object.fromEntries(i.coins.map(c => [c.key, c.address])) as Record<string, string>,
  coinThreshold: Object.fromEntries(i.coins.map(c => [c.key, String(c.threshold)])) as Record<string, string>,
  // Per-coin Cash Out PIN map. Used to gate the Cash Out button so
  // it only enables once the user has typed exactly 4 numeric digits.
  cashOutPin: Object.fromEntries(i.coins.map(c => [c.key, ''])) as Record<string, string>,
});

// Snapshot of the initial form state. Used to decide whether the
// "Update Account" button glows amber: if any field that posts via
// form="account-details-form" diverges from its pristine value, the
// account section is "dirty" and the user has unsaved changes.
const initialAccount = {
  email: i.email,
  donatePercent: String(i.donatePercent),
  isAnonymous: i.isAnonymous,
  coinAddress: { ...Object.fromEntries(i.coins.map(c => [c.key, c.address])) } as Record<string, string>,
  coinThreshold: { ...Object.fromEntries(i.coins.map(c => [c.key, String(c.threshold)])) } as Record<string, string>,
};
// Numeric compare: <input type="number"> v-models flip the bound
// value's type from "string" (our String(...) seed) to "number" the
// first time the user touches the field, so `"50" !== 50` would
// otherwise keep the button glowing even after a revert. NaN === NaN
// is treated as equal so both-empty fields don't read as dirty.
function numEqual(a: unknown, b: unknown): boolean {
  const na = Number(a), nb = Number(b);
  if (Number.isNaN(na) && Number.isNaN(nb)) return true;
  return na === nb;
}
function coinHasAddress(coin: CoinSlotState): boolean {
  return String(form.value.coinAddress[coin.key] || '').trim() !== '';
}
function thresholdInputMin(coin: CoinSlotState): number {
  const value = Number(form.value.coinThreshold[coin.key]);
  // A threshold of 0 only disables auto payout while this coin has no
  // payout address. Once an address exists, this same coin must carry
  // a real threshold; other coin cards remain independent.
  if (coinHasAddress(coin)) return coin.thresholdMin;
  return Number.isFinite(value) && value !== 0 ? coin.thresholdMin : 0;
}
const accountDirty = computed(() => {
  const f = form.value;
  if (f.email !== initialAccount.email) return true;
  if (!numEqual(f.donatePercent, initialAccount.donatePercent)) return true;
  if (f.isAnonymous !== initialAccount.isAnonymous) return true;
  for (const k of Object.keys(initialAccount.coinAddress)) {
    if (f.coinAddress[k] !== initialAccount.coinAddress[k]) return true;
    if (!numEqual(f.coinThreshold[k], initialAccount.coinThreshold[k])) return true;
  }
  return false;
});

function pinReady(coinKey: string): boolean {
  return /^\d{4}$/.test(form.value.cashOutPin[coinKey] || '');
}

type PendingPayout = {
  active: boolean;
  requestedAt: string | null;
  txid: string | null;
  amount: string | null;
  kind: 'manual' | 'auto' | null;
};

type CashOutQuote = {
  coin: string;
  currency: string;
  address: string;
  amount: string;
  fee: string;
  sendAmount: string;
};

function pendingLabel(kind: 'manual' | 'auto' | null | undefined): string {
  if (kind === 'auto')   return 'Auto - Pending payout';
  if (kind === 'manual') return 'Manual - Pending payout';
  return 'Pending payout';
}

// Trim seconds off "YYYY-MM-DD HH:MM:SS" for the inline-details readout.
function fmtRequestedAt(s: string | null | undefined): string {
  if (!s) return '—';
  return s.slice(0, 16).replace('T', ' ');
}

const pendingPayout = ref<Record<string, PendingPayout>>(
  Object.fromEntries(i.coins.map(c => [c.key, { ...c.pendingPayout }])) as Record<string, PendingPayout>
);

type BodyView = 'fields' | 'msg' | 'details' | 'quote';
const bodyView = ref<Record<string, BodyView>>(
  Object.fromEntries(i.coins.map(c => [c.key, 'fields' as BodyView])) as Record<string, BodyView>
);
function setBodyView(coinKey: string, view: BodyView) {
  bodyView.value = { ...bodyView.value, [coinKey]: view };
}

const AUTO_DISMISS_MS = 4000;
const popups = ref<PopupMessage[]>([...i.popups]);
const dismissedCoinPopups = ref<Set<string>>(new Set());

function cashOutPopupForCoin(coinKey: string) {
  if (dismissedCoinPopups.value.has(coinKey)) return null;
  // Reverse-walk: AJAX appends, so the freshest popup for this coin is the last match.
  for (let idx = popups.value.length - 1; idx >= 0; idx--) {
    if (popups.value[idx].coin === coinKey) return popups.value[idx];
  }
  return null;
}
function dismissCoinPopup(coinKey: string) {
  const next = new Set(dismissedCoinPopups.value);
  next.add(coinKey);
  dismissedCoinPopups.value = next;
  if (bodyView.value[coinKey] === 'msg') setBodyView(coinKey, 'fields');
}
function scheduleAutoDismiss(coinKey: string, type: PopupMessage['type']) {
  // Success popups stay until the pending-payout label is opened;
  // errors / info auto-flip back.
  if (type === 'success') return;
  window.setTimeout(() => dismissCoinPopup(coinKey), AUTO_DISMISS_MS);
}
onMounted(() => {
  for (const p of popups.value) {
    if (p.coin) {
      setBodyView(p.coin, 'msg');
      scheduleAutoDismiss(p.coin, p.type);
    }
  }
});

const cashOutQuote = ref<CashOutQuote | null>(null);
const cashOutQuoteForm = ref<HTMLFormElement | null>(null);
const cashOutQuoteAction = ref('');
const cashOutQuoteBusy = ref<string | null>(null);
const cashOutSendBusy = ref(false);

function quoteForCoin(coinKey: string): CashOutQuote | null {
  return cashOutQuote.value?.coin === coinKey ? cashOutQuote.value : null;
}

function cashOutAjaxUrl(): string {
  return i.formAction + (i.formAction.includes('?') ? '&' : '?') + '_ajax=1';
}

function quoteAction(action: string): string {
  return action.replace(/^cashOut/, 'quoteCashOut');
}

function handleCashOutPopups(data: { popups?: PopupMessage[] }, coinKey: string): boolean {
  let success = false;
  if (Array.isArray(data.popups)) {
    for (const p of data.popups) {
      popups.value.push(p);
      if (p.coin) {
        if (p.type === 'success') {
          success = true;
          pendingPayout.value = {
            ...pendingPayout.value,
            [p.coin]: {
              active: true,
              requestedAt: new Date().toISOString().slice(0, 19).replace('T', ' '),
              txid: null,
              amount: null,
              kind: 'manual',
            },
          };
        }
        setBodyView(p.coin, 'msg');
        scheduleAutoDismiss(p.coin, p.type);
      }
    }
  }
  if (!success && (!data.popups || data.popups.length === 0)) {
    setBodyView(coinKey, 'fields');
  }
  return success;
}

async function submitCashOut(coinKey: string, ev: Event) {
  ev.preventDefault();
  const formEl = ev.target as HTMLFormElement;
  const fd = new FormData(formEl);
  const action = String(fd.get('do') || '');
  fd.set('do', quoteAction(action));
  if (dismissedCoinPopups.value.has(coinKey)) {
    const next = new Set(dismissedCoinPopups.value);
    next.delete(coinKey);
    dismissedCoinPopups.value = next;
  }
  cashOutQuoteBusy.value = coinKey;
  try {
    const res = await fetch(cashOutAjaxUrl(), { method: 'POST', body: fd, credentials: 'same-origin' });
    const data = await res.json() as { popups?: PopupMessage[]; quote?: CashOutQuote };
    handleCashOutPopups(data, coinKey);
    if (data.quote) {
      cashOutQuote.value = data.quote;
      cashOutQuoteForm.value = formEl;
      cashOutQuoteAction.value = action;
      setBodyView(coinKey, 'quote');
    }
  } catch (err) {
    popups.value.push({
      content: 'Cash out request failed; please retry.',
      type: 'errormsg',
      coin: coinKey,
    });
    setBodyView(coinKey, 'msg');
    scheduleAutoDismiss(coinKey, 'errormsg');
  } finally {
    cashOutQuoteBusy.value = null;
  }
}

function cancelCashOutQuote() {
  const coinKey = cashOutQuote.value?.coin || '';
  cashOutQuote.value = null;
  cashOutQuoteAction.value = '';
  const formEl = cashOutQuoteForm.value;
  cashOutQuoteForm.value = null;
  if (coinKey) setBodyView(coinKey, 'fields');
  if (coinKey) formEl?.querySelector<HTMLInputElement>('input[name="authPin"]')?.focus();
}

async function sendQuotedCashOut() {
  const quote = cashOutQuote.value;
  const formEl = cashOutQuoteForm.value;
  if (!quote || !formEl || !cashOutQuoteAction.value) return;

  const fd = new FormData(formEl);
  fd.set('do', cashOutQuoteAction.value);
  cashOutSendBusy.value = true;
  try {
    const res = await fetch(cashOutAjaxUrl(), { method: 'POST', body: fd, credentials: 'same-origin' });
    const data = await res.json() as { popups?: PopupMessage[] };
    const success = handleCashOutPopups(data, quote.coin);
    if (success) {
      cashOutQuote.value = null;
      cashOutQuoteAction.value = '';
      cashOutQuoteForm.value = null;
      formEl.reset();
      form.value.cashOutPin[quote.coin] = '';
    }
  } catch (err) {
    popups.value.push({
      content: 'Cash out request failed; please retry.',
      type: 'errormsg',
      coin: quote.coin,
    });
    setBodyView(quote.coin, 'msg');
    scheduleAutoDismiss(quote.coin, 'errormsg');
  } finally {
    cashOutSendBusy.value = false;
  }
}

const topPopups = computed(() => popups.value.filter(p => !p.coin));

// Live password strength display (legacy template referenced #pw_strength
// + #pw_match but the JS that drove it isn't in the v2 bundle, so the
// numbers were always blank). We provide a minimal port: length + char
// classes -> 0..5 score. Server-side strength rules unchanged.
const newPassword = ref('');
const newPassword2 = ref('');
const pwStrength = computed(() => {
  const p = newPassword.value;
  if (p.length === 0) return null;
  let score = 0;
  if (p.length >= 8) score++;
  if (p.length >= 12) score++;
  if (/[a-z]/.test(p) && /[A-Z]/.test(p)) score++;
  if (/\d/.test(p)) score++;
  if (/[^A-Za-z0-9]/.test(p)) score++;
  return score; // 0..5
});
const pwStrengthLabel = computed(() => {
  const s = pwStrength.value;
  if (s === null) return '';
  return ['Very weak', 'Weak', 'Fair', 'Good', 'Strong', 'Very strong'][s] ?? '';
});
const pwMatch = computed(() => {
  if (newPassword.value === '' && newPassword2.value === '') return null;
  return newPassword.value === newPassword2.value;
});

// API key click-to-copy. `navigator.clipboard` is only exposed in
// secure contexts (HTTPS / localhost). On plain http:// it's
// undefined, so we fall back to the legacy hidden-textarea +
// execCommand('copy') trick.
const apiKeyCopied = ref(false);
async function copyApiKey() {
  let ok = false;
  if (window.isSecureContext && navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(i.apiKey);
      ok = true;
    } catch {
      // browser blocked the secure-context path; fall through to legacy
    }
  }
  if (!ok) {
    const ta = document.createElement('textarea');
    ta.value = i.apiKey;
    ta.setAttribute('readonly', '');
    ta.style.position = 'fixed';
    ta.style.left = '-9999px';
    ta.style.top = '0';
    document.body.appendChild(ta);
    ta.select();
    try { ok = document.execCommand('copy'); } catch { ok = false; }
    document.body.removeChild(ta);
  }
  if (ok) {
    apiKeyCopied.value = true;
    setTimeout(() => { apiKeyCopied.value = false; }, 1500);
  }
}
</script>

<template>
  <div class="account-edit-v2">
    <!-- POPUPS — top of page; mirror legacy layout/colour conventions.
         Per-coin cashOut successes are filtered out here and rendered
         inline on the matching payout card body further down. -->
    <div v-if="topPopups.length" class="bsx-popups">
      <p
        v-for="(p, idx) in topPopups"
        :key="idx"
        :class="['bsx-popup', `bsx-popup-${p.type}`]"
        v-text="p.content"
      ></p>
    </div>

    <!-- SECTION 1 — Account.
         Top: Account Information + Account Details (2-up).
         Bottom: Account Actions row (Confirm + Change Password + Reset PIN, 3-up).

         The Account Details <form> wraps only the Info+Details grid here.
         Per-coin inputs in Section 2, plus the Confirm card's PIN/Save in
         this section, all reference the form via the HTML5 `form="…"`
         attribute, so submit still posts every editable field together. -->
    <section class="bsx-section">
      <header class="bsx-section-head bsx-section-head-row">
        <h2>Account</h2>
        <!-- Update Account controls promoted into the section header.
             The PIN input and submit button both use form="account-
             details-form" so they post the (legally far-away) Account
             Information + Account Details fields when clicked. -->
        <div class="bsx-section-actions">
          <input
            id="authPinDetails"
            form="account-details-form"
            type="password"
            name="authPin"
            placeholder="PIN"
            title="4-digit Account PIN. Use Reset PIN below if you forgot it."
            :disabled="detailsLocked"
            maxlength="4"
            size="4"
            autocomplete="current-password"
            required
            class="bsx-pin-input"
          >
          <template v-if="i.twoFactor.enabled && i.twoFactor.details">
            <button
              v-if="!i.twoFactor.detailsSent && !i.twoFactor.detailsUnlocked"
              form="account-details-form"
              type="submit"
              name="unlock"
              value="1"
              class="bsx-btn bsx-btn-secondary bsx-btn-small"
            >
              Unlock by E-mail
            </button>
            <button
              v-else
              form="account-details-form"
              type="submit"
              :class="['bsx-btn', 'bsx-btn-primary', 'bsx-btn-small', { 'bsx-btn-dirty': accountDirty }]"
              :disabled="!i.twoFactor.detailsUnlocked"
            >
              Update Account
            </button>
          </template>
          <button
            v-else
            form="account-details-form"
            type="submit"
            :class="['bsx-btn', 'bsx-btn-primary', 'bsx-btn-small', { 'bsx-btn-dirty': accountDirty }]"
          >
            Update Account
          </button>
        </div>
      </header>

      <form
        id="account-details-form"
        :action="i.formAction"
        method="post"
        class="bsx-form"
      >
        <input type="hidden" name="do" value="updateAccount">
        <input type="hidden" name="ctoken" :value="i.csrfToken">
        <input type="hidden" name="utype" value="account_edit">
        <input v-if="i.twoFactor.enabled" type="hidden" name="ea_token" :value="i.twoFactor.eaToken">
        <!-- Always send is_anonymous=0 first; the checkbox below overrides
             with 1 when checked. HTML omits unchecked boxes from POST,
             so without this NOT NULL accounts.is_anonymous would explode. -->
        <input type="hidden" name="is_anonymous" value="0">

        <div class="bsx-section-grid bsx-section-grid-2">
          <!-- Account Information (read-only). -->
          <article class="bsx-card">
            <header><h3>Account Information</h3></header>
            <div class="bsx-card-body">
              <div class="kv-row">
                <div class="kv">
                  <label>Username</label>
                  <input type="text" :value="i.username" disabled>
                </div>
                <div class="kv">
                  <label>ID</label>
                  <input type="text" :value="i.userId" disabled>
                </div>
              </div>
              <div v-if="i.apiKeyEnabled" class="kv">
                <label>API Key</label>
                <div class="api-key-row">
                  <input type="text" :value="i.apiKey" disabled>
                  <button type="button" class="bsx-btn bsx-btn-ghost" @click="copyApiKey">
                    {{ apiKeyCopied ? 'Copied' : 'Copy' }}
                  </button>
                </div>
              </div>
            </div>
          </article>

          <!-- Account Details (email / donation / anonymous toggle). -->
          <article class="bsx-card">
            <header><h3>Account Details</h3></header>
            <div class="bsx-card-body">
              <div class="kv-row">
                <div class="kv">
                  <label for="email">Email</label>
                  <input
                    id="email"
                    type="email"
                    name="email"
                    v-model="form.email"
                    :disabled="detailsLocked"
                    maxlength="255"
                  >
                </div>
                <div class="kv">
                  <label for="donatePercent">Donation %</label>
                  <!-- Smaller input + hint inline to its right so the
                       cell height stays the same as Email's, keeping the
                       toggle row aligned with API Key in Account Info. -->
                  <div class="kv-input-with-hint">
                    <input
                      id="donatePercent"
                      class="kv-input-narrow"
                      type="number"
                      name="donatePercent"
                      v-model="form.donatePercent"
                      :min="donateMin"
                      max="100"
                      step="0.01"
                      :disabled="detailsLocked"
                    >
                    <small class="kv-hint">Minimum 0%, max 100%.</small>
                  </div>
                </div>
              </div>
              <!-- Toggle group: only the toggle pill is clickable; the
                   label text alongside is not a click target (deliberate
                   so users don't fat-finger the toggle by clicking the
                   row). The native checkbox is visually hidden inside
                   the <label>, which still associates it semantically. -->
              <div class="kv-checkbox">
                <label class="bsx-toggle-wrap" for="is-anonymous-toggle">
                  <input
                    id="is-anonymous-toggle"
                    type="checkbox"
                    name="is_anonymous"
                    value="1"
                    v-model="form.isAnonymous"
                    :disabled="detailsLocked"
                    aria-labelledby="is-anonymous-text"
                  >
                  <span class="bsx-toggle" aria-hidden="true"></span>
                </label>
                <span id="is-anonymous-text" class="kv-checkbox-text">
                  Hide me from public stats (anonymous mode)
                </span>
              </div>
            </div>
          </article>
        </div>
      </form>

      <!-- ACCOUNT ACTIONS row inside Section 1 (2-up: Change PW | Reset PIN).
           The "Confirm" card collapsed into the section header above,
           which now hosts the Account PIN + Update Account button. -->
      <div class="bsx-section-grid bsx-section-grid-2 bsx-actions-row">

        <!-- CHANGE PASSWORD (do=updatePassword) — own form, own card. -->
        <form :action="i.formAction" method="post" class="bsx-form">
          <input type="hidden" name="do" value="updatePassword">
          <input type="hidden" name="ctoken" :value="i.csrfToken">
          <input type="hidden" name="utype" value="change_pw">
          <input v-if="i.twoFactor.enabled" type="hidden" name="cp_token" :value="i.twoFactor.cpToken">

          <article class="bsx-card">
            <header>
              <h3>Change Password</h3>
              <div class="bsx-card-actions">
                <template v-if="i.twoFactor.enabled && i.twoFactor.changepw">
                  <button
                    v-if="!i.twoFactor.changepwSent && !i.twoFactor.changepwUnlocked"
                    type="submit"
                    name="unlock"
                    value="1"
                    class="bsx-btn bsx-btn-secondary bsx-btn-small"
                  >
                    Unlock by E-mail
                  </button>
                  <button
                    v-else
                    type="submit"
                    class="bsx-btn bsx-btn-primary bsx-btn-small"
                    :disabled="!i.twoFactor.changepwUnlocked"
                  >
                    Update Password
                  </button>
                </template>
                <button
                  v-else
                  type="submit"
                  class="bsx-btn bsx-btn-primary bsx-btn-small"
                >
                  Update Password
                </button>
              </div>
            </header>
            <!-- 2-column body: row 1 = Current Password | Account PIN,
                 row 2 = New Password | Confirm New Password.
                 Grid-laid so a row's two fields stay aligned and the
                 strength + match hints sit under their own input. -->
            <div class="bsx-card-body bsx-pw-grid">
              <div class="kv">
                <label for="currentPassword">Current Password</label>
                <input
                  id="currentPassword"
                  type="password"
                  name="currentPassword"
                  :disabled="passwordLocked"
                  autocomplete="current-password"
                  required
                >
              </div>
              <div class="kv">
                <label for="authPinPassword">Account PIN</label>
                <input
                  id="authPinPassword"
                  type="password"
                  name="authPin"
                  :disabled="passwordLocked"
                  maxlength="4"
                  size="4"
                  autocomplete="current-password"
                  required
                >
              </div>
              <div class="kv">
                <label for="newPassword">New Password</label>
                <input
                  id="newPassword"
                  type="password"
                  name="newPassword"
                  v-model="newPassword"
                  :disabled="passwordLocked"
                  autocomplete="new-password"
                  required
                >
                <small v-if="pwStrengthLabel" class="kv-hint" :class="`pw-strength-${pwStrength}`">
                  Strength: {{ pwStrengthLabel }}
                </small>
              </div>
              <div class="kv">
                <label for="newPassword2">Confirm New Password</label>
                <input
                  id="newPassword2"
                  type="password"
                  name="newPassword2"
                  v-model="newPassword2"
                  :disabled="passwordLocked"
                  autocomplete="new-password"
                  required
                >
                <small v-if="pwMatch !== null" class="kv-hint" :class="pwMatch ? 'pw-match-ok' : 'pw-match-bad'">
                  {{ pwMatch ? 'Passwords match.' : 'Passwords do not match.' }}
                </small>
              </div>
            </div>
          </article>
        </form>

        <!-- RESET PIN (do=genPin) — own form, own card. -->
        <form :action="i.formAction" method="post" class="bsx-form">
          <input type="hidden" name="do" value="genPin">
          <input type="hidden" name="ctoken" :value="i.csrfToken">

          <article class="bsx-card">
            <header>
              <h3>Reset PIN</h3>
              <div class="bsx-card-actions">
                <button type="submit" class="bsx-btn bsx-btn-secondary bsx-btn-small">
                  Send New PIN
                </button>
              </div>
            </header>
            <div class="bsx-card-body">
              <p class="bsx-note">
                We'll generate a new 4-digit PIN and e-mail it to you.
                Enter your current password to authorise.
              </p>
              <div class="kv">
                <label for="resetPinPw">Current Password</label>
                <input
                  id="resetPinPw"
                  type="password"
                  name="currentPassword"
                  autocomplete="current-password"
                  required
                >
              </div>
            </div>
          </article>
        </form>
      </div><!-- /.bsx-actions-row -->
    </section><!-- /Section 1: Account -->

    <!-- SECTION 2 — Payout Settings (per-coin), 3-up. Each card holds:
           1) auto-payout settings (address + threshold) — always shown,
              inputs reference form="account-details-form" so they post
              with the Account Details save.
           2) optional manual-payout block (own <form>, do=cashOut[_mm…])
              shown only when the admin hasn't disabled manual payouts
              AND this coin slot has a transaction handler. Subtle
              divider separates the two. -->
    <section class="bsx-section">
      <header class="bsx-section-head"><h2>Payout Settings</h2></header>
      <p v-if="!i.manualPayoutsDisabled" class="bsx-section-note">
        Manual payout network fees are estimated by the wallet before sending.
      </p>
      <!-- 2-up so each card is wide enough for a full bech32 address
           (~43 chars) without truncating the input value. -->
      <div class="bsx-section-grid bsx-section-grid-2">
        <article
          v-for="coin in i.coins"
          :key="coin.key"
          class="bsx-card payout-coin-card"
        >
          <!-- Header now hosts the cash-out controls right-aligned next
               to the title. Balance is always shown; PIN + Cash Out
               appear only when admin allows manual payouts AND this slot
               has a cash-out handler. Hidden inputs + form submit live
               inside this <form>; the form's display: contents lets its
               children flow as flex items of the header. -->
          <header>
            <h3 class="coin-header">
              <img
                v-if="coin.iconUrl"
                :src="coin.iconUrl"
                :alt="coin.coinName"
                class="coin-header-icon"
                loading="lazy"
                @error="(e) => handleCoinIconError(e, coin.iconFallbackUrl)"
              />
              <span :class="['coin-header-name', `coin-name-${coin.currency.toLowerCase()}`]">{{ coin.coinName }}</span>
            </h3>
            <div class="bsx-card-actions">
              <!-- Header has two states. While a payout is pending for
                   this slot, the balance + Cash Out controls swap out
                   for a clickable "Pending payout" label that flips
                   the body to the details view (requestedAt + txid).
                   The label stays until the pending state clears
                   (failure path / next page load). -->
              <button
                v-if="pendingPayout[coin.key]?.active"
                type="button"
                class="cashout-pending-label"
                @click="setBodyView(coin.key,
                                    bodyView[coin.key] === 'details' ? 'fields' : 'details')"
                :aria-pressed="bodyView[coin.key] === 'details'"
              >
                {{ pendingLabel(pendingPayout[coin.key]?.kind) }}
              </button>
              <span v-else class="cash-out-balance-inline">
                <span class="muted">Balance</span>
                <strong>{{ coin.confirmedBalance }}</strong>
              </span>
              <form
                v-if="!pendingPayout[coin.key]?.active && !i.manualPayoutsDisabled && coin.cashOutEnabled"
                :action="i.formAction"
                method="post"
                class="bsx-cashout-form"
                @submit="submitCashOut(coin.key, $event)"
              >
                <input type="hidden" name="do" :value="coin.cashOutAction">
                <input type="hidden" name="ctoken" :value="i.csrfToken">
                <input type="hidden" name="utype" value="withdraw_funds">
                <input v-if="i.twoFactor.enabled" type="hidden" name="wf_token" :value="i.twoFactor.wfToken">
                <input
                  type="password"
                  name="authPin"
                  v-model="form.cashOutPin[coin.key]"
                  placeholder="PIN"
                  maxlength="4"
                  size="4"
                  required
                  inputmode="numeric"
                  pattern="[0-9]{4}"
                  :disabled="withdrawLocked"
                  autocomplete="current-password"
                  class="cash-out-pin"
                >
                <button
                  type="submit"
                  class="bsx-btn bsx-btn-primary bsx-btn-small"
                  :disabled="withdrawLocked
                             || coin.confirmedBalance <= 0
                             || cashOutQuoteBusy === coin.key
                             || quoteForCoin(coin.key) !== null
                             || cashOutSendBusy
                             || !pinReady(coin.key)"
                >
                  {{ cashOutQuoteBusy === coin.key ? 'Estimating' : 'Cash Out' }}
                </button>
              </form>
            </div>
          </header>
          <div class="bsx-card-body cashout-body-stack">
            <!-- Fields are ALWAYS rendered (v-show, not v-if) so their
                 form="account-details-form" inputs stay in the DOM and
                 submit with Update Account even while the pending-
                 payout details or cash-out message overlay is shown.
                 If we unmount them, the threshold/address field would
                 be missing from $_POST and PHP's `?? 0` default would
                 zero out the value on save. -->
            <div
              class="cashout-fields"
              :class="{ 'is-hidden': bodyView[coin.key] !== 'fields' }"
              :aria-hidden="bodyView[coin.key] !== 'fields'"
              :inert="bodyView[coin.key] !== 'fields'"
            >
              <div class="kv">
                <label :for="`addr-${coin.key}`">Coin Address</label>
                <div class="kv-input-with-hint">
                  <input
                    :id="`addr-${coin.key}`"
                    form="account-details-form"
                    type="text"
                    :name="coin.addressField"
                    v-model="form.coinAddress[coin.key]"
                    :disabled="detailsLocked"
                    maxlength="90"
                    size="70"
                    spellcheck="false"
                    autocomplete="off"
                  >
                  <span
                    v-if="classifyAddress(form.coinAddress[coin.key])"
                    :class="['addr-type-pill',
                             `addr-type-${classifyAddress(form.coinAddress[coin.key])}`]"
                    :data-tooltip="ADDR_TYPE_TOOLTIP[classifyAddress(form.coinAddress[coin.key])]"
                    :aria-label="ADDR_TYPE_TOOLTIP[classifyAddress(form.coinAddress[coin.key])]"
                    tabindex="0"
                  >{{ classifyAddress(form.coinAddress[coin.key]) }}</span>
                </div>
              </div>
              <div class="kv">
                <label :for="`thr-${coin.key}`">Auto-Payout Threshold</label>
                <!-- Smaller input + range hint inline to its right, same
                     pattern as Donation % so the cell stays single-line. -->
                <div class="kv-input-with-hint">
                  <input
                    :id="`thr-${coin.key}`"
                    class="kv-input-narrow"
                    form="account-details-form"
                    type="number"
                    :name="coin.thresholdField"
                    v-model="form.coinThreshold[coin.key]"
                    :min="thresholdInputMin(coin)"
                    :max="coin.thresholdMax"
                    :required="coinHasAddress(coin)"
                    step="0.00000001"
                    :disabled="detailsLocked"
                  >
                  <small class="kv-hint">
                    {{ coin.thresholdMin }}–{{ coin.thresholdMax }} {{ coin.currency }}<template v-if="coinHasAddress(coin)"> required with address.</template><template v-else>, or 0 to disable.</template>
                  </small>
                </div>
              </div>
            </div>
            <!-- Overlay: pending-payout details or cash-out msg, sat on
                 top of the (hidden) fields. Flip animation preserved
                 via Transition. -->
            <Transition name="bsx-flip" mode="out-in">
              <!-- Pending-payout details (operator clicked the
                   "Pending payout" header). -->
              <div
                v-if="bodyView[coin.key] === 'details' && pendingPayout[coin.key]?.active"
                :key="`details-${coin.key}`"
                class="cashout-msg-block cashout-msg-info cashout-details-block cashout-overlay"
                role="status"
              >
                <p class="cashout-detail-line">
                  <span class="muted">Requested:</span>
                  <strong>{{ fmtRequestedAt(pendingPayout[coin.key]?.requestedAt) }}</strong>
                  <template v-if="pendingPayout[coin.key]?.amount">
                    <span class="muted">&nbsp;&nbsp;Amount:</span>
                    <strong>{{ pendingPayout[coin.key]!.amount }} {{ coin.currency }}</strong>
                  </template>
                </p>
                <p class="cashout-detail-line">
                  <span class="muted">{{ pendingPayout[coin.key]?.txid ? 'Txid:' : 'Status:' }}</span>
                  <strong v-if="pendingPayout[coin.key]?.txid"
                          class="cashout-detail-txid"
                          :title="pendingPayout[coin.key]!.txid!">{{ pendingPayout[coin.key]!.txid }}</strong>
                  <strong v-else>Queued, awaiting broadcast</strong>
                </p>
              </div>
              <!-- CashOut just-submitted message (success/error). -->
              <div
                v-else-if="bodyView[coin.key] === 'msg' && cashOutPopupForCoin(coin.key)"
                :key="`success-${coin.key}`"
                :class="['cashout-msg-block', 'cashout-overlay',
                         `cashout-msg-${cashOutPopupForCoin(coin.key)!.type}`]"
                :role="cashOutPopupForCoin(coin.key)!.type === 'errormsg' ? 'alert' : 'status'"
              >
                <p class="cashout-msg-text" v-text="cashOutPopupForCoin(coin.key)!.content"></p>
              </div>
              <!-- Wallet fee quote. Replaces the field body without
                   changing card height; Send performs the actual queue. -->
              <div
                v-else-if="bodyView[coin.key] === 'quote' && quoteForCoin(coin.key)"
                :key="`quote-${coin.key}`"
                class="cashout-quote-block cashout-overlay"
                role="status"
              >
                <dl class="cashout-quote-lines">
                  <div>
                    <dt>Balance</dt>
                    <dd>{{ quoteForCoin(coin.key)!.amount }}</dd>
                  </div>
                  <div>
                    <dt>Network fee</dt>
                    <dd>{{ quoteForCoin(coin.key)!.fee }}</dd>
                  </div>
                  <div>
                    <dt>Sent amount</dt>
                    <dd>{{ quoteForCoin(coin.key)!.sendAmount }}</dd>
                  </div>
                </dl>
                <div class="cashout-quote-actions">
                  <button type="button" class="bsx-btn bsx-btn-primary bsx-btn-small cashout-send-btn" :disabled="cashOutSendBusy" @click="sendQuotedCashOut">
                    {{ cashOutSendBusy ? 'Sending' : 'Send' }}
                  </button>
                  <button type="button" class="bsx-btn bsx-btn-ghost bsx-btn-small cashout-cancel-btn" :disabled="cashOutSendBusy" @click="cancelCashOutQuote">
                    Cancel
                  </button>
                </div>
              </div>
            </Transition>
          </div>
        </article>
      </div>
    </section><!-- /Section 2: Payout Settings + Manual Payouts -->
  </div>
</template>

<style scoped>
.account-edit-v2 {
  padding: 1em;
  color: var(--text-primary, #cdd);
  font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.bsx-form { display: contents; }

.bsx-section {
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 8px;
  padding: 14px 16px 16px;
  background: rgba(255, 255, 255, 0.015);
}
.bsx-section-head { margin: -2px 0 12px; }
.bsx-section-head h2 {
  margin: 0;
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.10em;
  color: #4fc3f7;
  font-weight: 700;
}
.bsx-section-head-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
}
.bsx-section-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}
.bsx-pin-input {
  padding: 4px 8px;
  text-align: center;
  letter-spacing: 0.20em;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  width: 90px;
}
.bsx-btn-dirty {
  box-shadow:
    0 0 0 1px rgba(255, 184, 28, 0.65),
    0 0 10px rgba(255, 184, 28, 0.45);
  border-color: rgba(255, 184, 28, 0.75) !important;
  animation: bsx-dirty-pulse 1.8s ease-in-out infinite;
}
@keyframes bsx-dirty-pulse {
  0%, 100% {
    box-shadow:
      0 0 0 1px rgba(255, 184, 28, 0.55),
      0 0 8px  rgba(255, 184, 28, 0.35);
  }
  50% {
    box-shadow:
      0 0 0 1px rgba(255, 184, 28, 0.85),
      0 0 14px rgba(255, 184, 28, 0.60);
  }
}
@media (prefers-reduced-motion: reduce) {
  .bsx-btn-dirty { animation: none; }
}
/* Compound selector outranks the base .bsx-card-body flex rule below. */
.bsx-card-body.bsx-pw-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  column-gap: 14px;
  row-gap: 12px;
}
@media (max-width: 720px) {
  .bsx-card-body.bsx-pw-grid { grid-template-columns: 1fr; }
}
.bsx-section-note {
  margin: -4px 0 12px;
  font-size: 12px;
  color: #cdd;
  opacity: 0.75;
}
.bsx-section-grid {
  display: grid;
  gap: 12px;
  align-items: start;
}
.bsx-section-grid-2 { grid-template-columns: repeat(2, minmax(0, 1fr)); }
.bsx-section-grid-3 { grid-template-columns: repeat(3, minmax(0, 1fr)); }

.bsx-actions-row {
  margin-top: 14px;
  padding-top: 14px;
  border-top: 1px dashed rgba(255, 255, 255, 0.08);
}

@media (max-width: 1280px) {
  .bsx-section-grid-3 { grid-template-columns: repeat(2, minmax(0, 1fr)); }
}
@media (max-width: 720px) {
  .bsx-section-grid-2,
  .bsx-section-grid-3 { grid-template-columns: 1fr; }
}

.bsx-popups { display: flex; flex-direction: column; gap: 6px; }
.bsx-popup {
  margin: 0;
  padding: 8px 14px;
  border-radius: 6px;
  border-left: 3px solid #4fc3f7;
  border-right: 3px solid #4fc3f7;
  background: rgba(79, 195, 247, 0.08);
  font-size: 13px;
  line-height: 1.45;
  color: #cdd;
}
.bsx-popup-success {
  border-left-color: #b5e7a0;
  border-right-color: #b5e7a0;
  background: rgba(181, 231, 160, 0.08);
}
.bsx-popup-errormsg {
  border-left-color: #f5cba7;
  border-right-color: #f5cba7;
  background: rgba(245, 203, 167, 0.08);
}

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
.bsx-card-actions {
  display: flex;
  align-items: center;
  gap: 6px;
  flex: 0 0 auto;
}
.bsx-card h3 {
  margin: 0;
  font-size: 13px;
  text-transform: uppercase;
  color: #cdd;
  letter-spacing: 0.04em;
}
.bsx-card-body { padding: 14px 16px; display: flex; flex-direction: column; gap: 12px; }

.kv {
  display: grid;
  grid-template-columns: 150px minmax(0, 1fr);
  align-items: center;
  gap: 6px 4px;
}
.kv > label {
  font-size: 12px;
  color: #cdd;
  font-weight: 600;
  letter-spacing: 0.02em;
  justify-self: start;
  text-align: left;
}
.kv input[type=text],
.kv input[type=email],
.kv input[type=password],
.kv input[type=number] {
  font: inherit;
  font-size: 13px;
  padding: 6px 8px;
  background: rgba(255,255,255,.04);
  border: 1px solid rgba(255,255,255,.10);
  border-radius: 4px;
  color: #f0f0f0;
  width: 100%;
  box-sizing: border-box;
  transition: border-color 200ms ease, box-shadow 200ms ease;
}
.kv input[disabled] {
  opacity: 0.55;
  cursor: not-allowed;
}
.kv input[type=text]:focus,
.kv input[type=email]:focus,
.kv input[type=password]:focus,
.kv input[type=number]:focus {
  outline: none;
  border-color: #4fc3f7;
  box-shadow: inset 0 2px 2px rgba(0, 0, 0, 0.20), 0 0 10px rgba(79, 195, 247, 0.55);
}
[data-theme="light"] .kv input[type=text]:focus,
[data-theme="light"] .kv input[type=email]:focus,
[data-theme="light"] .kv input[type=password]:focus,
[data-theme="light"] .kv input[type=number]:focus {
  border-color: #1565c0;
  box-shadow: inset 0 2px 2px rgba(0, 0, 0, 0.10), 0 0 10px rgba(21, 101, 192, 0.45);
}
.kv-hint {
  grid-column: 2 / -1;
  font-size: 11px;
  opacity: 0.6;
  color: #cdd;
}

.addr-type-pill {
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  padding: 7px 12px;
  border-radius: 4px;
  border: 1px solid transparent;
  line-height: 1.2;
  flex: 0 0 auto;
  white-space: nowrap;
  cursor: help;
  user-select: none;
  box-sizing: border-box;
}
.addr-type-pill.addr-type-bech32 {
  color: #4fc3f7;
  border-color: rgba(79, 195, 247, 0.45);
  background: rgba(79, 195, 247, 0.10);
}
.addr-type-pill.addr-type-legacy {
  color: #b5e7a0;
  border-color: rgba(181, 231, 160, 0.45);
  background: rgba(181, 231, 160, 0.10);
}
.addr-type-pill.addr-type-p2sh {
  color: #f0a050;
  border-color: rgba(240, 160, 80, 0.45);
  background: rgba(240, 160, 80, 0.10);
}
.addr-type-pill.addr-type-none {
  color: #e57373;
  border-color: rgba(229, 115, 115, 0.45);
  background: rgba(229, 115, 115, 0.10);
}
[data-theme="light"] .addr-type-pill.addr-type-bech32 { color: #1565c0; border-color: rgba(21,101,192,.50); background: rgba(21,101,192,.08); }
[data-theme="light"] .addr-type-pill.addr-type-legacy { color: #2e7d32; border-color: rgba(46,125,50,.50);  background: rgba(46,125,50,.08); }
[data-theme="light"] .addr-type-pill.addr-type-p2sh   { color: #ef6c00; border-color: rgba(239,108,0,.50);  background: rgba(239,108,0,.08); }
[data-theme="light"] .addr-type-pill.addr-type-none   { color: #c62828; border-color: rgba(198,40,40,.50);  background: rgba(198,40,40,.08); }

.addr-type-pill[data-tooltip] { position: relative; outline: none; }
.addr-type-pill[data-tooltip]::after {
  content: attr(data-tooltip);
  position: absolute;
  top: calc(100% + 8px);
  right: 0;
  background: rgba(20, 23, 28, 0.96);
  border: 1px solid rgba(79, 195, 247, 0.35);
  color: #cdd;
  padding: 6px 10px;
  border-radius: 4px;
  font-size: 11px;
  font-weight: 400;
  letter-spacing: normal;
  text-transform: none;
  white-space: nowrap;
  opacity: 0;
  pointer-events: none;
  transition: opacity 150ms ease, transform 150ms ease;
  transform: translateY(-2px);
  z-index: 100;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.45);
}
.addr-type-pill[data-tooltip]::before {
  content: '';
  position: absolute;
  top: calc(100% + 3px);
  right: 14px;
  width: 8px;
  height: 8px;
  background: rgba(20, 23, 28, 0.96);
  border-top: 1px solid rgba(79, 195, 247, 0.35);
  border-left: 1px solid rgba(79, 195, 247, 0.35);
  transform: rotate(45deg) translateY(-2px);
  opacity: 0;
  pointer-events: none;
  transition: opacity 150ms ease, transform 150ms ease;
  z-index: 101;
}
.addr-type-pill[data-tooltip]:hover::after,
.addr-type-pill[data-tooltip]:focus-visible::after,
.addr-type-pill[data-tooltip]:hover::before,
.addr-type-pill[data-tooltip]:focus-visible::before {
  opacity: 1;
  transform: translateY(0);
}
.addr-type-pill[data-tooltip]:hover::before,
.addr-type-pill[data-tooltip]:focus-visible::before {
  transform: rotate(45deg) translateY(0);
}
[data-theme="light"] .addr-type-pill[data-tooltip]::after,
[data-theme="light"] .addr-type-pill[data-tooltip]::before {
  background: #ffffff;
  border-color: rgba(21, 101, 192, 0.40);
  color: #1f2933;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
}

.coin-header {
  display: inline-flex;
  align-items: center;
  padding-left: 38px; /* icon (33) + 5 px gap to coin name */
}
/* Drop header padding so the absolute coin icon hugs the left edge. */
.payout-coin-card > header {
  padding-left: 0;
  position: relative;
}
.coin-header-icon {
  position: absolute;
  left: 8px;
  top: 50%;
  transform: translateY(-50%);
  width: 33px;
  height: 33px;
  object-fit: contain;
  border-radius: 4px;
  opacity: 0.95;
}
.coin-header-name {
  font-weight: 600;
  letter-spacing: 0.02em;
}
.coin-header-name.coin-name-bbtc { color: #ea4335; }
.coin-header-name.coin-name-blc  { color: #ff9800; }
.coin-header-name.coin-name-elt  { color: #34a853; }
.coin-header-name.coin-name-lit  { color: #fbbc04; }
.coin-header-name.coin-name-pho  { color: #4285f4; }
.coin-header-name.coin-name-umo  { color: #7b61ff; }

.kv-row {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px 16px;
}
.kv-row > .kv {
  display: flex;
  flex-direction: column;
  align-items: stretch;
  gap: 4px;
}
.kv-input-with-hint {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 100%;
  min-width: 0;
}
.kv-input-with-hint > input.kv-input-narrow {
  flex: 0 0 auto;
  width: 110px;
}
.kv-input-with-hint > .kv-hint {
  flex: 1 1 auto;
  margin: 0;
  grid-column: auto;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
@media (max-width: 720px) {
  .kv-row { grid-template-columns: 1fr; }
}
.kv-checkbox {
  display: flex;
  gap: 10px;
  align-items: center;
  font-size: 13px;
  color: #cdd;
  min-height: 30px;
}
.bsx-toggle-wrap {
  cursor: pointer;
  display: inline-flex;
  align-items: center;
}
.bsx-toggle-wrap:has(input:disabled) {
  cursor: not-allowed;
}
.kv-checkbox-text {
  color: #cdd;
  letter-spacing: 0.02em;
}
.kv-checkbox input[type=checkbox] {
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
.kv-checkbox input[type=checkbox]:checked + .bsx-toggle {
  background: rgba(79, 195, 247, 0.55);
  border-color: rgba(79, 195, 247, 0.65);
}
.kv-checkbox input[type=checkbox]:checked + .bsx-toggle::after {
  transform: translateX(16px);
  background: #ffffff;
}
.kv-checkbox input[type=checkbox]:disabled ~ .bsx-toggle {
  opacity: 0.45;
}
.kv-checkbox input[type=checkbox]:disabled ~ * { cursor: not-allowed; }
.kv-checkbox input[type=checkbox]:focus-visible + .bsx-toggle {
  outline: 2px solid rgba(79, 195, 247, 0.7);
  outline-offset: 2px;
}

.api-key-row {
  display: flex;
  gap: 8px;
  align-items: center;
}
.api-key-row input { flex: 1 1 auto; }

.bsx-note {
  margin: 0;
  font-size: 12px;
  opacity: 0.75;
  color: #cdd;
}

.form-actions {
  display: flex;
  justify-content: flex-end;
  gap: 10px;
}

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
.bsx-btn[disabled] {
  opacity: 0.45;
  cursor: not-allowed;
}
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
.bsx-btn-ghost {
  background: transparent;
  border-color: rgba(255,255,255,.18);
  color: #cdd;
}
.bsx-btn-small { padding: 4px 10px; font-size: 12px; }

.cash-out-balance-inline {
  font-size: 12px;
  color: #cdd;
  white-space: nowrap;
}
.cash-out-balance-inline strong {
  margin-left: 4px;
  color: #e0f0fa;
  font-weight: 700;
}
.bsx-card-actions .bsx-cashout-form {
  display: inline-flex;
  align-items: center;
  gap: 6px;
}
.cash-out-pin {
  font: inherit;
  font-size: 12px;
  padding: 3px 6px;
  background: rgba(255,255,255,.04);
  border: 1px solid rgba(255,255,255,.10);
  border-radius: 4px;
  color: #f0f0f0;
  width: 56px;
  text-align: center;
  box-sizing: border-box;
}

.pw-strength-0,
.pw-strength-1 { color: #f5cba7; }
.pw-strength-2 { color: #ffce9c; }
.pw-strength-3 { color: #cdd; }
.pw-strength-4,
.pw-strength-5 { color: #b5e7a0; }
.pw-match-ok { color: #b5e7a0; }
.pw-match-bad { color: #f5cba7; }

@media (max-width: 720px) {
  .kv { grid-template-columns: 1fr; }
  .cash-out-line {
    grid-template-columns: 1fr;
    gap: 6px;
  }
}

.cashout-body-stack {
  position: relative;
  height: 76px;
  overflow: hidden;
  perspective: 900px;
  transform-style: preserve-3d;
}
.cashout-fields {
  position: absolute;
  inset: 14px 16px;
  display: flex;
  flex-direction: column;
  gap: 12px;
  transition: opacity 180ms ease, transform 180ms ease;
  transform-origin: center;
  backface-visibility: hidden;
}
.cashout-fields.is-hidden {
  opacity: 0;
  pointer-events: none;
  transform: rotateX(-90deg);
}
.cashout-overlay {
  position: absolute;
  inset: 14px 16px;
  z-index: 2;
  backface-visibility: hidden;
}

.cashout-msg-block.cashout-overlay {
  position: absolute;
}
.cashout-msg-block {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  gap: 6px;
  min-height: 68px;
}
.cashout-msg-text {
  margin: 0;
  font-size: 14px;
  font-weight: 600;
}
.cashout-msg-success .cashout-msg-text  { color: #b5e7a0; }
.cashout-msg-errormsg .cashout-msg-text { color: #f5cba7; }
.cashout-msg-info .cashout-msg-text     { color: #4fc3f7; }
.cashout-detail-line {
  margin: 0;
  font-size: 14px;
  color: #cdd;
  display: flex;
  gap: 6px;
  align-items: baseline;
  justify-content: center;
  flex-wrap: wrap;
  line-height: 1.2;
  max-width: 100%;
}
.cashout-detail-line .muted   { color: #99a; }
.cashout-detail-line strong   { color: #e0f0fa; font-weight: 600; }
.cashout-detail-txid {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 13px;
  word-break: break-all;
  white-space: normal;
  max-width: 100%;
}
.cashout-details-block {
  gap: 4px;
  padding-bottom: 0;
  min-height: 70px;
}
.cashout-details-block .cashout-detail-line:first-of-type { margin-top: 0; }

.cashout-quote-block {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  align-items: center;
  gap: 16px;
}
.cashout-quote-lines {
  margin: 0;
  display: grid;
  gap: 2px;
  justify-self: center;
  min-width: 0;
}
.cashout-quote-lines div {
  display: grid;
  grid-template-columns: 92px max-content;
  align-items: baseline;
  gap: 8px;
  justify-content: start;
  min-width: 0;
}
.cashout-quote-lines dt {
  color: #99a;
  font-size: 13px;
  font-weight: 700;
  white-space: nowrap;
  text-align: left;
}
.cashout-quote-lines dd {
  margin: 0;
  color: #e0f0fa;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 14px;
  text-align: left;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.cashout-quote-actions {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
}
.cashout-quote-actions .bsx-btn {
  width: 74px;
  justify-content: center;
}
.cashout-quote-actions .cashout-send-btn {
  color: #b5e7a0;
  border-color: rgba(181, 231, 160, 0.45);
  background: rgba(181, 231, 160, 0.10);
}
.cashout-quote-actions .cashout-send-btn:hover:not([disabled]) {
  border-color: rgba(181, 231, 160, 0.70);
  background: rgba(181, 231, 160, 0.18);
}
.cashout-quote-actions .cashout-cancel-btn {
  color: #e57373;
  border-color: rgba(229, 115, 115, 0.45);
  background: rgba(229, 115, 115, 0.08);
}
.cashout-quote-actions .cashout-cancel-btn:hover:not([disabled]) {
  border-color: rgba(229, 115, 115, 0.70);
  background: rgba(229, 115, 115, 0.16);
}

.cashout-pending-label {
  appearance: none;
  background: rgba(79, 195, 247, 0.10);
  border: 1px solid rgba(79, 195, 247, 0.45);
  color: #cfe9fa;
  font-weight: 600;
  font-size: 12px;
  padding: 4px 14px;
  border-radius: 6px;
  cursor: pointer;
  letter-spacing: 0.02em;
  white-space: nowrap;
}
.cashout-pending-label[aria-pressed="true"] {
  background: rgba(79, 195, 247, 0.22);
  border-color: rgba(79, 195, 247, 0.75);
}
.cashout-pending-label:hover {
  background: rgba(79, 195, 247, 0.18);
}
.bsx-flip-enter-active,
.bsx-flip-leave-active {
  transition: opacity 180ms ease, transform 180ms ease;
  transform-origin: center;
}
.bsx-flip-enter-from { opacity: 0; transform: rotateX(90deg); }
.bsx-flip-leave-to   { opacity: 0; transform: rotateX(-90deg); }

</style>
