<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { useDashboardData } from '../../composables/useDashboardData';
import { useUserBalance } from '../../composables/useUserBalance';
import { useUserWorkers } from '../../composables/useUserWorkers';
import { autoScaleHashrate } from '../../composables/useHashrateUnit';
import { useSse } from '../../composables/useSse';
import Gauge from '../../components/Gauge.vue';
import HashrateChart from '../../components/HashrateChart.vue';
import SharesDonut from '../../components/SharesDonut.vue';
import BalanceCard from '../../components/BalanceCard.vue';
import WorkersTable from '../../components/WorkersTable.vue';
import StatsBlock from '../../components/StatsBlock.vue';
import type { CoinStats, PoolMessage } from '../../api/types';

type Point = [number, number];

interface InitialBalance {
  key: string;
  currency: string;
  confirmed: number;
  unconfirmed: number;
  // Wave 2: pending payout broadcast on chain, not yet reconciled.
  // Excluded from confirmed by the PHP getBalance SQL so confirmed
  // never goes negative. Optional for forward-compat with deploys
  // that haven't picked up the new field.
  inflight?: number;
}

const props = withDefaults(defineProps<{
  apiKey: string;
  userId: number;
  refreshMs: number;
  longRefreshMs: number;
  payoutSystem: string;
  currency: string;
  pplnsTarget: string;
  initialBalances?: InitialBalance[];
  initialStats?: CoinStats[];
  initialMessages?: PoolMessage[];
  sessionKey?: string;
}>(), {
  initialBalances: () => [],
  initialStats: () => [],
  initialMessages: () => [],
  sessionKey: 'anon',
});

const { data, error } = useDashboardData(props.apiKey, props.userId, props.refreshMs);
const { data: balanceResp } = useUserBalance(props.apiKey, props.userId, props.longRefreshMs);
const { data: workersResp } = useUserWorkers(props.apiKey, props.userId, props.longRefreshMs);

// SSE side-car (cronjobs-py/cronjobs_py/sse.py) emits a `stats` event
// every ~10 s with `pool_khs` and `net_khs`. We prefer those over the
// AJAX poll's values when they arrive — sub-second push update path,
// independent of the 10 s AJAX cadence.
const { lastEvent } = useSse('/sse/pool');
const ssePoolKhs = ref<number | null>(null);
const sseNetKhs = ref<number | null>(null);
watch(lastEvent, (ev) => {
  if (ev?.type === 'stats') {
    ssePoolKhs.value = ev.pool_khs;
    sseNetKhs.value = ev.net_khs;
  }
});

// Rolling 20-point buffers for the trend chart — same cadence + size
// as legacy js_api.tpl.
const BUFFER_SIZE = 20;
const personalHashrateBuf = ref<Point[]>([]);
const poolHashrateBuf = ref<Point[]>([]);
const personalSharerateBuf = ref<Point[]>([]);

watch(data, (d) => {
  if (!d) return;
  const now = Date.now();
  const dd = d.getdashboarddata.data;
  const append = (buf: Point[], pt: Point) => {
    buf.push(pt);
    while (buf.length > BUFFER_SIZE) buf.shift();
  };
  append(personalHashrateBuf.value, [now, dd.raw.personal.hashrate]);
  append(poolHashrateBuf.value, [now, dd.raw.pool.hashrate]);
  append(personalSharerateBuf.value, [now, dd.personal.sharerate]);
  personalHashrateBuf.value = [...personalHashrateBuf.value];
  poolHashrateBuf.value = [...poolHashrateBuf.value];
  personalSharerateBuf.value = [...personalSharerateBuf.value];
});

// Three primary gauges
const pool = computed(() => {
  const khs = ssePoolKhs.value ?? data.value?.getdashboarddata.data.pool.hashrate ?? 0;
  return autoScaleHashrate(khs);
});
const personal = computed(() => {
  const khs = data.value?.getdashboarddata.data.personal.hashrate ?? 0;
  return autoScaleHashrate(khs);
});
const network = computed(() => {
  const khs = sseNetKhs.value ?? data.value?.getdashboarddata.data.network.hashrate ?? 0;
  return autoScaleHashrate(khs);
});

