import { ref, onUnmounted } from 'vue';
import type { SseEvent } from '../api/types';

// EventSource wrapper with exponential reconnect backoff. Ports the logic
// from public/site_assets/mpos/js/sse-live.js (legacy framework-free
// client). Backoff ladder mirrors that file.

const BACKOFF_LADDER_MS = [1000, 2000, 5000, 10000, 30000];

export function useSse(url: string) {
  const connected = ref(false);
  const lastEvent = ref<SseEvent | null>(null);
  let es: EventSource | null = null;
  let backoffIndex = 0;
  let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  let stopped = false;

  function connect() {
    if (stopped) return;
    es = new EventSource(url);
    es.onopen = () => {
      connected.value = true;
      backoffIndex = 0;
    };
    es.onmessage = (ev) => {
      try {
        const parsed = JSON.parse(ev.data) as SseEvent;
        lastEvent.value = parsed;
      } catch {
        // Ignore parse failures — keep-alives may not be JSON.
      }
    };
    es.onerror = () => {
      connected.value = false;
      es?.close();
      es = null;
      if (stopped) return;
      const delay = BACKOFF_LADDER_MS[Math.min(backoffIndex, BACKOFF_LADDER_MS.length - 1)];
      backoffIndex = Math.min(backoffIndex + 1, BACKOFF_LADDER_MS.length - 1);
      reconnectTimer = setTimeout(connect, delay);
    };
  }

  connect();
  onUnmounted(() => {
    stopped = true;
    es?.close();
    if (reconnectTimer) clearTimeout(reconnectTimer);
  });

  return { connected, lastEvent };
}
