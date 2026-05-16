// Initial state shape rendered by transactions.inc.php into a single
// data-initial JSON blob on #app-transactions.

export type TxStatus = 'Confirmed' | 'Unconfirmed' | 'Orphan';

export interface TransactionRow {
  id: number;
  timestamp: string;     // YYYY-MM-DD HH:MM:SS
  // Account name that owns the transaction. Empty in user-facing view
  // (that's the logged-in user); populated in admin view across all
  // users.
  username: string;
  type: string;          // 'Credit' | 'Credit_PPS' | 'Debit_AP' | 'Debit_MP' | 'Fee' | 'Donation' | 'Bonus' | 'TXFee' | …
  status: TxStatus;
  coinAddress: string;   // empty for non-payout rows
  txid: string;          // empty if no on-chain tx
  height: number;        // 0 = no block (n/a in legacy)
  amount: number;
  amountClass: 'credit' | 'debit';
}

export interface PopupMessage {
  content: string;
  type: 'success' | 'errormsg' | 'info';
}

export interface TransactionsInitial {
  formAction: string;
  transactions: TransactionRow[];
  // Type dropdown — keys are submit values, values are display labels.
  // Server-rendered from $transaction->getTypes() so the SPA stays in
  // sync with whatever the controller actually accepts.
  transactionTypes: Record<string, string>;
  transactionStatus: Record<string, string>;
  filter: { type: string; status: string; account?: string; address?: string };
  limit: number;
  start: number;
  explorerUrl: string;
  explorerDisabled: boolean;
  // Per-type running totals (`Credit` → 305.0, `Debit_AP` → 152.0, …).
  // Hidden when `summaryDisabled` is true (admin setting
  // `disable_transactionsummary`).
  summary: Record<string, number>;
  summaryDisabled: boolean;
  // Coin symbol of this transactions view (e.g. 'BLC', 'PHO').
  currency: string;
  // Admin consolidated transaction view: selected coin and switcher
  // options. User-facing per-coin views leave coinOptions empty.
  selectedCoin: string;
  coinOptions: Array<{ value: string; label: string; currency: string; name: string }>;
  // Full coin name (e.g. 'Blakecoin') from
  // $config['gettingstarted']['coinname'] — falls back to the ticker
  // when not configured. Centered in the Summary card header.
  coinName: string;
  // Render the Username column (admin context, where transactions
  // span all users). False on the user-facing view.
  showUsername: boolean;
  popups: PopupMessage[];
}
