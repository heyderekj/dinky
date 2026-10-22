// Dinky's recreated windows: fit each one to its desktop, and the small demos (drop zone, format picker,
// right-click menu, before/after slider). Every file and size is made up. Honors Reduced Motion.
(() => {
  const still = () => document.documentElement.classList.contains('fmb-still') || matchMedia('(prefers-reduced-motion: reduce)').matches;
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
  const mb = (n) => n.toFixed(2) + ' MB';
  // requestAnimationFrame pauses in background tabs; fall back to timers so a demo never stalls half way
  const frame = (fn) => (document.hidden ? setTimeout(() => fn(performance.now()), 50) : requestAnimationFrame(fn));

  /* ---------- Fit: the app's windows are drawn at 1:1 points, then zoomed down to fit their desktop ----------
     On a phone the main windows (440–460pt) switch to a narrower 360pt layout, like a narrow window, so they
     need less zoom and their text stays readable. Windows with their own compact layout set data-cw. */
  const fits = $$('.dk-fit > [data-w]');
  function fit() {
    for (const win of fits) {
      const avail = win.parentElement.clientWidth;
      const full = Number(win.dataset.w);
      const compact = Number(win.dataset.cw || (full <= 460 ? 360 : 0));
      const useCompact = compact && avail < full * 0.78;
      const w = useCompact ? compact : full;
      win.classList.toggle('is-compact', !!useCompact);
      $$('.dk-prefs', win).concat(win.classList.contains('dk-prefs') ? [win] : []).forEach((p) => p.classList.toggle('is-compact', !!useCompact));
      win.style.setProperty('--w', w + 'px');
      win.style.zoom = String(Math.min(1, avail / w));
    }
  }
  fit();
  if ('ResizeObserver' in window) {
    const ro = new ResizeObserver(() => fit());
    fits.forEach((w) => ro.observe(w.parentElement));
  } else addEventListener('resize', fit);

  function onVisible(el, fn, threshold = 0.45) {
    if (!('IntersectionObserver' in window)) { fn(); return; }
    const io = new IntersectionObserver((es) => { if (es.some((e) => e.isIntersecting)) { io.disconnect(); fn(); } }, { threshold });
    io.observe(el);
  }

  /* A demo inside a guided row's scene plays each time its scene opens, and on first view only if
     its scene is the open one. Outside a scene it plays once, when it scrolls into view. */
  function whenShown(el, fn, threshold = 0.45) {
    const scene = el.closest('[data-scene]');
    if (!scene) { onVisible(el, fn, threshold); return; }
    scene.addEventListener('scene:show', () => fn());
    onVisible(el, () => { if (scene.classList.contains('is-on')) fn(); }, threshold);
  }

  /* ---------- Guided feature rows: steps on one side, a scene per step on the desktop ----------
     Advances every 6.5s while the row is at least 45% in view and the mouse isn't over it. It never
     changes step while someone is scrolling or touching the page, and stops for good once someone taps
     a step. No auto-advance with Reduced Motion. Opening a step fires scene:show on its scene. */
  let lastScroll = 0, touching = false;
  addEventListener('scroll', () => { lastScroll = performance.now(); }, { passive: true });
  addEventListener('touchstart', () => { touching = true; }, { passive: true, capture: true });
  addEventListener('touchend', () => { touching = false; lastScroll = performance.now(); }, { passive: true, capture: true });
  addEventListener('touchcancel', () => { touching = false; }, { passive: true, capture: true });
  const canHover = matchMedia('(hover: hover)');
  for (const row of $$('[data-guided]')) {
    const DUR = 6500;
    const steps = $$('[data-step]', row);
    const scenes = $$('[data-scene]', row);
    const list = steps[0].parentElement;
    let at = 0, timer = 0, inView = false, hovering = false, chosen = false, tapped = false;
    row.style.setProperty('--g-dur', DUR + 'ms');
    const schedule = () => {
      clearTimeout(timer);
      const playing = inView && !hovering && !chosen && !still();
      row.classList.toggle('is-playing', playing);
      if (playing) timer = setTimeout(advance, DUR);
    };
    const advance = () => {
      // Someone is reading or scrolling: hold this step until they settle.
      if (touching || performance.now() - lastScroll < 1200) { timer = setTimeout(advance, 600); return; }
      open((at + 1) % steps.length);
    };
    /* Stacked (phones and tablets), the steps sit above the desktop. Reserve the height of the tallest
       open step so changing step never moves the desktop or the rest of the page. */
    let lastWidth = 0;
    const reserve = () => {
      if (list.offsetWidth === lastWidth) return;
      lastWidth = list.offsetWidth;
      list.style.minHeight = '';
      if (!matchMedia('(max-width: 900px)').matches) return;
      const text = (s) => $('.g-step__text', s);
      const gap = parseFloat(getComputedStyle(list).rowGap) || 0;
      const closed = steps.reduce((sum, s) => sum + s.offsetHeight - text(s).offsetHeight, 0) + gap * (steps.length - 1);
      const tallest = Math.max(...steps.map((s) => text(s).scrollHeight + (s.classList.contains('is-on') ? 0 : 6)));
      list.style.minHeight = Math.ceil(closed + tallest) + 'px';
    };
    reserve();
    document.fonts?.ready.then(() => { lastWidth = 0; reserve(); });
    if ('ResizeObserver' in window) new ResizeObserver(reserve).observe(list);
    const open = (n, focus = false) => {
      at = n;
      steps.forEach((s, k) => {
        const on = k === n;
        s.classList.toggle('is-on', on);
        s.setAttribute('aria-selected', String(on));
        s.tabIndex = on ? 0 : -1;
        // Restart the progress line
        const bar = $('.g-step__bar', s);
        if (bar) { bar.style.animation = 'none'; void bar.offsetWidth; bar.style.animation = ''; }
      });
      scenes.forEach((sc, k) => {
        const on = k === n;
        sc.classList.toggle('is-on', on);
        sc.hidden = !on;
        if (on) sc.dispatchEvent(new CustomEvent('scene:show'));
      });
      if (focus) steps[n].focus();
      schedule();
    };
    steps.forEach((s, k) => {
      s.addEventListener('pointerdown', (e) => { tapped = e.pointerType !== 'mouse'; });
      s.addEventListener('click', () => { if (tapped) chosen = true; tapped = false; open(k); });
      s.addEventListener('keydown', (e) => {
        const d = e.key === 'ArrowDown' || e.key === 'ArrowRight' ? 1 : e.key === 'ArrowUp' || e.key === 'ArrowLeft' ? -1 : 0;
        if (!d) return;
        e.preventDefault();
        open((at + d + steps.length) % steps.length, true);
      });
    });
    // Hovering the row with a mouse holds the current step, so it doesn't change while someone reads or tries the demo.
    row.addEventListener('pointerenter', (e) => { if (e.pointerType === 'mouse') { hovering = true; schedule(); } });
    row.addEventListener('pointerleave', (e) => { if (e.pointerType === 'mouse') { hovering = false; schedule(); } });
    if ('IntersectionObserver' in window) {
      new IntersectionObserver(([e]) => { inView = e.isIntersecting; hovering = canHover.matches && row.matches(':hover'); schedule(); }, { threshold: 0.45 }).observe(row);
    }
  }

  /* Progress a row from 0 to 100% over ms, then mark it done. */
  function runRow(row, ms, alive = () => true) {
    return new Promise((resolve) => {
      const pct = $('.dk-prog__pct', row);
      row.dataset.state = 'working';
      if (still()) ms = Math.min(ms, 900);
      const t0 = performance.now();
      const step = (t) => {
        if (!alive()) { resolve(); return; }
        const p = Math.min(1, (t - t0) / ms);
        const eased = 1 - Math.pow(1 - p, 1.6);
        row.style.setProperty('--p', eased.toFixed(3));
        if (pct) pct.textContent = Math.floor(eased * 100) + '%';
        if (p < 1) frame(step);
        else { row.dataset.state = 'done'; resolve(); }
      };
      frame(step);
    });
  }

  /* ---------- 1. Drop zone: drag in → Release to compress → progress → done ---------- */
  const demo = $('[data-drop-demo]');
  if (demo) {
    const drag = $('[data-drag]', demo);
    const rows = $$('.dk-row', demo);
    const replay = $('[data-drop-replay]');
    const live = $('[data-drop-live]');
    let run = 0;
    const say = (t) => { if (live) live.textContent = t; };

    async function play() {
      const me = ++run;
      const alive = () => me === run;
      replay.hidden = false;
      replay.setAttribute('data-busy', '');
      rows.forEach((r) => { r.dataset.state = 'working'; r.classList.remove('is-in'); r.style.setProperty('--p', 0); $('.dk-prog__pct', r).textContent = '0%'; });
      // At rest, with the files waiting outside the window
      drag.style.transition = 'none';
      drag.classList.remove('is-dropped');
      drag.classList.add('is-away');
      demo.dataset.state = 'idle';
      void drag.offsetWidth;
      drag.style.transition = '';
      await wait(still() ? 300 : 700); if (!alive()) return;
      // Drag in: the drop zone lights up as soon as the files cross the window
      drag.classList.remove('is-away');
      await wait(still() ? 0 : 380); if (!alive()) return;
      demo.dataset.state = 'hover';
      say('Release to compress');
      await wait(still() ? 1400 : 1600); if (!alive()) return;
      // Release
      drag.classList.add('is-dropped');
      await wait(still() ? 0 : 260); if (!alive()) return;
      demo.dataset.state = 'working';
      say('Working through the pile.');
      rows.forEach((r, i) => { r.style.animationDelay = i * 70 + 'ms'; r.classList.add('is-in'); });
      await Promise.all(rows.map((r) => runRow(r, Number(r.dataset.dur))));
      if (!alive()) return;
      demo.dataset.state = 'done';
      say('Done. Look how little they are now.');
      replay.removeAttribute('data-busy');
    }

    replay.addEventListener('click', play);
    whenShown(demo, () => play());
  }

  /* ---------- Scenes with a list that compresses when shown (clipboard, kinds, watch folder, kept file) ---------- */
  for (const win of $$('[data-batch]')) {
    const rows = $$('.dk-row[data-dur]', win);
    const limit = Number(win.dataset.limit) || 3;
    let run = 0;
    async function play() {
      const me = ++run;
      rows.forEach((r) => { r.dataset.state = 'queued'; r.style.setProperty('--p', 0); const pct = $('.dk-prog__pct', r); if (pct) pct.textContent = '0%'; });
      win.dataset.state = 'working';
      await wait(still() ? 0 : 500); if (me !== run) return;
      let next = 0;
      const worker = async () => {
        while (next < rows.length && me === run) { const r = rows[next++]; await runRow(r, Number(r.dataset.dur), () => me === run); }
      };
      await Promise.all(Array.from({ length: Math.min(limit, rows.length) }, worker));
      if (me === run) win.dataset.state = 'done';
    }
    whenShown(win, play);
  }

  /* ---------- 2. Sidebar format picker: real radio chips ---------- */
  for (const group of $$('[data-format-picker]')) {
    const chips = $$('[role="radio"]', group);
    const desc = group.parentElement.querySelector('[data-format-desc]');
    const pick = (chip, focus) => {
      chips.forEach((c) => { const on = c === chip; c.setAttribute('aria-checked', on); c.tabIndex = on ? 0 : -1; });
      if (desc) desc.textContent = chip.dataset.desc;
      if (focus) chip.focus();
    };
    chips.forEach((c, i) => {
      c.addEventListener('click', () => pick(c, false));
      c.addEventListener('keydown', (e) => {
        const d = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[e.key];
        if (d) { e.preventDefault(); pick(chips[(i + d + chips.length) % chips.length], true); }
        else if (e.key === 'Home') { e.preventDefault(); pick(chips[0], true); }
        else if (e.key === 'End') { e.preventDefault(); pick(chips[chips.length - 1], true); }
      });
    });
  }

  /* ---------- 5. Results: right-click (or click) a queued row for its menu ---------- */
  const results = $('[data-results]');
  if (results) {
    const menu = $('[data-menu-el]', results);
    const body = $('.dk-body', results);
    const live = $('[data-results-live]', results.parentElement);
    const announce = (t) => { if (live) live.textContent = t; };
    let owner = null;

    const items = (m) => $$(':scope > [role="menuitem"]', m);
    function closeSubs() { $$('.dk-menu .dk-menu', menu).forEach((s) => { s.hidden = true; }); $$('[data-sub]', menu).forEach((b) => b.setAttribute('aria-expanded', 'false')); }
    function close(focusOwner) {
      if (menu.hidden) return;
      menu.hidden = true;
      if (owner) { owner.setAttribute('aria-expanded', 'false'); if (focusOwner) owner.focus(); }
      owner = null;
    }
    function open(row, x, y, focusFirst) {
      owner && owner.setAttribute('aria-expanded', 'false');
      owner = row;
      menu.innerHTML = $(`template[data-menu="${row.dataset.kind}"]`, results).innerHTML;
      menu.setAttribute('aria-label', $('.dk-row__name', row).textContent);
      menu.hidden = false;
      row.setAttribute('aria-expanded', 'true');
      const zoom = parseFloat(getComputedStyle(results).zoom) || 1;
      const b = body.getBoundingClientRect();
      // Coordinates arrive in screen pixels; the window may be zoomed, so convert back to its own points.
      let left = (x - b.left) / zoom, top = (y - b.top) / zoom;
      const bw = body.clientWidth, bh = body.clientHeight;
      left = Math.max(6, Math.min(left, bw - menu.offsetWidth - (row.dataset.kind === 'video' ? 130 : 6)));
      top = Math.max(4, Math.min(top, bh - menu.offsetHeight - 4));
      menu.style.left = left + 'px';
      menu.style.top = top + 'px';
      if (focusFirst) items(menu)[0].focus();
    }
    function rowAt(row) {
      const r = row.getBoundingClientRect();
      return [r.left + r.width * 0.42, r.top + r.height * 0.72];
    }
    async function compress(row, fmt) {
      const out = $('[data-out]', row);
      out.textContent = mb(Number(row.dataset.size) * Number(row.dataset.factor) * ({ AVIF: 0.75, PNG: 2.9, HEIC: 1.15, JPEG: 1.4, Low: 0.7, High: 1.45 }[fmt.split(' · ').pop()] || 1));
      row.removeAttribute('tabindex');
      row.removeAttribute('role');
      row.removeAttribute('aria-haspopup');
      row.removeAttribute('aria-expanded');
      row.classList.remove('dk-row--menu');
      row.removeAttribute('aria-label');
      row.setAttribute('aria-hidden', 'true');
      const name = $('.dk-row__name', row).textContent;
      announce(`Compressing ${name} as ${fmt}.`);
      await runRow(row, 1800 + Math.random() * 800);
      announce(`${name} done: ${mb(Number(row.dataset.size))} to ${out.textContent}.`);
    }

    for (const row of $$('.dk-row--menu', results)) {
      row.addEventListener('contextmenu', (e) => { if (!row.classList.contains('dk-row--menu')) return; e.preventDefault(); open(row, e.clientX, e.clientY, false); });
      row.addEventListener('click', (e) => { if (!row.classList.contains('dk-row--menu')) return; if (owner === row && !menu.hidden) { close(); return; } open(row, e.clientX || rowAt(row)[0], e.clientY || rowAt(row)[1], e.detail === 0); });
      row.addEventListener('keydown', (e) => {
        if (!row.classList.contains('dk-row--menu')) return;
        if (e.key === 'Enter' || e.key === ' ' || e.key === 'ContextMenu' || (e.shiftKey && e.key === 'F10')) { e.preventDefault(); open(row, ...rowAt(row), true); }
      });
    }

    menu.addEventListener('click', (e) => {
      const btn = e.target.closest('button');
      if (!btn || !owner) return;
      // A submenu item only opens its submenu (as on the Mac). A tap fires pointerover first, which already opened it.
      if (btn.hasAttribute('data-sub')) { e.stopPropagation(); openSub(btn, e.detail === 0); return; }
      const row = owner;
      if (btn.dataset.fmt) { close(); compress(row, btn.dataset.fmt); }
      else if (btn.dataset.act === 'remove') { close(); announce(`Removed ${$('.dk-row__name', row).textContent}.`); row.remove(); }
      else if (btn.dataset.act === 'clear') { close(); $$('.dk-row', results).forEach((r) => r.remove()); $('.dk-bar__status', results).textContent = 'Think dinky.'; $$('.dk-bar__btn', results).forEach((b) => b.remove()); announce('Cleared the list.'); }
    });
    function openSub(btn, focus) {
      const s = btn.nextElementSibling;
      if (s.hidden) { closeSubs(); s.hidden = false; btn.setAttribute('aria-expanded', 'true'); }
      if (focus) items(s)[0].focus();
    }
    menu.addEventListener('pointerover', (e) => {
      const btn = e.target.closest('button');
      if (!btn || btn.closest('.dk-menu .dk-menu')) return;
      if (btn.hasAttribute('data-sub')) openSub(btn, false);
      else closeSubs();
    });
    menu.addEventListener('keydown', (e) => {
      const cur = document.activeElement;
      const list = items(cur.parentElement);
      const i = list.indexOf(cur);
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); list[(i + (e.key === 'ArrowDown' ? 1 : -1) + list.length) % list.length].focus(); }
      else if (e.key === 'ArrowRight' && cur.hasAttribute('data-sub')) { e.preventDefault(); openSub(cur, true); }
      else if (e.key === 'ArrowLeft' && cur.parentElement !== menu) { e.preventDefault(); const opener = cur.parentElement.previousElementSibling; closeSubs(); opener.focus(); }
      else if (e.key === 'Escape') { e.preventDefault(); close(true); }
      else if (e.key === 'Tab') close(false);
    });
    document.addEventListener('pointerdown', (e) => { if (!menu.hidden && !menu.contains(e.target) && !e.target.closest('.dk-row--menu')) close(false); });

    // Show the menu once, on the first queued image, when the list scrolls into view
    onVisible(results, async () => {
      await wait(still() ? 0 : 700);
      const first = $('.dk-row--menu[data-kind="image"]', results);
      if (first && menu.hidden && !owner) open(first, ...rowAt(first), false);
    }, 0.6);
  }

  /* ---------- 6. Before & after: drag or use the keyboard; Side by Side / Slider ---------- */
  for (const wrap of $$('[data-sheetwrap]')) {
    const sheet = $('.dk-sheet', wrap);
    const cmp = $('[data-compare]', wrap);
    const handle = $('[data-handle]', wrap);
    let pos = 50;
    const set = (p) => {
      pos = Math.max(0, Math.min(100, p));
      cmp.style.setProperty('--pos', pos + '%');
      handle.setAttribute('aria-valuenow', Math.round(pos));
      handle.setAttribute('aria-valuetext', Math.round(pos) + '% original');
      cmp.toggleAttribute('data-near-left', pos <= 15);
      cmp.toggleAttribute('data-near-right', pos >= 85);
    };
    const fromEvent = (e) => { const r = cmp.getBoundingClientRect(); set(((e.clientX - r.left) / r.width) * 100); };
    // A mouse moves the line at once. A finger moves it on a sideways drag or a tap, so scrolling the page
    // past the picture (touch-action: pan-y hands that to the browser) never moves it.
    cmp.addEventListener('pointerdown', (e) => {
      if (e.button !== 0) return;
      const mouse = e.pointerType === 'mouse';
      const x0 = e.clientX;
      let moved = false;
      cmp.setPointerCapture(e.pointerId);
      if (mouse) { fromEvent(e); handle.focus({ preventScroll: true }); }
      const move = (ev) => { if (!mouse && !moved && Math.abs(ev.clientX - x0) < 4) return; moved = true; fromEvent(ev); };
      const up = (ev) => {
        if (!mouse && !moved && ev.type === 'pointerup') fromEvent(ev);
        cmp.removeEventListener('pointermove', move); cmp.removeEventListener('pointerup', up); cmp.removeEventListener('pointercancel', up);
      };
      cmp.addEventListener('pointermove', move);
      cmp.addEventListener('pointerup', up);
      cmp.addEventListener('pointercancel', up);
    });
    handle.addEventListener('keydown', (e) => {
      const step = { ArrowLeft: -2, ArrowDown: -2, ArrowRight: 2, ArrowUp: 2, PageDown: -10, PageUp: 10 }[e.key];
      if (step) { e.preventDefault(); set(pos + step); }
      else if (e.key === 'Home') { e.preventDefault(); set(0); }
      else if (e.key === 'End') { e.preventDefault(); set(100); }
    });
    for (const b of $$('[data-mode-btn]', wrap)) {
      b.addEventListener('click', () => {
        sheet.dataset.mode = b.dataset.modeBtn;
        $$('[data-mode-btn]', wrap).forEach((x) => x.setAttribute('aria-pressed', x === b));
      });
    }
    // A small nudge when it comes into view (or its scene opens), so it reads as draggable
    let nudging = false;
    whenShown(wrap, async () => {
      if (still() || nudging || sheet.dataset.mode !== 'slider') return;
      nudging = true;
      cmp.classList.add('is-nudging');
      for (const p of [50, 38, 62, 50]) { set(p); await wait(420); }
      cmp.classList.remove('is-nudging');
      nudging = false;
    }, 0.6);
  }
})();
