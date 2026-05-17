<script setup lang="ts">
import { ref, computed } from 'vue';
import type { TransactionsInitial } from './types';

const props = defineProps<{
  initial: TransactionsInitial;
}>();

const i = props.initial;

// Local mirror of the filter so v-model works on the dropdowns. The
// form is GET so submitting the form just navigates to the same URL
// with the filter query params applied — page reload, but that's
// what makes the URL bookmarkable / shareable.
const filterType = ref(i.filter.type);
const filterStatus = ref(i.filter.status);
const filterCoin = ref(i.selectedCoin || '');
const filterForm = ref<HTMLFormElement | null>(null);
const hasCoinSelector = computed(() => Array.isArray(i.coinOptions) && i.coinOptions.length > 1);

// GET-form submission discards the action URL's query string and
// rebuilds it from the form's name/value pairs, so the page/action
// must travel as hidden inputs. Parse them out of i.formAction —
// which the PHP side encodes per-slot (e.g. transactions_mm1 for
// the BBTC admin view) — so the filter stays on the same coin and
// same context (admin vs. account) instead of falling back to BLC.
const _formActionParams = new URLSearchParams(i.formAction.replace(/^\?/, ''));
const formPage = _formActionParams.get('page') || 'account';
const formActionName = _formActionParams.get('action') || 'transactions';
// Admin-only filters (match `filter[account]` and `filter[address]`
// in the legacy admin page). Carried through pagination so URLs
// survive Next/Prev.
const filterAccount = ref(i.filter.account ?? '');
const filterAddress = ref(i.filter.address ?? '');

function submitFilters() {
  filterForm.value?.submit();
}

// Pagination URLs. Legacy controller reads ?start=N from the URL;
// the filter form preserves filter[type] and filter[status]. Building
// the prev/next links here keeps the v2 page in sync with that scheme.
function pageUrl(start: number): string {
  // Parse i.formAction (e.g. "?page=admin&action=transactions_mm") so
  // the prev/next links land on the correct page+action regardless of
  // user/admin context.
  const base = new URLSearchParams(i.formAction.replace(/^\?/, ''));
  const params = new URLSearchParams();
  for (const [k, v] of base) params.set(k, v);
  if (start > 0) params.set('start', String(start));
  if (filterCoin.value)    params.set('coin', filterCoin.value);
  if (filterType.value)    params.set('filter[type]',    filterType.value);
  if (filterStatus.value)  params.set('filter[status]',  filterStatus.value);
  if (filterAccount.value) params.set('filter[account]', filterAccount.value);
  if (filterAddress.value) params.set('filter[address]', filterAddress.value);
  // Decode the bracket chars that URLSearchParams percent-encodes —
  // PHP reads them either way but the legacy URLs are unencoded so
  // we match for visual consistency.
  return `?${params.toString().replace(/%5B/g, '[').replace(/%5D/g, ']')}`;
}

const hasPrev = computed(() => i.start > 0);
const prevStart = computed(() => Math.max(0, i.start - i.limit));
// We don't know total count without an extra query. The controller's
// behaviour is: if a full page is returned, there might be more; if
// fewer rows are returned we're at the end. Mirror that heuristic.
const hasNext = computed(() => i.transactions.length >= i.limit);
const nextStart = computed(() => i.start + i.limit);

function fmtAmount(n: number): string {
  if (!Number.isFinite(n)) return '0.00000000';
  return n.toLocaleString('en-US', {
    minimumFractionDigits: 8,
    maximumFractionDigits: 8,
  });
}
function truncate(s: string, n = 20): string {
  if (!s) return '';
  return s.length > n ? `${s.slice(0, n - 3)}...` : s;
}
function txExplorerHref(txid: string): string {
  if (i.explorerDisabled || !i.explorerUrl) return '#';
  return `${i.explorerUrl}${txid}`;
}
function blockHref(height: number): string {
  // The transactions page is scoped to a single coin (i.currency), so
  // every block link inherits that coin. Without it the round page
  // defaults to BLC and tries to look up an aux height in the parent
  // blocks table — empty BLOCKDETAILS, all zeros.
  const coin = i.currency || '';
  return coin
    ? `?page=statistics&action=round&coin=${encodeURIComponent(coin)}&height=${height}`
    : `?page=statistics&action=round&height=${height}`;
}

// For the address column, we don't have an explorer for addresses —
// click reveals the full string via prompt() so the user can copy
// (legacy uses alert(), but prompt is selectable).
function showAddress(addr: string) {
  if (addr) window.prompt('Coin address', addr);
}

