// Hand-written TS contract for the MPOS JSON API. The PHP backend is untyped,
// so this file is the contract. If a field is missing here, the dashboard
// page won't see it. Keep narrow: only what the v2 dashboard consumes.
//
// Source of truth for shape: public/include/pages/api/{getdashboarddata,
// getuserworkers,getuserbalance}.inc.php — verify when bindings change.

export interface DashboardDataResponse {
  getdashboarddata: {
    data: {
      raw: {
        network: { hashrate: number };
        pool: { hashrate: number };
        personal: { hashrate: number };
      };
      network: {
        hashrate: number;
        difficulty: number;
        block: number;
        esttimeperblock: number;
        nextdifficulty?: number;
        blocksuntildiffchange?: number;
      };
      pool: {
        info?: { name: string; currency: string };
        hashrate: number;
        sharerate?: number;
        shares: {
          valid: number;
          invalid: number;
          invalid_percent?: number;
          estimated?: number;
          progress?: number;
        };
        workers: number;
        difficulty?: number;
        target_bits?: number;
      };
      personal: {
        hashrate: number;
        sharerate: number;
        sharedifficulty?: number;
        shares: {
          valid: number;
          invalid: number;
          invalid_percent?: number;
          unpaid?: number;
        };
        estimates?: {
          block?: number;
          fee?: number;
          donation?: number;
          payout?: number;
          hours1?: number;
          hours24?: number;
          days7?: number;
          days14?: number;
          days30?: number;
        };
      };
      system?: { load: number[] };
    };
    runtime: number;
  };
}

export interface WorkerRow {
  id: number;
  username: string;
  hashrate: number;
  sharerate: number;
  shares: { valid: number; invalid: number };
  monitor: boolean;
}

export interface UserWorkersResponse {
  getuserworkers: {
    data: WorkerRow[];
  };
}

export interface UserBalanceResponse {
  getuserbalance: {
    // `inflight` is set when a Debit_AP/Debit_MP/TXFee row exists
    // whose matching transactions_outbox.status is 'broadcast'
    // (payout broadcast, awaiting reconcile_min_confirmations).
    // Excluded from `confirmed` so that bucket never goes negative.
    // Optional: legacy / pre-Wave-2 deploys won't return it.
    data: {
      confirmed: number;
      unconfirmed: number;
      estimate: number;
      inflight?: number;
    };
  };
}

// Per-coin stats snapshot rendered server-side by the v2 dashboard
// controller (mirrors smarty_globals.inc.php's $GLOBAL fields plus
// $bitcoin_mm{,1,3,4,5}->getdifficulty/getblockcount). Consumed by
// StatsBlock.vue.
export interface CoinStats {
  key: string;
  currency: string;
  icon_url: string;
  payout_system: string;
  pplns_target: number | string | null;
  roundshares: { valid: number; invalid: number; estimated: number; progress: number };
  your_shares: { valid: number; invalid: number };
  estimates: {
    block: number; fee: number; donation: number; payout: number;
    hours1: number; hours24: number; days7: number; days14: number; days30: number;
  };
  network: { difficulty: number; esttimeperblock: number; block: number };
}

// Pool messages — rendered on the back face of the Overview card flip.
// Body is plain text (no HTML). `posted` is ISO YYYY-MM-DD; the SPA
// formats it MM/DD/YY for the card corner.
export interface PoolMessage {
  id: string;
  type: 'info' | 'success' | 'warning';
  title: string;
  body: string;
  posted?: string;
}

// SSE event payloads (from cronjobs-py/cronjobs_py/sse.py).
export type SseEvent =
  | { type: 'hello' }
  | { type: 'share'; username: string; valid: boolean; difficulty?: number }
  | { type: 'block'; height: number; chain: string; finder?: string }
  | { type: 'stats'; pool_khs: number; net_khs: number; workers_active: number };
