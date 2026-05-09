<div id="bsx-v2-shell" class="getting-started-v2">
  <article class="bsx-card gs-card">
    <header>
      <h3>Getting Started Guide</h3>
      <span class="card-meta">5 steps</span>
    </header>
    <div class="bsx-card-body">

      <ol class="gs-steps">

        <li class="gs-step">
          <div class="gs-step-num">1</div>
          <div class="gs-step-body">
            <h4>Create your account</h4>
            <ul>
              <li><a href="{$smarty.server.SCRIPT_NAME}?page=register">Register here</a>, or log in if you already have an account.</li>
              <li>Create a <a href="{$smarty.server.SCRIPT_NAME}?page=account&action=workers">worker</a> that will be used by the miner to login.</li>
            </ul>
          </div>
        </li>

        <li class="gs-step">
          <div class="gs-step-num">2</div>
          <div class="gs-step-body">
            <h4>Create a Blakecoin address to receive payments</h4>
            <ul>
              <li>Download the Blakecoin client &amp; block chain from <a href="{$SITECOINURL|default:"https://blakecoin.io"}" target="_blank" rel="noopener">{$SITECOINURL|default:"blakecoin.io"}</a>.</li>
              <li>Generate a new address in the client.</li>
              <li>Paste it into your <a href="{$smarty.server.SCRIPT_NAME}?page=account&action=edit">account settings</a> to receive payouts.</li>
            </ul>
            <p class="gs-note">
              <strong>Note:</strong> each of the blockchains in the merge needs its OWN wallet —
              don't try to reuse the same wallet with different addresses. They are independent networks.
            </p>

