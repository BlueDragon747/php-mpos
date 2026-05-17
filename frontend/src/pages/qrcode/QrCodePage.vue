<script setup lang="ts">
import { ref, onMounted, watch } from 'vue';
import QRCode from 'qrcode';
import type { QrCodeInitial } from './types';

const props = defineProps<{
  initial: QrCodeInitial;
}>();

const i = props.initial;

// Render the QR onto a <canvas> after mount. Re-renders on theme
// change so the colours match dark/light mode.
const canvasRef = ref<HTMLCanvasElement | null>(null);
const renderError = ref('');

async function drawQr() {
  if (!canvasRef.value || !i.payload) return;
  // Pull foreground/background straight from CSS custom properties
  // we set in the wrapper template — that way light mode swaps
  // automatically without us hard-coding.
  const styles = getComputedStyle(document.documentElement);
  const isLight = document.documentElement.getAttribute('data-theme') === 'light';
  const dark = isLight ? '#1f2933' : '#1f1f1f';
  const light = isLight ? '#ffffff' : '#f5f5f5';
  try {
    await QRCode.toCanvas(canvasRef.value, i.payload, {
      errorCorrectionLevel: 'M',
      margin: 2,
      width: 280,
      color: { dark, light },
    });
    renderError.value = '';
  } catch (err) {
    renderError.value = (err as Error).message;
  }
  void styles;
}

onMounted(() => {
  drawQr();
  // Re-draw when the user toggles theme so colours stay in sync.
  const obs = new MutationObserver((muts) => {
    for (const m of muts) {
      if (m.type === 'attributes' && m.attributeName === 'data-theme') {
        drawQr();
        break;
      }
    }
  });
  obs.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
});
watch(() => i.payload, () => drawQr());

// Click-to-copy with a small "Copied" badge per row.
// `navigator.clipboard` is only exposed in secure contexts
// (HTTPS / localhost). On plain http:// it's undefined, so we fall
// back to the legacy hidden-textarea + execCommand('copy') trick.
const copiedKey = ref<string | null>(null);
async function copy(key: string, value: string) {
  let ok = false;
  if (window.isSecureContext && navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(value);
      ok = true;
    } catch {
      // browser blocked the secure-context path; fall through to legacy
    }
  }
  if (!ok) {
    const ta = document.createElement('textarea');
    ta.value = value;
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
    copiedKey.value = key;
    setTimeout(() => {
      if (copiedKey.value === key) copiedKey.value = null;
    }, 1500);
  }
}
</script>

<template>
  <div class="qrcode-v2">
    <article v-if="i.apiDisabled" class="bsx-card">
      <header><h3>API QR Code</h3></header>
      <div class="bsx-card-body qr-disabled">
        <p>The pool API is disabled by the administrator.</p>
      </div>
    </article>

    <article v-else class="bsx-card">
      <header><h3>API QR Code</h3></header>
      <div class="bsx-card-body qr-grid">

        <!-- LEFT: QR canvas. -->
        <div class="qr-canvas-wrap">
          <canvas ref="canvasRef" class="qr-canvas" aria-label="API string QR code"></canvas>
          <p class="qr-help">
            Scan this with a mobile pool client to import your API
            credentials in one step.
          </p>
          <p v-if="renderError" class="qr-error">QR render failed: {{ renderError }}</p>
        </div>

        <!-- RIGHT: copyable breakdown of the encoded fields. -->
        <div class="qr-fields">
          <div class="kv">
            <label>API URL</label>
            <div class="copy-row">
              <code class="copy-value" :title="i.apiUrl">{{ i.apiUrl }}</code>
              <button
                type="button"
                class="bsx-btn bsx-btn-ghost bsx-btn-small"
                @click="copy('apiUrl', i.apiUrl)"
              >{{ copiedKey === 'apiUrl' ? 'Copied' : 'Copy' }}</button>
            </div>
          </div>
          <div class="kv">
            <label>API Key</label>
            <div class="copy-row">
              <code class="copy-value" :title="i.apiKey">{{ i.apiKey }}</code>
              <button
                type="button"
                class="bsx-btn bsx-btn-ghost bsx-btn-small"
                @click="copy('apiKey', i.apiKey)"
              >{{ copiedKey === 'apiKey' ? 'Copied' : 'Copy' }}</button>
            </div>
          </div>
          <div class="kv">
            <label>User ID</label>
            <div class="copy-row">
              <code class="copy-value">{{ i.userId }}</code>
              <button
                type="button"
                class="bsx-btn bsx-btn-ghost bsx-btn-small"
                @click="copy('userId', String(i.userId))"
              >{{ copiedKey === 'userId' ? 'Copied' : 'Copy' }}</button>
            </div>
          </div>
          <div class="kv">
            <label>Encoded Payload</label>
            <div class="copy-row">
              <code class="copy-value copy-payload" :title="i.payload">{{ i.payload }}</code>
              <button
                type="button"
                class="bsx-btn bsx-btn-ghost bsx-btn-small"
                @click="copy('payload', i.payload)"
              >{{ copiedKey === 'payload' ? 'Copied' : 'Copy' }}</button>
            </div>
          </div>
        </div>

      </div>
    </article>
  </div>
</template>

<style scoped>
.qrcode-v2 {
  padding: 1em;
  color: var(--text-primary, #cdd);
  font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
}

/* Card chrome — same as the rest of v2. */
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
.bsx-card h3 {
  margin: 0;
  font-size: 13px;
  text-transform: uppercase;
  color: #cdd;
  letter-spacing: 0.04em;
}
.bsx-card-body { padding: 14px 16px; }

/* Two-column body: QR on the left, copyable fields on the right.
   Collapses to single column under 720 px. */
.qr-grid {
  display: grid;
  grid-template-columns: minmax(280px, auto) minmax(0, 1fr);
  gap: 20px;
  align-items: start;
}
@media (max-width: 720px) {
  .qr-grid { grid-template-columns: 1fr; }
}

.qr-canvas-wrap {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
}
.qr-canvas {
  display: block;
  border-radius: 6px;
  background: #f5f5f5;
  padding: 8px;
  border: 1px solid rgba(255,255,255,.06);
}
.qr-help {
  margin: 0;
  font-size: 11px;
  opacity: 0.65;
  text-align: center;
  max-width: 280px;
}
.qr-error {
  margin: 0;
  font-size: 11px;
  color: #e57373;
}

.qr-fields {
  display: flex;
  flex-direction: column;
  gap: 12px;
  min-width: 0;
}
.kv {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.kv > label {
  font-size: 11px;
  color: #99a;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.copy-row {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}
.copy-value {
  flex: 1 1 auto;
  min-width: 0;
  font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
  font-size: 12px;
  padding: 5px 8px;
  background: rgba(255,255,255,.04);
  border: 1px solid rgba(255,255,255,.10);
  border-radius: 4px;
  color: #f0f0f0;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.copy-payload {
  /* The full payload string is long; allow it to wrap so users can
     read it in full inside the box. */
  white-space: normal;
  word-break: break-all;
  text-overflow: clip;
  overflow: visible;
  line-height: 1.3;
}

.qr-disabled {
  text-align: center;
  font-size: 13px;
  opacity: 0.7;
  padding: 24px;
}

/* Buttons — same as the rest of v2. */
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
.bsx-btn-ghost {
  background: transparent;
  border-color: rgba(255,255,255,.18);
  color: #cdd;
}
.bsx-btn-small { padding: 4px 10px; font-size: 12px; }
</style>
