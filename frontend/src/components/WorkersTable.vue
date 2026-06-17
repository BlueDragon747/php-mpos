<script setup lang="ts">
import { computed, ref } from 'vue';
import type { WorkerRow } from '../api/types';
import { autoScaleHashrate } from '../composables/useHashrateUnit';

const props = withDefaults(defineProps<{
  workers?: WorkerRow[];
  loading?: boolean;
}>(), {
  workers: () => [],
  loading: false,
});

type SortKey = 'name' | 'hashrate' | 'difficulty';
type SortDir = 'asc' | 'desc';

const sortKey = ref<SortKey>('name');
const sortDir = ref<SortDir>('asc');

function workerName(w: WorkerRow): string {
  return String(w.username ?? '');
}

function compareNames(a: WorkerRow, b: WorkerRow): number {
  return workerName(a).localeCompare(workerName(b), undefined, {
    numeric: true,
    sensitivity: 'base',
  });
}

function finiteNumber(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

function setSort(key: SortKey): void {
  if (sortKey.value === key) {
    sortDir.value = sortDir.value === 'asc' ? 'desc' : 'asc';
    return;
  }

  sortKey.value = key;
  sortDir.value = key === 'name' ? 'asc' : 'desc';
}

function sortButtonClass(key: SortKey): Record<string, boolean> {
  return {
    'is-active': sortKey.value === key,
    'is-desc': sortKey.value === key && sortDir.value === 'desc',
  };
}

const sortedWorkers = computed(() => {
  const direction = sortDir.value === 'asc' ? 1 : -1;
  return [...props.workers].sort((a, b) => {
    if (sortKey.value === 'name') {
      return compareNames(a, b) * direction;
    }

    const field = sortKey.value === 'hashrate' ? 'hashrate' : 'difficulty';
    const av = finiteNumber(a[field]);
    const bv = finiteNumber(b[field]);
    if (av === null && bv === null) return compareNames(a, b);
    if (av === null) return 1;
    if (bv === null) return -1;
    const numeric = av === bv ? 0 : av > bv ? 1 : -1;
    return numeric === 0 ? compareNames(a, b) : numeric * direction;
  });
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
        <th class="left" :aria-sort="sortKey === 'name' ? (sortDir === 'asc' ? 'ascending' : 'descending') : 'none'">
          <button type="button" class="sort-head sort-head-left" :class="sortButtonClass('name')" @click="setSort('name')">
            Worker
          </button>
        </th>
        <th class="right" :aria-sort="sortKey === 'hashrate' ? (sortDir === 'asc' ? 'ascending' : 'descending') : 'none'">
          <button type="button" class="sort-head sort-head-right" :class="sortButtonClass('hashrate')" @click="setSort('hashrate')">
            Hashrate
          </button>
        </th>
        <th class="right" :aria-sort="sortKey === 'difficulty' ? (sortDir === 'asc' ? 'ascending' : 'descending') : 'none'">
          <button type="button" class="sort-head sort-head-right" :class="sortButtonClass('difficulty')" @click="setSort('difficulty')">
            Avg Share Diff
          </button>
        </th>
      </tr>
    </thead>
    <tbody>
      <tr v-if="loading && workers.length === 0">
        <td colspan="3" class="muted">Loading workers…</td>
      </tr>
      <tr v-else-if="workers.length === 0">
        <td colspan="3" class="muted">No worker information available</td>
      </tr>
      <tr v-for="w in sortedWorkers" :key="w.id">
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
  position: sticky;
  top: 0;
  z-index: 2;
  background: rgba(255,255,255,.04);
  color: #cdd;
}
.sort-head {
  appearance: none;
  width: 100%;
  padding: 0;
  border: 0;
  background: transparent;
  color: inherit;
  font: inherit;
  font-weight: 700;
  cursor: pointer;
}
.sort-head-left {
  text-align: left;
}
.sort-head-right {
  text-align: right;
}
.sort-head::after {
  content: "";
  display: inline-block;
  width: 0;
  height: 0;
  margin-left: 5px;
  border-left: 4px solid transparent;
  border-right: 4px solid transparent;
  border-bottom: 5px solid currentColor;
  opacity: 0;
  transform: translateY(-1px);
}
.sort-head.is-active::after {
  opacity: 0.75;
}
.sort-head.is-desc::after {
  border-bottom: 0;
  border-top: 5px solid currentColor;
  transform: translateY(1px);
}
.sort-head:focus-visible {
  outline: 1px solid rgba(79,195,247,.75);
  outline-offset: 2px;
}
.left  { text-align: left; }
.right { text-align: right; }
.muted { opacity: 0.55; text-align: center; }
</style>
