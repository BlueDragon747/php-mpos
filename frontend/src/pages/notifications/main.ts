import { createApp } from 'vue';
import NotificationsPage from './NotificationsPage.vue';
import type { NotificationsInitial } from './types';

const root = document.getElementById('app-notifications');
if (!root) {
  throw new Error('No #app-notifications mount point found');
}

function parseInitial(): NotificationsInitial {
  try {
    return JSON.parse(root!.dataset.initial ?? '{}') as NotificationsInitial;
  } catch {
    return {} as NotificationsInitial;
  }
}

createApp(NotificationsPage, {
  initial: parseInitial(),
}).mount(root);
