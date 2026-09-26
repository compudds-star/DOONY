// Fuzzy phrase matching that survives how speech recognition writes things.
// Both sides are reduced to a "compact" form — lowercase letters and digits
// only — so "face time" finds "FaceTime", "e mail" finds "e-mail", and
// "rock and roll" finds "rock & roll". Each compact character remembers the
// index in the original string it came from, so a match maps back to exact
// DOM offsets. Pure functions, no DOM.
(function (root) {
  "use strict";

  const ALNUM = /[\p{L}\p{N}]/u;

  // Returns { text, map } where map[i] is the original index of text[i].
  function compact(original) {
    let text = "";
    const map = [];
    const src = String(original);
    for (let i = 0; i < src.length; i++) {
      const ch = src[i];
      if (ch === "&") {
        text += "and";
        map.push(i, i, i);
        continue;
      }
      // Strip diacritics so "cafe" matches "café".
      const folded = ch.normalize("NFKD").replace(/[̀-ͯ]/g, "").toLowerCase();
      for (const f of folded) {
        if (ALNUM.test(f)) {
          text += f;
          map.push(i);
        }
      }
    }
    return { text, map };
  }

  function compactQuery(phrase) {
    return compact(phrase).text;
  }

  function findAll(hay, needle) {
    const hits = [];
    if (!needle) return hits;
    let i = hay.indexOf(needle);
    while (i !== -1) {
      hits.push(i);
      i = hay.indexOf(needle, i + 1);
    }
    return hits;
  }

  // Picks the occurrence the user most likely means. `score(index)` returns a
  // distance (lower is better) — the DOM layer uses distance from the
  // viewport; without one, the first occurrence wins.
  function best(hits, score) {
    if (!hits.length) return -1;
    if (!score) return hits[0];
    let bestHit = hits[0];
    let bestScore = score(hits[0]);
    for (let k = 1; k < hits.length; k++) {
      const s = score(hits[k]);
      if (s < bestScore) {
        bestScore = s;
        bestHit = hits[k];
      }
    }
    return bestHit;
  }

  // Finds [start, end) in compact coordinates spanning from the start phrase
  // through the first end phrase that follows it. Returns null if either
  // phrase is missing or the end never follows the start.
  function findRange(hay, startPhrase, endPhrase, score) {
    const a = compactQuery(startPhrase);
    const b = compactQuery(endPhrase);
    if (!a || !b) return null;
    const starts = findAll(hay, a).filter((s) => hay.indexOf(b, s + a.length) !== -1);
    const s = best(starts, score);
    if (s === -1) return null;
    const e = hay.indexOf(b, s + a.length);
    return { start: s, end: e + b.length };
  }

  function findPhrase(hay, phrase, score) {
    const q = compactQuery(phrase);
    const s = best(findAll(hay, q), score);
    return s === -1 ? null : { start: s, end: s + q.length };
  }

  // Expands [start, end) in ORIGINAL string coordinates out to the enclosing
  // sentence(s). Used within one paragraph's text.
  function expandToSentence(text, start, end) {
    const terminator = /[.!?…]["')\]]*\s/g;
    let from = 0;
    let m;
    terminator.lastIndex = 0;
    while ((m = terminator.exec(text)) !== null && m.index < start) {
      from = m.index + m[0].length;
    }
    terminator.lastIndex = Math.max(end - 1, 0);
    m = terminator.exec(text);
    const to = m ? m.index + m[0].trimEnd().length : text.length;
    // Skip leading whitespace so the selection starts on the first word.
    while (from < to && /\s/.test(text[from])) from++;
    return { start: from, end: to };
  }

  const api = { compact, compactQuery, findAll, findRange, findPhrase, expandToSentence };
  root.VoiceClipMatch = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
