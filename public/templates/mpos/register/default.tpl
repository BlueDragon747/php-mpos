<div id="bsx-v2-shell" class="register-v2">
  <article class="bsx-card register-card">
    <header>
      <h3>Register</h3>
      <span class="card-meta">create new account</span>
    </header>
    <form action="{$smarty.server.SCRIPT_NAME}" method="post" class="register-form">
      <input type="hidden" name="page" value="{$smarty.request.page|escape}">
{if $smarty.request.token|default:""}
      <input type="hidden" name="token" value="{$smarty.request.token|escape}">
{/if}
      <input type="hidden" name="ctoken" value="{$CTOKEN|escape|default:""}">
      <input type="hidden" name="action" value="register">

      <div class="bsx-card-body">

        <div class="reg-row reg-row-full">
          <label for="reg-username">Username <span class="reg-req" aria-hidden="true">*</span></label>
          <input id="reg-username" type="text" name="username"
                 value="{$smarty.post.username|escape|default:""}"
                 placeholder="Pick a username" maxlength="20"
                 autocomplete="username" required>
          <span class="reg-hint">Up to 20 characters.</span>
        </div>

        <div class="reg-row reg-row-half">
          <label for="pw_field">
            Password <span class="reg-req" aria-hidden="true">*</span>
            <span class="reg-pw-meta" id="pw_strength">strength</span>
          </label>
          <input id="pw_field" type="password" name="password1"
                 placeholder="Choose a strong password" maxlength="100"
                 autocomplete="new-password" required>
        </div>

        <div class="reg-row reg-row-half">
          <label for="pw_field2">
            Repeat password <span class="reg-req" aria-hidden="true">*</span>
            <span class="reg-pw-meta" id="pw_match"></span>
          </label>
          <input id="pw_field2" type="password" name="password2"
                 placeholder="Same password again" maxlength="100"
                 autocomplete="new-password" required>
        </div>

        <div class="reg-row reg-row-half">
          <label for="reg-email1">Email <span class="reg-req" aria-hidden="true">*</span></label>
          <input id="reg-email1" type="email" name="email1"
                 value="{$smarty.post.email1|escape|default:""}"
                 placeholder="you@example.com"
                 autocomplete="email" required>
        </div>

        <div class="reg-row reg-row-half">
          <label for="reg-email2">Repeat email <span class="reg-req" aria-hidden="true">*</span></label>
          <input id="reg-email2" type="email" name="email2"
                 value="{$smarty.post.email2|escape|default:""}"
                 placeholder="Same email again"
                 autocomplete="email" required>
        </div>

        <div class="reg-row reg-row-half">
          <label for="reg-pin">PIN</label>
          <input id="reg-pin" type="password" inputmode="numeric" pattern="[0-9]*"
                 name="pin" maxlength="4" size="4"
                 placeholder="••••" class="reg-pin-input">
          <span class="reg-hint">4-digit number — <strong>remember this!</strong></span>
        </div>

        <div class="reg-row reg-row-half reg-tac-row">
          <label for="tac" class="reg-tac-label">
            <input type="checkbox" id="tac" name="tac" value="1">
            <span class="reg-tac-box" aria-hidden="true">
              <span class="reg-tac-x">&times;</span>
              <span class="reg-tac-check">&#x2713;</span>
            </span>
          </label>
          <span class="reg-tac-text">I accept the
            <a onclick="TINY.box.show({literal}{url:'?page=tacpop',width:936,height:740}{/literal})">Terms and Conditions</a></span>
        </div>

{if $RECAPTCHA|default:""}
        <div class="reg-row reg-row-full reg-recaptcha">
          {nocache}{$RECAPTCHA nofilter}{/nocache}
        </div>
{/if}

        <div class="reg-actions">
          <button type="submit" class="bsx-btn bsx-btn-primary">Register</button>
        </div>
      </div>
    </form>
  </article>
