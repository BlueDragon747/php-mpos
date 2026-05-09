<script setup lang="ts">
import { ref, computed, nextTick, onMounted, onBeforeUnmount, watch } from 'vue';
import EasyMDE from 'easymde';
import 'easymde/dist/easymde.min.css';
import type { NewsInitial, NewsEntry } from './types';

const props = defineProps<{ initial: NewsInitial }>();
const i = props.initial;

// Live editable list — seeded from server, updated locally on actions
// that POST back. Submission still hits PHP via standard form POST,
// which redirects/reloads, so the local list mostly matters until the
// page reloads. We keep it reactive in case we later switch to AJAX.
const entries = ref<NewsEntry[]>([...i.news]);

// Form state. Mode toggles between 'add' and 'edit'.
type Mode = 'add' | 'edit';
const mode = ref<Mode>('add');
const editId = ref<number | null>(null);
const fHeader  = ref('');
const fContent = ref('');
const fShowOn  = ref<'home' | 'dashboard' | 'both'>('home');
const fActive  = ref<0 | 1>(0);   // only meaningful in edit mode

const formCardEl = ref<HTMLElement | null>(null);
const editorTextarea = ref<HTMLTextAreaElement | null>(null);
let mdEditor: EasyMDE | null = null;

// Fullscreen + theme state for the host wrapper. EasyMDE adds
// `.fullscreen` to `.editor-toolbar` and `.CodeMirror` but NOT to
// `.EasyMDEContainer` (issue #553), so we maintain our own flag via
// the onToggleFullScreen callback and bind it to .bsx-mde-host. The
// host is also wrapped in <Teleport to="body" :disabled="!isFullscreen">
// so position:fixed escapes .bsx-card's overflow:hidden containing
// block. isDark is read once on mount; mid-edit theme flips are out
// of scope (see plan).
const isFullscreen = ref(false);
const isDark = ref(
  document.documentElement.getAttribute('data-theme') !== 'light'
);

// Mount EasyMDE on the textarea once it lands in the DOM. The
// editor's underlying value is the authoritative source; we mirror
// it into `fContent` on every change so Vue can drive Edit/Cancel
// state transitions and submit-time validation.
onMounted(() => {
  if (!editorTextarea.value) return;
  mdEditor = new EasyMDE({
    element: editorTextarea.value,
    initialValue: fContent.value,
    spellChecker: false,        // browsers handle this and zh/etc. cause noise
    autoDownloadFontAwesome: true,
    placeholder: 'Compose with Markdown — # Heading, **bold**, [link](url), - bullets, `code`, etc.',
    status: ['lines', 'words'],
    // Default editor height — bumped 25% from EasyMDE's stock 240
    // for this admin form. Fullscreen still fills the viewport.
    minHeight: '300px',
    // Keep source + preview pane scrolled to the same line in
    // side-by-side mode. EasyMDE's default is true but we set it
    // explicitly so a future option-default change doesn't break us.
    syncSideBySidePreviewScroll: true,
    onToggleFullScreen: (full: boolean) => { isFullscreen.value = full; },
    toolbar: [
      'bold', 'italic', 'strikethrough', '|',
      'heading-1', 'heading-2', 'heading-3', '|',
      'quote', 'unordered-list', 'ordered-list', '|',
      'link', 'image', 'code', 'horizontal-rule', '|',
      'preview', 'side-by-side', 'fullscreen', '|',
      'guide',
    ],
  });
  mdEditor.codemirror.on('change', () => {
    fContent.value = mdEditor!.value();
  });
});
onBeforeUnmount(() => {
  if (mdEditor) {
    mdEditor.toTextArea();
    mdEditor = null;
  }
});

// When mode flips (Edit clicked / Cancel pressed) the model is
// updated by Vue but EasyMDE's CodeMirror still shows the old text.
// Push the new value into the editor explicitly.
watch(fContent, (newVal) => {
  if (mdEditor && mdEditor.value() !== newVal) {
    mdEditor.value(newVal);
  }
});
const submitLabel = computed(() => mode.value === 'edit' ? 'Save Changes' : 'Add Post');
const headingText = computed(() => mode.value === 'edit' ? 'Edit News Post' : 'Add News Post');

function startEdit(entry: NewsEntry): void {
  mode.value    = 'edit';
  editId.value  = entry.id;
  fHeader.value = entry.header;
  fContent.value = entry.content;   // raw markdown
  fShowOn.value = entry.show_on;
  fActive.value = entry.active;
  nextTick(() => {
    // 'nearest' = scroll only if the form is off-screen; if it's
    // already visible, don't move the page. 'start' would always
    // pin the form to the viewport top, jolting the page down.
    formCardEl.value?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  });
}