// Sub-gauges
const sharerate = computed(() => data.value?.getdashboarddata.data.personal.sharerate ?? 0);
const querytime = computed(() => Math.round(data.value?.getdashboarddata.runtime ?? 0));
const sharerateMax = computed(() => {
  const v = sharerate.value;
  return v > 1 ? Math.round(v * 2) : 1;
});
const gaugeMax = (value: number) => (value > 0 ? Math.round(value * 2) : 1);

// Donut data
const donutData = computed(() => ({
  personalValid: data.value?.getdashboarddata.data.personal.shares.valid ?? 0,
  poolValid: data.value?.getdashboarddata.data.pool.shares.valid ?? 0,
  personalInvalid: data.value?.getdashboarddata.data.personal.shares.invalid ?? 0,
  poolInvalid: data.value?.getdashboarddata.data.pool.shares.invalid ?? 0,
}));

// Sidebar data — start from controller-rendered snapshot of all 6 coins
// (primary + 5 mergemine), then keep the primary live-updated via the
// AJAX poll. Mergemine balances stay snapshot-only until the API
// exposes them per-coin; flagged as a follow-up.
const allBalances = computed(() => {
  const snapshot = props.initialBalances.slice();
  if (snapshot.length === 0) return snapshot;
  const live = balanceResp.value?.getuserbalance.data;
  if (live && snapshot[0]) {
    snapshot[0] = {
      ...snapshot[0],
      confirmed: live.confirmed ?? snapshot[0].confirmed,
      unconfirmed: live.unconfirmed ?? snapshot[0].unconfirmed,
      inflight: live.inflight ?? snapshot[0].inflight,
    };
  }
  return snapshot;
});
const workersList = computed(() => {
  return workersResp.value?.getuserworkers.data ?? [];
});

// Banner. fees/noFees/donatePercent are hardcoded to match the admin seed
// (no_fees=1, donate_percent=0.0). TODO: surface via controller — legacy
// reads $GLOBAL.fees / $GLOBAL.userdata.no_fees / .donate_percent.
const fees = computed(() => 0);
const noFees = computed(() => true);
const donatePercent = computed(() => 0);

// Pool messages — instead of an overlay, the gauges card flips in
// place to show the messages on its "back". Dismissal stored in
// sessionStorage keyed by sessionKey so logout-and-back-in surfaces
// them again (PHP regenerates session id on auth → storage namespace
// flips with it).
const STORAGE_KEY = `mpos-v2-msgs-dismissed:${props.sessionKey}`;
const showMessages = ref(false);

function readDismissed(): string[] {
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY);
    return raw ? (JSON.parse(raw) as string[]) : [];
  } catch {
    return [];
  }
}
function writeDismissed(ids: string[]) {
  try { sessionStorage.setItem(STORAGE_KEY, JSON.stringify(ids)); } catch { /* ignore */ }
}

const undismissedMessages = computed(() => {
  const dismissed = new Set(readDismissed());
  return props.initialMessages.filter((m) => !dismissed.has(m.id));
});

// On first paint with undismissed messages we auto-flip to the back
// face (messages). After 8 s we auto-flip back to the gauges and
// persist dismissal so we don't auto-flip again this session. The
// timer is canceled if the user clicks the chip first.
let autoFlipTimer: number | null = null;
function dismissAll() {
  const all = props.initialMessages.map((m) => m.id);
  writeDismissed(all);
}
function cancelAutoFlip() {
  if (autoFlipTimer !== null) {
    clearTimeout(autoFlipTimer);
    autoFlipTimer = null;
  }
}

// Toggle: flipping TO messages = just show. Flipping BACK FROM
// messages = persist dismissal so we don't auto-flip again this
// session. Any manual click cancels the pending auto-flip timer.
function toggleMessages() {
  cancelAutoFlip();
  if (showMessages.value) {
    dismissAll();
    showMessages.value = false;
  } else {
    showMessages.value = true;
  }
}

