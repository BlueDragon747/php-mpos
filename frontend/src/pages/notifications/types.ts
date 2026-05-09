// Hydration shape rendered by notifications.inc.php into a single
// data-initial JSON blob on #app-notifications.

export type NotificationType =
  | 'new_block'
  | 'auto_payout'
  | 'idle_worker'
  | 'manual_payout'
  | 'success_login';

export interface NotificationSetting {
  type: NotificationType | string;
  label: string;     // human-readable ("New Block", "Auto Payout", …)
  active: boolean;
}

export interface NotificationHistoryRow {
  id: number;
  time: string;        // YYYY-MM-DD HH:MM:SS
  type: string;
  label: string;
  active: boolean;     // whether the email actually went out
}

export interface PopupMessage {
  content: string;
  type: 'success' | 'errormsg' | 'info';
}

export interface NotificationsInitial {
  formAction: string;
  csrfToken: string;
  settings: NotificationSetting[];
  history: NotificationHistoryRow[];
  popups: PopupMessage[];
}
