<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount, watch } from 'vue';
import { ensureJqplot } from '../composables/useJqplot';

// Vue wrapper around the legacy jqplot donut chart. Mirrors the
// `jqPlotShareinfoOptions` block in templates/mpos/dashboard/js_api.tpl
// — two concentric rings, outer = valid (your + pool), inner = invalid
// (your + pool). DonutRenderer plugin.

/* eslint-disable @typescript-eslint/no-explicit-any */

const props = withDefaults(defineProps<{
  personalValid: number;
  poolValid: number;
  personalInvalid: number;
  poolInvalid: number;
  height?: number;
}>(), {
  height: 210,
});

const containerEl = ref<HTMLDivElement | null>(null);
const containerId = `bsx-shares-donut-${Math.random().toString(36).slice(2, 10)}`;
let plot: any = null;

function buildOptions(): any {
  const $ = window.$;
  return {
    title: 'Shares',
    highlighter: { show: false },
    grid: { drawBorder: false, background: 'transparent', shadow: false },
    seriesColors: ['#26a4ed', '#ee8310', '#e9e744'],
    seriesDefaults: {
      renderer: $.jqplot.DonutRenderer,
      rendererOptions: {
        ringMargin: 10,
        sliceMargin: 10,
        startAngle: -90,
        showDataLabels: true,
        dataLabels: 'value',
        dataLabelThreshold: 0,
      },
    },
    legend: { show: false },
  };
}

function dataArray(): Array<Array<[string, number]>> {
  // Two rings, each with two labelled slices.
  return [
    [['your valid', props.personalValid || 0], ['pool valid', props.poolValid || 0]],
    [['your invalid', props.personalInvalid || 0], ['pool invalid', props.poolInvalid || 0]],
  ];
}

onMounted(async () => {
  await ensureJqplot();
  if (!containerEl.value) return;
  plot = window.$.jqplot(containerId, dataArray(), buildOptions());
});

watch(
  () => [props.personalValid, props.poolValid, props.personalInvalid, props.poolInvalid],
  () => {
    if (!plot) return;
    // Donut series can't replot just data — destroy + recreate.
    try { plot.destroy(); } catch { /* ignore */ }
    if (containerEl.value) containerEl.value.innerHTML = '';
    plot = window.$.jqplot(containerId, dataArray(), buildOptions());
  }
);

onBeforeUnmount(() => {
  if (plot) {
    try { plot.destroy(); } catch { /* ignore */ }
    plot = null;
  }
  if (containerEl.value) containerEl.value.innerHTML = '';
});
</script>

<template>
  <div
    :id="containerId"
    ref="containerEl"
    :style="{ width: '100%', height: height + 'px' }"
    class="bsx-shares-donut"
  ></div>
</template>

<style scoped>
.bsx-shares-donut { width: 100%; }
</style>
