// Initial-state shape rendered by the PHP controller into a single
// data-initial JSON blob on #app-account-edit. Mirror server field
// names exactly so the Vue form posts to the existing controller
// without a translation layer.

export interface CoinSlotState {
  // Slot key as MPOS knows it: 'main' (primary), 'mm', 'mm1', 'mm3', 'mm4', 'mm5'.
  key: 'main' | 'mm' | 'mm1' | 'mm3' | 'mm4' | 'mm5';
  // Display label, e.g. 'BLC', 'PHO', 'BBC', 'ELT', 'UMO', 'LIT'.
  currency: string;
  // Long coin name for the per-coin card header, e.g. 'Blakecoin'.
  coinName: string;
  // GitHub raw URL to the coin's bitcoin.png icon, derived from its
  // releases-URL via _ae_coin_icon_url(). Empty string if unmapped —
  // the Vue side hides the <img> in that case.
  iconUrl: string;
  // Current saved values from the accounts table.
  address: string;
  threshold: number;
  // Per-coin auto-payout threshold range (min/max). Sourced from a
  // hardcoded ticker→range map in the PHP controller; falls back to
  // the global ap_threshold config when a ticker isn't mapped.
  thresholdMin: number;
  thresholdMax: number;
  // Cash-Out box: confirmed balance + flag for whether this slot has a
  // cashOut handler (the legacy template hides cashOut for mm5).
  confirmedBalance: number;
  cashOutEnabled: boolean;
  // Form action name expected by the PHP switch: 'cashOut' for primary,
  // 'cashOut_mm', 'cashOut_mm1', 'cashOut_mm3', 'cashOut_mm4', 'cashOut_mm5'.
  cashOutAction: string;
  // POST field names — match the legacy template's `paymentAddress`,
  // `paymentAddress_mm`, `payoutThreshold`, `payoutThreshold_mm`, …
  addressField: string;
  thresholdField: string;
}

export interface DonateThreshold {
  min: number;
}

export interface TwoFactorState {
  // Master switch.
  enabled: boolean;
  // Per-action flags ($GLOBAL.twofactor.options.*).
  details: boolean;
  changepw: boolean;
  withdraw: boolean;
  // Whether a token is currently sent / unlocked for each action.
  detailsSent: boolean;
  detailsUnlocked: boolean;
  changepwSent: boolean;
  changepwUnlocked: boolean;
  withdrawSent: boolean;
  withdrawUnlocked: boolean;
  // Echoed-back tokens to round-trip on resubmit.
  eaToken: string;
  cpToken: string;
  wfToken: string;
}

export interface PopupMessage {
  content: string;
  type: 'success' | 'errormsg' | 'info';
}

export interface EditAccountInitial {
  // Page form action target — usually '?page=account&action=edit'. PHP
  // renders this so the Vue form doesn't have to know the route name.
  formAction: string;

  // Read-only header section.
  username: string;
  userId: number;
  apiKey: string;
  apiKeyEnabled: boolean;

  // Account details.
  email: string;

  // Anonymous toggle.
  isAnonymous: boolean;

  // Coin slots in render order. Length 6 (main + 5 mm slots).
  coins: CoinSlotState[];

  // Donation %.
  donatePercent: number;
  donateThreshold: DonateThreshold;

  // Threshold range from $config['ap_threshold'].
  apThresholdMin: number;
  apThresholdMax: number;

  // Manual payout transaction fee (display only).
  txFeeManual: number;
  manualPayoutsDisabled: boolean;

  // CSRF token (rendered into every form's hidden input).
  csrfToken: string;

  // Two-factor state.
  twoFactor: TwoFactorState;

  // Pop-up messages from $_SESSION['POPUP'] (success/error from last POST).
  popups: PopupMessage[];

  // Currently active "Light Mode" / "Dark Mode" classes etc. — read from
  // <html data-theme> by the page itself, not server-rendered.
}
