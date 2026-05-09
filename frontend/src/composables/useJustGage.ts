// Lazy-load Raphael 2.1.x + JustGage 1.0.1 (the exact pair the legacy
// MPOS dashboard uses) from the existing /site_assets/mpos/js/ paths.
// Same-origin so no CORS, already deployed by the legacy install, no
// duplication into the Vite bundle.
//
// JustGage attaches itself to `window.JustGage` and uses `window.Raphael`
// — they're 2012-era global-script libs, not ES modules. This composable
// guarantees the scripts load once (a module-level promise) regardless
// of how many gauges call it concurrently.

declare global {
  interface Window {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    JustGage: any;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    Raphael: any;
  }
}

const RAPHAEL_URL = '/site_assets/mpos/js/raphael.2.1.0.min.js';
const JUSTGAGE_URL = '/site_assets/mpos/js/justgage.1.0.1.min.js';

let loadPromise: Promise<void> | null = null;

function loadScript(src: string): Promise<void> {
  return new Promise((resolve, reject) => {
    if (document.querySelector(`script[src="${src}"]`)) {
      // Already loaded by another caller (or by the legacy page).
      resolve();
      return;
    }
    const script = document.createElement('script');
    script.src = src;
    script.async = false;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error(`Failed to load ${src}`));
    document.head.appendChild(script);
  });
}

export function ensureJustGage(): Promise<void> {
  if (window.JustGage && window.Raphael) return Promise.resolve();
  if (loadPromise) return loadPromise;
  loadPromise = (async () => {
    if (!window.Raphael) await loadScript(RAPHAEL_URL);
    if (!window.JustGage) await loadScript(JUSTGAGE_URL);
  })();
  return loadPromise;
}
