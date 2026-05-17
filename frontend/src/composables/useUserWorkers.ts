import { ref, onUnmounted } from 'vue';
import { api } from '../api/client';
import type { UserWorkersResponse } from '../api/types';

// Polls /index.php?page=api&action=getuserworkers at the long-refresh
// interval. Mirrors the legacy worker1 timer's getuserworkers leg.

export function useUserWorkers(apiKey: string, userId: number, intervalMs: number) {
  const data = ref<UserWorkersResponse | null>(null);
  const error = ref<Error | null>(null);
  let timer: ReturnType<typeof setTimeout> | null = null;
  let stopped = false;

  async function tick() {
    if (stopped) return;
    try {
      data.value = await api.getUserWorkers({ apiKey, userId });
      error.value = null;
    } catch (err) {
      error.value = err as Error;
    }
    if (!stopped) timer = setTimeout(tick, intervalMs);
  }

  tick();
  onUnmounted(() => {
    stopped = true;
    if (timer) clearTimeout(timer);
  });

  return { data, error };
}
