// Runs the real content script in headless Chromium against a sample page,
// with the WebExtension `browser` API stubbed. Safari itself isn't available
// off a Mac; this checks the DOM logic, selection, cut, paste, and the Siri
// inbox round-trip.
//
//   NODE_PATH=$(npm root -g) node tests/e2e.mjs
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const here = path.dirname(fileURLToPath(import.meta.url));
const res = (f) => readFileSync(path.join(here, "../VoiceClipExtension/Resources", f), "utf8");

const PAGE = `<!doctype html><html><body>
<h1>Settings help</h1>
<p id="p1">You can call anyone on FaceTime from here. To share where you are, open Maps and send your location. It updates live.</p>
<p id="p2">Pricing starts at $5 per month. The deadline for the discount is Friday. Plans renew yearly.</p>
<div style="display:none">FaceTime hidden location</div>
<label>Email <input id="email" type="text"></label>
<label>Notes <textarea id="notes">Dear team, please review the draft. Thanks, Eric</textarea></label>
<input id="pw" type="password" value="secret FaceTime location">
</body></html>`;

const STUB = `
  window.__clip = null;
  window.__inbox = [];
  window.__results = [];
  const listeners = [];
  window.browser = {
    runtime: {
      async sendMessage(msg) {
        if (msg.type === "copy") { window.__clip = msg.text; return { ok: true }; }
        if (msg.type === "readClipboard") return window.__clip ? { ok: true, text: window.__clip } : { ok: false, error: "empty" };
        if (msg.type === "poll") return window.__inbox.shift() || {};
        if (msg.type === "result") { window.__results.push(msg); return { ok: true }; }
      },
      onMessage: { addListener(fn) { listeners.push(fn); } },
    },
    storage: {
      local: { get: async (d) => ({ ...d, siriListen: true }) },
      onChanged: { addListener() {} },
    },
  };
  window.__run = (command) => listeners[0]({ type: "run", command });
`;

const browser = await chromium.launch();
const page = await browser.newPage();
await page.setContent(PAGE);
await page.addScriptTag({ content: STUB });
for (const f of ["parser.js", "textmatch.js", "content.js"]) await page.addScriptTag({ content: res(f) });

const run = (cmd) => page.evaluate((c) => window.__run(c), cmd);
const clip = () => page.evaluate(() => window.__clip);
let failures = 0;
async function check(name, fn) {
  try {
    await fn();
    console.log("ok   ", name);
  } catch (e) {
    failures++;
    console.log("FAIL ", name, "\n     ", e.message.split("\n").join("\n      "));
  }
}

await check("copy from FaceTime to location", async () => {
  const r = await run("copy from face time to location");
  assert.equal(r.ok, true, r.message);
  assert.equal(await clip(), "FaceTime from here. To share where you are, open Maps and send your location");
  assert.equal(await page.evaluate(() => getSelection().toString()), await clip());
});

await check("paragraph about pricing", async () => {
  const r = await run("copy the paragraph about pricing");
  assert.equal(r.ok, true, r.message);
  assert.equal(await clip(), "Pricing starts at $5 per month. The deadline for the discount is Friday. Plans renew yearly.");
});

await check("sentence containing deadline", async () => {
  const r = await run("copy the sentence containing deadline");
  assert.equal(r.ok, true, r.message);
  assert.equal(await clip(), "The deadline for the discount is Friday.");
});

await check("from X to the end (paragraph)", async () => {
  const r = await run("copy from open maps to the end");
  assert.equal(r.ok, true, r.message);
  assert.equal(await clip(), "open Maps and send your location. It updates live.");
});

await check("from X to end of sentence", async () => {
  const r = await run("copy from open maps to the end of the sentence");
  assert.equal(r.ok, true, r.message);
  assert.equal(await clip(), "open Maps and send your location.");
});

await check("ambiguous 'to' resolves against the page", async () => {
  const r = await run("copy from to share to maps");
  assert.equal(r.ok, true, r.message);
  assert.equal(await clip(), "To share where you are, open Maps");
});

await check("not found gives a clear error", async () => {
  const r = await run("copy from banana to location");
  assert.equal(r.ok, false);
  assert.match(r.message, /Couldn't find “banana”/);
});

await check("cut on page text copies only", async () => {
  const r = await run("cut from pricing to month");
  assert.equal(r.ok, true, r.message);
  assert.match(r.message, /can't be cut/);
  assert.match(await page.textContent("#p2"), /^Pricing starts/);
});

await check("cut inside the focused textarea", async () => {
  await page.focus("#notes");
  const r = await run("cut from please to draft");
  assert.equal(r.ok, true, r.message);
  assert.equal(await clip(), "please review the draft");
  assert.equal(await page.inputValue("#notes"), "Dear team, . Thanks, Eric");
});

await check("paste into a named field", async () => {
  const r = await run("paste into the email field");
  assert.equal(r.ok, true, r.message);
  assert.equal(await page.inputValue("#email"), "please review the draft");
});

await check("paste with nothing focused fails politely", async () => {
  await page.evaluate(() => document.activeElement.blur());
  const r = await run("paste");
  assert.equal(r.ok, false);
});

await check("password fields are never searched", async () => {
  await page.focus("#pw");
  await run("copy from secret to location");
  assert.notEqual(await clip(), "secret FaceTime location");
});

await check("Siri inbox round-trip", async () => {
  await page.evaluate(() => document.activeElement.blur());
  await page.evaluate(() => window.__inbox.push({ id: "abc", command: "copy the sentence containing updates" }));
  await page.waitForFunction(() => window.__results.length > 0, null, { timeout: 5000 });
  const results = await page.evaluate(() => window.__results);
  assert.equal(results[0].id, "abc");
  assert.equal(results[0].ok, true, results[0].message);
  assert.equal(await clip(), "It updates live.");
});

await browser.close();
console.log(failures ? `\n${failures} failed` : "\nall passed");
process.exit(failures ? 1 : 0);
