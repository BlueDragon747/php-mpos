import { createApp } from 'vue';
import NewsPage from './NewsPage.vue';
import type { NewsInitial } from './types';

const mount = document.getElementById('app-news');
if (mount) {
  const raw = mount.getAttribute('data-initial') || '{}';
  let initial: NewsInitial;
  try {
    initial = JSON.parse(raw);
  } catch {
    initial = { formAction: '?page=admin&action=news', csrfToken: '', news: [] };
  }
  createApp(NewsPage, { initial }).mount(mount);
}
