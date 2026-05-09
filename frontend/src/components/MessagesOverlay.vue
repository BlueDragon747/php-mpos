<script setup lang="ts">
// One-shot login overlay for pool messages. Sits on top of the
// dashboard via fixed positioning — does NOT push any layout. The
// Overview header has a small chip that opens this on demand
// (handled by the parent via v-model:visible). Dismissal is recorded
// in sessionStorage keyed by session-id, so logout-and-back-in
// surfaces the messages again.

import type { PoolMessage } from '../api/types';

const props = defineProps<{
  messages: PoolMessage[];
  visible: boolean;
}>();

const emit = defineEmits<{
  (e: 'update:visible', v: boolean): void;
  (e: 'dismiss'): void;
}>();

// Closing the overlay (× button or backdrop click) is treated as
// "don't show again until next login" — no separate "remind me later"
// path. Re-opening is via the chip in the Overview header.
function close() {
  emit('dismiss');
  emit('update:visible', false);
}
</script>

<template>
  <Teleport to="body">
    <Transition name="bsx-overlay">
      <div v-if="visible" class="bsx-overlay" @click.self="close">
        <div class="bsx-overlay-card" role="dialog" aria-modal="true" aria-labelledby="bsx-overlay-title">
          <header class="bsx-overlay-header">
            <h3 id="bsx-overlay-title">Pool Messages</h3>
            <button class="bsx-overlay-x" type="button" aria-label="Close" @click="close">×</button>
          </header>
          <div class="bsx-overlay-body">
            <article
              v-for="m in props.messages"
              :key="m.id"
              class="bsx-msg"
              :class="`bsx-msg-${m.type}`"
            >
              <h4 v-if="m.title">{{ m.title }}</h4>
              <div class="bsx-msg-body" v-html="m.body"></div>
            </article>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.bsx-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.55);
  backdrop-filter: blur(2px);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 1.5em;
  z-index: 1000;
  font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
}
.bsx-overlay-card {
  background: #1a1d21;
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 8px;
  width: 100%;
  max-width: 730px;          /* 560 px + 30% */
  max-height: 80vh;
  display: flex;
  flex-direction: column;
  box-shadow: 0 12px 48px rgba(0, 0, 0, 0.6);
}
.bsx-overlay-header {
  padding: 12px 16px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.bsx-overlay-header h3 {
  margin: 0;
  font-size: 14px;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: #cdd;
}
.bsx-overlay-x {
  background: transparent;
  border: 0;
  color: #cdd;
  font-size: 22px;
  line-height: 1;
  cursor: pointer;
  padding: 0 6px;
  border-radius: 4px;
}
.bsx-overlay-x:hover { background: rgba(255, 255, 255, 0.06); }
.bsx-overlay-body {
  padding: 12px 16px;
  overflow-y: auto;
  scrollbar-width: thin;
  scrollbar-color: rgba(255, 255, 255, 0.18) transparent;
}
.bsx-msg {
  padding: 10px 12px;
  border-radius: 6px;
  margin-bottom: 10px;
  border-left: 3px solid #4fc3f7;
  background: rgba(79, 195, 247, 0.06);
}
.bsx-msg-success { border-left-color: #b5e7a0; background: rgba(181, 231, 160, 0.06); }
.bsx-msg-warning { border-left-color: #f5cba7; background: rgba(245, 203, 167, 0.06); }
.bsx-msg h4 {
  margin: 0 0 4px;
  font-size: 13px;
  color: #cdd;
}
.bsx-msg p {
  margin: 0;
  font-size: 13px;
  color: #cdd;
  white-space: pre-line;        /* preserve \n line breaks from PHP */
  line-height: 1.45;
}
/* Transition */
.bsx-overlay-enter-active, .bsx-overlay-leave-active {
  transition: opacity 180ms ease;
}
.bsx-overlay-enter-active .bsx-overlay-card,
.bsx-overlay-leave-active .bsx-overlay-card {
  transition: transform 180ms ease, opacity 180ms ease;
}
.bsx-overlay-enter-from, .bsx-overlay-leave-to { opacity: 0; }
.bsx-overlay-enter-from .bsx-overlay-card,
.bsx-overlay-leave-to .bsx-overlay-card {
  transform: translateY(8px);
  opacity: 0;
}
</style>
