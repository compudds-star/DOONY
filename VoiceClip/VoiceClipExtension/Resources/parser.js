// Turns a spoken command ("copy from FaceTime to location") into a structured
// request. Pure functions, no DOM — loaded as a content script and by the
// Node tests.
(function (root) {
  "use strict";

  // Speech recognition routinely mishears short verbs. These only ever run
  // on text the user explicitly spoke or typed to VoiceClip, so being a bit
  // generous here costs nothing.
  const VERBS = {
    copy: "copy", copies: "copy", copied: "copy", coffee: "copy", copying: "copy",
    cut: "cut", cuts: "cut", cup: "cut", cutting: "cut",
    select: "select", selects: "select", highlight: "select", mark: "select",
    paste: "paste", pastes: "paste", pasted: "paste", paced: "paste", pace: "paste",
  };

  const LEADING_FILLER = /^(?:(?:ok(?:ay)?|hey|please|voice ?clip|can you|could you|now)\b[\s,]*)+/;
  const TRAILING_FILLER = /[\s,]*\b(?:please|thanks|thank you)$/;

  const SELECTION = /^(?:it|this|that|(?:the )?(?:current )?selection|(?:the )?selected(?: text)?|what(?:'s| is) selected)$/;
  const EVERYTHING = /^(?:all|everything|(?:the )?(?:whole |entire )?page|all (?:the )?text|all of it)$/;
  const BLOCK = /^(?:the )?(paragraph|sentence|line)(?: (?:that )?(?:containing|contains|with|about|has|mentioning|mentions|says|saying|starting with|starts with|that starts with|beginning with|begins with|including|includes))? (.+)$/;
  const RANGE_SEP = / (?:to|through|thru|till|until|up to|up until) /g;
  const END_TARGET = /^(?:the )?end(?: of (?:the )?(paragraph|sentence|page))?$/;
  const PASTE_INTO = /^(?:in|into|in to|inside|to|at) (?:the )?(.+?)(?: (?:field|box|input|area))?$/;

  function normalizeCommand(raw) {
    return String(raw || "")
      .normalize("NFKC")
      .toLowerCase()
      .replace(/[“”"]/g, "")
      .replace(/[’]/g, "'")
      .replace(/[.!?]+$/g, "")
      .replace(/\s+/g, " ")
      .trim()
      .replace(LEADING_FILLER, "")
      .replace(TRAILING_FILLER, "")
      .trim();
  }

  function stripQuotesAndArticles(phrase) {
    return phrase.replace(/^(?:the (?:words?|phrase|text) |the words? |word |phrase |text )/, "").trim();
  }

  // Every way "A to B" could split. "copy from how to cook to dessert" is
  // ambiguous on text alone; the resolver tries each split against the page.
  function rangeSplits(body) {
    const splits = [];
    RANGE_SEP.lastIndex = 0;
    let m;
    while ((m = RANGE_SEP.exec(body)) !== null) {
      const start = body.slice(0, m.index).trim();
      const end = body.slice(m.index + m[0].length).trim();
      if (start && end) splits.push({ start: stripQuotesAndArticles(start), end: parseEnd(end) });
      RANGE_SEP.lastIndex = m.index + 1;
    }
    return splits;
  }

  function parseEnd(text) {
    const m = END_TARGET.exec(text);
    if (m) return { kind: "end", unit: m[1] || "paragraph" };
    return { kind: "phrase", phrase: stripQuotesAndArticles(text) };
  }

  function parseTarget(body) {
    if (!body || SELECTION.test(body)) return { kind: "selection" };
    if (EVERYTHING.test(body)) return { kind: "all" };

    if (body.startsWith("from ")) {
      const rest = body.slice(5).trim();
      const splits = rangeSplits(rest);
      if (splits.length) return { kind: "range", splits };
      // "copy from FaceTime" with no end: treat as "to the end of the paragraph".
      return { kind: "range", splits: [{ start: stripQuotesAndArticles(rest), end: { kind: "end", unit: "paragraph" } }] };
    }

    const block = BLOCK.exec(body);
    if (block) {
      const unit = block[1] === "line" ? "sentence" : block[1];
      return { kind: "block", unit, phrase: stripQuotesAndArticles(block[2]) };
    }

    // No "from": the phrase is literal first, a range only if the literal
    // phrase isn't on the page ("copy how to cook" vs "copy intro to summary").
    return { kind: "phrase", phrase: stripQuotesAndArticles(body), splits: rangeSplits(body) };
  }

  function parseCommand(raw) {
    const text = normalizeCommand(raw);
    if (!text) return { error: "Say a command, like “copy from FaceTime to location”." };

    const firstSpace = text.indexOf(" ");
    const head = firstSpace === -1 ? text : text.slice(0, firstSpace);
    const verb = VERBS[head];
    if (!verb) return { error: `Start with copy, cut, select, or paste — heard “${text}”.` };

    const body = firstSpace === -1 ? "" : text.slice(firstSpace + 1).trim();

    if (verb === "paste") {
      if (!body || /^(?:it|this|that|here|clipboard|the clipboard)$/.test(body)) {
        return { verb, target: { kind: "focused" } };
      }
      const into = PASTE_INTO.exec(body);
      if (into) return { verb, target: { kind: "field", name: into[1] } };
      return { verb, target: { kind: "field", name: body } };
    }

    return { verb, target: parseTarget(body) };
  }

  const api = { parseCommand, normalizeCommand };
  root.VoiceClipParser = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
