<script setup lang="ts">
import type { WorkerRow } from '../api/types';
import { autoScaleHashrate } from '../composables/useHashrateUnit';

withDefaults(defineProps<{
  workers?: WorkerRow[];
  loading?: boolean;
}>(), {
  workers: () => [],
  loading: false,
});

function formatHashrate(khs: number): string {
  const s = autoScaleHashrate(khs);
  return `${s.value.toFixed(2)} ${s.unit}`;
}

function formatDifficulty(diff?: number): string {
  if (!Number.isFinite(diff)) return '—';
  return Math.round(diff as number).toLocaleString('en-US');
}
</script>

<template>
  <table class="bsx-workers-table">
    <thead>
      <tr>
        <th class="left">Worker</th>
        <th class="right">Hashrate</th>
        <th class="right">Avg Share Diff</th>
      </tr>
    </thead>
    <tbody>
      <tr v-if="loading && workers.length === 0">
        <td colspan="3" class="muted">Loading workers…</td>
      </tr>
      <tr v-else-if="workers.length === 0">
        <td colspan="3" class="muted">No worker information available</td>
      </tr>
      <tr v-for="w in workers" :key="w.id">
        <td class="left">{{ w.username }}</td>
        <td class="right">{{ formatHashrate(w.hashrate) }}</td>
        <td class="right">{{ formatDifficulty(w.difficulty) }}</td>
      </tr>
    </tbody>
  </table>
</template>

<style scoped>
.bsx-workers-table {
  width: 100%;
  border-collapse: collapse;
  margin-top: 8px;
}
.bsx-workers-table th, .bsx-workers-table td {
  padding: 5px 8px;
  font-size: 14px;
  border-bottom: 1px solid rgba(255,255,255,.05);
}
.bsx-workers-table th {
  background: rgba(255,255,255,.04);
  color: #cdd;
}
.left  { text-align: left; }
.right { text-align: right; }
.muted { opacity: 0.55; text-align: center; }
</style>