// Transaction summary table — flatten the keyed object into an
// ordered list of [type, total] pairs so the v-for is stable across
// renders. Hidden when summaryDisabled is true OR no totals exist.
const summaryEntries = computed(() => {
  if (i.summaryDisabled || !i.summary) return [];
  return Object.entries(i.summary);
});
const showSummaryCard = computed(() => !i.summaryDisabled && (summaryEntries.value.length > 0 || hasCoinSelector.value));
function summaryAmountClass(type: string): 'credit' | 'debit' {
  return /^(Credit|Bonus)/.test(type) ? 'credit' : 'debit';
}
</script>

<template>
  <div class="transactions-v2">
    <!-- Transaction Summary — single-row table (one column per type)
         showing per-type running totals. Hidden when the admin setting
         `disable_transactionsummary` is on. -->
    <article v-if="showSummaryCard" class="bsx-card tx-summary-card">
      <header class="tx-summary-head">
        <h3>Transaction Summary</h3>
        <select
          v-if="hasCoinSelector"
          form="tx-filter-form"
          name="coin"
          v-model="filterCoin"
          class="tx-filter-select tx-filter-coin tx-summary-coin-select"
          aria-label="Select coin"
          @change="submitFilters"
        >
          <option
            v-for="coin in i.coinOptions"
            :key="coin.value"
            :value="coin.value"
          >{{ coin.label }}</option>
        </select>
        <span v-else class="tx-summary-coin">{{ i.coinName }}</span>
        <span class="tx-summary-spacer" aria-hidden="true"></span>
      </header>
      <div v-if="summaryEntries.length > 0" class="bsx-card-body tx-table-wrap">
        <table class="tx-table tx-summary-table">
          <thead>
            <tr>
              <th v-for="[type] in summaryEntries" :key="type">{{ type }}</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td
                v-for="[type, total] in summaryEntries"
                :key="type"
                :class="['td-amount', `tx-amount-${summaryAmountClass(type)}`]"
              >{{ fmtAmount(total) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <div v-else class="bsx-card-body tx-summary-empty">
        No summary data for this coin.
      </div>
    </article>

    <article class="bsx-card">
      <header>
        <h3>Transaction History</h3>
        <!-- Filter form lives in the header. GET submission so the
             resulting URL (with `filter[type]` / `filter[status]` /
             `start`) is bookmarkable; page reloads on Filter click. -->
        <form
          id="tx-filter-form"
          ref="filterForm"
          method="get"
          :action="i.formAction"
          class="tx-filter-form"
        >
          <input type="hidden" name="page" :value="formPage">
          <input type="hidden" name="action" :value="formActionName">
          <input
            v-if="!hasCoinSelector && filterCoin"
            type="hidden"
            name="coin"
            :value="filterCoin"
          >
          <select name="filter[type]" v-model="filterType" class="tx-filter-select">
            <option
              v-for="(label, key) in i.transactionTypes"
              :key="key"
              :value="key"
            >{{ key === '' ? '— Any Type —' : (label || key) }}</option>
          </select>
          <select name="filter[status]" v-model="filterStatus" class="tx-filter-select">
            <option
              v-for="(label, key) in i.transactionStatus"
              :key="key"
              :value="key"
            >{{ key === '' ? '— Any Status —' : label }}</option>
          </select>
          <input
            v-if="i.showUsername"
            type="text"
            name="filter[account]"
            v-model="filterAccount"
            placeholder="Account"
            class="tx-filter-input"
            autocomplete="off"
          >
          <input
            v-if="i.showUsername"
            type="text"
            name="filter[address]"
            v-model="filterAddress"
            placeholder="Address"
            class="tx-filter-input tx-filter-input-wide"
            autocomplete="off"
          >
          <button type="submit" class="bsx-btn bsx-btn-primary bsx-btn-small">
            Filter
          </button>
        </form>
      </header>
      <div class="bsx-card-body tx-table-wrap">
        <table class="tx-table">
          <thead>
            <tr>
              <th class="th-id">ID</th>
              <th v-if="i.showUsername" class="th-user">Username</th>
              <th class="th-date">Date</th>
              <th class="th-type">TX Type</th>
              <th class="th-status">Status</th>
              <th class="th-addr">Payment Address</th>
              <th class="th-txid">TX #</th>
              <th class="th-block">Block #</th>
              <th class="th-amount">Amount</th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="i.transactions.length === 0">
              <td :colspan="i.showUsername ? 9 : 8" class="empty-row">
                No transactions match the current filter.
              </td>
            </tr>
            <tr v-for="t in i.transactions" :key="t.id">
              <td class="td-id">{{ t.id }}</td>
              <td v-if="i.showUsername" class="td-user">{{ t.username }}</td>
              <td class="td-date">{{ t.timestamp }}</td>
              <td class="td-type">{{ t.type }}</td>
              <td class="td-status">
                <span :class="['tx-status', `tx-status-${t.status.toLowerCase()}`]">
                  {{ t.status }}
                </span>
              </td>
              <td class="td-addr">
                <a v-if="t.coinAddress"
                   href="#"
                   :title="t.coinAddress"
                   @click.prevent="showAddress(t.coinAddress)"
                >{{ truncate(t.coinAddress) }}</a>
              </td>
              <td class="td-txid">
                <a v-if="t.txid"
                   :href="txExplorerHref(t.txid)"
                   :title="t.txid"
                   :target="i.explorerDisabled ? undefined : '_blank'"
                   rel="noopener"
                >{{ truncate(t.txid) }}</a>
              </td>
              <td class="td-block">
                <a v-if="t.height > 0" :href="blockHref(t.height)">{{ t.height }}</a>
                <span v-else class="muted">n/a</span>
              </td>
              <td :class="['td-amount', `tx-amount-${t.amountClass}`]">
                {{ fmtAmount(t.amount) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <footer class="tx-footer">
        <p class="tx-legend">
          <strong>Debit_AP</strong> = Auto Threshold Payment
          <span class="muted">·</span>
          <strong>Debit_MP</strong> = Manual Payment
          <span class="muted">·</span>
          <strong>Donation</strong> = Donation
          <span class="muted">·</span>
          <strong>Fee</strong> = Pool Fees
        </p>
        <nav class="tx-pager" aria-label="Pagination">
          <a
            class="bsx-btn bsx-btn-small"
            :class="{ 'is-disabled': !hasPrev }"
            :href="hasPrev ? pageUrl(prevStart) : undefined"
            :aria-disabled="!hasPrev || undefined"
          >‹ Prev</a>
          <span class="tx-pager-info">
            Showing {{ i.start + 1 }}–{{ i.start + i.transactions.length }}
          </span>
          <a
            class="bsx-btn bsx-btn-small"
            :class="{ 'is-disabled': !hasNext }"
            :href="hasNext ? pageUrl(nextStart) : undefined"
            :aria-disabled="!hasNext || undefined"
          >Next ›</a>
        </nav>
      </footer>
    </article>
  </div>
</template>

<style scoped>
.transactions-v2 {
  padding: 1em;
  color: var(--text-primary, #cdd);
  font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.bsx-card header.tx-summary-head {
  display: grid;
  grid-template-columns: 1fr auto 1fr;
  align-items: center;
}
.tx-summary-head h3 { text-align: left; }
.tx-summary-coin {
  font-size: 13px;
  font-weight: 700;
  letter-spacing: 0.04em;
  color: #4fc3f7;
  text-align: center;
  white-space: nowrap;
}
.tx-summary-spacer {}
.tx-summary-coin-select {
  justify-self: center;
  text-transform: none;
}
.tx-summary-empty {
  padding: 12px;
  text-align: center;
  color: #99a;
  font-size: 12px;
  font-style: italic;
}
.tx-summary-card .tx-summary-table th,
.tx-summary-card .tx-summary-table td,
.tx-summary-card .tx-summary-table td.td-amount {
  text-align: center;
}
.tx-summary-table th {
  font-size: 11px;
  letter-spacing: 0.04em;
}
.tx-summary-table td {
  font-size: 12px;
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
  flex-wrap: wrap;
  gap: 12px;
}
.bsx-card h3 {
  margin: 0;
  font-size: 13px;
  text-transform: uppercase;
  color: #cdd;
  letter-spacing: 0.04em;
}
.bsx-card-body { padding: 0; }

.tx-filter-form {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  flex-wrap: wrap;
  gap: 6px;
  flex: 0 0 auto;
}
.tx-filter-select {
  font: inherit;
  font-size: 12px;
  padding: 3px 24px 3px 8px;
  background: rgba(255,255,255,.04);
  border: 1px solid rgba(255,255,255,.10);
  border-radius: 4px;
  color: #f0f0f0;
  appearance: none;
  -webkit-appearance: none;
  background-image: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 12 12'><path d='M3 5l3 3 3-3' fill='none' stroke='%23cdd' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'/></svg>");
  background-repeat: no-repeat;
  background-position: right 6px center;
  background-size: 10px 10px;
  cursor: pointer;
  max-width: 180px;
}
.tx-filter-coin {
  min-width: 150px;
  max-width: 230px;
}
.tx-filter-select:focus {
  outline: 2px solid rgba(79, 195, 247, 0.55);
  outline-offset: 0;
}
.tx-filter-input {
  font: inherit;
  font-size: 12px;
  padding: 3px 8px;
  background: rgba(255,255,255,.04);
  border: 1px solid rgba(255,255,255,.10);
  border-radius: 4px;
  color: #f0f0f0;
  width: 130px;
  box-sizing: border-box;
}
.tx-filter-input:focus {
  outline: 2px solid rgba(79, 195, 247, 0.55);
  outline-offset: 0;
}
.tx-filter-input::placeholder {
  color: #99a;
  opacity: 0.7;
}
.tx-filter-input-wide { width: 200px; }

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
  text-decoration: none;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  transition: background 150ms ease, border-color 150ms ease, opacity 150ms ease;
}
.bsx-btn:hover:not(.is-disabled) {
  background: rgba(79, 195, 247, 0.20);
  border-color: rgba(79, 195, 247, 0.55);
}
.bsx-btn.is-disabled {
  opacity: 0.4;
  cursor: not-allowed;
  pointer-events: none;
}
.bsx-btn-primary {
  background: rgba(79, 195, 247, 0.16);
  border-color: rgba(79, 195, 247, 0.45);
  color: #e0f0fa;
}
.bsx-btn-small { padding: 4px 10px; font-size: 12px; }

.tx-table-wrap { overflow-x: auto; }
.tx-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 12px;
}
.tx-table th,
.tx-table td {
  padding: 6px 10px;
  text-align: left;
  border-bottom: 1px solid rgba(255,255,255,.05);
  white-space: nowrap;
}
.tx-table thead th {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: #99a;
  font-weight: 700;
  background: rgba(255,255,255,0.02);
  border-bottom-color: rgba(255,255,255,0.10);
}
.tx-table tbody tr:nth-child(even) td {
  background: rgba(255,255,255,0.015);
}
.tx-table tbody tr:last-child td { border-bottom: 0; }

.tx-status {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.02em;
  border: 1px solid transparent;
}
.tx-status-confirmed {
  background: rgba(181, 231, 160, 0.18);
  border-color: rgba(181, 231, 160, 0.45);
  color: #b5e7a0;
}
.tx-status-unconfirmed {
  background: rgba(245, 203, 167, 0.18);
  border-color: rgba(245, 203, 167, 0.45);
  color: #f5cba7;
}
.tx-status-orphan {
  background: rgba(229, 115, 115, 0.18);
  border-color: rgba(229, 115, 115, 0.45);
  color: #e57373;
}

.th-id, .td-id, .th-block, .td-block, .th-amount, .td-amount,
.td-txid, .td-addr {
  font-variant-numeric: tabular-nums;
}
.td-id, .td-block, .td-amount, .td-txid, .td-addr {
  font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
  font-size: 12px;
}
.td-user {
  font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
  font-size: 12px;
  font-weight: 600;
  color: #e0f0fa;
}
.th-amount, .td-amount { text-align: right; }
.tx-amount-credit { color: #b5e7a0; }
.tx-amount-debit  { color: #e57373; }

.td-addr a, .td-txid a, .td-block a {
  color: #4fc3f7;
  text-decoration: none;
}
.td-addr a:hover, .td-txid a:hover, .td-block a:hover {
  text-decoration: underline;
}

.empty-row {
  text-align: center;
  opacity: 0.6;
  padding: 14px 0;
}
.muted { opacity: 0.55; }

.tx-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 8px 14px;
  background: rgba(255,255,255,0.02);
  border-top: 1px solid rgba(255,255,255,0.06);
  flex-wrap: wrap;
}
.tx-legend {
  margin: 0;
  font-size: 11px;
  opacity: 0.7;
  color: #cdd;
}
.tx-legend strong { color: #4fc3f7; font-weight: 700; }
.tx-pager {
  display: flex;
  align-items: center;
  gap: 8px;
}
.tx-pager-info {
  font-size: 11px;
  opacity: 0.65;
  color: #cdd;
  font-variant-numeric: tabular-nums;
}
</style>