{if $MERGEMINE_COINS|default:[]|@count > 0}
            <h5 class="gs-sub-h">Coin clients &amp; releases</h5>
            <ul class="gs-coin-list">
{foreach $MERGEMINE_COINS as $coin}
              <li class="gs-coin-item">
                <a href="{$coin.url|escape}" target="_blank" rel="noopener" title="View {$coin.name|escape} releases on GitHub">
                  <span class="gs-coin-name">{$coin.name|escape}</span>
                  <span class="gs-coin-ticker">{$coin.ticker|escape}</span>
                  <span class="gs-coin-arrow">&rarr;</span>
                </a>
              </li>
{/foreach}
            </ul>
{/if}
          </div>
        </li>

        <li class="gs-step">
          <div class="gs-step-num">3</div>
          <div class="gs-step-body">
            <h4>Download a miner</h4>
            <ul>
              <li><em>CGMiner</em> &middot; AMD GPU Windows &middot; <a href="https://github.com/ckolivas/cgminer/releases" target="_blank" rel="noopener">Download here</a></li>
              <li><em>CGMiner</em> &middot; AMD GPU Linux (Mint x64) &middot; <a href="https://github.com/ckolivas/cgminer/releases" target="_blank" rel="noopener">Download here</a></li>
              <li><em>SGMiner</em> &middot; AMD GPU Windows / Linux &middot; <a href="https://github.com/genesismining/sgminer-gm/releases" target="_blank" rel="noopener">Download here</a></li>
              <li><em>CCMiner</em> &middot; Nvidia GPU Windows &middot; <a href="https://github.com/tpruvot/ccminer/releases" target="_blank" rel="noopener">Download here</a> <span class="gs-tag">tested on GTX 1060 — algo <code>blakecoin</code></span></li>
              <li><em>Other miners</em> &middot; CPU / GPU / FPGA precompiled binaries (Linux / Windows) &middot; <a href="https://bitcointalk.org/index.php?topic=475856.0" target="_blank" rel="noopener">Ask here</a></li>
              <li><em>CGMiner</em> &middot; Linux / Windows &middot; <a href="http://ck.kolivas.org/apps/cgminer/" target="_blank" rel="noopener">Download here</a></li>
            </ul>
          </div>
        </li>

        <li class="gs-step">
          <div class="gs-step-num">4</div>
          <div class="gs-step-body">
            <h4>Configure your miner</h4>

            <h5 class="gs-sub-h">Baikal Giant-B ASIC</h5>
            <dl class="gs-conn">
              <dt>Pool URL</dt>
              <dd><code>stratum+tcp://{$SITESTRATUMURL|default:$smarty.server.SERVER_NAME}:{$SITESTRATUMPORT|default:"3334"}</code></dd>
              <dt>Algorithm</dt>
              <dd><code>Blake256r8</code></dd>
              <dt>User</dt>
              <dd><code><em>Weblogin</em>.<em>Worker</em></code></dd>
              <dt>Pass</dt>
              <dd><code><em>WorkerPassword</em></code></dd>
              <dt>Extranonce</dt>
              <dd><span class="gs-pill">Disable</span> <span class="gs-hint">(uncheck the Extranonce box)</span></dd>
            </dl>

            <p class="gs-lead">Stratum settings (recommended):</p>
            <dl class="gs-conn">
              <dt>Stratum URL</dt>
              <dd><code>stratum+tcp://{$SITESTRATUMURL|default:$smarty.server.SERVER_NAME}</code></dd>
              <dt>Port</dt>
              <dd><code>{$SITESTRATUMPORT|default:"3334"}</code></dd>
              <dt>Username</dt>
              <dd><code><em>Weblogin</em>.<em>Worker</em></code></dd>
              <dt>Password</dt>
              <dd><code><em>Worker password</em></code></dd>
            </dl>

            <p class="gs-lead">Example command-line invocations:</p>

            <div class="gs-cmd">
              <div class="gs-cmd-label">AMD CGMiner — Windows</div>
              <pre class="gs-pre">cgminer.exe --blake256 -o stratum+tcp://{$SITESTRATUMURL|default:$smarty.server.SERVER_NAME}:{$SITESTRATUMPORT|default:"3334"} -u <em>Weblogin</em>.<em>Worker</em> -p <em>WorkerPassword</em></pre>
            </div>
            <div class="gs-cmd">
              <div class="gs-cmd-label">AMD CGMiner — Linux</div>
              <pre class="gs-pre">./cgminer --blake256 -o stratum+tcp://{$SITESTRATUMURL|default:$smarty.server.SERVER_NAME}:{$SITESTRATUMPORT|default:"3334"} -u <em>Weblogin</em>.<em>Worker</em> -p <em>WorkerPassword</em></pre>
            </div>
            <div class="gs-cmd">
              <div class="gs-cmd-label">AMD SGMiner — Windows</div>
              <pre class="gs-pre">sgminer.exe --no-submit-stale --kernel blakecoin --gpu-platform 0 -I 30 --no-extranonce -o stratum+tcp://{$SITESTRATUMURL|default:$smarty.server.SERVER_NAME}:{$SITESTRATUMPORT|default:"3334"} -u <em>Weblogin</em>.<em>Worker</em> -p <em>WorkerPassword</em></pre>
            </div>
            <div class="gs-cmd">
              <div class="gs-cmd-label">Nvidia CCMiner — Windows</div>
              <pre class="gs-pre">ccminer.exe -a blakecoin -o stratum+tcp://{$SITESTRATUMURL|default:$smarty.server.SERVER_NAME}:{$SITESTRATUMPORT|default:"3334"} -u <em>Weblogin</em>.<em>Worker</em> -p <em>WorkerPassword</em></pre>
            </div>

            <p class="gs-foot">You can create additional workers with custom usernames and passwords on the <a href="{$smarty.server.SCRIPT_NAME}?page=account&action=workers">workers page</a>.</p>

            <h5 class="gs-sub-h">Example conf files</h5>
            <ul>
              <li><em>AMD CGMiner</em> &middot; download the example <a href="{$PATH}/conf/cgminer.conf" target="_blank" rel="noopener">cgminer.conf</a> (right-click &rarr; Save link as)</li>
              <li><em>Nvidia CCMiner</em> &middot; download the example <a href="{$PATH}/conf/ccminer.conf" target="_blank" rel="noopener">ccminer.conf</a> (right-click &rarr; Save link as), or grab a <a href="{$PATH}/conf/ccminer-multipool.conf" target="_blank" rel="noopener">multi-pool failover config</a> <span class="gs-hint">— thanks to SidGrip</span></li>
            </ul>
          </div>
        </li>

        <li class="gs-step">
          <div class="gs-step-num">5</div>
          <div class="gs-step-body">
            <h4>Advanced settings &amp; FAQ</h4>
            <ul>
              <li>Don't set <strong>intensity</strong> too high — <code>I=11</code> is standard and safest. Higher intensity takes more GPU RAM. Check for <strong>hardware errors</strong> in CGMiner (HW). <code>HW=0</code> is good, otherwise lower intensity.</li>
              <li>Set <strong>shaders</strong> according to the miner's readme (or your card's spec). CGMiner uses this value at first run to calculate <strong>thread-concurrency</strong>. Easiest way to optimise is to copy a known-good config from another miner with the same hardware.</li>
            </ul>
          </div>
        </li>

      </ol>

    </div>
  </article>
