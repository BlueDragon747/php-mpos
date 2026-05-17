// Hydration shape rendered by invitations.inc.php into a single
// data-initial JSON blob on #app-invitations.

export interface InvitationRow {
  email: string;
  time: string;        // YYYY-MM-DD HH:MM:SS (server format)
  isActivated: boolean;
}

export interface PopupMessage {
  content: string;
  type: 'success' | 'errormsg' | 'info';
}

export interface InvitationsInitial {
  formAction: string;
  csrfToken: string;
  invitations: InvitationRow[];
  sentCount: number;
  maxCount: number;
  // True when sentCount >= maxCount — controller will refuse new
  // invitations and the form button is rendered disabled.
  limitHit: boolean;
  invitationsDisabled: boolean;
  defaultMessage: string;
  popups: PopupMessage[];
}