if (typeof window !== 'undefined' && undismissedMessages.value.length > 0) {
  showMessages.value = true;
  autoFlipTimer = window.setTimeout(() => {
    autoFlipTimer = null;
    // Only flip back if we're still on the messages face — user may
    // have manually flipped back already (which clears this timer
    // anyway, but we double-check defensively).
    if (showMessages.value) {
      dismissAll();
      showMessages.value = false;
    }
  }, 8000);
}

// `posted` is ISO YYYY-MM-DD from PHP; render as MM/DD/YY for the
// card corner. Pure-string parsing (no Date()) so timezone shifts can't
// roll the day backward.
function formatDate(iso: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
  if (!m) return iso;
  const [, yyyy, mm, dd] = m;
  return `${mm}/${dd}/${yyyy.slice(2)}`;
}
</script>

<template>
  <div class="dashboard-v2">
    <div v-if="error" class="error">
      <strong>API error:</strong> {{ error.message }}
    </div>

    <div v-else-if="!data" class="loading">Loading…</div>

    <template v-else>
      <div class="dashboard-grid">
        <!-- Main content column -->
        <div class="dashboard-main">
          <article class="bsx-card">
            <header class="overview-header">
              <h3>Overview / Pool Workers: {{ data.getdashboarddata.data.pool.workers }}</h3>
              <button
                v-if="props.initialMessages.length > 0"
                type="button"
                class="bsx-msg-chip"
                :class="{ 'is-active': showMessages }"
                @click="toggleMessages"
              >
                <span class="bsx-msg-chip-dot" :class="{ 'is-active': showMessages }"></span>
                <span v-if="!showMessages">
                  {{ props.initialMessages.length }} message<span v-if="props.initialMessages.length !== 1">s</span>
                </span>
                <span v-else>Back to dashboard</span>
              </button>
            </header>
            <div class="bsx-card-body">
              <!-- Flip stage wraps ONLY the gauges row. Donut + trend chart
                   stay visible below regardless of which face is showing. -->
              <div class="flip-stage" :class="{ flipped: showMessages }">
                <div class="flip-inner">
                  <div class="flip-front">
              <div class="bsx-row bsx-row-center">
                <div class="bsx-col">
                  <Gauge
                    :value="pool.value"
                    :min="0"
                    :max="gaugeMax(pool.value)"
                    title="Pool Hashrate"
                    :unit="pool.unit"
                    :width="240"
                    :height="180"
                  />
                  <Gauge
                    :value="sharerate"
                    :min="0"
                    :max="sharerateMax"
                    title="Sharerate"
                    unit="shares/s"
                    :width="120"
                    :height="90"
                    :decimals="2"
                  />
                </div>
                <div class="bsx-col">
                  <Gauge
                    :value="personal.value"
                    :min="0"
                    :max="gaugeMax(personal.value)"
                    title="Hashrate"
                    :unit="personal.unit"
                    :width="440"
                    :height="320"
                  />
                </div>
                <div class="bsx-col">
                  <Gauge
                    :value="network.value"
                    :min="0"
                    :max="gaugeMax(network.value)"
                    title="Net Hashrate"
                    :unit="network.unit"
                    :width="240"
                    :height="180"
                  />
                  <Gauge
                    :value="querytime"
                    :min="0"
                    :max="500"
                    title="Querytime"
                    unit="ms"
                    :width="120"
                    :height="90"
                    :decimals="0"
                  />
                </div>
              </div>
                  </div>
                  <!-- BACK: pool messages list. Absolute over the gauges
                       row only; donut + trend chart stay below visible.
                       Scrolls if messages exceed the gauges row height. -->
                  <div class="flip-back">
                    <div class="flip-back-inner">
                      <article
                        v-for="m in props.initialMessages"
                        :key="m.id"
                        class="bsx-msg"
                        :class="`bsx-msg-${m.type}`"
                      >
                        <!-- Plain <div> here, NOT <header>: legacy
                             `.module header { height: 38px; background: ... }`
                             would force a 38 px dark banner since the v2 page
                             is rendered inside <article class="module ..."> -->
                        <div v-if="m.title || m.posted" class="bsx-msg-head">
                          <h4 v-if="m.title">{{ m.title }}</h4>
                          <time
                            v-if="m.posted"
                            class="bsx-msg-date"
                            :datetime="m.posted"
                          >{{ formatDate(m.posted) }}</time>
                        </div>
                        <div class="bsx-msg-body" v-html="m.body"></div>
                      </article>
                      <p v-if="props.initialMessages.length === 0" class="bsx-msg-empty">
                        No pool messages.
                      </p>
                    </div>
                  </div>
                </div>
              </div>

              <SharesDonut
                :personal-valid="donutData.personalValid"
                :pool-valid="donutData.poolValid"
                :personal-invalid="donutData.personalInvalid"
                :pool-invalid="donutData.poolInvalid"
                :height="210"
              />

              <HashrateChart
                :personal="personalHashrateBuf"
                :pool="poolHashrateBuf"
                :sharerate="personalSharerateBuf"
                :refresh-seconds="props.refreshMs / 1000"
                :height="240"
              />
            </div>
          </article>

        </div>

        <!-- Sidebar -->
        <aside class="dashboard-sidebar">
          <article class="bsx-card">
            <header><h3>Account Information</h3></header>
            <div class="bsx-card-body">
              <p class="banner">
                <template v-if="noFees">You are mining without any pool fees applied</template>
                <template v-else-if="fees > 0">You are mining at <span class="fees">{{ fees }}%</span> pool fee</template>
                <template v-else>This pool does not apply fees</template>
                <template v-if="donatePercent > 0"> and you donate <span class="donate">{{ donatePercent }}%</span>.</template>
                <template v-else> and you are not donating.</template>
              </p>

              <div class="account-fixed">
                <BalanceCard
                  v-for="b in allBalances"
                  :key="b.key"
                  :currency="b.currency"
                  :confirmed="b.confirmed"
                  :unconfirmed="b.unconfirmed"
                  :inflight="b.inflight ?? 0"
                />
              </div>

              <!-- Workers area takes any remaining vertical space inside
                   the stretched sidebar; the inner table scrolls when
                   it overflows. -->
              <div class="account-workers">
                <WorkersTable :workers="workersList" :loading="!workersResp" />
              </div>
            </div>
          </article>
        </aside>
      </div>

      <!-- Per-coin stats — full-width row below the main + sidebar grid. -->
      <div class="bsx-stats-grid">
        <StatsBlock
          v-for="s in props.initialStats"
          :key="s.key"
          :stats="s"
        />
      </div>

      <p class="footnote">
        Refresh interval: {{ props.refreshMs / 1000 }} seconds. Hashrate based on shares submitted in the past 5 minutes. ·
        Payout system: <code>{{ props.payoutSystem }}</code>
      </p>

    </template>
  </div>
