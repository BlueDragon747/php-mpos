import { createApp } from 'vue';
import WorkersPage from './WorkersPage.vue';
import type { WorkersInitial } from './types';

const root = document.getElementById('app-workers');
if (!root) {
  throw new Error('No #app-workers mount point found');
}

function parseInitial(): WorkersInitial {
  try {
    return JSON.parse(root!.dataset.initial ?? '{}') as WorkersInitial;
  } catch {
    return {} as WorkersInitial;
  }
}

createApp(WorkersPage, {
  initial: parseInitial(),
}).mount(root);
