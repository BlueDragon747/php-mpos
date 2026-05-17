import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = fileURLToPath(new URL('.', import.meta.url));

export default defineConfig({
  plugins: [vue()],

  // PHP renders <script src="/v2/dist/...">. Vite must build assets with
  // that public base so dynamic import() chunks resolve correctly.
  base: '/v2/dist/',

  build: {
    outDir: resolve(__dirname, '../public/v2/dist'),
    emptyOutDir: true,
    manifest: true,
    rollupOptions: {
      // Multi-page mode: each entry HTML produces its own bundle. The HTML
      // files at the project root are *build-time only* — PHP serves the
      // real page in prod and reads the manifest to find the hashed JS/CSS
      // names. Add a new entry per page as we migrate it.
      input: {
        dashboard: resolve(__dirname, 'dashboard.html'),
        'account-edit': resolve(__dirname, 'account-edit.html'),
        workers: resolve(__dirname, 'workers.html'),
        transactions: resolve(__dirname, 'transactions.html'),
        notifications: resolve(__dirname, 'notifications.html'),
        invitations: resolve(__dirname, 'invitations.html'),
        qrcode: resolve(__dirname, 'qrcode.html'),
        news: resolve(__dirname, 'news.html'),
      },
    },
  },
});
