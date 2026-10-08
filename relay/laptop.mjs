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

let file = {};
try { file = JSON.parse(readFileSync(join(dirname(fileURLToPath(import.meta.url)), "config.json"), "utf8")); } catch {}
const WORKER = String(process.env.NEXTUP_WORKER_URL || file.workerUrl || "").replace(/\/$/, "");
const TOKEN = process.env.NEXTUP_RELAY_TOKEN || file.relayToken || "";
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
    const p = spawn("claude", ["-p", "--output-format", "text"], { cwd: SANDBOX, shell: process.platform === "win32" });
    let out = "", err = "";
    const kill = setTimeout(() => p.kill(), 150e3);
    p.stdout.on("data", (d) => (out += d));
    p.stderr.on("data", (d) => (err += d));
    p.on("error", (e) => { clearTimeout(kill); reject(e); });
    p.on("close", (code) => { clearTimeout(kill); code === 0 && out.trim() ? resolve(out.trim()) : reject(new Error(err.trim() || `claude exited with ${code}`)); });
    p.stdin.end(prompt);
  });
}

console.log(`Next Up relay running. Waiting for questions from ${WORKER}`);
for (;;) {
  try {
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
