// The hero menu bar on the Testament Made app sites (Dinky, Binky, Slinky), made to work like the Mac's.
// Menus open with each app's real items; the Apple menu, Spotlight and Control Center work; and each app
// has its own small surprise. One file, copied to all three sites. Mouse only: the menu bar is decoration
// (aria-hidden), and everything here is also reachable on the page itself.
//
// Hooks in the page: a `.menubar[data-menubar="<App>"]` with items tagged data-mb="apple|app|file|edit|
// view|window|help|extra|battery|wifi|spotlight|cc|clock". The window that Minimize and Hide act on is
// tagged data-mb-window. App-specific actions are sent to the page as a `menubar:action` event.
(() => {
  const bar = document.querySelector('.menubar[data-menubar]');
  if (!bar) return;
  const app = bar.dataset.menubar;
  const desk = bar.closest('.desktop') || bar.parentElement;
  const still = () => document.documentElement.classList.contains('fmb-still') || matchMedia('(prefers-reduced-motion: reduce)').matches;
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
  const emit = (action) => document.dispatchEvent(new CustomEvent('menubar:action', { detail: { app, action } }));

  // ---------- Menus: each app's real items. [label, shortcut, action] or '-' for a separator. ----------
  const apple = [
    ['About This Mac', '', 'aboutMac'], '-',
    ['System Settings…'], ['App Store'], '-',
    ['Force Quit…', '⌥⌘⎋'], '-',
    ['Sleep', '', 'sleep'], ['Restart…'], ['Shut Down…'], '-',
    ['Lock Screen', '⌃⌘Q', 'sleep'], ['Log Out…', '⇧⌘Q'],
  ];
  const edit = [['Undo', '⌘Z', null, true], ['Redo', '⇧⌘Z', null, true], '-', ['Cut', '⌘X'], ['Copy', '⌘C'], ['Paste', '⌘V'], ['Select All', '⌘A'], '-', ['Find…', '⌘F', 'spotlight']];
  const windowMenu = [['Minimize', '⌘M', 'minimize'], ['Zoom', '', 'fullscreen'], '-', ['Bring All to Front', '', 'restore']];
  const MENUS = {
    Slinky: {
      app: [['About Slinky', '', 'about'], ['Check for Updates…', '', 'upToDate'], '-', ['Lock Slinky', '⌃⌘L', 'lock'], '-', ['Settings…', '⌘,'], '-', ['Hide Slinky', '⌘H', 'hide'], ['Quit Slinky', '⌘Q']],
      file: [['Add Item…', '⌘N', 'add-item'], ['New Project…', '⇧⌘N', 'new-project'], ['Import…', '⇧⌘I', 'import'], '-', ['Quick Access', '⌥⌘K', 'quick-access'], '-', ['Close Window', '⌘W', 'minimize']],
      view: [['All Items', '⌘1'], ['Keys & Tokens', '⌘2'], ['Recovery Codes', '⌘3'], ['Recovery Keys', '⌘4'], ['Health', '⌘5'], ['Recently Deleted', '⌘6'], ['Activity', '⌘7'], ['People', '⌘8'], '-', ['Show Sidebar', '⌃⌘S', 'toggle-sidebar'], '-', ['Enter Full Screen', '⌃⌘F', 'fullscreen']],
      help: [['Slinky Help', '', 'help']],
      extra: {
        status: () => ($('[data-mb-window].is-locked') ? ['Locked', false] : ['Unlocked', true]),
        button: { icon: 'lock', label: 'Lock Slinky', action: 'lock' },
        groups: [
          [['Quick Access', '⌥⌘K', 'quick-access', 'search'], ['Add Item…', '⌘N', 'add-item', 'plus']],
          [['2 things to look at in Health', '', null, 'heart']],
          ['Recently Copied', { key: 'STRIPE_SECRET_KEY', note: 'Copy' }, { key: 'GITHUB_TOKEN', note: 'Copy' }],
          [['Open Slinky', '', 'restore', 'window'], ['Settings…', '⌘,', null, 'gear'], ['About Slinky', '', 'about', 'info'], ['Quit Slinky', '⌘Q', null, 'power']],
        ],
      },
    },
    Dinky: {
      app: [['About Dinky', '', 'about'], ['Check for Updates…', '', 'upToDate'], '-', ['Settings…', '⌘,'], '-', ['Hide Dinky', '⌘H', 'hide'], ['Quit Dinky', '⌘Q']],
      file: [['Open Files…', '⌘O'], ['Clipboard Compress', '⇧⌘V', 'clipboard'], '-', ['Compress Now', '⌘↩'], ['Clear All', '⌥⌘K'], '-', ['Close Window', '⌘W', 'minimize']],
      view: [['Show Sidebar', '⌃⌘S'], '-', ['Enter Full Screen', '⌃⌘F', 'fullscreen']],
      help: [['Dinky Help', '⇧⌘?', 'help']],
      extra: {
        status: () => ['1.2 GB saved so far', false],
        groups: [
          [['Open Files…', '⌘O', null, 'open'], ['Clipboard Compress', '⇧⌘V', 'clipboard', 'clipboard'], ['Floating dropzone', '', 'dropzone', 'tray', 'check']],
          ['Recently compressed', { file: 'img', name: 'hero-photo.webp', note: '−72%' }, { file: 'doc', name: 'Pitch deck.pdf', note: '−48%' }, { file: 'vid', name: 'demo-reel.mp4', note: '−81%' }],
          [['Open Dinky', '', 'restore', 'window'], ['Settings…', '⌘,', null, 'gear'], ['About Dinky', '', 'about', 'info'], ['Quit Dinky', '⌘Q', 'wave', 'power']],
        ],
      },
    },
    Binky: {
      app: [['About Binky', '', 'about'], ['Check for Updates…', '', 'upToDate'], ['History…'], ['Last Sort Summary…', '⌥⌘B'], '-', ['Settings…', '⌘,'], '-', ['Hide Binky', '⌘H', 'hide'], ['Quit Binky', '⌘Q']],
      file: [['Open Files…', '⌘O'], ['Sort All', '⌘↩', 'sort'], '-', ['Close Window', '⌘W', 'minimize']],
      view: [['Quick Sort', '⌘1'], ['Routines', '⌘2'], '-', ['Enter Full Screen', '⌃⌘F', 'fullscreen']],
      help: [['Binky Help', '⇧⌘?', 'help']],
      extra: {
        status: () => (routinesOn ? [binkySorted ? 'Sorted 5 · just now' : 'Sorted 215 · 4 min. ago', true] : ['Watching paused.', false]),
        button: { icon: () => (routinesOn ? 'pause' : 'play'), label: () => (routinesOn ? 'Pause watching' : 'Resume watching'), action: 'watch' },
        groups: [
          [['Sort All Folders', '', 'sort', 'tray'], ['Sort Auto-install DMGs', '', 'sort', 'folder'], ['Sort Sort my Downloads', '', 'sort', 'folder']],
          [['91 want a second look.', '', 'review', 'review']],
          [['Show Binky', '', 'restore', 'window'], ['History…', '', null, 'history'], ['Settings…', '⌘,', null, 'gear'], ['About Binky', '', 'about', 'info'], ['Quit Binky', '⌘Q', null, 'power']],
        ],
      },
    },
  };
  const menus = MENUS[app] || MENUS.Slinky;
  const menuFor = { apple, app: menus.app, file: menus.file, edit, view: menus.view, window: windowMenu, help: menus.help, extra: menus.extra };

  // ---------- Menu rendering ----------
  let open = null; // { key, el }
  const clearOn = () => bar.querySelectorAll('.fmb-on').forEach((el) => el.classList.remove('fmb-on'));
  const close = () => { if (open) { open.el.remove(); open = null; } clearOn(); };
  const place = (el, anchor) => {
    const d = desk.getBoundingClientRect();
    const a = anchor.getBoundingClientRect();
    el.style.top = `${a.bottom - d.top + 4}px`;
    const left = Math.min(a.left - d.left, d.width - el.offsetWidth - 8);
    el.style.left = `${Math.max(8, left)}px`;
  };
  const openMenu = (key, anchor) => {
    const items = menuFor[key];
    if (!items) return;
    if (!Array.isArray(items)) return extraPanel(anchor);
    close();
    const el = document.createElement('div');
    el.className = 'fmb-menu';
    for (const it of items) {
      if (it === '-') { el.append(Object.assign(document.createElement('hr'), { className: 'fmb-sep' })); continue; }
      const [label, keys = '', action = null, disabled = false] = it;
      const row = document.createElement('div');
      row.className = 'fmb-item' + (disabled ? ' is-off' : '');
      row.innerHTML = `<span></span><kbd></kbd>`;
      row.firstChild.textContent = label;
      row.lastChild.textContent = keys;
      if (!disabled) row.addEventListener('click', (e) => { e.stopPropagation(); close(); run(action); });
      el.append(row);
    }
    desk.append(el);
    place(el, anchor);
    anchor.classList.add('fmb-on');
    open = { key, el };
  };

  // ---------- Panels (About, Spotlight, Control Center) ----------
  let panel = null;
  let scrim = null;
  const closePanel = () => {
    panel?.remove(); panel = null; clearOn(); desk.classList.remove('fmb-thinking');
    if (scrim) { scrim.remove(); scrim = null; document.documentElement.classList.remove('fmb-sheet-open'); }
  };
  // Panels open on the hero desktop; the phone Spotlight sheet opens over the whole page (host = body).
  const showPanel = (html, cls, anchor, host = desk) => {
    close(); closePanel();
    panel = document.createElement('div');
    panel.className = `fmb-panel ${cls}`;
    panel.innerHTML = html;
    panel.addEventListener('click', (e) => e.stopPropagation());
    host.append(panel);
    if (anchor) { place(panel, anchor); anchor.classList.add('fmb-on'); }
    return panel;
  };
  const icon = () => $('.dock__app.is-current img')?.getAttribute('src') || '';
  const version = () => (($('.hero') || document.body).textContent.match(/\bv(\d+\.\d+(?:\.\d+)?)\b/) || [])[1] || '';
  const about = () => {
    const p = showPanel(`
      <img src="${icon()}" alt="" width="72" height="72" />
      <b>${app}</b><span>Version ${version()}</span>
      <small>© 2026 Testament Made, LLC</small>
      <button type="button" class="fmb-btn">OK</button>`, 'fmb-about');
    p.querySelector('button').addEventListener('click', closePanel);
  };
  const aboutMac = () => {
    const p = showPanel(`
      <svg viewBox="0 0 120 76" width="120" height="76" aria-hidden="true"><rect x="16" y="4" width="88" height="58" rx="5" fill="none" stroke="currentColor" stroke-width="3"/><rect x="22" y="10" width="76" height="46" rx="2" fill="var(--fmb-accent)" opacity=".85"/><path d="M4 64h112l-6 8H10z" fill="currentColor"/></svg>
      <b>MacBook Pro</b><span>14-inch, 2026</span>
      <dl><dt>Chip</dt><dd>Apple M5 Pro</dd><dt>Memory</dt><dd>24 GB</dd><dt>macOS</dt><dd>Tahoe 26</dd><dt>Apps</dt><dd>Dinky, Binky, Slinky</dd></dl>
      <button type="button" class="fmb-btn">More Info…</button>`, 'fmb-about');
    p.querySelector('button').addEventListener('click', closePanel);
  };
  // sheet: true opens it as a full-width sheet over the page (from the Dock's Search button on a phone).
  const spotlight = (anchor, sheet = false) => {
    // Headlines (with their small label above, like "Recovery") and FAQ questions on this page.
    const clean = (t) => t.replace(/\s+/g, ' ').trim();
    const words = (el) => clean(el.innerText || el.textContent);
    const sections = [
      ...$$('main h2').filter((h) => h.textContent.trim() && !h.closest('.desktop')).map((h) => {
        const host = h.closest('section, .g-row, .ss-row, [class*="row"]') || h;
        const label = h.previousElementSibling?.matches('.eyebrow, [class*="eyebrow"], [class*="label"]') ? clean(h.previousElementSibling.textContent) : '';
        return { el: host, text: words(h), find: `${label} ${words(h)}` };
      }),
      ...$$('main summary, main .faq-q').filter((q) => !q.closest('.desktop')).map((q) => ({ el: q.closest('details, .faq-item') || q, text: clean(q.textContent), find: clean(q.textContent) })),
    ];
    // Tahoe's Spotlight: a large glass and a large placeholder.
    const p = showPanel(`<label class="fmb-search"><svg class="fmb-glass" viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><circle cx="10.2" cy="10.2" r="7" fill="none" stroke="currentColor" stroke-width="2.1"/><path d="m15.4 15.4 5.6 5.6" stroke="currentColor" stroke-width="2.3" stroke-linecap="round"/></svg><input type="search" enterkeyhint="search" placeholder="${sheet ? 'Search or ask' : 'Spotlight Search'}" aria-label="Search this page" autocomplete="off" spellcheck="false" />${sheet ? '<button type="button" class="fmb-cancel">Cancel</button>' : ''}</label><div class="fmb-results"></div>`, sheet ? 'fmb-spot fmb-sheet' : 'fmb-spot', null, sheet ? document.body : desk);
    if (sheet) {
      scrim = document.createElement('div');
      scrim.className = 'fmb-scrim';
      scrim.addEventListener('click', closePanel);
      p.before(scrim);
      document.documentElement.classList.add('fmb-sheet-open');
      p.querySelector('.fmb-cancel').addEventListener('click', closePanel);
      p.append(Object.assign(document.createElement('div'), { className: 'fmb-glow', innerHTML: '<i></i><i></i>' }));
    } else {
      p.style.left = '50%'; p.style.top = '44px'; p.style.translate = '-50% 0';
    }
    const glowHost = sheet ? p : desk;
    const input = p.querySelector('input');
    const list = p.querySelector('.fmb-results');
    let sel = 0; let shown = [];
    // Questions get an "Ask" row that answers from the site's own words (family-ask.js → /api/ask).
    const canAsk = typeof window.familyAsk === 'function';
    const looksLikeQuestion = (q) => /\?$/.test(q) || /^(how|what|why|can|does|do|is|are|will|should|where|when|who|which)\b/i.test(q);
    const answer = document.createElement('div');
    answer.className = 'fmb-answer'; answer.hidden = true;
    answer.innerHTML = '<span class="fmb-orb" aria-hidden="true"></span><div><p class="fmb-answer__text" aria-live="polite"></p><p class="fmb-answer__src" hidden></p></div>';
    p.append(answer);
    let stopAsk = () => {};
    const askNow = (q) => {
      stopAsk();
      list.innerHTML = ''; p.classList.remove('has-results');
      answer.hidden = false; p.classList.add('is-answering');
      const text = answer.querySelector('.fmb-answer__text'); const src = answer.querySelector('.fmb-answer__src');
      text.textContent = ''; src.hidden = true;
      glowHost.classList.add('fmb-thinking');
      stopAsk = window.familyAsk(q, {
        onSources: (list2) => window.familyAskSources?.(src, list2),
        onText: (t) => { text.textContent += t; },
        onDone: () => { glowHost.classList.remove('fmb-thinking'); window.familyLinkify?.(text); },
      });
    };
    const render = () => {
      const raw = input.value.trim();
      const q = raw.toLowerCase();
      answer.hidden = true; p.classList.remove('is-answering'); glowHost.classList.remove('fmb-thinking'); stopAsk();
      const hits = q ? sections.filter((s) => s.find.toLowerCase().includes(q)).slice(0, 5) : [];
      const askRow = canAsk && raw.length >= 2 ? [{ ask: true, text: raw }] : [];
      shown = looksLikeQuestion(raw) || !hits.length ? [...askRow, ...hits] : [...hits, ...askRow];
      sel = Math.min(sel, Math.max(0, shown.length - 1));
      list.innerHTML = '';
      shown.forEach((s, i) => {
        const r = document.createElement('div');
        r.className = 'fmb-result' + (i === sel ? ' is-on' : '') + (s.ask ? ' fmb-result--ask' : '');
        r.innerHTML = s.ask ? '<span class="fmb-orb" aria-hidden="true"></span><span></span>' : `<img src="${icon()}" alt="" width="20" height="20" /><span></span>`;
        r.lastChild.textContent = s.ask ? `Ask “${s.text}”` : s.text;
        r.addEventListener('click', () => (s.ask ? askNow(s.text) : go(s.el)));
        list.append(r);
      });
      p.classList.toggle('has-results', shown.length > 0);
    };
    const go = (el) => { closePanel(); window.familyReveal?.(el); if (el.tagName === 'DETAILS') el.open = true; el.scrollIntoView({ behavior: still() ? 'auto' : 'smooth', block: 'center' }); };
    input.addEventListener('input', () => { sel = 0; render(); });
    input.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowDown') { sel = Math.min(sel + 1, shown.length - 1); render(); e.preventDefault(); }
      if (e.key === 'ArrowUp') { sel = Math.max(sel - 1, 0); render(); e.preventDefault(); }
      if (e.key === 'Enter' && shown[sel]) (shown[sel].ask ? askNow(shown[sel].text) : go(shown[sel].el));
    });
    if (anchor) anchor.classList.add('fmb-on');
    input.focus({ preventScroll: true });
  };

  // Dark Mode for the whole page: flip every prefers-color-scheme rule, the way the system setting would.
  const sysDark = () => matchMedia('(prefers-color-scheme: dark)').matches;
  let forced = null; // null = follow the system, true = dark, false = light
  const originals = new Map();
  const flip = (dark) => {
    forced = dark === sysDark() ? null : dark;
    const walk = (rules) => {
      for (const r of rules) {
        if (r.media && (originals.has(r) || /prefers-color-scheme/.test(r.media.mediaText))) {
          if (!originals.has(r)) originals.set(r, r.media.mediaText);
          let t = originals.get(r);
          if (forced !== null) {
            t = t.replace(/\(\s*prefers-color-scheme:\s*dark\s*\)/g, forced ? '(min-width: 0px)' : '(max-width: 0px)')
                 .replace(/\(\s*prefers-color-scheme:\s*light\s*\)/g, forced ? '(max-width: 0px)' : '(min-width: 0px)');
          }
          r.media.mediaText = t;
        }
        if (r.cssRules) walk(r.cssRules);
      }
    };
    for (const sheet of document.styleSheets) { try { walk(sheet.cssRules); } catch { /* another site's sheet */ } }
    const meta = $('meta[name="color-scheme"]');
    if (meta) meta.content = forced === null ? 'light dark' : forced ? 'dark' : 'light';
    $$('picture source[media*="prefers-color-scheme"]').forEach((s) => {
      if (!s.dataset.media) s.dataset.media = s.media;
      s.media = forced === null ? s.dataset.media : (forced ? 'all' : 'not all');
    });
  };
  const isDark = () => (forced === null ? sysDark() : forced);
  let wifiOn = true; let routinesOn = true; let binkySorted = false; let dropzoneOn = true; let network = 'Home';
  const WIFI = (w = 15) => `<svg viewBox="0 0 680 520" width="${w}" height="${Math.round(w * 0.76)}" aria-hidden="true">${bar.querySelector('[data-mb="wifi"] svg')?.innerHTML || ''}</svg>`;
  const LOCK = '<svg viewBox="0 0 20 20" width="11" height="11" aria-hidden="true"><path d="M10 2.5a3.6 3.6 0 0 1 3.6 3.6V8h.4A1.5 1.5 0 0 1 15.5 9.5v6A1.5 1.5 0 0 1 14 17H6a1.5 1.5 0 0 1-1.5-1.5v-6A1.5 1.5 0 0 1 6 8h.4V6.1A3.6 3.6 0 0 1 10 2.5Zm0 1.7a1.9 1.9 0 0 0-1.9 1.9V8h3.8V6.1A1.9 1.9 0 0 0 10 4.2Z" fill="currentColor"/></svg>';
  const setWifi = (on) => { wifiOn = on; bar.querySelector('[data-mb="wifi"]')?.classList.toggle('fmb-dim', !on); };
  // The Wi-Fi menu, as on Tahoe: a switch, the network you're on, and others nearby.
  const wifiMenu = (anchor) => {
    const others = ['Testament Made', `${app} Guest`, 'Coffee Shop'].filter((n) => n !== network);
    const p = showPanel(`
      <div class="fmb-row fmb-row--head"><b>Wi-Fi</b><button type="button" class="fmb-switch" role="switch" aria-label="Wi-Fi"></button></div>
      <div class="fmb-wifi-body">
        <hr class="fmb-sep" /><p class="fmb-label">Known Network</p>
        <button type="button" class="fmb-net is-joined" data-net="${network}"><i>${WIFI()}</i><span>${network}</span>${LOCK}</button>
        <p class="fmb-label">Other Networks</p>
        ${others.map((n) => `<button type="button" class="fmb-net" data-net="${n}"><i>${WIFI()}</i><span>${n}</span>${n.includes('Guest') || n === 'Coffee Shop' ? '' : LOCK}</button>`).join('')}
      </div>
      <hr class="fmb-sep" /><div class="fmb-item fmb-item--plain"><span>Wi-Fi Settings…</span></div>`, 'fmb-menu fmb-wifi', anchor);
    const sw = p.querySelector('.fmb-switch');
    const sync = () => { sw.setAttribute('aria-checked', String(wifiOn)); sw.classList.toggle('is-on', wifiOn); p.classList.toggle('is-off', !wifiOn); };
    sw.addEventListener('click', () => { setWifi(!wifiOn); sync(); });
    p.querySelectorAll('.fmb-net:not(.is-joined)').forEach((b) => b.addEventListener('click', () => {
      network = b.dataset.net; setWifi(true); closePanel();
      toast(`Joined “${network}”.`);
    }));
    sync();
  };
  // The battery menu. "Using Significant Energy" names a few apps everyone in design and dev jokes about
  // (a different three each time), never ours: they're small and native.
  const HOGS = [['Google Chrome', 'chrome'], ['Figma', 'figma'], ['Slack', 'slack'], ['Xcode', 'xcode'], ['Zoom', 'zoom'], ['Discord', 'discord'], ['Notion', 'notion'],
    ['Arc', 'arc'], ['Cursor', 'cursor'], ['Visual Studio Code', 'vscode'], ['Microsoft Edge', 'edge'], ['Steam', 'steam'], ['OBS', 'obs'], ['Firefox', 'firefox']];
  const battery = 60 + Math.floor(Math.random() * 35);
  const batteryMenu = (anchor) => {
    const hogs = HOGS.slice().sort(() => Math.random() - 0.5).slice(0, 3);
    showPanel(`
      <div class="fmb-row fmb-row--head"><b>Battery</b><span class="fmb-dimtext">${battery}%</span></div>
      <div class="fmb-item fmb-item--plain is-off"><span>Power Source: Battery</span></div>
      <hr class="fmb-sep" /><p class="fmb-label">Using Significant Energy</p>
      ${hogs.map(([n, slug]) => `<div class="fmb-item fmb-item--plain fmb-hog"><img src="/menubar-apps/${slug}.webp" alt="" width="18" height="18" /><span>${n}</span></div>`).join('')}
      <hr class="fmb-sep" /><div class="fmb-item fmb-item--plain"><span>Battery Settings…</span></div>`, 'fmb-menu fmb-batt', anchor);
  };
  // The clock opens Notification Center: what this page has told you, newest first.
  const notifications = (anchor) => {
    const ago = (d) => { const m = Math.round((Date.now() - d) / 60000); return m < 1 ? 'now' : `${m}m ago`; };
    const p = showPanel(history.length
      ? history.slice(0, 5).map((h) => `<div class="fmb-note"><img src="${icon()}" alt="" width="30" height="30" /><span><b>${app}<time>${ago(h.at)}</time></b><small></small></span></div>`).join('')
      : `<p class="fmb-empty">No Notifications</p>`, 'fmb-nc', anchor);
    p.querySelectorAll('.fmb-note small').forEach((el, i) => { el.textContent = history[i].text; });
    p.style.left = 'auto'; p.style.right = '8px';
  };
  // The menu bar icon opens each app's panel (macOS 27 style, the same in all three): a header with what the
  // app is doing and one round button, then rows in groups, a caption over a list of recent things.
  const SYM = { // 18px row symbols, drawn after the SF Symbols the apps use
    open: '<path d="M2.5 5.5A1.5 1.5 0 0 1 4 4h3l1.5 1.5h5.5A1.5 1.5 0 0 1 15.5 7v6a1.5 1.5 0 0 1-1.5 1.5H4A1.5 1.5 0 0 1 2.5 13z"/><path d="M9 8v4.5M6.75 10.25h4.5"/>',
    clipboard: '<rect x="4" y="3.5" width="10" height="12" rx="2"/><path d="M7 2.5h4v2.2H7zM7 9h4M7 12h2.5"/>',
    tray: '<path d="M2.5 10.5V13A1.5 1.5 0 0 0 4 14.5h10a1.5 1.5 0 0 0 1.5-1.5v-2.5h-3.6a2.9 2.9 0 0 1-5.8 0z"/><path d="M9 2.5v6.5M6.4 6.4 9 9l2.6-2.6"/>',
    folder: '<path d="M2.5 5.5A1.5 1.5 0 0 1 4 4h3l1.5 1.5h5.5A1.5 1.5 0 0 1 15.5 7v6a1.5 1.5 0 0 1-1.5 1.5H4A1.5 1.5 0 0 1 2.5 13z"/>',
    review: '<path d="M2.5 5.5A1.5 1.5 0 0 1 4 4h3l1.5 1.5h5.5A1.5 1.5 0 0 1 15.5 7v6a1.5 1.5 0 0 1-1.5 1.5H4A1.5 1.5 0 0 1 2.5 13z"/><path d="M7.6 8.6a1.5 1.5 0 1 1 2.1 1.4c-.5.2-.7.6-.7 1v.2M9 12.9v.1"/>',
    window: '<rect x="2.5" y="3.5" width="13" height="11" rx="2"/><path d="M2.5 6.5h13"/>',
    gear: '<circle cx="9" cy="9" r="2.3"/><path d="M9 2.2v2.1M9 13.7v2.1M2.2 9h2.1M13.7 9h2.1M4.2 4.2l1.5 1.5M12.3 12.3l1.5 1.5M4.2 13.8l1.5-1.5M12.3 5.7l1.5-1.5"/>',
    info: '<circle cx="9" cy="9" r="6.5"/><path d="M9 8.2v4.3M9 5.7v.1"/>',
    power: '<path d="M9 2.5v6"/><path d="M5.3 4.9a5.4 5.4 0 1 0 7.4 0"/>',
    search: '<circle cx="8" cy="8" r="4.6"/><path d="m11.4 11.4 4 4"/>',
    plus: '<path d="M9 3.5v11M3.5 9h11"/>',
    heart: '<path d="M9 15s-6-3.5-6-8a3.2 3.2 0 0 1 6-1.6A3.2 3.2 0 0 1 15 7c0 4.5-6 8-6 8z"/>',
    history: '<circle cx="9.5" cy="9" r="6"/><path d="M9.5 5.8V9l2.3 1.4M2 7.2l1.6 1.9 1.9-1.5"/>',
    lock: '<rect x="4" y="8" width="10" height="7.5" rx="1.8" fill="currentColor" stroke="none"/><path d="M6.2 8V6a2.8 2.8 0 0 1 5.6 0v2"/>',
    unlock: '<rect x="4" y="8" width="10" height="7.5" rx="1.8" fill="currentColor" stroke="none"/><path d="M6.2 8V6a2.8 2.8 0 0 1 5.4-1"/>',
    pause: '<path d="M6.5 4.5v9M11.5 4.5v9" stroke-width="2.6"/>',
    play: '<path d="M6 4.2v9.6L14 9z" fill="currentColor" stroke="none"/>',
  };
  const sym = (n) => `<svg viewBox="0 0 18 18" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${SYM[n] || ''}</svg>`;
  const CHECK = '<svg viewBox="0 0 12 12" width="11" height="11" aria-hidden="true"><path d="m2.2 6.4 2.4 2.4 5.2-5.6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  const FILE = { img: '#4aa3df', doc: '#e5484d', vid: '#8e5cf0' };
  const fileGlyph = (k) => `<svg viewBox="0 0 22 26" width="18" height="22" aria-hidden="true"><path d="M2.5 1h11.5l5.5 5.5v17a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 1 23.5v-21A1.5 1.5 0 0 1 2.5 1z" fill="#fff" stroke="#c8c8cc"/><rect x="4" y="13" width="14" height="8" rx="1.5" fill="${FILE[k] || FILE.img}"/></svg>`;
  const SERVICE = { STRIPE: ['#635bff', 'S'], GITHUB: ['#24292f', 'G'], OPENAI: ['#10a37f', 'O'] };
  const extraPanel = (anchor) => {
    const spec = menuFor.extra;
    const val = (v) => (typeof v === 'function' ? v() : v);
    const p = showPanel('', 'fmb-menu fmb-xp', anchor);
    const render = () => {
      const [status, live] = spec.status();
      const btn = spec.button ? `<button type="button" class="fmb-xp__btn" aria-label="${val(spec.button.label)}" title="${val(spec.button.label)}">${sym(spec.button.icon === 'lock' && $('[data-mb-window].is-locked') ? 'lock' : spec.button.icon === 'lock' ? 'unlock' : val(spec.button.icon))}</button>` : '';
      const row = ([label, keys = '', action = null, ic = '', extra = '']) => {
        const on = action === 'watch' ? routinesOn : action === 'dropzone' ? dropzoneOn : true;
        const tail = extra === 'check' ? `<kbd>${on ? CHECK : ''}</kbd>` : `<kbd>${keys}</kbd>`;
        return `<div class="fmb-item fmb-xp__row" data-act="${action || ''}"><i>${sym(ic)}</i><span></span>${tail}</div>`;
      };
      const recent = (r) => r.key
        ? `<div class="fmb-item fmb-xp__row fmb-xp__recent" data-copy="${r.key}"><i class="fmb-xp__svc" style="background:${(SERVICE[r.key.split('_')[0]] || ['#8a8a8e'])[0]}">${(SERVICE[r.key.split('_')[0]] || ['', '•'])[1]}</i><code></code><kbd>${r.note}</kbd></div>`
        : `<div class="fmb-item fmb-xp__row fmb-xp__recent"><i class="fmb-xp__file">${fileGlyph(r.file)}</i><span></span><kbd class="fmb-xp__note">${r.note}</kbd></div>`;
      p.innerHTML = `
        <div class="fmb-xp__head"><img src="${icon()}" alt="" width="30" height="30" /><span><b>${app}</b><small><i class="fmb-xp__dot${live ? ' is-live' : ''}"></i>${status}</small></span>${btn}</div>
        ${spec.groups.map((g) => `<hr class="fmb-sep" /><div class="fmb-xp__group">${typeof g[0] === 'string'
          ? `<p class="fmb-label">${g[0]}</p>${g.slice(1).map(recent).join('')}`
          : g.map(row).join('')}</div>`).join('')}`;
      // Labels go in as text.
      const rows = spec.groups.flatMap((g) => (typeof g[0] === 'string' ? g.slice(1).map((r) => r.key || r.name) : g.map((r) => r[0])));
      p.querySelectorAll('.fmb-xp__row').forEach((el, i) => { (el.querySelector('span') || el.querySelector('code')).textContent = rows[i]; });
      p.querySelector('.fmb-xp__btn')?.addEventListener('click', () => press(spec.button.action));
      p.querySelectorAll('.fmb-xp__row[data-act]').forEach((el) => el.addEventListener('click', () => press(el.dataset.act)));
      p.querySelectorAll('[data-copy]').forEach((el) => el.addEventListener('click', () => { closePanel(); toast(`Copied ${el.dataset.copy}. It clears from the clipboard in 30 seconds.`); }));
      p.querySelectorAll('.fmb-xp__recent:not([data-copy])').forEach((el) => el.addEventListener('click', closePanel));
    };
    const press = (action) => {
      if (action === 'watch') { routinesOn = !routinesOn; return render(); }
      if (action === 'dropzone') { dropzoneOn = !dropzoneOn; render(); return toast(dropzoneOn ? 'The floating dropzone pops up in a corner whenever you drag files.' : 'Floating dropzone off.'); }
      closePanel();
      if (action === 'review') return toast('91 files want a second look in Review.');
      run(action || null);
    };
    render();
  };
  // Each app's own Control Center tile: [title, icon, subtitle(), press()].
  const appTile = {
    Slinky: () => {
      const locked = () => !!$('[data-mb-window].is-locked');
      return ['Lock Slinky', '<svg viewBox="0 0 20 20" width="15" height="15" aria-hidden="true"><path d="M10 2a4.2 4.2 0 0 1 4.2 4.2V8h.6A1.7 1.7 0 0 1 16.5 9.7v6.6a1.7 1.7 0 0 1-1.7 1.7H5.2a1.7 1.7 0 0 1-1.7-1.7V9.7A1.7 1.7 0 0 1 5.2 8h.6V6.2A4.2 4.2 0 0 1 10 2Zm0 1.8a2.4 2.4 0 0 0-2.4 2.4V8h4.8V6.2A2.4 2.4 0 0 0 10 3.8Z" fill="currentColor"/></svg>',
        () => (locked() ? 'Locked' : 'Unlocked'), locked, () => { if (!locked()) emit('lock'); }];
    },
    Dinky: () => ['Clipboard Compress', '<svg viewBox="0 0 20 20" width="15" height="15" aria-hidden="true"><rect x="4" y="3.5" width="12" height="14" rx="2.4" fill="none" stroke="currentColor" stroke-width="1.6"/><rect x="7" y="2" width="6" height="3.4" rx="1.2" fill="currentColor"/><path d="M10 8v6m-2.6-2.6L10 14l2.6-2.6" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
      () => '⇧⌘V', () => false, () => { closePanel(); toast('Compressed the clipboard image: 1.4 MB → 212 KB.'); }],
    Binky: () => ['Routines', '<svg viewBox="0 0 20 20" width="15" height="15" aria-hidden="true"><path d="M3 6.5a1.5 1.5 0 0 1 1.5-1.5h3.6l1.5 1.6h5.9A1.5 1.5 0 0 1 17 8.1v6.4a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 3 14.5z" fill="currentColor"/></svg>',
      () => (routinesOn ? 'Watching 2 folders' : 'Paused'), () => routinesOn, () => { routinesOn = !routinesOn; }],
  };
  const control = (anchor) => {
    const [tTitle, tIcon, tSub, tOn, tPress] = (appTile[app] || appTile.Slinky)();
    const dmg = $('a[href$=".dmg"]')?.getAttribute('href') || $('a[data-download]')?.getAttribute('href') || '#';
    const family = $$('.dock__app').map((a) => ({ href: a.getAttribute('href'), img: a.querySelector('img')?.getAttribute('src'), name: a.querySelector('.dock__name')?.textContent || '', on: a.classList.contains('is-current') }));
    const p = showPanel(`
      <div class="fmb-cc">
        <button type="button" class="fmb-tile" data-t="wifi"><i>${bar.querySelector('[data-mb="wifi"] svg')?.outerHTML || ''}</i><span><b>Wi-Fi</b><small></small></span></button>
        <button type="button" class="fmb-tile" data-t="dark"><i><svg viewBox="0 0 20 20" width="16" height="16" aria-hidden="true"><circle cx="10" cy="10" r="7" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M10 3a7 7 0 0 1 0 14z" fill="currentColor"/></svg></i><span><b>Dark Mode</b><small></small></span></button>
        <button type="button" class="fmb-tile fmb-tile--wide" data-t="app"><i>${tIcon}</i><span><b>${tTitle}</b><small></small></span></button>
        <button type="button" class="fmb-tile fmb-tile--sq" data-t="still"><i><svg viewBox="0 0 20 20" width="16" height="16" aria-hidden="true"><circle cx="10" cy="10" r="7" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M8 7v6M12 7v6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg></i><span><b>Reduce Motion</b><small></small></span></button>
        <a class="fmb-tile fmb-tile--sq" data-t="get" href="${dmg}"><i><svg viewBox="0 0 20 20" width="16" height="16" aria-hidden="true"><path d="M10 3v9.5m-4-4 4 4 4-4M4 15.5h12" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg></i><span><b>Download</b><small>${app}${version() ? ' ' + version() : ''}</small></span></a>
        <div class="fmb-family">
          <a class="fmb-family__head" href="https://testamentmade.com" target="_blank" rel="noopener">Testament Made</a>
          <div class="fmb-family__apps">${family.map((f) => `<a href="${f.href}"${f.on ? ' class="is-on" aria-current="page"' : ''}><img src="${f.img}" alt="" width="36" height="36" /><span>${f.name}</span></a>`).join('')}</div>
        </div>
      </div>`, 'fmb-ccp', anchor);
    p.style.left = 'auto'; p.style.right = '8px';
    const sync = () => {
      const w = p.querySelector('[data-t="wifi"]'); w.classList.toggle('is-on', wifiOn); w.querySelector('small').textContent = wifiOn ? network : 'Off';
      const d = p.querySelector('[data-t="dark"]'); d.classList.toggle('is-on', isDark()); d.querySelector('small').textContent = isDark() ? 'On' : 'Off';
      const t = p.querySelector('[data-t="app"]'); t.classList.toggle('is-on', !!tOn()); t.querySelector('small').textContent = tSub();
      const m = p.querySelector('[data-t="still"]'); m.classList.toggle('is-on', still()); m.querySelector('small').textContent = still() ? 'On' : 'Off';
    };
    p.querySelector('[data-t="wifi"]').addEventListener('click', () => { setWifi(!wifiOn); sync(); });
    p.querySelector('[data-t="dark"]').addEventListener('click', () => { flip(!isDark()); sync(); });
    p.querySelector('[data-t="app"]').addEventListener('click', () => { tPress(); if (panel === p) setTimeout(sync, 60); });
    p.querySelector('[data-t="still"]').addEventListener('click', () => {
      // Turns off the page's animations and the demos' auto-advance (it can't turn off the system setting).
      if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;
      document.documentElement.classList.toggle('fmb-still');
      document.dispatchEvent(new CustomEvent('menubar:motion'));
      sync();
    });
    sync();
  };

  // ---------- Window: minimize into the Dock, hide, full screen, sleep ----------
  const win = () => $('[data-mb-window]', desk);
  let away = false;
  const minimize = (fade) => {
    const w = win(); if (!w || away) return;
    const dockIcon = $('.dock__app.is-current');
    const a = w.getBoundingClientRect(); const b = dockIcon ? dockIcon.getBoundingClientRect() : { left: a.left + a.width / 2, top: innerHeight, width: 0, height: 0 };
    const dx = b.left + b.width / 2 - (a.left + a.width / 2); const dy = b.top + b.height / 2 - (a.top + a.height / 2);
    away = true;
    if (still() || fade) { w.style.visibility = 'hidden'; return; }
    w.animate([{ transform: 'none', opacity: 1 }, { transform: `translate(${dx * 0.5}px, ${dy * 0.35}px) scale(0.5, 0.3)`, opacity: 0.8, offset: 0.55 }, { transform: `translate(${dx}px, ${dy}px) scale(0.04)`, opacity: 0 }],
      { duration: 560, easing: 'cubic-bezier(.5,0,.75,0)' }).finished.then(() => { w.style.visibility = 'hidden'; });
  };
  const restore = () => {
    const w = win(); if (!w || !away) return;
    away = false;
    w.style.visibility = '';
    if (!still()) w.animate([{ transform: 'translateY(30px) scale(0.92)', opacity: 0 }, { transform: 'none', opacity: 1 }], { duration: 420, easing: 'cubic-bezier(.22,1,.36,1)' });
    const d = $('.dock__app.is-current');
    if (d && !still()) { d.classList.remove('is-launching'); void d.offsetWidth; d.classList.add('is-launching'); setTimeout(() => d.classList.remove('is-launching'), 900); }
  };
  // While the window is in the Dock, the app's own Dock icon brings it back.
  $('.dock__app.is-current')?.addEventListener('click', (e) => { if (away) { e.preventDefault(); restore(); desk.scrollIntoView({ behavior: still() ? 'auto' : 'smooth', block: 'center' }); } });
  const sleepNow = () => {
    close(); closePanel();
    const veil = document.createElement('div');
    veil.className = 'fmb-sleep';
    desk.append(veil);
    requestAnimationFrame(() => veil.classList.add('is-on'));
    emit('lock');
    const wake = () => { veil.classList.remove('is-on'); setTimeout(() => veil.remove(), 500); };
    veil.addEventListener('click', wake);
  };
  const history = [];
  const toast = (text) => {
    history.unshift({ text, at: new Date() });
    const t = document.createElement('div');
    t.className = 'fmb-toast';
    t.innerHTML = `<img src="${icon()}" alt="" width="34" height="34" /><span><b>${app}<time>now</time></b><small></small></span>`;
    t.querySelector('small').textContent = text;
    desk.append(t);
    requestAnimationFrame(() => t.classList.add('is-on'));
    setTimeout(() => { t.classList.remove('is-on'); setTimeout(() => t.remove(), 500); }, 3600);
  };

  // ---------- Actions ----------
  function run(action) {
    switch (action) {
      case null: case undefined: return;
      case 'about': return about();
      case 'aboutMac': return aboutMac();
      case 'upToDate': return toast(`${app} ${version()} is the newest version.`);
      case 'sleep': return sleepNow();
      case 'spotlight': return spotlight(bar.querySelector('[data-mb="spotlight"]'));
      case 'minimize': return minimize(false);
      case 'hide': return minimize(true);
      case 'restore': return restore();
      case 'fullscreen': return document.fullscreenElement ? document.exitFullscreen() : desk.requestFullscreen?.().catch(() => {});
      case 'clipboard': return toast('Compressed the clipboard image: 1.4 MB → 212 KB.');
      case 'help': return ($('#faq') || $('footer'))?.scrollIntoView({ behavior: still() ? 'auto' : 'smooth', block: 'start' });
      default: return emit(action);
    }
  }

  // ---------- Wiring ----------
  bar.addEventListener('click', (e) => {
    const item = e.target.closest('[data-mb]');
    if (!item) return;
    e.stopPropagation();
    const key = item.dataset.mb;
    if (open?.key === key || (panel && item.classList.contains('fmb-on'))) { close(); closePanel(); return; }
    closePanel();
    if (key === 'spotlight') return spotlight(item);
    if (key === 'cc') return control(item);
    if (key === 'wifi') return wifiMenu(item);
    if (key === 'battery') return batteryMenu(item);
    if (key === 'clock') return notifications(item);
    openMenu(key, item);
  });
  // Like the Mac: once a menu is open, moving across the bar opens the others.
  bar.addEventListener('pointerover', (e) => {
    if (e.pointerType !== 'mouse') return; // a finger taps titles; it shouldn't switch menus on the way
    const item = e.target.closest('[data-mb]');
    if (open && item && menuFor[item.dataset.mb] && open.key !== item.dataset.mb) openMenu(item.dataset.mb, item);
  });
  document.addEventListener('click', () => { close(); closePanel(); });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') { close(); closePanel(); } });
  addEventListener('resize', close);
  bar.classList.add('fmb-live');
  // The thinking glow around the desktop's edge (shown while Spotlight answers).
  desk.append(Object.assign(document.createElement('div'), { className: 'fmb-glow', innerHTML: '<i></i><i></i>' }));

  // ---------- Each app's own surprise ----------
  if (app === 'Dinky') {
    // Drop any picture on the page onto Dinky's menu bar icon and it gets dinky.
    const target = bar.querySelector('[data-mb="extra"]');
    let dragged = null;
    document.addEventListener('dragstart', (e) => { if (e.target instanceof HTMLImageElement) dragged = e.target; });
    document.addEventListener('dragend', () => { dragged = null; target?.classList.remove('fmb-drop'); });
    target?.addEventListener('dragover', (e) => { if (dragged) { e.preventDefault(); target.classList.add('fmb-drop'); } });
    target?.addEventListener('dragleave', () => target.classList.remove('fmb-drop'));
    target?.addEventListener('drop', (e) => {
      e.preventDefault(); target.classList.remove('fmb-drop');
      const img = dragged; if (!img) return;
      const before = Math.max(48, Math.round((img.naturalWidth * img.naturalHeight * 3) / 1024 / 6));
      const saved = 0.62 + ((img.naturalWidth % 17) / 100);
      const after = Math.max(6, Math.round(before * (1 - saved)));
      if (!still()) img.animate([{ transform: 'scale(1)' }, { transform: 'scale(0.82)' }, { transform: 'scale(0.9)' }], { duration: 700, easing: 'cubic-bezier(.22,1,.36,1)', fill: 'forwards' });
      const name = (img.getAttribute('src') || 'image').split('/').pop().split('?')[0];
      toast(`${name}: ${before} KB → ${after} KB. ${Math.round(saved * 100)}% smaller.`);
    });
    document.addEventListener('menubar:action', (e) => {
      if (e.detail.action !== 'wave' || !target) return;
      if (!still()) target.animate([{ rotate: '0deg' }, { rotate: '-18deg' }, { rotate: '14deg' }, { rotate: '-12deg' }, { rotate: '8deg' }, { rotate: '0deg' }], { duration: 1100, easing: 'ease-in-out' });
      toast('Bye for now. Drop a picture on this hand to shrink it.');
    });
  }
  if (app === 'Binky') {
    // A few loose files on the hero desktop; Sort Now tucks them into folders.
    const files = [['IMG_2041.HEIC', 'img', 0], ['Invoice-0423.pdf', 'doc', 1], ['design-assets.zip', 'zip', 2], ['Screenshot 2026-10-17.png', 'img', 0], ['contract-final.pdf', 'doc', 1]];
    const folders = ['Images', 'Documents', 'Archives'];
    const layer = document.createElement('div');
    layer.className = 'fmb-files';
    layer.setAttribute('aria-hidden', 'true');
    const fileIcon = (k) => k === 'img' ? '<svg viewBox="0 0 32 40" width="30" height="38"><path d="M3 1h18l8 8v28a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V3a2 2 0 0 1 2-2z" fill="#fff" stroke="#c8c8cc"/><rect x="5" y="14" width="22" height="16" rx="2" fill="#7cc4f2"/><path d="M5 30l7-8 5 5 4-3 6 6z" fill="#3f9b5f"/></svg>'
      : k === 'doc' ? '<svg viewBox="0 0 32 40" width="30" height="38"><path d="M3 1h18l8 8v28a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V3a2 2 0 0 1 2-2z" fill="#fff" stroke="#c8c8cc"/><rect x="6" y="26" width="20" height="8" rx="1.5" fill="#e5484d"/><path d="M7 14h18M7 18h18M7 22h12" stroke="#c8c8cc" stroke-width="1.6"/></svg>'
      : '<svg viewBox="0 0 32 40" width="30" height="38"><path d="M3 1h18l8 8v28a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V3a2 2 0 0 1 2-2z" fill="#fff" stroke="#c8c8cc"/><path d="M15 3v24" stroke="#8a8a8e" stroke-width="3" stroke-dasharray="2 2"/><rect x="12" y="26" width="6" height="7" rx="1.5" fill="#8a8a8e"/></svg>';
    const folderIcon = '<svg viewBox="0 0 44 36" width="44" height="36"><path d="M2 6a3 3 0 0 1 3-3h11l4 4h19a3 3 0 0 1 3 3v21a3 3 0 0 1-3 3H5a3 3 0 0 1-3-3z" fill="#5ab2ee"/><path d="M2 12h40v19a3 3 0 0 1-3 3H5a3 3 0 0 1-3-3z" fill="#7dc6f6"/></svg>';
    layer.innerHTML = files.map(([n, k], i) => `<div class="fmb-file" style="--i:${i}">${fileIcon(k)}<span>${n}</span></div>`).join('')
      + folders.map((n, i) => `<div class="fmb-folder" style="--i:${i}">${folderIcon}<span>${n}</span></div>`).join('');
    desk.append(layer);
    let sorted = false;
    const sort = async () => {
      if (sorted) { toast('Nothing new to sort. The desktop is tidy.'); return; }
      sorted = true; binkySorted = true;
      layer.classList.add('is-sorting');
      const fileEls = $$('.fmb-file', layer); const folderEls = $$('.fmb-folder', layer);
      for (let i = 0; i < fileEls.length; i++) {
        const f = fileEls[i]; const to = folderEls[files[i][2]];
        const a = f.getBoundingClientRect(); const b = to.getBoundingClientRect();
        const dx = b.left + b.width / 2 - (a.left + a.width / 2); const dy = b.top + b.height / 2 - (a.top + a.height / 2);
        if (still()) { f.style.opacity = '0'; continue; }
        await f.animate([{ transform: 'none', opacity: 1 }, { transform: `translate(${dx * 0.5}px, ${dy * 0.5 - 40}px) scale(0.8)`, opacity: 1 }, { transform: `translate(${dx}px, ${dy}px) scale(0.3)`, opacity: 0 }],
          { duration: 620, easing: 'cubic-bezier(.4,0,.2,1)', fill: 'forwards' }).finished;
        to.animate([{ transform: 'scale(1)' }, { transform: 'scale(1.12)' }, { transform: 'scale(1)' }], { duration: 260 });
      }
      toast('Sorted 5 files: 2 into Images, 2 into Documents, 1 into Archives.');
    };
    document.addEventListener('menubar:action', (e) => { if (e.detail.action === 'sort') sort(); });
  }
})();
