import { createApp } from 'vue';
import EditAccountPage from './EditAccountPage.vue';
import type { EditAccountInitial } from './types';

const root = document.getElementById('app-account-edit');
if (!root) {
  throw new Error('No #app-account-edit mount point found');
}

// Single source of initial state: a JSON blob in data-initial. PHP encodes
// this with JSON_HEX_APOS|JSON_HEX_QUOT|… so apostrophes in addresses or
// emails don't break the attribute. Using one blob beats threading 30+
// data-* attributes.
function parseInitial(): EditAccountInitial {
  try {
    return JSON.parse(root!.dataset.initial ?? '{}') as EditAccountInitial;
  } catch {
    return {} as EditAccountInitial;
  }
}

createApp(EditAccountPage, {
  initial: parseInitial(),
}).mount(root);
