<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount, watch } from 'vue';
import { ensureJustGage } from '../composables/useJustGage';

// Thin Vue wrapper over the legacy JustGage 1.0.1 + Raphael 2.1.0 pair
// already bundled in MPOS at /site_assets/mpos/js/. Lets us reuse the
// pixel-exact gauge rendering that the upstream MPOS dashboard has used
// for years — no need to re-port the SVG math, the inner-shadow filter,
// or the colour gradient. We keep the v2 architecture (TS types,
// composables, modular components, Vite build) for everything else.
//
// JustGage init params mirror what `templates/mpos/dashboard/js_api.tpl`
// passes today: gaugeColor #6f7a8a, valueFontColor #555, shadow 0.8/0/10.

const props = withDefaults(defineProps<{
  value: number;
  min?: number;
  max?: number;
  title?: string;
  unit?: string;       // → JustGage `label`
  width?: number;
  height?: number;
  // Override colours if the dark MPOS theme makes a default unreadable.
  gaugeColor?: string;
  valueFontColor?: string;
  titleFontColor?: string;
  labelFontColor?: string;
  shadowOpacity?: number;
  shadowSize?: number;
  shadowVerticalOffset?: number;
  decimals?: number;
}>(), {
  min: 0,
  max: 100,
  title: '',
  unit: '',
  width: 240,
  height: 180,
  gaugeColor: '#6f7a8a',
  valueFontColor: '#888',
  titleFontColor: '#cdd',
  labelFontColor: '#b3b3b3',
  shadowOpacity: 0.8,
  shadowSize: 0,
  shadowVerticalOffset: 10,
  decimals: 2,
});

// JustGage bakes `titleFontColor` into the SVG `fill` attribute at
// construction time and exposes no setter for it after init. CSS would
// also have a hard time discriminating the title from value/label/min/max
// since they share tag (`text`) and Raphael doesn't add classes. So we
// read the active theme at mount and recreate the gauge whenever
// <html data-theme> flips. theme.js (site_assets/mpos/js/theme.js) sets
// data-theme="light"|"dark" on the documentElement.
function pickTitleColor(): string {
  if (typeof document === 'undefined') return props.titleFontColor;
  const theme = document.documentElement.getAttribute('data-theme');
  // In light mode, the default '#cdd' is washed out on white. Use a
  // mid-dark slate so the gauge title is comfortably readable.
  if (theme === 'light') return '#1f2933';
  return props.titleFontColor;
}

// Mirror legacy js_api.tpl: `parseFloat(value).toFixed(2)` before each
// JustGage call. Without this, JustGage prints the raw float and long
// values overflow the gauge box (we just hit `774.116153925313`).
function fmt(v: number): number {
  return Number.isFinite(v) ? Number(v.toFixed(props.decimals)) : 0;
}

// Each instance needs a unique DOM id; JustGage uses it as the SVG anchor.
const containerId = `bsx-gauge-${Math.random().toString(36).slice(2, 10)}`;
const containerEl = ref<HTMLDivElement | null>(null);
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let gauge: any = null;

function buildGauge() {
  if (!containerEl.value) return;
  containerEl.value.innerHTML = '';
  gauge = new window.JustGage({
    id: containerId,
    value: fmt(props.value),
    min: props.min,
    max: props.max,
    title: props.title,
    label: props.unit,
    gaugeColor: props.gaugeColor,
    valueFontColor: props.valueFontColor,
    titleFontColor: pickTitleColor(),
    labelFontColor: props.labelFontColor,
    shadowOpacity: props.shadowOpacity,
    shadowSize: props.shadowSize,
    shadowVerticalOffset: props.shadowVerticalOffset,
    showInnerShadow: true,
  });
}

let themeObserver: MutationObserver | null = null;

onMounted(async () => {
  await ensureJustGage();
  buildGauge();
  // Re-create the gauge when the theme flips so titleFontColor updates.
  themeObserver = new MutationObserver((muts) => {
    for (const m of muts) {
      if (m.type === 'attributes' && m.attributeName === 'data-theme') {
        buildGauge();
        break;
      }
    }
  });
  themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
});

watch(() => props.value, (v) => {
  if (gauge && typeof gauge.refresh === 'function') {
    gauge.refresh(fmt(v));
  }
});

onBeforeUnmount(() => {
  // Raphael leaves SVG nodes inside the container; clear them so a
  // remount (e.g. <KeepAlive>) doesn't double up gauges.
  if (containerEl.value) containerEl.value.innerHTML = '';
  gauge = null;
  if (themeObserver) {
    themeObserver.disconnect();
    themeObserver = null;
  }
});
</script>

<template>
  <div
    :id="containerId"
    ref="containerEl"
    :style="{ width: width + 'px', height: height + 'px' }"
    class="bsx-gauge"
  ></div>
</template>

<style scoped>
.bsx-gauge { display: inline-block; }
</style>
