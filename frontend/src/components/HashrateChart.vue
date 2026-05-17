<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount, watch } from 'vue';
import { ensureJqplot } from '../composables/useJqplot';

// Vue wrapper around the legacy jqplot trend chart. Mirrors the
// `jqPlotOverviewOptions` block in templates/mpos/dashboard/js_api.tpl
// — three series (Own / Pool / Sharerate), dual Y-axis, time on X,
// trendline on Own, enhanced legend with toggle.

/* eslint-disable @typescript-eslint/no-explicit-any */

type Point = [number, number];

const props = withDefaults(defineProps<{
  personal: Point[];
  pool: Point[];
  sharerate: Point[];
  refreshSeconds?: number;
  height?: number;
}>(), {
  refreshSeconds: 10,
  height: 240,
});

const containerEl = ref<HTMLDivElement | null>(null);
const containerId = `bsx-hashrate-chart-${Math.random().toString(36).slice(2, 10)}`;
let plot: any = null;

function buildOptions(): any {
  const $ = window.$;
  return {
    highlighter: { show: true },
    grid: { drawBorder: false, background: 'transparent', shadow: false },
    stackSeries: false,
    seriesColors: ['#26a4ed', '#ee8310', '#e9e744'],
    seriesDefaults: {
      lineWidth: 4,
      shadow: false,
      fill: false,
      fillAndStroke: true,
      fillAlpha: 0.3,
      trendline: { show: true, color: '#be1e2d', lineWidth: 1.0, label: 'Your Average', shadow: true },
      markerOptions: { show: true, size: 6 },
      rendererOptions: { smooth: true },
    },
    series: [
      { yaxis: 'yaxis', label: 'Own', fill: true },
      { yaxis: 'yaxis', label: 'Pool', fill: false, trendline: { show: false }, lineWidth: 2, markerOptions: { show: true, size: 4 } },
      { yaxis: 'y3axis', label: 'Sharerate', fill: false, trendline: { show: false } },
    ],
    legend: {
      show: true,
      location: 'sw',
      renderer: $.jqplot.EnhancedLegendRenderer,
      rendererOptions: { seriesToggleReplot: { resetAxes: true } },
    },
    axes: {
      yaxis: {
        min: 0,
        pad: 1.25,
        label: 'Hashrate',
        labelRenderer: $.jqplot.CanvasAxisLabelRenderer,
      },
      y3axis: {
        min: 0,
        pad: 1.25,
        label: 'Sharerate',
        labelRenderer: $.jqplot.CanvasAxisLabelRenderer,
      },
      xaxis: {
        showTicks: false,
        tickInterval: props.refreshSeconds,
        labelRenderer: $.jqplot.CanvasAxisLabelRenderer,
        renderer: $.jqplot.DateAxisRenderer,
        angle: 30,
        tickOptions: { formatString: '%T' },
      },
    },
  };
}

function dataArray(): Point[][] {
  // jqplot needs at least one point per series at init; if a series is
  // empty, give it a placeholder so the plot can render.
  const placeholder: Point = [Date.now(), 0];
  return [
    props.personal.length > 0 ? props.personal : [placeholder],
    props.pool.length > 0 ? props.pool : [placeholder],
    props.sharerate.length > 0 ? props.sharerate : [placeholder],
  ];
}

onMounted(async () => {
  await ensureJqplot();
  if (!containerEl.value) return;
  plot = window.$.jqplot(containerId, dataArray(), buildOptions());
});

watch(
  () => [props.personal, props.pool, props.sharerate],
  () => {
    if (!plot) return;
    plot.series[0].data = props.personal;
    plot.series[1].data = props.pool;
    plot.series[2].data = props.sharerate;
    plot.replot({ resetAxes: true });
  },
  { deep: true }
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
    class="bsx-hashrate-chart"
  ></div>
</template>

<style scoped>
.bsx-hashrate-chart { width: 100%; }
</style>

<style>
.jqplot-highlighter-tooltip {
  background: rgba(20, 23, 28, 0.96) !important;
  border: 1px solid rgba(79, 195, 247, 0.35) !important;
  color: #cdd !important;
  padding: 6px 10px !important;
  border-radius: 4px !important;
  font-size: 11px !important;
  font-weight: 500 !important;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.45) !important;
}
[data-theme="light"] .jqplot-highlighter-tooltip {
  background: #ffffff !important;
  border-color: rgba(21, 101, 192, 0.40) !important;
  color: #1f2933 !important;
  box-shadow: 0 4px 12px rgba(21, 101, 192, 0.15) !important;
}
</style>