function cancelEdit(): void {
  mode.value    = 'add';
  editId.value  = null;
  fHeader.value = '';
  fContent.value = '';
  fShowOn.value = 'home';
  fActive.value = 0;
}

function confirmDelete(entry: NewsEntry, ev: Event): void {
  if (!window.confirm(`Delete news entry #${entry.id}?`)) {
    ev.preventDefault();
  }
}

// Per-entry expand/collapse state. List defaults to all-collapsed
// so admins can scan post titles + actions quickly; individual posts
// open via the chevron in their header. Set keyed by entry.id.
const expandedIds = ref<Set<number>>(new Set());
function isExpanded(id: number): boolean {
  return expandedIds.value.has(id);
}
function toggleEntry(id: number): void {
  // Reassign so Vue picks up the change (Set mutation isn't reactive
  // by default).
  const next = new Set(expandedIds.value);
  if (next.has(id)) next.delete(id); else next.add(id);
  expandedIds.value = next;
}
</script>

<template>
  <div class="admin-news-v2">
    <!-- Add / Edit form (single form, mode-driven). -->
    <article ref="formCardEl" class="bsx-card">
      <header>
        <h3>{{ headingText }}</h3>
        <span class="news-hint">Markdown supported</span>
      </header>
      <form method="POST" :action="i.formAction">
        <input type="hidden" name="page" value="admin">
        <input type="hidden" name="action" value="news">
        <input type="hidden" name="ctoken" :value="i.csrfToken">

        <!-- Hidden fields differ between add and edit modes — the server
             expects data[header]/data[content]/data[show_on] for add,
             flat header/content/active/show_on/id for update. -->
        <input v-if="mode === 'add'"  type="hidden" name="do" value="add">
        <input v-if="mode === 'edit'" type="hidden" name="do" value="update">
        <input v-if="mode === 'edit'" type="hidden" name="id" :value="editId">

        <div class="bsx-card-body news-add-body">
          <input
            id="news-header"
            class="news-add-header"
            type="text"
            :name="mode === 'add' ? 'data[header]' : 'header'"
            v-model="fHeader"
            placeholder="Post title…"
            aria-label="News post header"
            required
          >

          <!-- EasyMDE mounts on this textarea after Vue first paints.
               It hides the textarea, replaces it with a CodeMirror-
               based editor + toolbar (Bold / Italic / Heading / Quote
               / List / Link / Code / Preview / Side-by-side /
               Fullscreen / Guide). The toolbar buttons wrap the
               selection in markdown syntax. The hidden textarea is
               still what the form posts on submit.

               <Teleport :disabled="!isFullscreen"> moves the host out
               of .bsx-card (which has overflow:hidden — would clip
               position:fixed) only while fullscreen is active. When
               disabled, the host stays in its original card slot. The
               textarea DOM node moves; its `name` attribute survives,
               so form POST still includes the content field. -->
          <Teleport to="body" :disabled="!isFullscreen">
            <div
              class="bsx-mde-host"
              :class="{
                'is-fullscreen': isFullscreen,
                'theme-dark':  isDark,
                'theme-light': !isDark,
              }"
            >
              <textarea
                ref="editorTextarea"
                id="news-content"
                class="news-textarea"
                :name="mode === 'add' ? 'data[content]' : 'content'"
                aria-label="News post content"
                required
              ></textarea>
            </div>
          </Teleport>

          <div class="news-show-on">
            <span class="news-show-on-label">Show on:</span>
            <label><input type="radio" :name="mode === 'add' ? 'data[show_on]' : 'show_on'" value="home"      v-model="fShowOn"> Home page</label>
            <label><input type="radio" :name="mode === 'add' ? 'data[show_on]' : 'show_on'" value="dashboard" v-model="fShowOn"> Dashboard messages</label>
            <label><input type="radio" :name="mode === 'add' ? 'data[show_on]' : 'show_on'" value="both"      v-model="fShowOn"> Both</label>

            <!-- Active toggle only shown in edit mode (matches legacy:
                 new posts always start inactive, you Activate them after). -->
            <label v-if="mode === 'edit'" class="news-active-toggle">
              <input type="hidden" name="active" value="0">
              <input type="checkbox" name="active" value="1" :checked="fActive === 1" @change="fActive = ($event.target as HTMLInputElement).checked ? 1 : 0">
              Active
            </label>
          </div>

          <div class="form-actions">
            <button v-if="mode === 'edit'" type="button" class="bsx-btn bsx-btn-ghost bsx-btn-small" @click="cancelEdit">Cancel</button>
            <button type="submit" class="bsx-btn bsx-btn-primary bsx-btn-small">{{ submitLabel }}</button>
          </div>
        </div>
      </form>
    </article>

    <!-- News entries list. Server-rendered HTML for content (matches
         what the dashboard / home page show). Edit / Delete / Activate
         / Set show_on actions per row. -->
    <p v-if="entries.length === 0" class="news-empty">No news posts yet — add one above.</p>

    <article
      v-for="entry in entries"
      :key="entry.id"
      class="bsx-card news-card"
      :class="{ 'is-inactive': entry.active !== 1 }"
    >
      <header>
        <!-- Expand/collapse chevron, leading the header. Closed by
             default so the list of posts stays scannable; click to
             reveal the body. -->
        <button
          type="button"
          class="bsx-btn bsx-btn-small bsx-btn-ghost news-toggle"
          :class="{ 'is-open': isExpanded(entry.id) }"
          :title="isExpanded(entry.id) ? 'Collapse' : 'Expand'"
          :aria-expanded="isExpanded(entry.id)"
          @click="toggleEntry(entry.id)"
        >
          <span class="news-toggle-chevron" aria-hidden="true">▾</span>
        </button>
        <h3>
          {{ entry.header }}
          <span v-if="entry.active === 1" class="status-pill ok">Active</span>
          <span v-else class="status-pill off">Inactive</span>
        </h3>
        <div class="bsx-card-actions">
          <span class="news-meta">
            posted {{ entry.time }} by <strong>{{ entry.author }}</strong>
          </span>

          <!-- Show-on placement dropdown (auto-submits on change). -->
          <form method="POST" :action="i.formAction" class="placement-form" title="Where this entry shows">
            <input type="hidden" name="page" value="admin">
            <input type="hidden" name="action" value="news">
            <input type="hidden" name="ctoken" :value="i.csrfToken">
            <input type="hidden" name="do" value="set_show_on">
            <input type="hidden" name="id" :value="entry.id">
            <select name="show_on" :value="entry.show_on" @change="(($event.target as HTMLFormElement).form as HTMLFormElement).submit()" aria-label="Show on">
              <option value="home"      :selected="entry.show_on === 'home'">Home</option>
              <option value="dashboard" :selected="entry.show_on === 'dashboard'">Dashboard</option>
              <option value="both"      :selected="entry.show_on === 'both'">Both</option>
            </select>
          </form>

          <!-- Toggle active. POST + ctoken; the controller's CSRF
               guard rejects GET mutations. -->
          <form method="POST" :action="i.formAction" class="inline-action-form">
            <input type="hidden" name="page" value="admin">
            <input type="hidden" name="action" value="news">
            <input type="hidden" name="ctoken" :value="i.csrfToken">
            <input type="hidden" name="do" value="toggle_active">
            <input type="hidden" name="id" :value="entry.id">
            <button
              type="submit"
              class="bsx-btn bsx-btn-small"
              :class="entry.active === 1 ? 'bsx-btn-secondary' : 'bsx-btn-primary'"
              :title="entry.active === 1 ? 'Deactivate (hide from dashboard)' : 'Activate (show on dashboard)'"
            >{{ entry.active === 1 ? 'Deactivate' : 'Activate' }}</button>
          </form>

          <!-- Edit (loads entry into the form above). -->
          <button
            type="button"
            class="bsx-btn bsx-btn-small bsx-btn-success"
            title="Edit news entry"
            @click="startEdit(entry)"
          >Edit</button>

          <!-- Delete. POST + ctoken; confirm() short-circuits via
               @submit handler. -->
          <form method="POST" :action="i.formAction" class="inline-action-form" @submit="confirmDelete(entry, $event)">
            <input type="hidden" name="page" value="admin">
            <input type="hidden" name="action" value="news">
            <input type="hidden" name="ctoken" :value="i.csrfToken">
            <input type="hidden" name="do" value="delete">
            <input type="hidden" name="id" :value="entry.id">
            <button
              type="submit"
              class="bsx-btn bsx-btn-small bsx-btn-danger"
              title="Delete news entry"
            >Delete</button>
          </form>
        </div>
      </header>
      <div
        v-if="isExpanded(entry.id)"
        class="bsx-card-body news-content"
        v-html="entry.contentHtml"
      ></div>
    </article>
  </div>