</template>

<style scoped>
.dashboard-v2 {
  padding: 1em;
  color: var(--text-primary, #cdd);
  font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
}
.error  {
  color: #e57373;
  padding: 0.75em;
  background: rgba(229,115,115,.1);
  border-radius: 4px;
}
.loading { opacity: 0.6; }

/* Main + sidebar two-column layout. align-items: stretch (default) so
   both columns share the row height. The grid row picks max of the two
   columns' intrinsic heights — but the sidebar's WORKERS area is
   flex: 1 1 0 so its content doesn't contribute to the sidebar's
   intrinsic, which means the row settles to the main column's height
   and the sidebar stretches to match. Workers list scrolls inside.
   Falls back to single column under 1024 px (no stretch, no scroll). */
.dashboard-grid {
  display: grid;
  grid-template-columns: minmax(0, 3fr) minmax(280px, 1fr);
  gap: 16px;
}
@media (max-width: 1024px) {
  .dashboard-grid { grid-template-columns: 1fr; }
  .dashboard-sidebar .bsx-card { height: auto; }
  .dashboard-sidebar .account-workers {
    overflow-y: visible;
    flex: 0 0 auto;
  }
}

.dashboard-main,
.dashboard-sidebar {
  min-width: 0;
  min-height: 0;
  display: flex;
  flex-direction: column;
}

/* Cards in either column flex to fill their column. */
.dashboard-main > .bsx-card,
.dashboard-sidebar .bsx-card {
  display: flex;
  flex-direction: column;
  flex: 1 1 auto;
  min-height: 0;
  margin-bottom: 0;
}
.dashboard-main > .bsx-card > .bsx-card-body,
.dashboard-sidebar .bsx-card > .bsx-card-body {
  display: flex;
  flex-direction: column;
  flex: 1 1 auto;
  min-height: 0;
  overflow: hidden;
}
.account-fixed { flex: 0 0 auto; }
.account-workers {
  /* flex-basis: 0 — content doesn't contribute to sidebar intrinsic
     height, so the grid row shrinks to the main column's height
     instead of the sidebar pushing it tall. */
  flex: 1 1 0;
  min-height: 80px;          /* floor so the table is always visible */
  overflow-y: auto;
  /* Custom scrollbar matching the dark MPOS theme. Firefox uses the
     `scrollbar-*` properties; WebKit uses the pseudo-elements below. */
  scrollbar-width: thin;
  scrollbar-color: rgba(255, 255, 255, 0.18) transparent;
}
.account-workers::-webkit-scrollbar {
  width: 8px;
}
.account-workers::-webkit-scrollbar-track {
  background: transparent;
}
.account-workers::-webkit-scrollbar-thumb {
  background-color: rgba(255, 255, 255, 0.18);
  border-radius: 4px;
  border: 2px solid transparent;
  background-clip: padding-box;
}
.account-workers::-webkit-scrollbar-thumb:hover {
  background-color: rgba(79, 195, 247, 0.45);
}

/* Reusable card */
.bsx-card {
  background: rgba(255,255,255,.03);
  border: 1px solid rgba(255,255,255,.06);
  border-radius: 6px;
  margin-bottom: 1em;
  overflow: hidden;
}
.bsx-card header {
  background: rgba(255,255,255,.05);
  padding: 8px 4px;
  border-bottom: 1px solid rgba(255,255,255,.06);
}
.bsx-card h3 {
  margin: 0;
  font-size: 13px;
  text-transform: uppercase;
  color: #cdd;
  letter-spacing: 0.04em;
}
.bsx-card-body { padding: 12px; }

/* bsx-row / bsx-col flex primitive */
.bsx-row {
  display: flex;
  flex-direction: row;
  align-items: flex-start;
  justify-content: flex-start;
  gap: 6px;
  width: 100%;
  box-sizing: border-box;
}
.bsx-row-center { justify-content: center; }
.bsx-col {
  flex: 0 0 auto;
  min-width: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
}

/* Full-width 4-up grid for the 6 per-coin stats blocks. Sits below the
   main+sidebar grid so it spans the entire dashboard width. Steps down
   to 3-up under 1400 px, 2-up under 900 px, 1-up under 600 px. */
.bsx-stats-grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 12px;
  margin-top: 1em;
}
@media (max-width: 1400px) {
  .bsx-stats-grid { grid-template-columns: repeat(3, minmax(0, 1fr)); }
}
@media (max-width: 900px) {
  .bsx-stats-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
}
@media (max-width: 600px) {
  .bsx-stats-grid { grid-template-columns: 1fr; }
}
.bsx-stats-grid > * { margin-bottom: 0; }