</div>

<style>
  .getting-started-v2 {
    margin: 0 16px 6px 16px;
    padding: 1em;
    color: var(--text-primary, #cdd);
    font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
  }
  section#main > .spacer { height: 0; }
  aside#sidebar {
    background: var(--bg-secondary);
    margin-top: 0;
    padding-top: 0;
    min-height: 0;
  }
  section#main { background: none; min-height: 0; }

  /* Card chrome */
  .getting-started-v2 .bsx-card {
    background: rgba(255,255,255,.03);
    border: 1px solid rgba(255,255,255,.06);
    border-radius: 6px;
    overflow: hidden;
  }
  .getting-started-v2 .bsx-card header {
    background: rgba(255,255,255,.05);
    padding: 6px 14px;
    border-bottom: 1px solid rgba(255,255,255,.06);
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .getting-started-v2 .bsx-card h3 {
    margin: 0;
    font-size: 12px;
    color: #cdd;
    letter-spacing: 0.04em;
    text-transform: uppercase;
  }
  .getting-started-v2 .card-meta {
    font-size: 10px;
    opacity: 0.65;
    color: #cdd;
    font-style: italic;
    margin-left: auto;
  }
  .getting-started-v2 .bsx-card-body { padding: 18px 22px; }

  /* Steps list */
  .getting-started-v2 .gs-steps {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 22px;
  }
  .getting-started-v2 .gs-step {
    display: grid;
    grid-template-columns: 36px minmax(0, 1fr);
    gap: 18px;
    align-items: start;
    padding-bottom: 18px;
    border-bottom: 1px solid rgba(255,255,255,.05);
  }
  .getting-started-v2 .gs-step:last-child { border-bottom: 0; padding-bottom: 0; }

  /* Step number circle */
  .getting-started-v2 .gs-step-num {
    width: 36px;
    height: 36px;
    border-radius: 50%;
    background: rgba(79, 195, 247, 0.10);
    border: 1px solid rgba(79, 195, 247, 0.45);
    color: #4fc3f7;
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: 700;
    font-size: 13px;
    font-variant-numeric: tabular-nums;
  }

  /* Step body */
  .getting-started-v2 .gs-step-body { min-width: 0; }
  .getting-started-v2 .gs-step-body h4 {
    margin: 4px 0 10px;
    font-size: 13px;
    font-weight: 700;
    letter-spacing: 0.02em;
    color: #e0f0fa;
  }
  .getting-started-v2 .gs-sub-h {
    margin: 14px 0 8px;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    font-weight: 700;
    color: #4fc3f7;
  }
  .getting-started-v2 .gs-step-body p,
  .getting-started-v2 .gs-step-body li {
    color: #cdd;
    font-size: 12px;
    line-height: 1.55;
  }
  .getting-started-v2 .gs-step-body ul {
    margin: 0 0 8px;
    padding-left: 22px;
  }
  .getting-started-v2 .gs-step-body ul li { margin: 0 0 4px; }
  .getting-started-v2 .gs-step-body ul li em {
    color: #b5e7a0;
    font-style: normal;
    font-weight: 600;
    margin-right: 4px;
  }
  .getting-started-v2 .gs-step-body a { color: #4fc3f7; text-decoration: none; }
  .getting-started-v2 .gs-step-body a:hover { text-decoration: underline; }
  .getting-started-v2 .gs-step-body code {
    background: rgba(0,0,0,0.30);
    border: 1px solid rgba(255,255,255,.10);
    padding: 1px 6px;
    border-radius: 3px;
    font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
    font-size: 11px;
    color: #e0f0fa;
  }
  .getting-started-v2 .gs-step-body code em {
    color: #ffd66e;
    font-style: italic;
    font-weight: 400;
  }
  .getting-started-v2 .gs-step-body strong { color: #e0f0fa; }
  .getting-started-v2 .gs-tag {
    margin-left: 6px;
    font-size: 10px;
    color: #ffd66e;
    font-style: italic;
  }
  .getting-started-v2 .gs-tag code {
    border-color: rgba(255, 214, 110, 0.40);
    color: #ffd66e;
  }
  .getting-started-v2 .gs-hint {
    color: #aab2bd;
    font-style: italic;
    font-size: 10px;
    margin-left: 4px;
  }
  .getting-started-v2 .gs-pill {
    display: inline-block;
    padding: 1px 8px;
    border-radius: 999px;
    font-size: 9px;
    font-weight: 700;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    background: rgba(229, 115, 115, 0.18);
    border: 1px solid rgba(229, 115, 115, 0.45);
    color: #ffb3b3;
  }
  .getting-started-v2 .gs-lead {
    margin: 12px 0 8px;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: #aab2bd;
    font-weight: 700;
  }
  .getting-started-v2 .gs-foot { margin-top: 10px; font-style: italic; opacity: 0.85; }
  .getting-started-v2 .gs-note {
    margin: 12px 0 0;
    padding: 10px 14px;
    border-left: 3px solid #ffd66e;
    background: rgba(255, 214, 110, 0.06);
    border-radius: 0 4px 4px 0;
    font-size: 11px;
    color: #f5e2b6;
  }
  .getting-started-v2 .gs-note strong { color: #ffd66e; }

  /* Coin clients & releases grid */
  .getting-started-v2 .gs-coin-list {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
    gap: 8px;
  }
  .getting-started-v2 .gs-coin-item { margin: 0; }
  .getting-started-v2 .gs-coin-item a {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 8px 12px;
    border: 1px solid rgba(255,255,255,.08);
    background: rgba(255,255,255,.02);
    border-radius: 4px;
    color: #e0f0fa !important;
    text-decoration: none !important;
    transition: background 150ms ease, border-color 150ms ease, transform 120ms ease;
  }
  .getting-started-v2 .gs-coin-item a:hover {
    background: rgba(79, 195, 247, 0.10);
    border-color: rgba(79, 195, 247, 0.40);
  }
  .getting-started-v2 .gs-coin-item a:hover .gs-coin-arrow { opacity: 1; }
  .getting-started-v2 .gs-coin-name {
    flex: 1 1 auto;
    font-weight: 700;
    font-size: 12px;
    min-width: 0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .getting-started-v2 .gs-coin-ticker {
    font-size: 9px;
    font-weight: 700;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    padding: 1px 6px;
    border-radius: 999px;
    background: rgba(79, 195, 247, 0.10);
    border: 1px solid rgba(79, 195, 247, 0.40);
    color: #4fc3f7;
    flex: 0 0 auto;
  }
  .getting-started-v2 .gs-coin-arrow {
    color: #4fc3f7;
    opacity: 0.4;
    font-size: 13px;
    flex: 0 0 auto;
    transition: opacity 150ms ease;
  }

  /* Connection info dl */
  .getting-started-v2 .gs-conn {
    margin: 0 0 12px;
    display: grid;
    grid-template-columns: 130px minmax(0, 1fr);
    column-gap: 14px;
    background: rgba(255,255,255,.02);
    border: 1px solid rgba(255,255,255,.06);
    border-radius: 4px;
    padding: 10px 14px;
  }
  .getting-started-v2 .gs-conn dt,
  .getting-started-v2 .gs-conn dd {
    margin: 0;
    padding: 4px 0;
    font-size: 11px;
  }
  .getting-started-v2 .gs-conn dt {
    color: #aab2bd;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    font-size: 10px;
    font-weight: 700;
  }
  .getting-started-v2 .gs-conn dd { color: #e0f0fa; }

  /* Command block */
  .getting-started-v2 .gs-cmd { margin: 0 0 10px; }
  .getting-started-v2 .gs-cmd-label {
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: #aab2bd;
    font-weight: 700;
    margin-bottom: 4px;
  }
  .getting-started-v2 .gs-pre {
    margin: 0;
    padding: 10px 14px;
    background: rgba(0,0,0,0.35);
    border: 1px solid rgba(255,255,255,.08);
    border-radius: 4px;
    font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
    font-size: 11px;
    line-height: 1.5;
    color: #d8e0e6;
    white-space: pre-wrap;
    word-break: break-all;
    overflow-x: auto;
  }
  .getting-started-v2 .gs-pre em {
    color: #ffd66e;
    font-style: italic;
    font-weight: 400;
  }

  /* Light mode */
  [data-theme="light"] .getting-started-v2 .bsx-card {
    background: #ffffff;
    border-color: rgba(0, 0, 0, 0.10);
  }
  [data-theme="light"] .getting-started-v2 .bsx-card header {
    background: #f1f3f5;
    border-bottom-color: rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] .getting-started-v2 .bsx-card h3 { color: #1f2933; }
  [data-theme="light"] .getting-started-v2 .card-meta { color: #4a5568; }
  [data-theme="light"] .getting-started-v2 .gs-step { border-bottom-color: rgba(0, 0, 0, 0.06); }
  [data-theme="light"] .getting-started-v2 .gs-step-num {
    background: rgba(25, 118, 210, 0.10);
    border-color: rgba(25, 118, 210, 0.45);
    color: #1565c0;
  }
  [data-theme="light"] .getting-started-v2 .gs-sub-h { color: #1565c0; }
  [data-theme="light"] .getting-started-v2 .gs-step-body h4 { color: #1f2933; }
  [data-theme="light"] .getting-started-v2 .gs-step-body p,
  [data-theme="light"] .getting-started-v2 .gs-step-body li,
  [data-theme="light"] .getting-started-v2 .gs-step-body strong { color: #1f2933; }
  [data-theme="light"] .getting-started-v2 .gs-step-body a { color: #1565c0; }
  [data-theme="light"] .getting-started-v2 .gs-step-body ul li em { color: #1b5e20; }
  [data-theme="light"] .getting-started-v2 .gs-step-body code {
    background: #f7f8fa;
    border-color: rgba(0,0,0,0.10);
    color: #1f2933;
  }
  [data-theme="light"] .getting-started-v2 .gs-step-body code em { color: #b53d00; }
  [data-theme="light"] .getting-started-v2 .gs-tag { color: #b53d00; }
  [data-theme="light"] .getting-started-v2 .gs-hint { color: #6c7686; }
  [data-theme="light"] .getting-started-v2 .gs-pill {
    background: rgba(198, 40, 40, 0.12);
    border-color: rgba(198, 40, 40, 0.45);
    color: #c62828;
  }
  [data-theme="light"] .getting-started-v2 .gs-note {
    background: rgba(239, 108, 0, 0.06);
    border-left-color: #ef6c00;
    color: #6b3a00;
  }
  [data-theme="light"] .getting-started-v2 .gs-note strong { color: #b53d00; }
  [data-theme="light"] .getting-started-v2 .gs-lead { color: #4a5568; }
  [data-theme="light"] .getting-started-v2 .gs-conn {
    background: #f7f8fa;
    border-color: rgba(0,0,0,0.08);
  }
  [data-theme="light"] .getting-started-v2 .gs-conn dt { color: #4a5568; }
  [data-theme="light"] .getting-started-v2 .gs-conn dd { color: #1f2933; }
  [data-theme="light"] .getting-started-v2 .gs-cmd-label { color: #4a5568; }
  [data-theme="light"] .getting-started-v2 .gs-pre {
    background: #1f2329;
    border-color: rgba(0,0,0,0.10);
    color: #e0f0fa;
  }
  [data-theme="light"] .getting-started-v2 .gs-pre em { color: #ffd66e; }
  [data-theme="light"] .getting-started-v2 .gs-coin-item a {
    background: #f7f8fa;
    border-color: rgba(0, 0, 0, 0.10);
    color: #1f2933 !important;
  }
  [data-theme="light"] .getting-started-v2 .gs-coin-item a:hover {
    background: rgba(25, 118, 210, 0.08);
    border-color: rgba(25, 118, 210, 0.40);
  }
  [data-theme="light"] .getting-started-v2 .gs-coin-ticker {
    background: rgba(25, 118, 210, 0.08);
    border-color: rgba(25, 118, 210, 0.40);
    color: #1565c0;
  }
  [data-theme="light"] .getting-started-v2 .gs-coin-arrow { color: #1565c0; }
</style>
