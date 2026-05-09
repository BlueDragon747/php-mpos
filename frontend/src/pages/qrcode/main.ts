import { createApp } from 'vue';
import QrCodePage from './QrCodePage.vue';
import type { QrCodeInitial } from './types';

const root = document.getElementById('app-qrcode');
if (!root) {
  throw new Error('No #app-qrcode mount point found');
}

function parseInitial(): QrCodeInitial {
  try {
    return JSON.parse(root!.dataset.initial ?? '{}') as QrCodeInitial;
  } catch {
    return {} as QrCodeInitial;
  }
}

createApp(QrCodePage, {
  initial: parseInitial(),
}).mount(root);
