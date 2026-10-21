// Marks tasks completed on the dashboard as DONE in your org files.
//
// The Worker keeps a list of tasks you ticked off with the dashboard's Done button. This finds the
// org heading with the same title (TODO, NEXT, WAITING… keywords; priority cookies and tags are
// ignored), switches it to DONE and adds a CLOSED timestamp, the way Emacs does. Files are listed in
// relay/config.json as "orgFiles"; whatever already syncs them (git, Dropbox, beorg) picks up the edit.
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { homedir } from "node:os";

const OPEN = /^(\*+)\s+(TODO|NEXT|STARTED|WAITING|HOLD)\s+(.*)$/;
const norm = (s) => String(s).toLowerCase()
  .replace(/\[#[a-z]\]/g, "")            // priority cookie
  .replace(/\s+:[\w@#%:]+:\s*$/, "")     // trailing tags
  .replace(/\[\d+\/\d+\]|\[\d+%\]/g, "") // progress cookies
  .replace(/[^\p{L}\p{N}]+/gu, " ").trim();

function stamp(d) {
  const p = (n) => String(n).padStart(2, "0");
  const day = d.toLocaleDateString("en-US", { weekday: "short" });
  return `[${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${day} ${p(d.getHours())}:${p(d.getMinutes())}]`;
}

/** Returns the file it changed, or "" if no open heading matched. */
export function markDone(files, title, when = new Date()) {
  const want = norm(title);
  if (!want) return "";
  for (const f0 of files) {
    const f = f0.replace(/^~(?=\/)/, homedir());
    if (!existsSync(f)) continue;
    const lines = readFileSync(f, "utf8").split("\n");
    const i = lines.findIndex((l) => { const m = l.match(OPEN); return m && norm(m[3]) === want; });
    if (i < 0) continue;
    const m = lines[i].match(OPEN);
    lines[i] = `${m[1]} DONE ${m[3]}`;
    const closed = `CLOSED: ${stamp(when)}`;
    const indent = " ".repeat(m[1].length + 1);
    const next = lines[i + 1] || "";
    if (/^\s*(SCHEDULED|DEADLINE):/.test(next)) lines[i + 1] = next.replace(/^(\s*)/, `$1${closed} `);
    else lines.splice(i + 1, 0, indent + closed);
    writeFileSync(f, lines.join("\n"));
    return f;
  }
  return "";
}
