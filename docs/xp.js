// Shared XP helpers for the dashboard and Quest Log pages: one outbox of rows for the XP sheet's
// Log tab, written with the Google sign-in stored by the dashboard.
(function () {
  const AKEY = "nextup.auth", CKEY = "nextup.cfg", QKEY = "xp.outbox";
  const pad = (n) => String(n).padStart(2, "0");
  const get = (k, d) => { try { const v = localStorage.getItem(k); return v ? JSON.parse(v) : d; } catch { return d; } };
  const put = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch {} };
  const num = (x, d) => { const n = parseFloat(x); return isFinite(n) ? n : (d === undefined ? 0 : d); };

  function dayKey(t, startHour) { const d = new Date(t - startHour * 36e5); return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()); }
  // Sheet Log columns: time ms, day, quest id, name, base XP, multiplier, XP, kind
  const toRow = (r, sh) => [r.t, dayKey(r.t, sh), r.q, r.name, r.base, r.mult, r.xp, r.kind];
  const fromRow = (r) => ({ t: num(r[0]), q: String(r[2] || ""), name: String(r[3] || ""), base: num(r[4]), mult: num(r[5], 1), xp: num(r[6]), kind: String(r[7] || "quest") });

  function token() { const a = get(AKEY, null); return a && a.exp > Date.now() + 30e3 ? a.token : ""; }
  class HttpError extends Error { constructor(s, m) { super(m); this.status = s; } }
  async function http(url, opts = {}) {
    const t = token(); if (!t) throw new HttpError(401, "signed out");
    const r = await fetch(url, { ...opts, headers: { Authorization: "Bearer " + t, ...(opts.body ? { "Content-Type": "application/json" } : {}) } });
    const text = await r.text(); let data = null; try { data = JSON.parse(text); } catch { data = text; }
    if (!r.ok) throw new HttpError(r.status, (data && data.error && (data.error.message || data.error)) || r.statusText);
    return data;
  }
  async function sheetId() {
    let c = get(CKEY, null);
    if (!c || !c.questSheetId) {
      const cfg = window.NEXTUP_CONFIG || {};
      c = await http(String(cfg.workerUrl || "").replace(/\/$/, "") + "/config");
      put(CKEY, { questSheetId: c.questSheetId || "", at: Date.now() });
      c = get(CKEY, {});
    }
    if (!c.questSheetId) throw new HttpError(404, "No XP sheet is set in the server config (QUEST_SHEET_ID).");
    return c.questSheetId;
  }
  const values = async (range) => (await http(`https://sheets.googleapis.com/v4/spreadsheets/${await sheetId()}/values/${encodeURIComponent(range)}`)).values || [];

  let flushing = null;
  window.XP = {
    dayKey, toRow, fromRow,
    rememberConfig(cfg) { if (cfg && "questSheetId" in cfg) put(CKEY, { questSheetId: cfg.questSheetId || "", at: Date.now() }); },
    sheetUrl() { const c = get(CKEY, null); return c && c.questSheetId ? `https://docs.google.com/spreadsheets/d/${c.questSheetId}/edit` : ""; },
    pending() { return get(QKEY, []); },
    queue(r, sh) { const q = get(QKEY, []); q.push(toRow(r, sh == null ? 4 : sh)); put(QKEY, q); },
    async load() {
      const [quests, log, settings] = await Promise.all([values("Quests!A2:F80"), values("Log!A2:H20000"), values("Settings!A2:B30")]);
      return { quests, log: log.map(fromRow).filter((r) => r.t > 0 && r.q), settings };
    },
    // Writes queued rows; returns the rows written (as objects). Safe to call often.
    flush() {
      if (flushing) return flushing;
      flushing = (async () => {
        const batch = get(QKEY, []); if (!batch.length) return [];
        const id = await sheetId();
        await http(`https://sheets.googleapis.com/v4/spreadsheets/${id}/values/${encodeURIComponent("Log!A1")}:append?valueInputOption=RAW&insertDataOption=INSERT_ROWS`, { method: "POST", body: JSON.stringify({ values: batch }) });
        const keys = new Set(batch.map((r) => r[0] + "|" + r[2]));
        put(QKEY, get(QKEY, []).filter((r) => !keys.has(r[0] + "|" + r[2])));
        return batch.map(fromRow);
      })().finally(() => { flushing = null; });
      return flushing;
    },
  };
})();
