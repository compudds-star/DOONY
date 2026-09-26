// node --test tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { parseCommand } = require("../VoiceClipExtension/Resources/parser.js");
const M = require("../VoiceClipExtension/Resources/textmatch.js");

test("the headline command", () => {
  const p = parseCommand("Copy from FaceTime to location.");
  assert.equal(p.verb, "copy");
  assert.equal(p.target.kind, "range");
  assert.deepEqual(p.target.splits[0], { start: "facetime", end: { kind: "phrase", phrase: "location" } });
});

test("misheard verbs and filler", () => {
  assert.equal(parseCommand("Hey VoiceClip, coffee from a to b please").verb, "copy");
  assert.equal(parseCommand("cup from a to b").verb, "cut");
  assert.equal(parseCommand("highlight everything").verb, "select");
});

test("every split is offered for ambiguous 'to'", () => {
  const p = parseCommand("copy from how to cook to dessert");
  assert.deepEqual(
    p.target.splits.map((s) => [s.start, s.end.phrase]),
    [["how", "cook to dessert"], ["how to cook", "dessert"]]
  );
});

test("range to the end", () => {
  const p = parseCommand("copy from Dear to the end of the sentence");
  assert.deepEqual(p.target.splits[0].end, { kind: "end", unit: "sentence" });
  assert.deepEqual(parseCommand("copy from Dear to the end").target.splits[0].end, { kind: "end", unit: "paragraph" });
  assert.deepEqual(parseCommand("copy from Dear").target.splits[0].end, { kind: "end", unit: "paragraph" });
});

test("blocks, selection, everything", () => {
  assert.deepEqual(parseCommand("copy the paragraph about pricing").target, { kind: "block", unit: "paragraph", phrase: "pricing" });
  assert.deepEqual(parseCommand("copy sentence containing deadline").target, { kind: "block", unit: "sentence", phrase: "deadline" });
  assert.deepEqual(parseCommand("copy").target, { kind: "selection" });
  assert.deepEqual(parseCommand("copy the selection").target, { kind: "selection" });
  assert.deepEqual(parseCommand("select everything").target, { kind: "all" });
  assert.deepEqual(parseCommand("copy the whole page").target, { kind: "all" });
});

test("a plain phrase keeps range splits as a fallback", () => {
  const p = parseCommand("copy intro to summary");
  assert.equal(p.target.kind, "phrase");
  assert.equal(p.target.phrase, "intro to summary");
  assert.deepEqual(p.target.splits[0].end, { kind: "phrase", phrase: "summary" });
});

test("paste targets", () => {
  assert.deepEqual(parseCommand("paste").target, { kind: "focused" });
  assert.deepEqual(parseCommand("paste here").target, { kind: "focused" });
  assert.deepEqual(parseCommand("paste into the email field").target, { kind: "field", name: "email" });
  assert.deepEqual(parseCommand("paste in notes").target, { kind: "field", name: "notes" });
});

test("rejects non-commands", () => {
  assert.ok(parseCommand("").error);
  assert.ok(parseCommand("what time is it").error);
});

test("compact matching survives speech spelling", () => {
  const hay = M.compact("Use FaceTime & e-mail at the café. Share your location.").text;
  assert.ok(M.findPhrase(hay, "face time"));
  assert.ok(M.findPhrase(hay, "facetime and email"));
  assert.ok(M.findPhrase(hay, "cafe"));
});

test("findRange maps back to original text", () => {
  const src = "Call on FaceTime, then share your Location. Later, location again.";
  const c = M.compact(src);
  const r = M.findRange(c.text, "face time", "location");
  const out = src.slice(c.map[r.start], c.map[r.end - 1] + 1);
  assert.equal(out, "FaceTime, then share your Location");
});

test("findRange requires the end after the start", () => {
  const c = M.compact("location first, FaceTime after");
  assert.equal(M.findRange(c.text, "facetime", "location"), null);
});

test("findRange prefers the best-scored start", () => {
  const src = "A one B. A two B.";
  const c = M.compact(src);
  const second = c.text.lastIndexOf("a");
  const r = M.findRange(c.text, "a", "b", (i) => (i === second ? 0 : 1));
  assert.equal(src.slice(c.map[r.start], c.map[r.end - 1] + 1), "A two B");
});

test("expandToSentence", () => {
  const t = "First one. The deadline is Friday. Last.";
  const i = t.indexOf("deadline");
  const x = M.expandToSentence(t, i, i + 8);
  assert.equal(t.slice(x.start, x.end), "The deadline is Friday.");
});