</template>

<style scoped>
.admin-news-v2 {
  margin: 0 16px 6px 16px;
  padding: 1em;
  color: var(--text-primary, #cdd);
  font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.bsx-card {
  background: rgba(255,255,255,.03);
  border: 1px solid rgba(255,255,255,.06);
  border-radius: 6px;
  overflow: hidden;
}
.bsx-card.is-inactive { opacity: 0.7; border-style: dashed; }
.bsx-card header {
  background: rgba(255,255,255,.05);
  padding: 6px 14px;
  border-bottom: 1px solid rgba(255,255,255,.06);
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
}
.bsx-card h3 {
  margin: 0;
  font-size: 13px;
  color: #cdd;
  letter-spacing: 0.04em;
  display: flex;
  align-items: center;
  gap: 10px;
  flex: 1 1 auto;
  min-width: 0;
}
.bsx-card-actions {
  display: flex;
  align-items: center;
  gap: 6px;
  flex: 0 0 auto;
  flex-wrap: wrap;
}
.bsx-card-body { padding: 14px 18px; }
.news-add-body { display: flex; flex-direction: column; gap: 12px; }
.news-hint {
  font-size: 11px;
  opacity: 0.65;
  color: #cdd;
  font-style: italic;
}
.news-meta {
  font-size: 11px;
  opacity: 0.65;
  color: #cdd;
  font-variant-numeric: tabular-nums;
}
.news-meta strong { color: #e0f0fa; font-weight: 600; }

.status-pill {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 999px;
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  border: 1px solid transparent;
}
.status-pill.ok {
  background: rgba(181, 231, 160, 0.18);
  border-color: rgba(181, 231, 160, 0.45);
  color: #b5e7a0;
}
.status-pill.off {
  background: rgba(255, 255, 255, 0.06);
  border-color: rgba(255, 255, 255, 0.16);
  color: #99a;
}

/* Title input. */
.news-add-header {
  font: inherit;
  font-size: 14px;
  padding: 8px 10px;
  background: rgba(255,255,255,.04);
  border: 1px solid rgba(255,255,255,.10);
  border-radius: 4px;
  color: #f0f0f0;
  width: 100%;
  box-sizing: border-box;
}

/* The native textarea is hidden once EasyMDE mounts; this rule just
   covers the brief moment between first paint and EasyMDE init. */
.news-textarea {
  font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
  font-size: 12px;
  padding: 8px 10px;
  background: rgba(255,255,255,.04);
  border: 1px solid rgba(255,255,255,.10);
  border-radius: 4px;
  color: #f0f0f0;
  width: 100%;
  box-sizing: border-box;
  min-height: 220px;
}

/* EasyMDE styling lives in the non-scoped <style> block below this
   one. Vue's scoped styles + :deep() were losing specificity races
   with EasyMDE's bundled CSS in side-by-side / fullscreen modes. */

/* Show-on radio row + active toggle. */
.news-show-on {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 14px;
  font-size: 12px;
  color: #cdd;
}
.news-show-on label { display: inline-flex; align-items: center; gap: 4px; }
.news-show-on-label { font-weight: 600; opacity: 0.85; }
.news-active-toggle { margin-left: auto; }

.form-actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
}

/* News content (rendered HTML from server-side Markdown). */
.news-content { font-size: 13px; line-height: 1.5; color: #cdd; }
.news-content :deep(p) { margin: 0 0 8px; }
.news-content :deep(p:last-child) { margin-bottom: 0; }
.news-content :deep(a) { color: #4fc3f7; }
.news-content :deep(code),
.news-content :deep(pre) {
  background: rgba(0,0,0,0.25);
  padding: 1px 5px;
  border-radius: 2px;
  font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
  font-size: 12px;
}
.news-content :deep(pre) { padding: 8px 10px; overflow-x: auto; }

.news-empty {
  margin: 0;
  text-align: center;
  opacity: 0.55;
  padding: 16px;
}

/* Placement form (auto-submits on select change). */
.placement-form select {
  font: inherit;
  font-size: 12px;
  padding: 3px 6px;
  background: rgba(255,255,255,.04);
  border: 1px solid rgba(255,255,255,.10);
  border-radius: 4px;
  color: #f0f0f0;
}
/* Native <option> elements render on the OS-controlled dropdown
   surface (white in most browsers, regardless of our select's
   styling). Force black text on the options so the choices stay
   readable when the dropdown opens — without this they pick up
   the parent's near-white color and disappear on the white panel. */
.placement-form select option {
  color: #000;
  background: #ffffff;
}

/* Buttons (mirror the rest of v2). */
.bsx-btn {
  font: inherit;
  font-size: 13px;
  font-weight: 600;
  letter-spacing: 0.04em;
  padding: 6px 16px;
  border-radius: 4px;
  cursor: pointer;
  border: 1px solid transparent;
  background: rgba(79, 195, 247, 0.10);
  border-color: rgba(79, 195, 247, 0.28);
  color: #cdd;
  text-decoration: none;
  display: inline-flex;
  align-items: center;
  transition: background 150ms ease, border-color 150ms ease;
}
.bsx-btn:hover { background: rgba(79, 195, 247, 0.20); border-color: rgba(79, 195, 247, 0.55); }
.bsx-btn-primary {
  background: rgba(79, 195, 247, 0.16);
  border-color: rgba(79, 195, 247, 0.45);
  color: #e0f0fa;
}
.bsx-btn-secondary {
  background: rgba(245, 203, 167, 0.10);
  border-color: rgba(245, 203, 167, 0.40);
  color: #f9e3d2;
}
.bsx-btn-success {
  background: rgba(181, 231, 160, 0.12);
  border-color: rgba(181, 231, 160, 0.45);
  color: #d6f5c2;
}
.bsx-btn-danger {
  background: rgba(229, 115, 115, 0.10);
  border-color: rgba(229, 115, 115, 0.45);
  color: #f9c8c8;
}
.bsx-btn-ghost {
  background: transparent;
  border-color: rgba(255,255,255,.18);
  color: #cdd;
}
.bsx-btn-small { padding: 4px 10px; font-size: 12px; }
.bsx-btn-tiny { padding: 2px 8px; font-size: 11px; }

/* Expand/collapse chevron in each news entry's header. The chevron
   rotates 180° when the entry is open so the affordance is obvious. */
.news-toggle {
  padding: 2px 8px;
  min-width: 28px;
  justify-content: center;
}
.news-toggle-chevron {
  display: inline-block;
  font-size: 12px;
  line-height: 1;
  transition: transform 150ms ease;
}
.news-toggle.is-open .news-toggle-chevron { transform: rotate(180deg); }

[data-theme="light"] .bsx-card { background: #ffffff; border-color: rgba(0,0,0,0.10); }
[data-theme="light"] .bsx-card header { background: #f1f3f5; border-bottom-color: rgba(0,0,0,0.08); }
[data-theme="light"] .bsx-card h3 { color: #1f2933; }
[data-theme="light"] .news-hint,
[data-theme="light"] .news-meta,
[data-theme="light"] .news-content,
[data-theme="light"] .news-show-on,
[data-theme="light"] .news-edit-toolbar { color: #2d3748; }
[data-theme="light"] .news-meta strong { color: #1f2933; }
[data-theme="light"] .news-content :deep(a),
[data-theme="light"] .news-preview :deep(a) { color: #1976d2; }
[data-theme="light"] .news-add-header,
[data-theme="light"] .news-textarea,
[data-theme="light"] .placement-form select {
  background: #ffffff;
  border-color: rgba(0,0,0,0.18);
  color: #1f2933;
}
[data-theme="light"] .news-preview {
  background: #ffffff;
  border-color: rgba(0,0,0,0.10);
  color: #1f2933;
}

/* Light-mode buttons + status pills. Dark-mode rules use rgba()
   colours tuned for dark surfaces — on white they wash out (pale
   text on near-white backgrounds = unreadable). Bump background
   alpha to ~.14 and switch to dark, fully-opaque text colours so
   each variant reads cleanly against the white card. */
[data-theme="light"] .bsx-btn {
  background: rgba(25, 118, 210, 0.10);
  border-color: rgba(25, 118, 210, 0.45);
  color: #1565c0;
}
[data-theme="light"] .bsx-btn:hover {
  background: rgba(25, 118, 210, 0.20);
  border-color: rgba(25, 118, 210, 0.65);
}
[data-theme="light"] .bsx-btn-primary {
  background: rgba(25, 118, 210, 0.18);
  border-color: rgba(25, 118, 210, 0.55);
  color: #0d47a1;
}
[data-theme="light"] .bsx-btn-secondary {
  background: rgba(239, 108, 0, 0.14);
  border-color: rgba(239, 108, 0, 0.55);
  color: #e65100;
}
[data-theme="light"] .bsx-btn-success {
  background: rgba(46, 125, 50, 0.14);
  border-color: rgba(46, 125, 50, 0.55);
  color: #1b5e20;
}
[data-theme="light"] .bsx-btn-danger {
  background: rgba(198, 40, 40, 0.14);
  border-color: rgba(198, 40, 40, 0.55);
  color: #b71c1c;
}
[data-theme="light"] .bsx-btn-ghost {
  background: transparent;
  border-color: rgba(0, 0, 0, 0.22);
  color: #1f2933;
}
[data-theme="light"] .status-pill.ok {
  background: rgba(46, 125, 50, 0.14);
  border-color: rgba(46, 125, 50, 0.55);
  color: #1b5e20;
}
[data-theme="light"] .status-pill.off {
  background: rgba(0, 0, 0, 0.05);
  border-color: rgba(0, 0, 0, 0.22);
  color: #5a6470;
}
</style>

<!-- EasyMDE / CodeMirror overrides — NON-scoped on purpose. EasyMDE
     creates its DOM dynamically after Vue mounts, and its bundled
     light-theme CSS has high specificity. Putting these rules in a
     non-scoped block guarantees they apply globally and beat the
     bundled stylesheet via !important. -->
<style>
.EasyMDEContainer { color: #cdd; }

/* Toolbar */
.EasyMDEContainer .editor-toolbar {
  background: rgba(255, 255, 255, .05) !important;
  border: 1px solid rgba(255, 255, 255, .10) !important;
  border-bottom: 0 !important;
  border-radius: 4px 4px 0 0 !important;
  opacity: 1 !important;
}
.EasyMDEContainer .editor-toolbar button {
  color: #cdd !important;
  border: 1px solid transparent !important;
}
.EasyMDEContainer .editor-toolbar button:hover,
.EasyMDEContainer .editor-toolbar button.active {
  background: rgba(79, 195, 247, .12) !important;
  border-color: rgba(79, 195, 247, .40) !important;
  color: #e0f0fa !important;
}
.EasyMDEContainer .editor-toolbar i.separator {
  border-left: 1px solid rgba(255, 255, 255, .12) !important;
  border-right: 0 !important;
}

/* Source (CodeMirror) — fixed height in normal flow so the editor
   doesn't grow forever; scrolls inside on overflow. 300 px is 25%
   taller than EasyMDE's prior 240 default. The fullscreen rule
   below removes this cap so the editor fills the viewport. */
.EasyMDEContainer .CodeMirror {
  background: #14171c !important;
  color: #f0f0f0 !important;
  border: 1px solid rgba(255, 255, 255, .10) !important;
  border-radius: 0 0 4px 4px !important;
  font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace !important;
  font-size: 12px !important;
  height: 300px !important;
  min-height: 300px !important;
  max-height: 300px !important;
}
.EasyMDEContainer .CodeMirror-cursor { border-left-color: #4fc3f7 !important; }
.EasyMDEContainer .CodeMirror-placeholder { opacity: .5 !important; }
.EasyMDEContainer .CodeMirror-selected { background: rgba(79, 195, 247, .20) !important; }
.EasyMDEContainer .CodeMirror-line span.cm-header  { color: #e0f0fa; font-weight: 700; }
.EasyMDEContainer .CodeMirror-line span.cm-strong  { color: #ffd66e; }
.EasyMDEContainer .CodeMirror-line span.cm-em      { color: #b5e7a0; font-style: italic; }
.EasyMDEContainer .CodeMirror-line span.cm-link,
.EasyMDEContainer .CodeMirror-line span.cm-url     { color: #4fc3f7; }
.EasyMDEContainer .CodeMirror-line span.cm-comment { color: rgba(255, 255, 255, .55); }
.EasyMDEContainer .CodeMirror-sizer,
.EasyMDEContainer .CodeMirror-gutters {
  background: #14171c !important;
}
.EasyMDEContainer .editor-statusbar {
  color: rgba(255, 255, 255, .55) !important;
  font-size: 11px;
}

/* Inline preview (eye icon) + side-by-side preview pane. Same fixed
   height as the source so the two panes stay aligned. */
.EasyMDEContainer .editor-preview,
.EasyMDEContainer .editor-preview-active,
.EasyMDEContainer .editor-preview-side,
.EasyMDEContainer .editor-preview-active-side {
  background: #14171c !important;
  color: #cdd !important;
  border: 1px solid rgba(255, 255, 255, .10) !important;
  height: 300px !important;
  min-height: 300px !important;
  max-height: 300px !important;
}
.EasyMDEContainer .editor-preview a,
.EasyMDEContainer .editor-preview-side a { color: #4fc3f7 !important; }

/* Side-by-side container: solid background + matching border. */
.EasyMDEContainer.sided--no-fullscreen {
  background: #14171c !important;
  border: 1px solid rgba(255, 255, 255, .10) !important;
  border-radius: 4px !important;
}
.EasyMDEContainer.sided--no-fullscreen .CodeMirror,
.EasyMDEContainer.sided--no-fullscreen .CodeMirror-sizer,
.EasyMDEContainer.sided--no-fullscreen .CodeMirror-gutters,
.EasyMDEContainer.sided--no-fullscreen .editor-preview-side {
  background: #14171c !important;
}

/* Fullscreen — driven by the .bsx-mde-host wrapper that Vue
   <Teleport> moves to <body> when EasyMDE's onToggleFullScreen
   fires. EasyMDE itself does NOT add .fullscreen to .EasyMDEContainer
   (issue #553), only to .editor-toolbar and .CodeMirror — which is
   why the prior selectors were dead code. Scoping off our own host
   class lets us beat EasyMDE's bundled rules cleanly without
   layering more !important on top.

   Site chrome is hidden while fullscreen is active so the toolbar
   never bleeds through ambient page elements. :has() matches any
   descendant of body carrying .bsx-mde-host.is-fullscreen
   (Chrome 105+, Safari 15.4+, Firefox 121+). */
body:has(.bsx-mde-host.is-fullscreen) #header,
body:has(.bsx-mde-host.is-fullscreen) #secondary_bar,
body:has(.bsx-mde-host.is-fullscreen) #sidebar,
body:has(.bsx-mde-host.is-fullscreen) .footer {
  display: none !important;
}
body:has(.bsx-mde-host.is-fullscreen) #main {
  margin: 0 !important;
  padding: 0 !important;
  width: 100vw !important;
}
body:has(.bsx-mde-host.is-fullscreen) {
  overflow: hidden !important;
}

/* Pin the host wrapper to the viewport. Belt-and-suspenders alongside
   EasyMDE's own position:fixed on inner elements — pinning the host
   too means our scoped rules below anchor correctly even if Teleport
   has races. */
.bsx-mde-host.is-fullscreen {
  position: fixed;
  inset: 0;
  z-index: 99999;
  background: #14171c;
}
.bsx-mde-host.theme-light.is-fullscreen { background: #ffffff; }

/* Toolbar background in fullscreen — explicit per theme.
   .bsx-mde-host.theme-X (2 classes) outranks EasyMDE's bundled
   .editor-toolbar.fullscreen (1 class) without needing !important. */
.bsx-mde-host.theme-dark .editor-toolbar.fullscreen {
  background: #14171c;
  border-bottom-color: rgba(255, 255, 255, 0.12);
}
.bsx-mde-host.theme-light .editor-toolbar.fullscreen {
  background: #ffffff;
  border-bottom-color: rgba(0, 0, 0, 0.10);
}

/* Kill EasyMDE's bundled white ::before/::after gradient pseudos
   on the fullscreen toolbar — they cause a "bright strip above
   toolbar" bleed in dark mode. */
.bsx-mde-host .editor-toolbar.fullscreen::before,
.bsx-mde-host .editor-toolbar.fullscreen::after { display: none; }

/* Inner editor surfaces — keep them solid + drop the height clamp
   so the editor + preview fill the viewport in fullscreen. */
.bsx-mde-host.is-fullscreen .CodeMirror,
.bsx-mde-host.is-fullscreen .CodeMirror-sizer,
.bsx-mde-host.is-fullscreen .CodeMirror-gutters,
.bsx-mde-host.is-fullscreen .editor-preview,
.bsx-mde-host.is-fullscreen .editor-preview-side {
  background: #14171c !important;
}
.bsx-mde-host.theme-light.is-fullscreen .CodeMirror,
.bsx-mde-host.theme-light.is-fullscreen .CodeMirror-sizer,
.bsx-mde-host.theme-light.is-fullscreen .CodeMirror-gutters,
.bsx-mde-host.theme-light.is-fullscreen .editor-preview,
.bsx-mde-host.theme-light.is-fullscreen .editor-preview-side {
  background: #ffffff !important;
}
.bsx-mde-host.is-fullscreen .CodeMirror,
.bsx-mde-host.is-fullscreen .editor-preview,
.bsx-mde-host.is-fullscreen .editor-preview-side {
  height: auto !important;
  min-height: 0 !important;
  max-height: none !important;
}

/* CodeMirror's "native" scrollbarStyle uses a clever architecture:
   - .CodeMirror-scroll is the actual scrollable container, but its
     native bars are deliberately clipped out of view (margin: -50px
     under parent's overflow:hidden) so they don't double up.
   - .CodeMirror-vscrollbar / .CodeMirror-hscrollbar are SEPARATE
     scrollable divs (each contains a 1px child sized via JS to match
     content). The browser renders a real native scrollbar on each.
     CodeMirror syncs scrollTop between these and .CodeMirror-scroll.
   So: leave the margin trick alone, and style the *-vscrollbar /
   *-hscrollbar divs — they're what's actually visible. Match the
   preview pane (and the rest of the site) exactly.
   ONE override: trim .CodeMirror-scroll's bundled padding-bottom from
   50px down to 8px. The default 50px wastes a big strip of viewport
   when scrolled to the end (the bottom 50px of the viewport is empty
   padding); 8px is enough to clear the floating .CodeMirror-hscrollbar
   overlay if it ever appears. The preview pane has 0 padding-bottom —
   matching that geometry is what stops the bottom-cut-off complaint. */
.EasyMDEContainer .CodeMirror-scroll {
  padding-bottom: 8px !important;
}
.EasyMDEContainer .CodeMirror-vscrollbar,
.EasyMDEContainer .CodeMirror-hscrollbar,
.EasyMDEContainer .editor-preview,
.EasyMDEContainer .editor-preview-side {
  scrollbar-width: thin;
  scrollbar-color: rgba(255, 255, 255, .18) transparent;
}
.EasyMDEContainer .CodeMirror-vscrollbar::-webkit-scrollbar,
.EasyMDEContainer .CodeMirror-hscrollbar::-webkit-scrollbar,
.EasyMDEContainer .editor-preview::-webkit-scrollbar,
.EasyMDEContainer .editor-preview-side::-webkit-scrollbar {
  width: 8px !important;
  height: 8px !important;
}
.EasyMDEContainer .CodeMirror-vscrollbar::-webkit-scrollbar-track,
.EasyMDEContainer .CodeMirror-hscrollbar::-webkit-scrollbar-track,
.EasyMDEContainer .editor-preview::-webkit-scrollbar-track,
.EasyMDEContainer .editor-preview-side::-webkit-scrollbar-track {
  background: transparent !important;
}
.EasyMDEContainer .CodeMirror-vscrollbar::-webkit-scrollbar-thumb,
.EasyMDEContainer .CodeMirror-hscrollbar::-webkit-scrollbar-thumb,
.EasyMDEContainer .editor-preview::-webkit-scrollbar-thumb,
.EasyMDEContainer .editor-preview-side::-webkit-scrollbar-thumb {
  background-color: rgba(255, 255, 255, .18) !important;
  border-radius: 4px !important;
  border: 2px solid transparent !important;
  background-clip: padding-box !important;
}
.EasyMDEContainer .CodeMirror-vscrollbar::-webkit-scrollbar-thumb:hover,
.EasyMDEContainer .CodeMirror-hscrollbar::-webkit-scrollbar-thumb:hover,
.EasyMDEContainer .editor-preview::-webkit-scrollbar-thumb:hover,
.EasyMDEContainer .editor-preview-side::-webkit-scrollbar-thumb:hover {
  background-color: rgba(79, 195, 247, .45) !important;
}

/* Light-mode mirror. Fullscreen-specific light overrides live with
   the .bsx-mde-host.theme-light rules above; this block covers the
   normal (non-fullscreen) flow. */
[data-theme="light"] .EasyMDEContainer .editor-toolbar { background: #f1f3f5 !important; border-color: rgba(0, 0, 0, .10) !important; }
[data-theme="light"] .EasyMDEContainer .editor-toolbar button { color: #1f2933 !important; }
[data-theme="light"] .EasyMDEContainer .CodeMirror,
[data-theme="light"] .EasyMDEContainer .CodeMirror-sizer,
[data-theme="light"] .EasyMDEContainer .CodeMirror-gutters,
[data-theme="light"] .EasyMDEContainer .editor-preview,
[data-theme="light"] .EasyMDEContainer .editor-preview-active,
[data-theme="light"] .EasyMDEContainer .editor-preview-side,
[data-theme="light"] .EasyMDEContainer .editor-preview-active-side,
[data-theme="light"] .EasyMDEContainer.sided--no-fullscreen,
[data-theme="light"] .EasyMDEContainer.sided--no-fullscreen .CodeMirror,
[data-theme="light"] .EasyMDEContainer.sided--no-fullscreen .editor-preview-side {
  background: #ffffff !important;
  color: #1f2933 !important;
  border-color: rgba(0, 0, 0, .10) !important;
}
</style>
