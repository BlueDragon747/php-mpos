<script setup lang="ts">
withDefaults(defineProps<{
  currency: string;
  confirmed?: number;
  unconfirmed?: number;
  inflight?: number;
}>(), {
  confirmed: 0,
  unconfirmed: 0,
  inflight: 0,
});

function fmt(n: number): string {
  return n.toFixed(6);
}
</script>

<template>
  <table class="bsx-balance-card">
    <thead>
      <tr><th colspan="2">{{ currency }} Account Balance</th></tr>
    </thead>
    <tbody>
      <tr>
        <td class="label">Confirmed</td>
        <td class="value confirmed">{{ fmt(confirmed) }}</td>
      </tr>
      <tr>
        <td class="label">Unconfirmed</td>
        <td class="value unconfirmed">{{ fmt(unconfirmed) }}</td>
      </tr>
      <!-- In-flight payout: shown only when a recently-broadcast
           Debit_AP/Debit_MP is awaiting reconcile_min_confirmations
           on chain. Reconciler archives it once the txid matures and
           this row drops out automatically. -->
      <tr v-if="inflight > 0">
        <td class="label">In-flight payout</td>
        <td class="value inflight">{{ fmt(inflight) }}</td>
      </tr>
    </tbody>
  </table>
</template>

<style scoped>
.bsx-balance-card {
  width: 100%;
  border-collapse: collapse;
  margin-bottom: 8px;
}
.bsx-balance-card th {
  text-align: left;
  padding: 6px 8px;
  background: rgba(255,255,255,.04);
  color: #cdd;
  font-size: 14px;
  border-bottom: 1px solid rgba(255,255,255,.08);
}
.bsx-balance-card td {
  padding: 5px 8px;
  font-size: 14px;
}
.bsx-balance-card td.label { font-weight: 600; color: #cdd; }
.bsx-balance-card td.value { text-align: right; width: 50%; }
.bsx-balance-card td.confirmed { color: #b5e7a0; }
.bsx-balance-card td.unconfirmed { color: #f5cba7; }
/* Muted so it reads as transient state, not as a positive balance. */
.bsx-balance-card td.inflight { color: #99a; font-style: italic; }
[data-theme="light"] .bsx-balance-card td.inflight { color: #5a6470; }
</style>
