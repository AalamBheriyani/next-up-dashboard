// Study deck for the kana practice page: reads words.csv and kanji.csv (the master lists the desktop
// flashcards app uses) and returns them in a compact form for the Worker's /relay/deck. The files are
// found through "deckDir" in relay/config.json; without it nothing is sent. Not in the repo: the word list
// comes from a textbook, so it lives only in the owner's account on the Worker.
import { readFileSync, statSync } from "node:fs";
import { join } from "node:path";

// Minimal CSV parser (quoted fields, doubled quotes, newlines inside quotes).
export function parseCsv(text) {
  const rows = []; let row = [], cell = "", q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"' && text[i + 1] === '"') { cell += '"'; i++; }
      else if (c === '"') q = false;
      else cell += c;
    } else if (c === '"') q = true;
    else if (c === ",") { row.push(cell); cell = ""; }
    else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(cell); cell = "";
      if (row.some((x) => x !== "")) rows.push(row);
      row = [];
    } else cell += c;
  }
  if (cell !== "" || row.length) { row.push(cell); rows.push(row); }
  const [head, ...rest] = rows;
  return rest.map((r) => Object.fromEntries(head.map((h, i) => [h, r[i] ?? ""])));
}

export function deckSignature(dir) {
  return ["words.csv", "kanji.csv"].map((f) => { try { return statSync(join(dir, f)).mtimeMs; } catch { return 0; } }).join(":");
}

export function readDeck(dir) {
  const words = parseCsv(readFileSync(join(dir, "words.csv"), "utf8"))
    .filter((r) => r.kana && r.english && /^\d+$/.test(r.lesson))
    .map((r) => [Number(r.lesson), r.source, r.section, r.kana, r.kanji, r.romaji, r.english, r.note]);
  let kanji = [];
  try {
    kanji = parseCsv(readFileSync(join(dir, "kanji.csv"), "utf8")).filter((r) => r.kanji && r.meaning)
      .map((r) => [r.kanji, r.meaning, r.readings]);
  } catch {}
  return { v: 1, words, kanji };
}
