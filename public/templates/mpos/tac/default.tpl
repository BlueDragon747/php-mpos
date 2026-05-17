<div id="bsx-v2-shell" class="tac-v2">
  <article class="bsx-card tac-card">
    <header>
      <h3>Terms &amp; Conditions</h3>
      <span class="card-meta">{$GLOBAL.website.name|escape}</span>
    </header>
    <div class="bsx-card-body">
      <p class="tac-lead">This Agreement governs your use of <strong>{$GLOBAL.website.name|escape}</strong>.</p>
      <ol class="tac-list">
        <li>By using any of the Pools or registering an account on the website, you agree to be bound by the terms and conditions below. If you do not agree with the terms and conditions in this Agreement you may not use the Pool.</li>
        <li>The {$GLOBAL.website.name|escape} staff may modify this Agreement and any policies affecting the Site at any point of time. Such modification is effective immediately upon posting to the website and will be distributed via email, forum post and a link in chat. Your continued use of the Pool following any modification to this Agreement shall be deemed an acceptance of all modifications.</li>
        <li>The Pool rewards miners according to a <strong>{$GLOBAL.config.payout_system|escape}</strong> system with a <strong>{$GLOBAL.fees}%</strong> fee. The fee may change at any time, but notice will be given before doing so. Any fee change will be communicated through the pool's news page.</li>
        <li>The Pool is not an e-wallet or a bank for your coins. The Pool and its operators are not responsible for any loss of coins which are stored on the Pool. It is your responsibility to configure your account so that the coins you mine are regularly transferred to your own secured offline wallet.</li>
        <li>The uptime of the pool or website is not guaranteed; maintenance and downtime may be required at times. Users are responsible for configuring their miners so that they will automatically reconnect, switch to all the pools we offer, or fall back to a backup pool in the case of downtime.</li>
        <li>Botnets are not welcome. Accounts with a large number of miners connecting from different IPs may be suspended without prior notice. If we are uncertain, an investigation will be opened and the user notified via their configured email address. If we do not receive a response, your account may be suspended.</li>
        <li>Multiple accounts controlled by one person may be considered as a botnet and an investigation will be opened &mdash; see clause&nbsp;6.</li>
      </ol>
    </div>
  </article>
</div>

<style>
  .tac-v2 {
    margin: 0;
    padding: 0;
    color: var(--text-primary, #cdd);
    font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
    box-sizing: border-box;
  }

  /* TINY.box popup chrome overrides */
  .tbox    { padding: 0 !important; top: 5vh !important; }
  .tinner  { background: transparent !important; padding: 0 !important; border: 0 !important; border-radius: 0 !important; }
  .tclose  { display: none !important; }

  /* Card chrome */
  .tac-v2 .bsx-card {
    background: #1f2329;
    border: 1px solid rgba(255,255,255,.10);
    border-radius: 6px;
    overflow: hidden;
    max-width: 880px;
    margin: 0 auto;
  }
  .tac-v2 .bsx-card header {
    background: #262b32;
    padding: 8px 16px;
    border-bottom: 1px solid rgba(255,255,255,.10);
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .tac-v2 .bsx-card h3 {
    margin: 0;
    font-size: 14px;
    color: #cdd;
    letter-spacing: 0.04em;
    text-transform: uppercase;
  }
  .tac-v2 .card-meta {
    font-size: 12px;
    opacity: 0.65;
    color: #cdd;
    font-style: italic;
    margin-left: auto;
  }
  .tac-v2 .bsx-card-body {
    padding: 18px 22px;
  }

  .tac-v2 .tac-lead {
    margin: 0 0 14px;
    font-size: 14px;
    color: #e0f0fa;
    line-height: 1.55;
  }
  .tac-v2 .tac-lead strong { color: #4fc3f7; }

  .tac-v2 .tac-list {
    margin: 0;
    padding: 0;
    list-style: none;
    counter-reset: tac-counter;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .tac-v2 .tac-list li {
    counter-increment: tac-counter;
    position: relative;
    padding: 10px 14px 10px 44px;
    background: rgba(255,255,255,.02);
    border: 1px solid rgba(255,255,255,.06);
    border-radius: 4px;
    font-size: 13px;
    line-height: 1.6;
    color: #d8e0e6;
  }
  .tac-v2 .tac-list li::before {
    content: counter(tac-counter);
    position: absolute;
    left: 12px;
    top: 10px;
    width: 22px;
    height: 22px;
    border-radius: 50%;
    background: rgba(79, 195, 247, 0.10);
    border: 1px solid rgba(79, 195, 247, 0.45);
    color: #4fc3f7;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    font-size: 11px;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }
  .tac-v2 .tac-list li strong { color: #ffd66e; font-weight: 700; }

  /* Light mode */
  [data-theme="light"] .tac-v2 .bsx-card {
    background: #f7f8fa;
    border-color: rgba(0, 0, 0, 0.18);
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] .tac-v2 .bsx-card header {
    background: #e7eaed;
    border-bottom-color: rgba(0, 0, 0, 0.14);
  }
  [data-theme="light"] .tac-v2 .bsx-card h3 { color: #1f2933; }
  [data-theme="light"] .tac-v2 .card-meta { color: #4a5568; }
  [data-theme="light"] .tac-v2 .tac-lead { color: #1f2933; }
  [data-theme="light"] .tac-v2 .tac-lead strong { color: #1565c0; }
  [data-theme="light"] .tac-v2 .tac-list li {
    background: #f7f8fa;
    border-color: rgba(0,0,0,0.08);
    color: #1f2933;
  }
  [data-theme="light"] .tac-v2 .tac-list li::before {
    background: rgba(25, 118, 210, 0.10);
    border-color: rgba(25, 118, 210, 0.45);
    color: #1565c0;
  }
  [data-theme="light"] .tac-v2 .tac-list li strong { color: #b53d00; }
</style>
