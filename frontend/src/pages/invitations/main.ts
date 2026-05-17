import { createApp } from 'vue';
import InvitationsPage from './InvitationsPage.vue';
import type { InvitationsInitial } from './types';

const root = document.getElementById('app-invitations');
if (!root) {
  throw new Error('No #app-invitations mount point found');
}

function parseInitial(): InvitationsInitial {
  try {
    return JSON.parse(root!.dataset.initial ?? '{}') as InvitationsInitial;
  } catch {
    return {} as InvitationsInitial;
  }
}

createApp(InvitationsPage, {
  initial: parseInitial(),
}).mount(root);
