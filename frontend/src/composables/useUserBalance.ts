import { ref, onUnmounted } from 'vue';
import { api } from '../api/client';
import type { UserBalanceResponse } from '../api/types';

// Polls /index.php?page=api&action=getuserbalance at the long-refresh
// interval. Returns the primary-coin balance only — mergemine coin
// balances need separate endpoints (or controller-rendered data).

export function useUserBalance(apiKey: string, userId: number, intervalMs: number) {
  const data = ref<UserBalanceResponse | null>(null);
  const error = ref<Error | null>(null);
  let timer: ReturnType<typeof setTimeout> | null = null;
  let stopped = false;

  async function tick() {
    if (stopped) return;
    try {
      data.value = await api.getUserBalance({ apiKey, userId });
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
