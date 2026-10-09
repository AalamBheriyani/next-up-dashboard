// Next Up laptop relay: answers the dashboard's "Ask Claude" questions with Claude Code on this
// computer, so they run on your Claude plan instead of a paid API key.
//
// Needs Node 18+ and Claude Code (`claude`) installed and signed in. Run: node relay/laptop.mjs
// Settings come from relay/config.json ({"workerUrl": "...", "relayToken": "..."}) or the
// NEXTUP_WORKER_URL / NEXTUP_RELAY_TOKEN environment variables.
import { spawn } from "node:child_process";
import { readFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { markDone } from "./org-done.mjs";

let file = {};
try { file = JSON.parse(readFileSync(join(dirname(fileURLToPath(import.meta.url)), "config.json"), "utf8")); } catch {}
const WORKER = String(process.env.NEXTUP_WORKER_URL || file.workerUrl || "").replace(/\/$/, "");
const TOKEN = process.env.NEXTUP_RELAY_TOKEN || file.relayToken || "";
const CLAUDE = process.env.NEXTUP_CLAUDE || file.claudeBin || "claude";
const ORG_FILES = Array.isArray(file.orgFiles) ? file.orgFiles : [];
if (!WORKER || !TOKEN) { console.error("Set workerUrl and relayToken in relay/config.json first."); process.exit(1); }

// Claude runs in an empty folder so it has nothing on this computer to read or change.
const SANDBOX = mkdtempSync(join(tmpdir(), "nextup-"));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function call(path, body) {
  const r = await fetch(WORKER + path, {
    method: body ? "POST" : "GET",
    headers: { Authorization: "Bearer " + TOKEN, ...(body ? { "Content-Type": "application/json" } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!r.ok) throw new Error(`${path} ${r.status} ${await r.text()}`);
  return r.json();
}

function runClaude(prompt) {
  return new Promise((resolve, reject) => {
    const p = spawn(CLAUDE, ["-p", "--output-format", "text"], { cwd: SANDBOX, shell: process.platform === "win32" });
    let out = "", err = "";
    const kill = setTimeout(() => p.kill(), 150e3);
    p.stdout.on("data", (d) => (out += d));
    p.stderr.on("data", (d) => (err += d));
    p.on("error", (e) => { clearTimeout(kill); reject(e); });
    p.on("close", (code) => { clearTimeout(kill); code === 0 && out.trim() ? resolve(out.trim()) : reject(new Error(err.trim() || `claude exited with ${code}`)); });
    p.stdin.end(prompt);
  });
}

// Tasks ticked off on the dashboard become DONE in the org files (checked once a minute).
let lastOrg = 0;
async function syncDone() {
  if (!ORG_FILES.length || Date.now() - lastOrg < 60e3) return;
  lastOrg = Date.now();
  const { done } = await call("/relay/done");
  if (!done || !done.length) return;
  const ids = [];
  for (const d of done) {
    const f = markDone(ORG_FILES, d.title, new Date(d.at));
    console.log(new Date().toLocaleTimeString(), f ? `DONE in ${f}: ${d.title}` : `no open org heading for: ${d.title}`);
    ids.push(d.taskId); // not found counts as handled too, so it isn't retried forever
  }
  await call("/relay/done", { ids });
}

// Anki: when Anki desktop is open with the AnkiConnect add-on, send due counts and review history
// to the dashboard every 5 minutes. Skipped quietly when Anki isn't running.
const ANKI = process.env.NEXTUP_ANKI_URL || file.ankiUrl || "http://127.0.0.1:8765";
let lastAnki = 0, lastPull = 0;
async function anki(action, params = {}) {
  const r = await fetch(ANKI, { method: "POST", body: JSON.stringify({ action, version: 6, params }) });
  const j = await r.json();
  if (j.error) throw new Error("AnkiConnect: " + j.error);
  return j.result;
}
async function syncAnki() {
  if (Date.now() - lastAnki < 300e3) return;
  lastAnki = Date.now();
  let names;
  try { names = await anki("deckNames"); } catch { return; } // Anki closed
  // Pull reviews done on your phone first: Anki syncs with AnkiWeb at most every 30 minutes.
  if (Date.now() - lastPull > 1800e3) {
    lastPull = Date.now();
    try { await anki("sync"); } catch (e) { console.error(new Date().toLocaleTimeString(), "Anki sync skipped:", e.message); }
  }
  const stats = await anki("getDeckStats", { decks: names });
  const decks = Object.values(stats)
    .filter((d) => !String(d.name).includes("::")) // top-level decks already include their subdecks
    .map((d) => ({ name: d.name, new: d.new_count, learn: d.learn_count, review: d.review_count }));
  const days = (await anki("getNumCardsReviewedByDay")).slice(0, 400); // [["2026-10-08", 37], ...]
  await call("/relay/anki", { decks, days });
  console.log(new Date().toLocaleTimeString(), `Anki: ${decks.length} decks sent`);
}

console.log(`Next Up relay running. Waiting for questions from ${WORKER}`);
for (;;) {
  try {
    await syncDone();
    await syncAnki().catch((e) => console.error(new Date().toLocaleTimeString(), e.message));
    const q = await call("/relay/next");
    if (q.id) {
      console.log(new Date().toLocaleTimeString(), "question received");
      try { await call("/relay/reply", { id: q.id, text: await runClaude(q.prompt) }); }
      catch (e) { console.error(e.message); await call("/relay/reply", { id: q.id, error: e.message.slice(0, 500) }); }
      continue;
    }
  } catch (e) { console.error(new Date().toLocaleTimeString(), e.message); await sleep(15e3); }
  await sleep(4e3);
}
