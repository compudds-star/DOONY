"use strict";

const $ = (id) => document.getElementById(id);
const form = $("form");
const input = $("cmd");
const statusEl = $("status");
const RECENT_MAX = 5;

function setStatus(text, ok) {
  statusEl.textContent = text;
  statusEl.className = ok === undefined ? "" : ok ? "ok" : "err";
}

async function run(command) {
  command = command.trim();
  if (!command) return;
  setStatus("Working…");
  let res;
  try {
    res = await browser.runtime.sendMessage({ type: "runInActiveTab", command });
  } catch (_) {
    res = { ok: false, message: "VoiceClip isn't responding. Try reloading the page." };
  }
  res = res || { ok: false, message: "No response from the page." };
  setStatus(res.message, res.ok);
  if (res.ok) {
    await remember(command);
    setTimeout(() => window.close(), 1200);
  }
}

// ---------------------------------------------------------------- recents

async function remember(command) {
  const { recent = [] } = await browser.storage.local.get("recent");
  const next = [command, ...recent.filter((c) => c !== command)].slice(0, RECENT_MAX);
  await browser.storage.local.set({ recent: next });
}

function fillList(ul, items) {
  ul.replaceChildren(
    ...items.map((text) => {
      const li = document.createElement("li");
      li.textContent = text;
      return li;
    })
  );
}

function wireList(ul) {
  ul.addEventListener("click", (e) => {
    const li = e.target.closest("li");
    if (!li) return;
    input.value = li.textContent;
    run(li.textContent);
  });
}

// ------------------------------------------------------------------ speech
// The Web Speech API works in Safari when Siri & Dictation is on, but not in
// every extension-popup context. If it's missing or fails, the keyboard's
// dictation key is the fallback (always available).

function setupMic() {
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SR) return;
  const mic = $("mic");
  mic.hidden = false;
  let rec = null;

  mic.addEventListener("click", () => {
    if (rec) {
      rec.stop();
      return;
    }
    rec = new SR();
    rec.lang = navigator.language || "en-US";
    rec.interimResults = true;
    rec.maxAlternatives = 1;
    let finalText = "";

    rec.onresult = (e) => {
      let interim = "";
      for (let i = e.resultIndex; i < e.results.length; i++) {
        const t = e.results[i][0].transcript;
        if (e.results[i].isFinal) finalText += t;
        else interim += t;
      }
      input.value = (finalText + interim).trim();
    };
    rec.onerror = (e) => {
      const msg = e.error === "not-allowed" || e.error === "service-not-allowed"
        ? "Microphone blocked here. Use the keyboard's 🎙 key instead."
        : "Didn't catch that. Try again, or use the keyboard's 🎙 key.";
      setStatus(msg, false);
    };
    rec.onend = () => {
      mic.classList.remove("live");
      rec = null;
      if (finalText.trim()) run(finalText);
    };

    try {
      rec.start();
      mic.classList.add("live");
      setStatus("Listening…");
    } catch (_) {
      rec = null;
      setStatus("Couldn't start the microphone. Use the keyboard's 🎙 key.", false);
    }
  });
}

// ------------------------------------------------------------------- init

form.addEventListener("submit", (e) => {
  e.preventDefault();
  run(input.value);
});
wireList($("examples"));
wireList($("recent"));
setupMic();

browser.storage.local.get({ recent: [], siriListen: true }).then(({ recent, siriListen }) => {
  if (recent.length) {
    fillList($("recent"), recent);
    $("recentWrap").hidden = false;
  }
  $("siri").checked = siriListen !== false;
});
$("siri").addEventListener("change", (e) => browser.storage.local.set({ siriListen: e.target.checked }));

input.focus();
