// Lazy-load jQuery 2.0.3 + jqplot core + the plugins the legacy
// dashboard uses (see public/templates/mpos/dashboard/js_api.tpl).
// Same-origin scripts already deployed by the legacy install — we
// don't bundle them into the Vite output.
//
// Order matters: jQuery → jquery-migrate → jqplot core → plugins.
// We sequentially `await` each load so execution order is guaranteed
// regardless of network timing.

/* eslint-disable @typescript-eslint/no-explicit-any */

declare global {
  interface Window {
    $: any;
    jQuery: any;
  }
}

const STYLESHEETS = [
  '/site_assets/mpos/js/jquery.jqplot.min.css',
];

const SCRIPTS = [
  '/site_assets/mpos/js/jquery-2.0.3.min.js',
  '/site_assets/mpos/js/jquery-migrate-1.2.1.min.js',
  '/site_assets/mpos/js/jquery.jqplot.min.js',
  // Plugins — match the order legacy js_api.tpl loads them in.
  '/site_assets/mpos/js/plugins/jqplot.json2.min.js',
  '/site_assets/mpos/js/plugins/jqplot.dateAxisRenderer.js',
  '/site_assets/mpos/js/plugins/jqplot.highlighter.js',
  '/site_assets/mpos/js/plugins/jqplot.canvasTextRenderer.min.js',
  '/site_assets/mpos/js/plugins/jqplot.canvasAxisLabelRenderer.min.js',
  '/site_assets/mpos/js/plugins/jqplot.canvasAxisTickRenderer.min.js',
  '/site_assets/mpos/js/plugins/jqplot.trendline.min.js',
  '/site_assets/mpos/js/plugins/jqplot.enhancedLegendRenderer.min.js',
  '/site_assets/mpos/js/plugins/jqplot.categoryAxisRenderer.min.js',
  '/site_assets/mpos/js/plugins/jqplot.pointLabels.js',
  '/site_assets/mpos/js/plugins/jqplot.donutRenderer.js',
];

let loadPromise: Promise<void> | null = null;

function loadScript(src: string): Promise<void> {
  return new Promise((resolve, reject) => {
    if (document.querySelector(`script[src="${src}"]`)) {
      resolve();
      return;
    }
    const s = document.createElement('script');
    s.src = src;
    s.async = false;
    s.onload = () => resolve();
    s.onerror = () => reject(new Error(`Failed to load ${src}`));
    document.head.appendChild(s);
  });
}

function loadStylesheet(href: string): void {
  if (document.querySelector(`link[href="${href}"]`)) return;
  const l = document.createElement('link');
  l.rel = 'stylesheet';
  l.href = href;
  document.head.appendChild(l);
}

export function ensureJqplot(): Promise<void> {
  if (window.$ && window.$.jqplot && window.$.jqplot.DonutRenderer) {
    return Promise.resolve();
  }
  if (loadPromise) return loadPromise;
  STYLESHEETS.forEach(loadStylesheet);
  loadPromise = (async () => {
    for (const src of SCRIPTS) {
      await loadScript(src);
    }
  })();
  return loadPromise;
}
