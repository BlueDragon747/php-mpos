// Initial state shape rendered by include/pages/admin/news.inc.php
// into a single data-initial JSON blob on #app-news.

export interface NewsEntry {
  id: number;
  header: string;
  content: string;          // raw markdown — what the textarea edits
  contentHtml: string;      // server-rendered HTML — what the list displays
  active: 0 | 1;
  show_on: 'home' | 'dashboard' | 'both';
  time: string;             // 'YYYY-MM-DD HH:MM:SS' or similar
  author: string;
}

export interface NewsInitial {
  formAction: string;       // '?page=admin&action=news'
  csrfToken: string;
  news: NewsEntry[];
}
