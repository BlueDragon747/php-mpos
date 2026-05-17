import { ref, onUnmounted } from 'vue';
import { api } from '../api/client';
import type { DashboardDataResponse } from '../api/types';

// Polls /index.php?page=api&action=getdashboarddata at a fixed interval.
// Mirrors the legacy js_api.tpl AJAX worker. Stops on component unmount.

export function useDashboardData(apiKey: string, userId: number, intervalMs: number) {
  const data = ref<DashboardDataResponse | null>(null);
  const error = ref<Error | null>(null);
  let timer: ReturnType<typeof setTimeout> | null = null;
  let stopped = false;

  async function tick() {
    if (stopped) return;
    try {
      data.value = await api.getDashboardData({ apiKey, userId });
      error.value = null;
    } catch (err) {
      error.value = err as Error;
    }
    if (!stopped) {
      timer = setTimeout(tick, intervalMs);
    }
  }

  tick();
  onUnmounted(() => {
    stopped = true;
    if (timer) clearTimeout(timer);
  });

  return { data, error };
}
