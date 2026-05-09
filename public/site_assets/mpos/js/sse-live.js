/* sse-live.js — Live MPOS dashboard updates over Server-Sent Events.
 *
 * Connects to /sse/pool (proxied by nginx to cronjobs-py sse on
 * 127.0.0.1:8090) and updates DOM cells annotated with `data-sse`
 * attributes. Falls back gracefully: if the EventSource fails to
 * open or the server isn't reachable, the page keeps working from
 * its existing AJAX poller.
 *
 * Markup convention:
 *   <span data-sse="net-hashrate">…</span>
 *   <span data-sse="pool-hashrate">…</span>
 *   <span data-sse="active-workers">…</span>
 *   <tr data-sse-worker="alice.miner1">
 *     <td data-sse="worker-status">…</td>
 *     <td data-sse="worker-last-share">…</td>
 *     <td data-sse="worker-shares">…</td>
 *   </tr>
 *
 * The script is deliberately framework-free (no jQuery dep) — drop
 * it into the dashboard template and it Just Works.
 */
(function () {
    'use strict';
    if (typeof EventSource === 'undefined') {
        console.warn('[sse-live] EventSource unsupported; falling back to AJAX poll');
        return;
    }

    var SSE_URL = '/sse/pool';
    var RECONNECT_BACKOFF_MS = [1000, 2000, 5000, 10000, 30000];
    var reconnectIdx = 0;

    // Lightweight rolling counters so the dashboard can show a
    // recent-share rate without re-querying the DB.
    var counters = {
        sharesValid: 0,
        sharesInvalid: 0,
        sharesUpstream: 0,
        lastShareTs: 0,
        bySession: {} // username -> { valid, invalid, lastTs, lastDifficulty }
    };

    function setText(selector, value) {
        var els = document.querySelectorAll(selector);
        for (var i = 0; i < els.length; i++) {
            els[i].textContent = String(value);
        }
    }

    function flashCell(selector, klass) {
        var els = document.querySelectorAll(selector);
        for (var i = 0; i < els.length; i++) {
            els[i].classList.add(klass);
            (function (el) {
                setTimeout(function () { el.classList.remove(klass); }, 600);
            })(els[i]);
        }
    }

    function fmtAgo(ts) {
        if (!ts) return '—';
        var dt = Math.max(0, Math.floor(Date.now() / 1000) - ts);
        if (dt < 60) return dt + 's ago';
        if (dt < 3600) return Math.floor(dt / 60) + 'm ago';
        if (dt < 86400) return Math.floor(dt / 3600) + 'h ago';
        return Math.floor(dt / 86400) + 'd ago';
    }

    function handleShare(ev) {
        if (ev.valid) counters.sharesValid++; else counters.sharesInvalid++;
        if (ev.upstream) counters.sharesUpstream++;
        counters.lastShareTs = ev.ts || Math.floor(Date.now() / 1000);

        var user = ev.username || '';
        if (!counters.bySession[user]) {
            counters.bySession[user] = { valid: 0, invalid: 0, lastTs: 0, lastDifficulty: 0 };
        }
        var s = counters.bySession[user];
        if (ev.valid) s.valid++; else s.invalid++;
        s.lastTs = ev.ts || Math.floor(Date.now() / 1000);
        s.lastDifficulty = ev.difficulty;

        // Update aggregate counters in the page.
        setText('[data-sse="shares-valid"]', counters.sharesValid);
        setText('[data-sse="shares-invalid"]', counters.sharesInvalid);
        setText('[data-sse="shares-upstream"]', counters.sharesUpstream);
        setText('[data-sse="last-share"]', fmtAgo(counters.lastShareTs));

        // Per-worker row update + flash.
        var rows = document.querySelectorAll('[data-sse-worker="' + cssEscape(user) + '"]');
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i];
            var statusEl = row.querySelector('[data-sse="worker-status"]');
            var lastEl   = row.querySelector('[data-sse="worker-last-share"]');
            var sharesEl = row.querySelector('[data-sse="worker-shares"]');
            if (statusEl) statusEl.textContent = 'online';
            if (lastEl)   lastEl.textContent   = fmtAgo(s.lastTs);
            if (sharesEl) sharesEl.textContent = (s.valid + s.invalid);
        }
        flashCell('[data-sse-worker="' + cssEscape(user) + '"]', 'sse-flash');
    }

    // ---- Hashrate gauges ----
    //
    // The dashboard's three JustGage dials (Net Hashrate, Pool
    // Hashrate, personal Hashrate) are constructed in
    // `js_static.tpl` as global vars `g1`, `g2`, `g3`. The SSE
    // service publishes raw kH/s every 10 s; we apply the same
    // modifier the page was rendered with (KH/MH/GH/TH). The
    // modifier comes from a tiny inline script the deploy injects
    // alongside this one — `window.SSE_LIVE_MODIFIERS` —  so we
    // never have to query PHP from JS.

    function applyHashrate(rawKHs, modifier) {
        if (typeof rawKHs !== 'number' || isNaN(rawKHs)) return null;
        if (typeof modifier !== 'number' || modifier <= 0) modifier = 1;
        return Math.round(rawKHs * modifier * 100) / 100; // 2dp
    }

    function refreshGauge(g, value) {
        if (!g || typeof value !== 'number' || isNaN(value)) return;
        try {
            g.refresh(value);
        } catch (err) {
            // JustGage on some browsers throws if value > max.
            // Fall back to setting both at once.
            try { g.refresh(value, Math.max(value, g.config.max || 1) * 1.05); }
            catch (e) { console.warn('[sse-live] gauge refresh failed', e); }
        }
    }

    function handleStats(ev) {
        var mods = window.SSE_LIVE_MODIFIERS || {};
        // g1 = Net Hashrate, g2 = Pool Hashrate, g3 = personal.
        var net  = applyHashrate(ev.net_hashrate_kHs,  mods.network);
        var pool = applyHashrate(ev.pool_hashrate_kHs, mods.pool);
        if (net  !== null) refreshGauge(window.g1, net);
        if (pool !== null) refreshGauge(window.g2, pool);
        // Active workers + sharerate, where the page exposes them.
        if (typeof ev.active_workers === 'number') {
            setText('[data-sse="active-workers"]', ev.active_workers);
        }
    }

    function handleBlock(ev) {
        // Bump a "blocks found this session" counter and surface a
        // toast-y banner if the page wants to render new blocks.
        var slotLabel = ev.slot || 'parent';
        console.log('[sse-live] block %s/%d  hash=%s  amount=%s',
                    slotLabel, ev.height, (ev.blockhash || '').slice(0, 16) + '…', ev.amount);

        // Optional toast: if the page has <div id="sse-toasts">…</div>,
        // append a banner. We don't manufacture one — operator opt-in.
        var toasts = document.getElementById('sse-toasts');
        if (toasts) {
            var div = document.createElement('div');
            div.className = 'sse-toast sse-toast-block';
            div.textContent = 'Block found on ' + slotLabel + ' at height ' + ev.height;
            toasts.appendChild(div);
            setTimeout(function () { div.remove(); }, 15000);
        }

        // Auto-refresh recent-blocks tables if the page exposes one.
        var blocksTable = document.querySelector('[data-sse="blocks-list"]');
        if (blocksTable) {
            var row = document.createElement('tr');
            row.className = 'sse-flash';
            row.innerHTML = '<td>' + ev.height + '</td>'
                          + '<td>' + slotLabel + '</td>'
                          + '<td>' + (ev.blockhash || '').slice(0, 16) + '…</td>'
                          + '<td>' + (ev.amount || 0).toFixed(8) + '</td>'
                          + '<td>' + ev.confirmations + '</td>';
            // Insert at top of <tbody>, trim to 25 rows.
            var tbody = blocksTable.tagName === 'TBODY' ? blocksTable : blocksTable.querySelector('tbody');
            if (tbody) {
                tbody.insertBefore(row, tbody.firstChild);
                while (tbody.children.length > 25) tbody.removeChild(tbody.lastChild);
            }
        }
    }

    // CSS.escape polyfill for old browsers.
    function cssEscape(s) {
        if (typeof CSS !== 'undefined' && CSS.escape) return CSS.escape(s);
        return String(s).replace(/[^a-zA-Z0-9_-]/g, function (c) {
            return '\\' + c.charCodeAt(0).toString(16) + ' ';
        });
    }

    function connect() {
        var es = new EventSource(SSE_URL);
        es.onopen = function () {
            reconnectIdx = 0;
            console.log('[sse-live] connected');
        };
        es.onmessage = function (e) {
            var ev;
            try { ev = JSON.parse(e.data); } catch (err) { return; }
            switch (ev.type) {
                case 'share': handleShare(ev); break;
                case 'block': handleBlock(ev); break;
                case 'stats': handleStats(ev); break;
                case 'hello': /* connected */ break;
                default: break;
            }
        };
        es.onerror = function () {
            es.close();
            var delay = RECONNECT_BACKOFF_MS[Math.min(reconnectIdx, RECONNECT_BACKOFF_MS.length - 1)];
            reconnectIdx++;
            console.warn('[sse-live] disconnected; reconnect in', delay, 'ms');
            setTimeout(connect, delay);
        };
    }

    // Wait until DOMContentLoaded to be safe — most MPOS pages put
    // the dashboard cells after the <script> tag.
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', connect);
    } else {
        connect();
    }
})();
