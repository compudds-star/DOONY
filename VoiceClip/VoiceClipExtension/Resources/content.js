// Runs in the page. Resolves a parsed command against the page text, shows
// what it matched, and performs copy / cut / select / paste. The clipboard
// itself is written by the native extension handler (UIPasteboard), because
// a web page's clipboard API needs a tap on that page — and a Siri command
// or a tap in the extension popup isn't one.
(function () {
  "use strict";
  if (window.top !== window) return;
  if (window.__voiceClipLoaded) return;
  window.__voiceClipLoaded = true;

  const { parseCommand } = globalThis.VoiceClipParser;
  const M = globalThis.VoiceClipMatch;

  const MAX_CLIP_CHARS = 500000;
  const SKIP = "script,style,noscript,template,textarea,input,select,option,iframe,canvas,svg,#voiceclip-host";
  const BLOCK = "p,li,td,th,h1,h2,h3,h4,h5,h6,blockquote,pre,dd,dt,figcaption,caption,article,section,div,main,body";
  const TEXT_INPUTS = new Set(["text", "search", "email", "url", "tel", ""]);

  // ---------------------------------------------------------------- text model

  function isVisible(el, cache) {
    if (cache.has(el)) return cache.get(el);
    let v;
    if (typeof el.checkVisibility === "function") {
      v = el.checkVisibility({ visibilityProperty: true, opacityProperty: false });
    } else {
      const cs = getComputedStyle(el);
      v = cs.display !== "none" && cs.visibility !== "hidden" && el.getClientRects().length > 0;
    }
    cache.set(el, v);
    return v;
  }

  // Flattens the visible text under `root` into one string plus the text
  // nodes it came from, then builds the compact (speech-tolerant) index.
  function collectText(root) {
    const cache = new Map();
    const segs = [];
    let full = "";
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        if (!/\S/.test(node.nodeValue)) return NodeFilter.FILTER_REJECT;
        const el = node.parentElement;
        if (!el || el.closest(SKIP) || !isVisible(el, cache)) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      },
    });
    let n;
    while ((n = walker.nextNode())) {
      segs.push({ node: n, start: full.length });
      full += n.nodeValue + "\n";
    }
    const c = M.compact(full);
    return { full, segs, hay: c.text, map: c.map };
  }

  function posAt(ctx, fullIndex) {
    let lo = 0;
    let hi = ctx.segs.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (ctx.segs[mid].start <= fullIndex) lo = mid;
      else hi = mid - 1;
    }
    const seg = ctx.segs[lo];
    return { node: seg.node, offset: Math.min(fullIndex - seg.start, seg.node.nodeValue.length) };
  }

  // [from, to) in ctx.full coordinates → DOM Range.
  function fullRange(ctx, from, to) {
    const a = posAt(ctx, from);
    const b = posAt(ctx, Math.max(to - 1, from));
    const r = document.createRange();
    r.setStart(a.node, a.offset);
    r.setEnd(b.node, Math.min(b.offset + 1, b.node.nodeValue.length));
    return r;
  }

  // [s, e) in compact coordinates → [from, to) in ctx.full coordinates.
  function compactToFull(ctx, s, e) {
    return { from: ctx.map[s], to: ctx.map[e - 1] + 1 };
  }

  // Lower is better: 0 if the match is on screen, else its distance in px.
  // Among on-screen matches the first in the page wins.
  function viewportScore(ctx) {
    return (s) => {
      const f = ctx.map[s];
      const rect = fullRange(ctx, f, f + 1).getBoundingClientRect();
      if (rect.bottom >= 0 && rect.top <= window.innerHeight) return 0;
      return rect.top < 0 ? -rect.bottom : rect.top - window.innerHeight;
    };
  }

  // ------------------------------------------------------------ editable fields

  function textField(el) {
    if (!el) return null;
    if (el.tagName === "TEXTAREA") return el;
    if (el.tagName === "INPUT" && TEXT_INPUTS.has((el.getAttribute("type") || "").toLowerCase())) return el;
    return null;
  }

  function editableRoot(node) {
    const el = node && (node.nodeType === 1 ? node : node.parentElement);
    return el && el.isContentEditable ? el : null;
  }

  function fieldLabel(el) {
    const parts = [
      el.getAttribute("aria-label"),
      el.getAttribute("placeholder"),
      el.getAttribute("name"),
      el.getAttribute("title"),
      el.id,
    ];
    const by = el.getAttribute("aria-labelledby");
    if (by) {
      for (const id of by.split(/\s+/)) {
        const l = document.getElementById(id);
        if (l) parts.push(l.textContent);
      }
    }
    if (el.labels) for (const l of el.labels) parts.push(l.textContent);
    return parts.filter(Boolean).join(" ");
  }

  function findFieldByName(name) {
    const want = M.compactQuery(name);
    if (!want) return null;
    const cache = new Map();
    const candidates = document.querySelectorAll("input, textarea, [contenteditable]:not([contenteditable='false'])");
    for (const el of candidates) {
      if (!(textField(el) || el.isContentEditable)) continue;
      if (el.disabled || el.readOnly || !isVisible(el, cache)) continue;
      if (M.compactQuery(fieldLabel(el)).includes(want)) return el;
    }
    return null;
  }

  // ------------------------------------------------------------------ resolve

  // Returns a match: { kind: "field", el, start, end } or { kind: "dom", range },
  // or { error }.
  function resolve(target) {
    const active = textField(document.activeElement);

    if (target.kind === "selection") {
      if (active && active.selectionStart !== active.selectionEnd) {
        return { kind: "field", el: active, start: active.selectionStart, end: active.selectionEnd };
      }
      const sel = window.getSelection();
      if (sel && sel.rangeCount && !sel.isCollapsed) return { kind: "dom", range: sel.getRangeAt(0).cloneRange() };
      return { error: "Nothing is selected. Say what to copy, like “copy from FaceTime to location”." };
    }

    if (target.kind === "all") {
      if (active) return { kind: "field", el: active, start: 0, end: active.value.length };
      const r = document.createRange();
      r.selectNodeContents(document.body);
      return { kind: "dom", range: r };
    }

    // The focused text field is searched first — "cut from X to Y" while
    // typing an email should act on the draft, not the page around it.
    if (active) {
      const hit = resolveInField(active, target);
      if (hit) return hit;
    }
    return resolveInPage(target);
  }

  function resolveInField(el, target) {
    const value = el.value;
    const c = M.compact(value);
    const toField = (s, e) => ({ kind: "field", el, start: c.map[s], end: c.map[e - 1] + 1 });

    const tryRange = (split) => {
      if (split.end.kind === "end") {
        const p = M.findPhrase(c.text, split.start);
        if (!p) return null;
        const from = c.map[p.start];
        if (split.end.unit === "sentence") {
          const x = M.expandToSentence(value, from, c.map[p.end - 1] + 1);
          return { kind: "field", el, start: from, end: x.end };
        }
        const nl = split.end.unit === "paragraph" ? value.indexOf("\n", from) : -1;
        return { kind: "field", el, start: from, end: nl === -1 ? value.length : nl };
      }
      const r = M.findRange(c.text, split.start, split.end.phrase);
      return r && toField(r.start, r.end);
    };

    if (target.kind === "range") return firstHit(target.splits, tryRange);
    if (target.kind === "phrase") {
      const p = M.findPhrase(c.text, target.phrase);
      if (p) return toField(p.start, p.end);
      return firstHit(target.splits || [], tryRange);
    }
    if (target.kind === "block") {
      const p = M.findPhrase(c.text, target.phrase);
      if (!p) return null;
      const from = c.map[p.start];
      const to = c.map[p.end - 1] + 1;
      if (target.unit === "sentence") {
        const x = M.expandToSentence(value, from, to);
        return { kind: "field", el, start: x.start, end: x.end };
      }
      const a = value.lastIndexOf("\n", from - 1) + 1;
      const b = value.indexOf("\n", to);
      return { kind: "field", el, start: a, end: b === -1 ? value.length : b };
    }
    return null;
  }

  function resolveInPage(target) {
    const ctx = collectText(document.body);
    const score = viewportScore(ctx);

    const tryRange = (split) => {
      if (split.end.kind === "end") {
        const p = M.findPhrase(ctx.hay, split.start, score);
        if (!p) return null;
        const { from, to } = compactToFull(ctx, p.start, p.end);
        const startRange = fullRange(ctx, from, to);
        if (split.end.unit === "page") {
          const r = startRange.cloneRange();
          r.setEndAfter(document.body.lastChild || document.body);
          return { kind: "dom", range: r };
        }
        const block = blockOf(startRange.startContainer);
        const blockMatch = sentenceOrBlock(block, startRange, split.end.unit);
        const r = startRange.cloneRange();
        r.setEnd(blockMatch.range.endContainer, blockMatch.range.endOffset);
        return { kind: "dom", range: r };
      }
      const hit = M.findRange(ctx.hay, split.start, split.end.phrase, score);
      if (!hit) return null;
      const { from, to } = compactToFull(ctx, hit.start, hit.end);
      return { kind: "dom", range: fullRange(ctx, from, to) };
    };

    let hit = null;
    if (target.kind === "range") {
      hit = firstHit(target.splits, tryRange);
      if (!hit) return notFound(target.splits.map((s) => s.start), target);
    } else if (target.kind === "phrase") {
      const p = M.findPhrase(ctx.hay, target.phrase, score);
      if (p) {
        const { from, to } = compactToFull(ctx, p.start, p.end);
        hit = { kind: "dom", range: fullRange(ctx, from, to) };
      } else {
        hit = firstHit(target.splits || [], tryRange);
      }
      if (!hit) return notFound([target.phrase], target);
    } else if (target.kind === "block") {
      const p = M.findPhrase(ctx.hay, target.phrase, score);
      if (!p) return notFound([target.phrase], target);
      const { from, to } = compactToFull(ctx, p.start, p.end);
      const phraseRange = fullRange(ctx, from, to);
      hit = sentenceOrBlock(blockOf(phraseRange.startContainer), phraseRange, target.unit);
    }
    return hit || { error: "I couldn't work out what to select." };
  }

  function firstHit(splits, fn) {
    for (const s of splits) {
      const h = fn(s);
      if (h) return h;
    }
    return null;
  }

  function notFound(phrases, target) {
    const shown = phrases.slice(0, 1).map((p) => `“${p}”`).join(", ");
    if (target.kind === "range" && target.splits.length) {
      const s = target.splits[0];
      const end = s.end.kind === "phrase" ? `“${s.end.phrase}”` : "the end";
      return { error: `Couldn't find ${shown} followed by ${end} on this page.` };
    }
    return { error: `Couldn't find ${shown} on this page.` };
  }

  function blockOf(node) {
    const el = node.nodeType === 1 ? node : node.parentElement;
    return (el && el.closest(BLOCK)) || document.body;
  }

  // Whole block for "paragraph"; the enclosing sentence(s) of `inner` for
  // "sentence".
  function sentenceOrBlock(block, inner, unit) {
    const r = document.createRange();
    r.selectNodeContents(block);
    if (unit !== "sentence") return { kind: "dom", range: r };

    const ctx = collectText(block);
    if (!ctx.segs.length) return { kind: "dom", range: r };
    const from = fullIndexOf(ctx, inner.startContainer, inner.startOffset);
    const to = fullIndexOf(ctx, inner.endContainer, inner.endOffset);
    if (from === -1 || to === -1) return { kind: "dom", range: r };
    const x = M.expandToSentence(ctx.full, from, to);
    return { kind: "dom", range: fullRange(ctx, x.start, x.end) };
  }

  function fullIndexOf(ctx, node, offset) {
    for (const seg of ctx.segs) if (seg.node === node) return seg.start + offset;
    return -1;
  }

  // ------------------------------------------------------------------- act

  function show(match) {
    if (match.kind === "field") {
      match.el.focus({ preventScroll: true });
      match.el.setSelectionRange(match.start, match.end);
      match.el.scrollIntoView({ block: "center", behavior: "smooth" });
      return;
    }
    const sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(match.range);
    const rect = match.range.getBoundingClientRect();
    if (rect.top < 0 || rect.bottom > window.innerHeight) {
      const el = match.range.startContainer.nodeType === 1 ? match.range.startContainer : match.range.startContainer.parentElement;
      if (el) el.scrollIntoView({ block: "center", behavior: "smooth" });
    }
    // iOS doesn't always paint a programmatic selection, so flash an overlay.
    setTimeout(() => flash(match.range), 350);
  }

  function textOf(match) {
    if (match.kind === "field") return match.el.value.slice(match.start, match.end);
    const sel = window.getSelection();
    // Selection.toString() follows layout (like innerText); Range.toString()
    // would include raw whitespace from the markup.
    const s = sel && sel.rangeCount ? sel.toString() : "";
    return (s || match.range.toString()).trim();
  }

  function isEditable(match) {
    if (match.kind === "field") return !match.el.readOnly && !match.el.disabled;
    return !!(editableRoot(match.range.startContainer) && editableRoot(match.range.endContainer));
  }

  function deleteMatch(match) {
    if (match.kind === "field") {
      match.el.focus({ preventScroll: true });
      match.el.setSelectionRange(match.start, match.end);
      // execCommand keeps the edit on the undo stack and fires the input
      // events frameworks listen for; setRangeText is the fallback.
      if (!document.execCommand("delete")) {
        match.el.setRangeText("", match.start, match.end, "start");
        match.el.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "deleteContent" }));
      }
      return;
    }
    const sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(match.range);
    if (!document.execCommand("delete")) match.range.deleteContents();
  }

  function insertText(el, text) {
    el.focus({ preventScroll: true });
    if (document.execCommand("insertText", false, text)) return;
    const field = textField(el);
    if (field) {
      const s = field.selectionStart ?? field.value.length;
      const e = field.selectionEnd ?? s;
      field.setRangeText(text, s, e, "end");
      field.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: text }));
      return;
    }
    const sel = window.getSelection();
    if (sel.rangeCount) {
      const r = sel.getRangeAt(0);
      r.deleteContents();
      r.insertNode(document.createTextNode(text));
      r.collapse(false);
    }
  }

  async function copyToClipboard(text) {
    if (!text) return { ok: false, message: "That selection has no text." };
    if (text.length > MAX_CLIP_CHARS) return { ok: false, message: "That's too much text to copy at once." };
    const res = await browser.runtime.sendMessage({ type: "copy", text });
    if (res && res.ok) return { ok: true };
    return { ok: false, message: (res && res.error) || "Couldn't reach the clipboard." };
  }

  function describe(text) {
    const words = text.split(/\s+/).filter(Boolean).length;
    if (words <= 6) return `“${text.replace(/\s+/g, " ")}”`;
    return `${words} words`;
  }

  async function run(command) {
    const parsed = parseCommand(command);
    if (parsed.error) return { ok: false, message: parsed.error };

    if (parsed.verb === "paste") return paste(parsed.target);

    const match = resolve(parsed.target);
    if (match.error) return { ok: false, message: match.error };
    show(match);
    const text = textOf(match);

    if (parsed.verb === "select") return { ok: true, message: `Selected ${describe(text)}.` };

    const copied = await copyToClipboard(text);
    if (!copied.ok) return copied;

    if (parsed.verb === "cut") {
      if (!isEditable(match)) return { ok: true, message: `Copied ${describe(text)}. This page text can't be cut, only copied.` };
      deleteMatch(match);
      return { ok: true, message: `Cut ${describe(text)}.` };
    }
    return { ok: true, message: `Copied ${describe(text)}.` };
  }

  async function paste(target) {
    let el;
    if (target.kind === "field") {
      el = findFieldByName(target.name);
      if (!el) return { ok: false, message: `Couldn't find a “${target.name}” field on this page.` };
    } else {
      const active = document.activeElement;
      el = textField(active) || (active && active.isContentEditable ? active : null);
      if (!el) return { ok: false, message: "Tap into a text field first, or say “paste into” and the field's name." };
    }
    const res = await browser.runtime.sendMessage({ type: "readClipboard" });
    if (!res || !res.ok) return { ok: false, message: (res && res.error) || "Couldn't read the clipboard." };
    insertText(el, res.text);
    return { ok: true, message: `Pasted ${describe(res.text)}.` };
  }

  // ------------------------------------------------------------------ UI

  let host;
  function ui() {
    if (host && host.isConnected) return host.__root;
    host = document.createElement("div");
    host.id = "voiceclip-host";
    host.style.cssText = "all:initial;position:fixed;inset:0;pointer-events:none;z-index:2147483647;";
    const root = host.attachShadow({ mode: "closed" });
    const style = document.createElement("style");
    style.textContent = `
      .toast{position:fixed;left:50%;bottom:calc(24px + env(safe-area-inset-bottom));transform:translateX(-50%);
        max-width:min(90vw,420px);padding:10px 14px;border-radius:12px;font:15px/1.35 -apple-system,system-ui,sans-serif;
        color:#fff;background:rgba(28,28,30,.92);box-shadow:0 4px 16px rgba(0,0,0,.25);transition:opacity .3s}
      .toast.err{background:rgba(180,35,24,.94)}
      .mark{position:absolute;background:rgba(255,159,10,.35);border-radius:3px;transition:opacity .6s}`;
    root.appendChild(style);
    (document.body || document.documentElement).appendChild(host);
    host.__root = root;
    return root;
  }

  function toast(message, ok) {
    const root = ui();
    root.querySelectorAll(".toast").forEach((t) => t.remove());
    const t = document.createElement("div");
    t.className = ok ? "toast" : "toast err";
    t.setAttribute("role", "status");
    t.textContent = message;
    root.appendChild(t);
    setTimeout(() => (t.style.opacity = "0"), 2600);
    setTimeout(() => t.remove(), 3000);
  }

  function flash(range) {
    const root = ui();
    const marks = [];
    for (const r of Array.from(range.getClientRects()).slice(0, 200)) {
      if (!r.width || !r.height) continue;
      const m = document.createElement("div");
      m.className = "mark";
      m.style.cssText = `left:${r.left}px;top:${r.top}px;width:${r.width}px;height:${r.height}px`;
      root.appendChild(m);
      marks.push(m);
    }
    setTimeout(() => marks.forEach((m) => (m.style.opacity = "0")), 1200);
    setTimeout(() => marks.forEach((m) => m.remove()), 1900);
  }

  async function runAndReport(command) {
    let result;
    try {
      result = await run(command);
    } catch (e) {
      result = { ok: false, message: "Something went wrong on this page." };
      console.error("[VoiceClip]", e);
    }
    toast(result.message, result.ok);
    return result;
  }

  // From the popup (via background).
  browser.runtime.onMessage.addListener((msg) => {
    if (msg && msg.type === "run" && typeof msg.command === "string") return runAndReport(msg.command);
    return undefined;
  });

  // ------------------------------------------------------------- Siri inbox
  // A Siri / Shortcuts command is dropped in the app's shared inbox; the tab
  // the user is looking at picks it up. Only the visible top-level page polls,
  // and the native side hands each command out once, so it runs in one tab.

  const POLL_MS = 1500;
  let pollTimer = null;
  let listening = true;
  let polling = false;

  async function pollOnce() {
    if (!listening || polling || document.visibilityState !== "visible") return;
    polling = true;
    try {
      const res = await browser.runtime.sendMessage({ type: "poll" });
      if (res && res.id && typeof res.command === "string") {
        const result = await runAndReport(res.command);
        browser.runtime.sendMessage({ type: "result", id: res.id, ok: result.ok, message: result.message });
      }
    } catch (_) {
      // Extension reloaded or native side unavailable; try again next tick.
    } finally {
      polling = false;
    }
  }

  function schedule() {
    clearInterval(pollTimer);
    pollTimer = null;
    if (listening && document.visibilityState === "visible") {
      pollTimer = setInterval(pollOnce, POLL_MS);
      pollOnce();
    }
  }

  browser.storage.local.get({ siriListen: true }).then((s) => {
    listening = s.siriListen !== false;
    schedule();
  });
  browser.storage.onChanged.addListener((changes, area) => {
    if (area === "local" && changes.siriListen) {
      listening = changes.siriListen.newValue !== false;
      schedule();
    }
  });
  document.addEventListener("visibilitychange", schedule);
  window.addEventListener("pageshow", schedule);
  window.addEventListener("focus", pollOnce);
})();
