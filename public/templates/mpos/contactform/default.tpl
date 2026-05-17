<div id="bsx-v2-shell" class="contactform-v2">
  <article class="bsx-card cf-card">
    <header>
      <h3>Contact Us</h3>
      <span class="card-meta">we'll get back to you</span>
    </header>
    <form action="{$smarty.server.SCRIPT_NAME}" method="post" class="cf-form">
      <input type="hidden" name="page" value="{$smarty.request.page|escape}">
      <input type="hidden" name="action" value="contactform">
      <div class="bsx-card-body">

        <div class="cf-row cf-row-half">
          <label for="senderName">Your name <span class="cf-req" aria-hidden="true">*</span></label>
          <input id="senderName" type="text" name="senderName"
                 value="{$smarty.request.senderName|escape|default:""}"
                 placeholder="Jane Doe" maxlength="100" required>
        </div>

        <div class="cf-row cf-row-half">
          <label for="senderEmail">Your email <span class="cf-req" aria-hidden="true">*</span></label>
          <input id="senderEmail" type="email" name="senderEmail"
                 value="{$smarty.request.senderEmail|escape|default:""}"
                 placeholder="you@example.com" maxlength="100" required>
        </div>

        <div class="cf-row">
          <label for="senderSubject">Subject <span class="cf-req" aria-hidden="true">*</span></label>
          <input id="senderSubject" type="text" name="senderSubject"
                 value="{$smarty.request.senderSubject|escape|default:""}"
                 placeholder="Brief summary of your message" maxlength="100" required>
        </div>

        <div class="cf-row">
          <label for="senderMessage">Message <span class="cf-req" aria-hidden="true">*</span></label>
          <textarea id="senderMessage" name="senderMessage"
                    rows="10" maxlength="10000"
                    placeholder="Type your message here…" required>{$smarty.request.senderMessage|escape|default:""}</textarea>
          <span class="cf-hint">Up to 10,000 characters.</span>
        </div>

{if $RECAPTCHA|default:""}
        <div class="cf-row cf-recaptcha">
          {nocache}{$RECAPTCHA nofilter}{/nocache}
        </div>
{/if}

        <div class="cf-actions">
          <button type="submit" name="sendMessage" class="bsx-btn bsx-btn-primary">Send message</button>
        </div>
      </div>
    </form>
  </article>
</div>

<style>
  .contactform-v2 {
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
  .contactform-v2 .bsx-card {
    background: rgba(255,255,255,.03);
    border: 1px solid rgba(255,255,255,.06);
    border-radius: 6px;
    overflow: hidden;
    max-width: 760px;
    margin: 0 auto;
  }
  .contactform-v2 .bsx-card header {
    background: rgba(255,255,255,.05);
    padding: 6px 14px;
    border-bottom: 1px solid rgba(255,255,255,.06);
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .contactform-v2 .bsx-card h3 {
    margin: 0;
    font-size: 12px;
    color: #cdd;
    letter-spacing: 0.04em;
    text-transform: uppercase;
  }
  .contactform-v2 .card-meta {
    font-size: 10px;
    opacity: 0.65;
    color: #cdd;
    font-style: italic;
    margin-left: auto;
  }
  .contactform-v2 .bsx-card-body {
    padding: 18px 22px;
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 14px 18px;
  }

  /* Form rows */
  .contactform-v2 .cf-row {
    grid-column: 1 / -1;
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-width: 0;
  }
  .contactform-v2 .cf-row-half { grid-column: span 1; }
  @media (max-width: 600px) {
    .contactform-v2 .cf-row-half { grid-column: 1 / -1; }
  }
  .contactform-v2 .cf-row label {
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: #aab2bd;
    font-weight: 700;
  }
  .contactform-v2 .cf-req { color: #ffd66e; margin-left: 2px; }
  .contactform-v2 .cf-row input[type="text"],
  .contactform-v2 .cf-row input[type="email"],
  .contactform-v2 .cf-row textarea {
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
  .contactform-v2 .cf-row textarea {
    font-family: inherit;
    line-height: 1.5;
    resize: vertical;
    min-height: 160px;
  }
  .contactform-v2 .cf-row input::placeholder,
  .contactform-v2 .cf-row textarea::placeholder { color: #8892a0; opacity: 0.5; }
  .contactform-v2 .cf-row input:focus,
  .contactform-v2 .cf-row textarea:focus {
    outline: none;
    border-color: rgba(79, 195, 247, 0.55);
    background: rgba(0,0,0,0.35);
  }
  .contactform-v2 .cf-hint {
    font-size: 10px;
    opacity: 0.6;
    color: #cdd;
    font-style: italic;
  }
  .contactform-v2 .cf-recaptcha {
    align-items: center;
    flex-direction: row;
    justify-content: center;
  }

  /* Submit row */
  .contactform-v2 .cf-actions {
    grid-column: 1 / -1;
    display: flex;
    justify-content: flex-end;
    margin-top: 4px;
  }
  .contactform-v2 .bsx-btn {
    font: inherit;
    font-size: 12px;
    font-weight: 700;
    letter-spacing: 0.04em;
    padding: 8px 18px;
    border-radius: 4px;
    cursor: pointer;
    border: 1px solid rgba(79, 195, 247, 0.45);
    background: rgba(79, 195, 247, 0.16);
    color: #e0f0fa;
    transition: background 150ms ease, border-color 150ms ease;
  }
  .contactform-v2 .bsx-btn:hover {
    background: rgba(79, 195, 247, 0.28);
    border-color: rgba(79, 195, 247, 0.65);
  }

  /* Light mode */
  [data-theme="light"] .contactform-v2 .bsx-card {
    background: #f7f8fa;
    border-color: rgba(0, 0, 0, 0.18);
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
  }
  [data-theme="light"] .contactform-v2 .bsx-card header {
    background: #e7eaed;
    border-bottom-color: rgba(0, 0, 0, 0.14);
  }
  [data-theme="light"] .contactform-v2 .bsx-card h3 { color: #1f2933; }
  [data-theme="light"] .contactform-v2 .card-meta { color: #4a5568; }
  [data-theme="light"] .contactform-v2 .cf-row label { color: #4a5568; }
  [data-theme="light"] .contactform-v2 .cf-req { color: #b53d00; }
  [data-theme="light"] .contactform-v2 .cf-row input[type="text"],
  [data-theme="light"] .contactform-v2 .cf-row input[type="email"],
  [data-theme="light"] .contactform-v2 .cf-row textarea {
    background: #ffffff;
    border-color: rgba(0,0,0,0.18);
    color: #1f2933;
  }
  [data-theme="light"] .contactform-v2 .cf-row input::placeholder,
  [data-theme="light"] .contactform-v2 .cf-row textarea::placeholder { color: #6c7686; opacity: 0.5; }
  [data-theme="light"] .contactform-v2 .cf-row input:focus,
  [data-theme="light"] .contactform-v2 .cf-row textarea:focus {
    border-color: rgba(25, 118, 210, 0.55);
    background: #ffffff;
  }
  [data-theme="light"] .contactform-v2 .cf-hint { color: #4a5568; }
  [data-theme="light"] .contactform-v2 .bsx-btn {
    background: rgba(25, 118, 210, 0.12);
    border-color: rgba(25, 118, 210, 0.45);
    color: #0d47a1;
  }
  [data-theme="light"] .contactform-v2 .bsx-btn:hover {
    background: rgba(25, 118, 210, 0.22);
    border-color: rgba(25, 118, 210, 0.60);
  }
</style>
