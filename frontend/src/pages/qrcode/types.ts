// Hydration shape rendered by qrcode.inc.php into a single
// data-initial JSON blob on #app-qrcode.

export interface QrCodeInitial {
  apiDisabled: boolean;
  apiUrl: string;
  apiKey: string;
  userId: number;
  // Same `|<apiUrl>|<apiKey>|<userId>|` format the legacy page
  // encoded into the QR.
  payload: string;
}
