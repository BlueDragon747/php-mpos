<script setup lang="ts">
import { computed, ref } from 'vue';
import type { EditAccountInitial } from './types';

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

function pinReady(coinKey: string): boolean {
  return /^\d{4}$/.test(form.value.cashOutPin[coinKey] || '');
}

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
    <!-- POPUPS — top of page; mirror legacy layout/colour conventions. -->
    <div v-if="i.popups.length" class="bsx-popups">
      <p
        v-for="(p, idx) in i.popups"
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
      <header class="bsx-section-head"><h2>Account</h2></header>

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

      <!-- ACCOUNT ACTIONS row inside Section 1 (3-up: Confirm | Change PW | Reset PIN). -->
      <div class="bsx-section-grid bsx-section-grid-3 bsx-actions-row">

        <!-- CONFIRM — submits Account Details via form="account-details-form".
             Submit button lives in the header (right side); body holds
             only the PIN input. -->
        <article class="bsx-card">
          <header>
            <h3>Confirm</h3>
            <div class="bsx-card-actions">
              <!-- Two-factor unlock branch. If 2FA is required for details
                   edits and the token isn't unlocked, "Unlock by E-mail"
                   replaces Save — clicking sends a confirmation email;
                   the user follows the link and comes back, the form
                   re-renders with the token consumed. -->
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
                  class="bsx-btn bsx-btn-primary bsx-btn-small"
                  :disabled="!i.twoFactor.detailsUnlocked"
                >
                  Update Account
                </button>
              </template>
              <button
                v-else
                form="account-details-form"
                type="submit"
                class="bsx-btn bsx-btn-primary bsx-btn-small"
              >
                Update Account
              </button>
            </div>
          </header>
          <div class="bsx-card-body">
            <div class="kv">
              <label for="authPinDetails">Account PIN</label>
              <input
                id="authPinDetails"
                form="account-details-form"
                type="password"
                name="authPin"
                :disabled="detailsLocked"
                maxlength="4"
                size="4"
                autocomplete="current-password"
                required
              >
              <small class="kv-hint">4-digit PIN. Use Reset PIN if you forgot it.</small>
            </div>
          </div>
        </article>

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
            <div class="bsx-card-body">
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
        Manual payout fee: <strong>{{ i.txFeeManual }}</strong> per request.
        Confirmed balance must exceed the fee.
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
                @error="(e) => ((e.target as HTMLImageElement).style.display = 'none')"
              />
              <span :class="['coin-header-name', `coin-name-${coin.currency.toLowerCase()}`]">{{ coin.coinName }}</span>
            </h3>
            <div class="bsx-card-actions">
              <span class="cash-out-balance-inline">
                <span class="muted">Balance</span>
                <strong>{{ coin.confirmedBalance }}</strong>
              </span>
              <form
                v-if="!i.manualPayoutsDisabled && coin.cashOutEnabled"
                :action="i.formAction"
                method="post"
                class="bsx-cashout-form"
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
                             || coin.confirmedBalance <= i.txFeeManual
                             || !pinReady(coin.key)"
                >
                  Cash Out
                </button>
              </form>
            </div>
          </header>
          <div class="bsx-card-body">
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
                  :min="coin.thresholdMin"
                  :max="coin.thresholdMax"
                  step="0.00000001"
                  :disabled="detailsLocked"
                >
                <small class="kv-hint">
                  {{ coin.thresholdMin }}–{{ coin.thresholdMax }} {{ coin.currency }}, or 0 to disable.
                </small>
              </div>
            </div>
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
/* Per-coin cards: drop the header's left padding so the absolute
   coin icon hugs the card's left edge, mirroring how the
   .bsx-card-actions cluster (PIN + Cash Out) hugs the right edge.
   `position: relative` anchors the icon's absolute placement to
   the outer <header> bar so its vertical centre matches the
   bar's centre and its size doesn't push the bar taller. */
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
</style>
