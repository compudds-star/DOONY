// Relays between the page, the popup, and the native handler
// (SafariWebExtensionHandler.swift). Web pages can't message this worker —
// there is no externally_connectable — so every sender here is our own
// content script or popup.
"use strict";

// Safari ignores the application id and routes to the containing app's
// extension handler.
const native = (msg) => browser.runtime.sendNativeMessage("application.id", msg);

async function runInActiveTab(command) {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  if (!tab || tab.id === undefined) return { ok: false, message: "No Safari tab is open." };
  try {
    const res = await browser.tabs.sendMessage(tab.id, { type: "run", command });
    return res || { ok: false, message: "The page didn't answer. Reload it and try again." };
  } catch (_) {
    return {
      ok: false,
      message: "VoiceClip can't reach this page. Tap aA → Manage Extensions → VoiceClip → Allow, or reload the page.",
    };
  }
}

browser.runtime.onMessage.addListener((msg, sender) => {
  if (!msg || typeof msg.type !== "string") return undefined;
  const fromTab = !!(sender && sender.tab);

  switch (msg.type) {
    case "copy":
      if (!fromTab || typeof msg.text !== "string") return undefined;
      return native({ type: "copy", text: msg.text });
    case "readClipboard":
      if (!fromTab) return undefined;
      return native({ type: "readClipboard" });
    case "poll":
      if (!fromTab) return undefined;
      return native({ type: "poll" });
    case "result":
      if (!fromTab || typeof msg.id !== "string") return undefined;
      return native({ type: "result", id: msg.id, ok: !!msg.ok, message: String(msg.message || "").slice(0, 300) });
    case "runInActiveTab":
      // Popup only: it has no sender.tab.
      if (fromTab || typeof msg.command !== "string") return undefined;
      return runInActiveTab(msg.command.slice(0, 500));
    default:
      return undefined;
  }
});