/* Overview card header — title on the left, chip floats right via
   `margin-left: auto`. Both gutters use em-based units so the gap
   scales with text size, and `clamp()` keeps the right gutter inside
   sane bounds across narrow → wide viewports. */
.overview-header {
  display: flex;
  align-items: center;
  gap: 12px;
  padding-right: clamp(1em, 3vw, 2.5em);
}
.overview-header h3 { flex: 0 1 auto; min-width: 0; }
.bsx-msg-chip {
  flex: 0 0 auto;
  white-space: nowrap;
  margin-left: auto;
  margin-right: 0.85em;
}
.bsx-msg-chip {
  font: inherit;
  font-size: 13px;
  font-weight: 600;
  letter-spacing: 0.04em;
  color: #cdd;
  background: rgba(79, 195, 247, 0.10);
  border: 1px solid rgba(79, 195, 247, 0.28);
  border-radius: 999px;
  padding: 5px 14px 5px 11px;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  gap: 8px;
}
.bsx-msg-chip:hover {
  background: rgba(79, 195, 247, 0.18);
  border-color: rgba(79, 195, 247, 0.55);
}
.bsx-msg-chip.is-active {
  background: rgba(79, 195, 247, 0.22);
  border-color: rgba(79, 195, 247, 0.6);
}
.bsx-msg-chip-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: #4fc3f7;
  box-shadow: 0 0 0 2px rgba(79, 195, 247, 0.18);
  flex-shrink: 0;
  transition: background 200ms ease;
}
.bsx-msg-chip-dot.is-active {
  background: #b5e7a0;
}

