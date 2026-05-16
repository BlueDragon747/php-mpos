# Blakestream-MPOS Frontend (v2)

Vue 3 + TypeScript + Vite frontend for MPOS, mounted page-by-page into the
existing PHP/Smarty UI. This file is the tracked frontend workflow
reference; operator-facing pool notes live in `../HELP.md`.

## Stack

- Vue 3 (Composition API + `<script setup lang="ts">`)
- Vite 6 (multi-page build, manifest emit)
- TypeScript (strict mode)
- ECharts 5 + vue-echarts (charting)
- bun (package manager + script runner; Vite still does the bundling)

## Charting choice — ECharts vs Chart.js

Picked **ECharts** for the trend graph and shares donut. Tradeoff: ECharts
is heavier than Chart.js (~200KB gzipped vs ~70KB) but covers every chart
shape MPOS needs without plugin gymnastics.

**Fallback:** if ECharts ends up too heavy or its API too verbose, swap to
Chart.js. The swap is component-local — only `HashrateChart.vue` and
`SharesDonut.vue` import the chart lib, so the change touches ~50 LoC.
Document the reason here if we make the swap.

## Layout

```
frontend/
├── dashboard.html              ← build entry only (PHP serves real HTML)
├── package.json
├── tsconfig.json / tsconfig.node.json
├── vite.config.ts
└── src/
    ├── api/
    │   ├── client.ts           (fetch wrapper, same-origin)
    │   └── types.ts            (hand-written API contract)
    ├── composables/
    │   ├── useDashboardData.ts (AJAX poll w/ refresh interval)
    │   ├── useSse.ts           (EventSource w/ reconnect backoff)
    │   └── useHashrateUnit.ts  (KH/MH/GH/TH auto-scale)
    ├── components/             (filled in step 2)
    └── pages/
        └── dashboard/
            ├── main.ts         (mount entry)
            └── DashboardPage.vue
```

## Build / deploy

```sh
cd frontend
bun install
bun run build      # emits to ../public/v2/dist/
```

The build emits a Vite manifest at `public/v2/dist/.vite/manifest.json`.
The PHP wrapper template (`public/templates/mpos/v2/dashboard.tpl`) reads
this manifest at request-time to emit the correct hashed `<script>` and
`<link>` tags.

## Why bun

Bun was tried for the BlakeStream Explorer's Node sync workers and
"failed" — but the underlying cause was likely SSD storage (post-NVMe
swap, Bun was fast). For this project Bun is just the package manager and
script runner — not the runtime — so the risk surface is smaller.

If Bun causes issues, fall back to npm: `npm install` and `npm run build`
both work with the same `package.json`. Document the fallback reason in
this README.

## Adding a new page (after dashboard ships)

1. Add `<page>.html` at the project root with a `<div id="app-<page>">` and
   `<script type="module" src="./src/pages/<page>/main.ts">`.
2. Add `<page>: resolve(__dirname, '<page>.html')` to `vite.config.ts`'s
   `rollupOptions.input`.
3. Create `src/pages/<page>/main.ts` and `src/pages/<page>/<Page>Page.vue`.
4. Add the matching PHP wrapper at
   `public/templates/mpos/v2/<page>.tpl` and controller at
   `public/include/pages/v2/<page>.inc.php`.
5. Follow the per-page workflow:
   read → inventory → API check → checklist → implement → visual diff →
   audit → toggle.
