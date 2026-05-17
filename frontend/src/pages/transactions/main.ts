import { createApp } from 'vue';
import TransactionsPage from './TransactionsPage.vue';
import type { TransactionsInitial } from './types';

const root = document.getElementById('app-transactions');
if (!root) {
  throw new Error('No #app-transactions mount point found');
}

function parseInitial(): TransactionsInitial {
  try {
    return JSON.parse(root!.dataset.initial ?? '{}') as TransactionsInitial;
  } catch {
    return {} as TransactionsInitial;
  }
}

createApp(TransactionsPage, {
  initial: parseInitial(),
}).mount(root);