/* Flip stage — gauges (front) ↔ messages (back). The container's
   height is driven by the front (in normal flow); the back is
   absolutely positioned and fills it, scrolling when content exceeds
   the front's height. */
.flip-stage {
  perspective: 1500px;
  position: relative;
}
.flip-inner {
  position: relative;
  transition: transform 0.7s cubic-bezier(0.2, 0.8, 0.2, 1);
  transform-style: preserve-3d;
}
.flip-stage.flipped .flip-inner { transform: rotateY(180deg); }
.flip-front,
.flip-back {
  -webkit-backface-visibility: hidden;
  backface-visibility: hidden;
}
.flip-back {
  position: absolute;
  inset: 0;
  transform: rotateY(180deg);
  display: flex;
}
.flip-back-inner {
  flex: 1 1 auto;
  min-height: 0;
  overflow-y: auto;
  overflow-x: hidden;
  scrollbar-width: thin;
  scrollbar-color: rgba(255, 255, 255, 0.18) transparent;
}
.flip-back-inner::-webkit-scrollbar { width: 8px; }
.flip-back-inner::-webkit-scrollbar-track { background: transparent; }
.flip-back-inner::-webkit-scrollbar-thumb {
  background-color: rgba(255, 255, 255, 0.18);
  border-radius: 4px;
  border: 2px solid transparent;
  background-clip: padding-box;
}
.flip-back-inner::-webkit-scrollbar-thumb:hover {
  background-color: rgba(79, 195, 247, 0.45);
}

/* Message cards inside the flip back. Symmetric coloured rails on
   both edges, severity-tinted background. */
.bsx-msg {
  padding: 8px 14px;
  border-radius: 6px;
  margin-bottom: 12px;
  border-left: 3px solid #4fc3f7;
  border-right: 3px solid #4fc3f7;
  background: rgba(79, 195, 247, 0.06);
}
.bsx-msg-success {
  border-left-color: #b5e7a0;
  border-right-color: #b5e7a0;
  background: rgba(181, 231, 160, 0.06);
}
.bsx-msg-warning {
  border-left-color: #f5cba7;
  border-right-color: #f5cba7;
  background: rgba(245, 203, 167, 0.06);
}
/* Header row: title + date. */
.bsx-msg-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 5px;
}
.bsx-msg h4 {
  /* Title rendered as a severity-coloured chip. inline-flex + line-height:1
     keeps top/bottom padding symmetric around the glyph.
     !important is required: the legacy `#main .module_content h4` selector
     has ID-level specificity and bleeds in from the page wrapper. */
  margin: 0 !important;
  font-size: 13px;
  line-height: 1;
  font-weight: 700;
  letter-spacing: 0.02em;
  flex: 0 1 auto;
  min-width: 0;
  display: inline-flex;
  align-items: center;
  padding: 5px 11px;
  border-radius: 4px;
  background: rgba(79, 195, 247, 0.14);
  border: 1px solid rgba(79, 195, 247, 0.40);
  color: #e0f0fa;
}
.bsx-msg-success h4 {
  background: rgba(181, 231, 160, 0.14);
  border-color: rgba(181, 231, 160, 0.40);
  color: #e8f5dd;
}
.bsx-msg-warning h4 {
  background: rgba(245, 203, 167, 0.14);
  border-color: rgba(245, 203, 167, 0.40);
  color: #f9e3d2;
}
.bsx-msg-date {
  flex: 0 0 auto;
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.04em;
  color: #99a;
  background: rgba(255, 255, 255, 0.04);
  padding: 2px 6px;
  border-radius: 3px;
  font-variant-numeric: tabular-nums;
  margin-right: 6px;
}
.bsx-msg p {
  /* !important: same ID-specificity bleed as the .bsx-msg h4 above
     (`#main .module_content p` from the page wrapper). */
  margin: 0 !important;
  font-size: 13px;
  color: #cdd;
  white-space: pre-line;
  line-height: 1.5;
}
/* Rendered news HTML (v-html'd) — basic typography. !important on the
   margins overrides legacy `#main .module_content p/h*` resets. */
