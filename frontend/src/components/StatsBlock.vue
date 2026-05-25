<script setup lang="ts">
// Single stats card for one coin: PPLNS Target (if applicable) +
// Round Shares + Payout Estimates + Network Info. Mirrors the
// legacy templates/mpos/dashboard/system_stats.tpl (which itself
// includes round_shares.tpl + payout_estimates.tpl + network_info.tpl).
//
// Consumes a pre-shaped CoinStats snapshot (see api/types.ts) that the
// v2 PHP controller assembles by calling smarty_globals.inc.php and
// reading $GLOBAL.{roundshares,roundshares_mm{,1,3,4,5},
// userdata.shares*, userdata.estimates*}, plus per-coin
// bitcoin->getdifficulty/getblockcount.

import type { CoinStats } from '../api/types';

const props = defineProps<{
  stats: CoinStats;
}>();

function fmt(n: number, decimals = 0): string {
  if (!Number.isFinite(n)) return '0';
  return n.toLocaleString('en-US', {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });
}
function fmt8(n: number): string { return fmt(n, 8); }

function pct(invalid: number, valid: number): string {
  const total = valid + invalid;
  if (total <= 0) return '0.00%';
  return `${((invalid / total) * 100).toFixed(2)}%`;
}

function secondsToWords(s: number): string {
  if (!Number.isFinite(s) || s <= 0) return '—';
  if (s < 60) return `${Math.round(s)} sec`;
  if (s < 3600) return `${Math.round(s / 60)} min`;
  if (s < 86400) {
    const h = Math.floor(s / 3600);
    const m = Math.round((s % 3600) / 60);
    return m > 0 ? `${h}h ${m}m` : `${h}h`;
  }
  const d = Math.floor(s / 86400);
  const h = Math.round((s % 86400) / 3600);
  return h > 0 ? `${d}d ${h}h` : `${d}d`;
}

function handleCoinIconError(event: Event): void {
  const img = event.target as HTMLImageElement | null;
  if (!img) return;
  if (props.stats.icon_fallback_url && img.dataset.fallbackApplied !== '1') {
    img.dataset.fallbackApplied = '1';
    img.src = props.stats.icon_fallback_url;
    return;
  }
  img.style.display = 'none';
}
</script>

<template>
  <article class="bsx-stats-block">
    <header>
      <h3>{{ stats.currency }} {{ stats.payout_system }} Stats</h3>
      <img
        v-if="stats.icon_url"
        :src="stats.icon_url"
        :alt="stats.currency"
        class="stats-coin-icon"
        loading="lazy"
        @error="handleCoinIconError"
      />
    </header>
    <div class="content">
      <table>
        <tbody>
          <tr v-if="stats.payout_system === 'pplns' && stats.pplns_target !== null && stats.pplns_target !== ''">
            <td class="label"><b>PPLNS Target</b></td>
            <td class="right">{{ stats.pplns_target }}</td>
          </tr>

          <tr><td colspan="2" class="section-head"><u>Round Shares</u></td></tr>
          <tr>
            <td class="label">Est. Shares</td>
            <td class="right">{{ fmt(stats.roundshares.estimated) }} (done: {{ stats.roundshares.progress.toFixed(2) }}%)</td>
          </tr>
          <tr>
            <td class="label">Pool Valid</td>
            <td class="right">{{ fmt(stats.roundshares.valid) }}</td>
          </tr>
          <tr>
            <td class="label">Your Valid</td>
            <td class="right">{{ fmt(stats.your_shares.valid) }}</td>
          </tr>
          <tr>
            <td class="label">Pool Invalid</td>
            <td class="right">
              {{ fmt(stats.roundshares.invalid) }}
              ({{ pct(stats.roundshares.invalid, stats.roundshares.valid) }})
            </td>
          </tr>
          <tr>
            <td class="label">Your Invalid</td>
            <td class="right">
              {{ fmt(stats.your_shares.invalid) }}
              ({{ pct(stats.your_shares.invalid, stats.your_shares.valid) }})
            </td>
          </tr>

          <tr><td colspan="2" class="section-head"><u>{{ stats.currency }} Estimates</u></td></tr>
          <template v-if="stats.payout_system !== 'pps'">
            <tr><td class="label">Block</td><td class="right">{{ fmt8(stats.estimates.block) }}</td></tr>
            <tr><td class="label">Fees</td><td class="right">{{ fmt8(stats.estimates.fee) }}</td></tr>
            <tr><td class="label">Donation</td><td class="right">{{ fmt8(stats.estimates.donation) }}</td></tr>
            <tr><td class="label">Payout</td><td class="right">{{ fmt8(stats.estimates.payout) }}</td></tr>
          </template>
          <template v-else>
            <tr><td class="label">in 1 hour</td><td class="right">{{ fmt8(stats.estimates.hours1) }}</td></tr>
            <tr><td class="label">in 24 hours</td><td class="right">{{ fmt8(stats.estimates.hours24) }}</td></tr>
            <tr><td class="label">in 7 days</td><td class="right">{{ fmt8(stats.estimates.days7) }}</td></tr>
            <tr><td class="label">in 14 days</td><td class="right">{{ fmt8(stats.estimates.days14) }}</td></tr>
            <tr><td class="label">in 30 days</td><td class="right">{{ fmt8(stats.estimates.days30) }}</td></tr>
          </template>

          <tr><td colspan="2" class="section-head"><u>Network Info</u></td></tr>
          <tr>
            <td class="label">Difficulty</td>
            <td class="right">{{ fmt(stats.network.difficulty, 8) }}</td>
          </tr>
          <tr>
            <td class="label">Est. Avg. Time per Block</td>
            <td class="right">{{ secondsToWords(stats.network.esttimeperblock) }}</td>
          </tr>
          <tr>
            <td class="label">Current Block</td>
            <td class="right">{{ stats.network.block }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </article>
</template>

<style scoped>
.bsx-stats-block {
  background: rgba(255,255,255,.03);
  border: 1px solid rgba(255,255,255,.06);
  border-radius: 6px;
  margin-bottom: 1em;
  overflow: hidden;
}
.bsx-stats-block header {
  background: rgba(255,255,255,.05);
  padding: 8px 4px;
  border-bottom: 1px solid rgba(255,255,255,.06);
  position: relative;
}
.bsx-stats-block h3 {
  margin: 0;
  font-size: 13px;
  text-transform: uppercase;
  color: #cdd;
  letter-spacing: 0.04em;
}
.bsx-stats-block .stats-coin-icon {
  position: absolute;
  right: 8px;
  top: 50%;
  transform: translateY(-50%);
  width: 33px;
  height: 33px;
  object-fit: contain;
  border-radius: 4px;
  opacity: 0.95;
}
.bsx-stats-block .content { padding: 8px 12px; }
.bsx-stats-block table { width: 100%; border-collapse: collapse; }
.bsx-stats-block td {
  padding: 4px 6px;
  font-size: 12px;
  color: #cdd;
}
.bsx-stats-block .section-head {
  padding-top: 10px;
  font-weight: 700;
  color: #4fc3f7;
}
.bsx-stats-block .right { text-align: right; }
.bsx-stats-block .label { font-weight: 600; }
</style>
