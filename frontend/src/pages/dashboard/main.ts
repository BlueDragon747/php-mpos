import { createApp } from 'vue';
import DashboardPage from './DashboardPage.vue';

const root = document.getElementById('app-dashboard');
if (!root) {
  throw new Error('No #app-dashboard mount point found');
}

const apiKey = root.dataset.apiKey ?? '';
const userId = Number(root.dataset.userId ?? 0);
const refreshMs = Number(root.dataset.refreshMs ?? 10_000);
const longRefreshMs = Number(root.dataset.longRefreshMs ?? 10_000);
const payoutSystem = root.dataset.payoutSystem ?? 'pplns';
const currency = root.dataset.currency ?? 'BLC';
const pplnsTarget = root.dataset.pplnsTarget ?? '';

interface InitialBalance {
  key: string;
  currency: string;
  confirmed: number;
  unconfirmed: number;
}
let initialBalances: InitialBalance[] = [];
try {
  initialBalances = JSON.parse(root.dataset.balances ?? '[]') as InitialBalance[];
} catch {
  initialBalances = [];
}

let initialStats: unknown[] = [];
try {
  initialStats = JSON.parse(root.dataset.stats ?? '[]') as unknown[];
} catch {
  initialStats = [];
}

let initialMessages: unknown[] = [];
try {
  initialMessages = JSON.parse(root.dataset.messages ?? '[]') as unknown[];
} catch {
  initialMessages = [];
}
const sessionKey = root.dataset.sessionKey ?? 'anon';

createApp(DashboardPage, {
  apiKey,
  userId,
  refreshMs,
  longRefreshMs,
  payoutSystem,
  currency,
  pplnsTarget,
  initialBalances,
  initialStats,
  initialMessages,
  sessionKey,
}).mount(root);