.bsx-msg-body { font-size: 13px; color: #cdd; line-height: 1.5; }
.bsx-msg-body h2 { font-size: 16px !important; margin: 0 0 6px !important; color: #4fc3f7; }
.bsx-msg-body h3 { font-size: 13px !important; margin: 10px 0 4px !important; letter-spacing: 0.04em; text-transform: uppercase; }
.bsx-msg-body h4 { font-size: 12px !important; margin: 8px 0 4px !important; }
.bsx-msg-body p  { margin: 0 0 6px !important; }
.bsx-msg-body ul,
.bsx-msg-body ol { margin: 0 0 8px !important; padding-left: 22px; }
.bsx-msg-body li { margin: 0 0 2px !important; }
.bsx-msg-body code,
.bsx-msg-body pre { background: rgba(0,0,0,0.25); padding: 1px 5px; border-radius: 2px; font-family: ui-monospace, Menlo, Consolas, monospace; font-size: 12px; }
.bsx-msg-body pre { padding: 8px 10px; overflow-x: auto; }
.bsx-msg-body a { color: #4fc3f7; }
.bsx-msg-body blockquote { margin: 0 0 8px; padding: 4px 10px; border-left: 3px solid rgba(255,255,255,0.18); font-style: italic; }
.bsx-msg-empty { font-size: 13px; opacity: 0.6; text-align: center; padding: 1em; }

.banner { font-size: 13px; color: #cdd; margin: 0 0 12px; line-height: 1.4; }
.banner .fees { color: #f5cba7; font-weight: 700; }
.banner .donate { color: #b5e7a0; font-weight: 700; }

.footnote {
  text-align: center;
  opacity: 0.55;
  font-size: 0.85em;
  margin-top: 1.2em;
}
.footnote code {
  background: rgba(0,0,0,.3);
  padding: 0 4px;
  border-radius: 2px;
}

/* Light-mode pool-message overrides — when the gauges flip to show
   pool messages, the title chip + body text need dark colours so
   they read against white. Default colours (#e0f0fa / #cdd) are
   tuned for the dark theme and disappear on the light card. */
[data-theme="light"] .bsx-msg h4 {
  background: rgba(25, 118, 210, 0.14);
  border-color: rgba(25, 118, 210, 0.55);
  color: #0d47a1;
}
[data-theme="light"] .bsx-msg-success h4 {
  background: rgba(46, 125, 50, 0.14);
  border-color: rgba(46, 125, 50, 0.55);
  color: #1b5e20;
}
[data-theme="light"] .bsx-msg-warning h4 {
  background: rgba(239, 108, 0, 0.14);
  border-color: rgba(239, 108, 0, 0.55);
  color: #e65100;
}
[data-theme="light"] .bsx-msg p,
[data-theme="light"] .bsx-msg-body { color: #1f2933 !important; }
[data-theme="light"] .bsx-msg-body a { color: #1565c0 !important; }
[data-theme="light"] .bsx-msg-date {
  color: #5a6470;
  background: rgba(0, 0, 0, 0.05);
}
</style>
