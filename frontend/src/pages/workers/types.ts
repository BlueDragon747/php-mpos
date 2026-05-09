// Initial-state shape rendered by public/include/pages/account/workers.inc.php
// into a single data-initial JSON blob on #app-workers. Mirrors the keys
// the v2 controller emits, in the SPA's preferred camelCase.

export interface WorkerRow {
  id: number;
  // Full worker name, e.g. "admin.rig01" — `subname` is the editable
  // suffix after the parent.
  username: string;
  subname: string;
  password: string;
  monitor: boolean;
  hashrate: number;            // kH/s
  difficulty: number;
  shares10m: number;            // count_all (last 10 min by default)
  sharesArch: number;           // count_all_archive
  isActive: boolean;            // hashrate > 0
}

export interface PopupMessage {
  content: string;
  type: 'success' | 'errormsg' | 'info';
}

export interface WorkersInitial {
  formAction: string;
  csrfToken: string;
  parentUsername: string;       // e.g. "admin"
  disableNotifications: boolean; // hides the Monitor toggle column when true
  workers: WorkerRow[];
  popups: PopupMessage[];
}