</div>

<style>
  .register-v2 {
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
  .register-v2 .bsx-card {
    background: rgba(255,255,255,.03);
    border: 1px solid rgba(255,255,255,.06);
    border-radius: 6px;
    overflow: hidden;
    max-width: 720px;
    margin: 0 auto;
  }
  .register-v2 .bsx-card header {
    background: rgba(255,255,255,.05);
    padding: 6px 14px;
    border-bottom: 1px solid rgba(255,255,255,.06);
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .register-v2 .bsx-card h3 {
    margin: 0;
    font-size: 14px;
    color: #cdd;
    letter-spacing: 0.04em;
    text-transform: uppercase;
  }
  .register-v2 .card-meta {
    font-size: 12px;
    opacity: 0.65;
    color: #cdd;
    font-style: italic;
    margin-left: auto;
  }
  .register-v2 .bsx-card-body {
    padding: 18px 22px;
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 14px 18px;
  }

  /* Form rows */
  .register-v2 .reg-row {
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-width: 0;
  }
  .register-v2 .reg-row-full { grid-column: 1 / -1; }
  .register-v2 .reg-row-half { grid-column: span 1; }
  @media (max-width: 600px) {
    .register-v2 .reg-row-half { grid-column: 1 / -1; }
  }
  .register-v2 .reg-row label {
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: #aab2bd;
    font-weight: 700;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }
  .register-v2 .reg-req { color: #ffd66e; margin-left: 2px; }
  .register-v2 .reg-pw-meta {
    margin-left: auto;
    font-size: 12px;
    font-weight: 400;
    text-transform: none;
    letter-spacing: 0;
    font-style: italic;
    color: #99a;
  }
  .register-v2 .reg-row input[type="text"],
  .register-v2 .reg-row input[type="email"],
  .register-v2 .reg-row input[type="password"] {
    width: 100%;
    box-sizing: border-box;
    background: rgba(0,0,0,0.25);
    border: 1px solid rgba(255,255,255,.10);
    border-radius: 4px;
    color: #e0f0fa;
    font: inherit;
    font-size: 14px;
    padding: 8px 10px;
    transition: border-color 150ms ease, background 150ms ease;
  }
  .register-v2 .reg-row input::placeholder { color: #8892a0; opacity: 0.5; }
  .register-v2 .reg-row input:focus {
    outline: none;
    border-color: rgba(79, 195, 247, 0.55);
    background: rgba(0,0,0,0.35);
  }
  .register-v2 .reg-pin-input {
    max-width: 120px;
    letter-spacing: 0.4em;
    text-align: center;
  }
  .register-v2 .reg-hint {
    font-size: 12px;
    opacity: 0.65;
    color: #cdd;
    font-style: italic;
  }
  .register-v2 .reg-hint strong { color: #ffd66e; font-style: normal; }

  /* T&C row */
  .register-v2 .reg-tac-row {
    align-self: end;
    flex-direction: row;
    align-items: center;
    gap: 12px;
  }
  .register-v2 .reg-tac-label {
    display: inline-flex;
    align-items: center;
    cursor: pointer;
    text-transform: none;
    letter-spacing: 0;
    font-weight: 400;
    flex: 0 0 auto;
  }
  .register-v2 .reg-tac-label input[type="checkbox"] {
    position: absolute;
    width: 1px; height: 1px;
    margin: -1px; padding: 0;
    border: 0;
    overflow: hidden;
    clip: rect(0 0 0 0);
    white-space: nowrap;
  }
  .register-v2 .reg-tac-box {
    width: 22px;
    height: 22px;
    flex: 0 0 auto;
    border: 1px solid rgba(229, 115, 115, 0.55);
    background: rgba(229, 115, 115, 0.10);
    border-radius: 4px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    font-size: 16px;
    line-height: 1;
    transition: background 150ms ease, border-color 150ms ease, color 150ms ease;
  }
  .register-v2 .reg-tac-x     { color: #ff6b6b; font-weight: 700; }
  .register-v2 .reg-tac-check { color: #b5e7a0; font-weight: 700; display: none; }
  .register-v2 .reg-tac-label input[type="checkbox"]:checked + .reg-tac-box {
    border-color: rgba(181, 231, 160, 0.55);
    background: rgba(181, 231, 160, 0.16);
  }
  .register-v2 .reg-tac-label input[type="checkbox"]:checked + .reg-tac-box .reg-tac-x { display: none; }
  .register-v2 .reg-tac-label input[type="checkbox"]:checked + .reg-tac-box .reg-tac-check { display: inline; }
  .register-v2 .reg-tac-label input[type="checkbox"]:focus-visible + .reg-tac-box {
    outline: 2px solid rgba(79, 195, 247, 0.55);
    outline-offset: 2px;
  }
  .register-v2 .reg-tac-text {
    font-size: 14px;
    line-height: 1.4;
    color: #cdd;
  }
  .register-v2 .reg-tac-text a {
    color: #4fc3f7;
    cursor: pointer;
    text-decoration: none;
  }
  .register-v2 .reg-tac-text a:hover { text-decoration: underline; }

  .register-v2 .reg-recaptcha {
    align-items: center;
    justify-content: center;
  }

  /* Submit */
  .register-v2 .reg-actions {
    grid-column: 1 / -1;
    display: flex;
    justify-content: flex-end;
    margin-top: 4px;
  }
  .register-v2 .bsx-btn {
    font: inherit;
    font-size: 14px;
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
  .register-v2 .bsx-btn:hover {
    background: rgba(79, 195, 247, 0.28);
    border-color: rgba(79, 195, 247, 0.65);
  }

  /* Light mode */
  [data-theme="light"] .register-v2 .bsx-card {
    background: #f7f8fa;
    border-color: rgba(0, 0, 0, 0.18);
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] .register-v2 .bsx-card header {
    background: #e7eaed;
    border-bottom-color: rgba(0, 0, 0, 0.14);
  }
  [data-theme="light"] .register-v2 .bsx-card h3 { color: #1f2933; }
  [data-theme="light"] .register-v2 .card-meta { color: #4a5568; }
  [data-theme="light"] .register-v2 .reg-row label { color: #4a5568; }
  [data-theme="light"] .register-v2 .reg-req { color: #b53d00; }
  [data-theme="light"] .register-v2 .reg-pw-meta { color: #6c7686; }
  [data-theme="light"] .register-v2 .reg-row input[type="text"],
  [data-theme="light"] .register-v2 .reg-row input[type="email"],
  [data-theme="light"] .register-v2 .reg-row input[type="password"] {
    background: #ffffff;
    border-color: rgba(0,0,0,0.18);
    color: #1f2933;
  }
  [data-theme="light"] .register-v2 .reg-row input::placeholder { color: #6c7686; opacity: 0.5; }
  [data-theme="light"] .register-v2 .reg-row input:focus {
    border-color: rgba(25, 118, 210, 0.55);
    background: #ffffff;
  }
  [data-theme="light"] .register-v2 .reg-hint { color: #4a5568; }
  [data-theme="light"] .register-v2 .reg-hint strong { color: #b53d00; }
  [data-theme="light"] .register-v2 .reg-tac-text { color: #1f2933; }
  [data-theme="light"] .register-v2 .reg-tac-text a { color: #1565c0; }
  [data-theme="light"] .register-v2 .bsx-btn {
    background: rgba(25, 118, 210, 0.12);
    border-color: rgba(25, 118, 210, 0.45);
    color: #0d47a1;
  }
  [data-theme="light"] .register-v2 .bsx-btn:hover {
    background: rgba(25, 118, 210, 0.22);
    border-color: rgba(25, 118, 210, 0.60);
  }
</style>
