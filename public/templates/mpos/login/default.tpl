<div id="bsx-v2-shell" class="login-v2">
  <article class="bsx-card login-card">
    <header>
      <h3>Login</h3>
      <span class="card-meta">existing account</span>
    </header>
    <form action="{$smarty.server.SCRIPT_NAME}?page=login" method="post" id="loginForm" class="login-form">
      <input type="hidden" name="ctoken" value="{$CTOKEN|escape|default:""}">
      <div class="bsx-card-body">

        <div class="login-row">
          <label for="login-username">Email <span class="login-req" aria-hidden="true">*</span></label>
          <input id="login-username" type="email" name="username"
                 value="{$smarty.request.username|default:""|escape}"
                 placeholder="you@example.com" maxlength="100"
                 autocomplete="username" tabindex="1" required>
        </div>

        <div class="login-row">
          <label for="login-password">Password <span class="login-req" aria-hidden="true">*</span></label>
          <input id="login-password" type="password" name="password"
                 placeholder="Your password" maxlength="100"
                 autocomplete="current-password" tabindex="2" required>
        </div>

{if $RECAPTCHA|default:""}
        <div class="login-row login-recaptcha">
          {nocache}{$RECAPTCHA nofilter}{/nocache}
        </div>
{/if}

        <div class="login-actions">
          <a class="login-forgot" href="{$smarty.server.SCRIPT_NAME}?page=password">Forgot your password?</a>
          <button type="submit" class="bsx-btn bsx-btn-primary">Login</button>
        </div>
      </div>
    </form>
  </article>
</div>

<style>
  .login-v2 {
    margin: 0 16px 6px 16px;
    padding: 1em;
    color: var(--text-primary, #cdd);
    font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
    min-height: calc(100vh - 200px);
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
  .login-v2 .bsx-card {
    background: rgba(255,255,255,.03);
    border: 1px solid rgba(255,255,255,.06);
    border-radius: 6px;
    overflow: hidden;
    max-width: 460px;
    margin: 0 auto;
  }
  .login-v2 .bsx-card header {
    background: rgba(255,255,255,.05);
    padding: 6px 14px;
    border-bottom: 1px solid rgba(255,255,255,.06);
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .login-v2 .bsx-card h3 {
    margin: 0;
    font-size: 12px;
    color: #cdd;
    letter-spacing: 0.04em;
    text-transform: uppercase;
  }
  .login-v2 .card-meta {
    font-size: 10px;
    opacity: 0.65;
    color: #cdd;
    font-style: italic;
    margin-left: auto;
  }
  .login-v2 .bsx-card-body {
    padding: 18px 22px;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  /* Form rows */
  .login-v2 .login-row {
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-width: 0;
  }
  .login-v2 .login-row label {
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: #aab2bd;
    font-weight: 700;
  }
  .login-v2 .login-req { color: #ffd66e; margin-left: 2px; }
  .login-v2 .login-row input[type="email"],
  .login-v2 .login-row input[type="password"] {
    width: 100%;
    box-sizing: border-box;
    background: rgba(0,0,0,0.25);
    border: 1px solid rgba(255,255,255,.10);
    border-radius: 4px;
    color: #e0f0fa;
    font: inherit;
    font-size: 12px;
    padding: 8px 10px;
    transition: border-color 150ms ease, background 150ms ease;
  }
  .login-v2 .login-row input::placeholder { color: #8892a0; opacity: 0.5; }
  .login-v2 .login-row input:focus {
    outline: none;
    border-color: rgba(79, 195, 247, 0.55);
    background: rgba(0,0,0,0.35);
  }
  .login-v2 .login-recaptcha {
    align-items: center;
    flex-direction: row;
    justify-content: center;
  }

  /* Submit row */
  .login-v2 .login-actions {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    margin-top: 6px;
  }
  .login-v2 .login-forgot {
    font-size: 11px;
    color: #4fc3f7;
    text-decoration: none;
  }
  .login-v2 .login-forgot:hover { text-decoration: underline; }
  .login-v2 .bsx-btn {
    font: inherit;
    font-size: 12px;
    font-weight: 700;
    letter-spacing: 0.04em;
    padding: 8px 22px;
    border-radius: 4px;
    cursor: pointer;
    border: 1px solid rgba(79, 195, 247, 0.45);
    background: rgba(79, 195, 247, 0.16);
    color: #e0f0fa;
    transition: background 150ms ease, border-color 150ms ease;
  }
  .login-v2 .bsx-btn:hover {
    background: rgba(79, 195, 247, 0.28);
    border-color: rgba(79, 195, 247, 0.65);
  }

  /* Light mode */
  [data-theme="light"] .login-v2 .bsx-card {
    background: #f7f8fa;
    border-color: rgba(0, 0, 0, 0.18);
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] .login-v2 .bsx-card header {
    background: #e7eaed;
    border-bottom-color: rgba(0, 0, 0, 0.14);
  }
  [data-theme="light"] .login-v2 .bsx-card h3 { color: #1f2933; }
  [data-theme="light"] .login-v2 .card-meta { color: #4a5568; }
  [data-theme="light"] .login-v2 .login-row label { color: #4a5568; }
  [data-theme="light"] .login-v2 .login-req { color: #b53d00; }
  [data-theme="light"] .login-v2 .login-row input[type="email"],
  [data-theme="light"] .login-v2 .login-row input[type="password"] {
    background: #ffffff;
    border-color: rgba(0,0,0,0.18);
    color: #1f2933;
  }
  [data-theme="light"] .login-v2 .login-row input::placeholder { color: #6c7686; opacity: 0.5; }
  [data-theme="light"] .login-v2 .login-row input:focus {
    border-color: rgba(25, 118, 210, 0.55);
    background: #ffffff;
  }
  [data-theme="light"] .login-v2 .login-forgot { color: #1565c0; }
  [data-theme="light"] .login-v2 .bsx-btn {
    background: rgba(25, 118, 210, 0.12);
    border-color: rgba(25, 118, 210, 0.45);
    color: #0d47a1;
  }
  [data-theme="light"] .login-v2 .bsx-btn:hover {
    background: rgba(25, 118, 210, 0.22);
    border-color: rgba(25, 118, 210, 0.60);
  }
</style>
