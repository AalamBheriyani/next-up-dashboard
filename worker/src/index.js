// Next Up server: a Cloudflare Worker that sits between the GitHub Pages site and
// the services that need secrets (TickTick and the Claude API).
//
// Every API route requires the Google access token the site got from "Sign in with Google".
// The Worker checks it with Google and only lets ALLOWED_EMAIL through.
import Anthropic from "@anthropic-ai/sdk";

const TT_API = "https://api.ticktick.com/open/v1";
const TT_AUTH = "https://ticktick.com/oauth/authorize";
const TT_TOKEN = "https://ticktick.com/oauth/token";
const MODEL = "claude-opus-5-5";

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const origin = new URL(env.SITE_URL).origin;
    const cors = {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Headers": "Authorization, Content-Type",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Max-Age": "86400",
      Vary: "Origin",
    };
    const json = (data, status = 200) =>
      new Response(JSON.stringify(data), { status, headers: { ...cors, "Content-Type": "application/json" } });
    const fail = (status, message) => json({ error: { message } }, status);

    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });

    // TickTick sends the browser back here after you approve access. No Google token on this hop,
    // so it is protected by the one-time state value created by /ticktick/start.
    if (url.pathname === "/ticktick/callback") {
      const state = url.searchParams.get("state");
      const code = url.searchParams.get("code");
      const stateEmail = state && (await store(env).get("tt_state:" + state));
      if (!code || !stateEmail) return new Response("Link expired. Start again from the dashboard.", { status: 400 });
      await store(env).delete("tt_state:" + state);
      const body = new URLSearchParams({ grant_type: "authorization_code", code, redirect_uri: callbackUrl(url), scope: "tasks:read tasks:write" });
      const r = await fetch(TT_TOKEN, {
        method: "POST",
        headers: { Authorization: "Basic " + btoa(String(env.TICKTICK_CLIENT_ID || "").trim() + ":" + String(env.TICKTICK_CLIENT_SECRET || "").trim()), "Content-Type": "application/x-www-form-urlencoded" },
        body,
      });
      if (!r.ok) return new Response("TickTick didn't accept the sign-in: " + (await r.text()), { status: 502 });
      const tok = await r.json();
      await store(env).put(ttKey(stateEmail), tok.access_token);
      await audit(env, stateEmail, "connected TickTick");
      return Response.redirect(env.SITE_URL + "?ticktick=connected", 302);
    }

    // The laptop relay script authenticates with the RELAY_TOKEN secret instead of Google.
    if (url.pathname === "/relay/next" || url.pathname === "/relay/reply" || url.pathname === "/relay/done" || url.pathname === "/relay/anki") {
      const h = req.headers.get("Authorization") || "";
      if (!env.RELAY_TOKEN || h !== "Bearer " + env.RELAY_TOKEN) return fail(401, "bad relay token");
      return withCors(await relay(env).fetch(req), cors);
    }

    // Permanent sign-in: the Worker keeps a Google refresh token (needs the GOOGLE_CLIENT_SECRET secret) and hands the
    // page a fresh one-hour Google access token whenever it presents its long-lived session token.
    if (url.pathname === "/auth/info") return json({ permanent: !!env.GOOGLE_CLIENT_SECRET });
    if (url.pathname === "/auth/start") {
      if (!env.GOOGLE_CLIENT_SECRET) return new Response("Permanent sign-in isn't set up yet (GOOGLE_CLIENT_SECRET).", { status: 501 });
      const state = crypto.randomUUID();
      const client = webClientId(env, url.searchParams.get("client"));
      await store(env).put("au_state:" + state, client, { expirationTtl: 600 });
      const q = new URLSearchParams({
        client_id: client, redirect_uri: url.origin + "/auth/callback", response_type: "code",
        scope: GOOGLE_SCOPES, access_type: "offline", prompt: "consent", include_granted_scopes: "true", state,
      });
      return Response.redirect("https://accounts.google.com/o/oauth2/v2/auth?" + q, 302);
    }
    if (url.pathname === "/auth/callback") {
      const state = url.searchParams.get("state"), code = url.searchParams.get("code");
      const client = state && (await store(env).get("au_state:" + state));
      if (!code || !client) return new Response("Link expired. Start again from the dashboard.", { status: 400 });
      await store(env).delete("au_state:" + state);
      const r = await fetch("https://oauth2.googleapis.com/token", {
        method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ code, client_id: client, client_secret: String(env.GOOGLE_CLIENT_SECRET || "").trim(), redirect_uri: url.origin + "/auth/callback", grant_type: "authorization_code" }),
      });
      if (!r.ok) return new Response("Google didn't accept the sign-in: " + (await r.text()), { status: 502 });
      const tok = await r.json();
      const idp = JSON.parse(atob(String(tok.id_token || "..").split(".")[1].replace(/-/g, "+").replace(/_/g, "/")) || "{}");
      const email = String(idp.email || "").toLowerCase();
      const allowed = String(env.ALLOWED_EMAIL || "").toLowerCase().split(/[\s,]+/).filter(Boolean);
      if (String(idp.email_verified) !== "true" || !allowed.includes(email)) return new Response("This Google account isn't allowed on this dashboard.", { status: 403 });
      if (tok.refresh_token) await store(env).put("rt:" + email, { token: tok.refresh_token, client });
      else if (!(await store(env).get("rt:" + email))) return new Response("Google didn't return a refresh token. Remove Next Up at myaccount.google.com/permissions and sign in again.", { status: 502 });
      const session = "nu_" + [...crypto.getRandomValues(new Uint8Array(32))].map((b) => b.toString(16).padStart(2, "0")).join("");
      await store(env).put("sess:" + (await sha256(session)), { email, at: Date.now() }, { expirationTtl: SESSION_DAYS * 86400 });
      await audit(env, email, "signed in", "stays signed in on this device");
      return Response.redirect(env.SITE_URL + "#nu_session=" + session, 302);
    }
    if (url.pathname === "/auth/token" || url.pathname === "/auth/logout") {
      const h = req.headers.get("Authorization") || "";
      const session = h.startsWith("Bearer nu_") ? h.slice(7) : "";
      const key = session && "sess:" + (await sha256(session));
      const sess = key && (await store(env).get(key));
      if (!sess) return fail(401, "session expired");
      if (url.pathname === "/auth/logout") { await store(env).delete(key); await audit(env, sess.email, "signed out"); return json({ ok: true }); }
      const rt = await store(env).get("rt:" + sess.email);
      const r = rt && (await fetch("https://oauth2.googleapis.com/token", {
        method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ client_id: rt.client, client_secret: String(env.GOOGLE_CLIENT_SECRET || "").trim(), refresh_token: rt.token, grant_type: "refresh_token" }),
      }));
      if (!r || !r.ok) { await store(env).delete(key); return fail(401, "Google sign-in expired. Sign in again."); }
      const tok = await r.json();
      await store(env).put(key, { ...sess, at: Date.now() }, { expirationTtl: SESSION_DAYS * 86400 }); // sliding: stays alive while used
      return json({ access_token: tok.access_token, expires_in: tok.expires_in, email: sess.email });
    }

    // Everything below needs a valid Google sign-in from one of the allowed accounts.
    const who = await checkGoogle(req, env);
    if (who.status) return fail(who.status, who.message);

    try {
      // The owner (first allowed email) gets the values from Worker secrets; everyone else gets the
      // sheet ids they saved from the dashboard. Each person's TickTick sign-in is stored separately.
      if (url.pathname === "/config" && req.method === "GET") {
        const mine = (await store(env).get("user:" + who.email)) || {};
        let links = [], profile = {};
        if (who.owner) {
          try { links = JSON.parse(env.LINKS || "[]"); } catch {}
          try { profile = JSON.parse(env.PROFILE || "{}"); } catch {}
        }
        return json({
          email: who.email,
          owner: who.owner,
          sheetId: mine.sheetId || (who.owner ? env.SHEET_ID || "" : ""),
          questSheetId: mine.questSheetId || (who.owner ? env.QUEST_SHEET_ID || "" : ""),
          links, profile,
          theme: mine.theme || null,
          layout: mine.layout || null,
          claudeApi: !!env.ANTHROPIC_API_KEY,
          relay: who.owner && !!env.RELAY_TOKEN,
          ticktick: !!(await store(env).get(ttKey(who.email))),
        });
      }

      if (url.pathname === "/log" && req.method === "GET") {
        const all = (await (await relay(env).fetch("https://internal/log-get")).json()).log || [];
        return json({ owner: who.owner, log: (who.owner ? all : all.filter((e) => e.email === who.email)).slice(-500).reverse() });
      }

      if (url.pathname === "/settings" && req.method === "POST") {
        const body = await req.json();
        await audit(env, who.email, "changed settings", ["sheetId", "questSheetId", "theme", "layout"].filter((k) => k in body).map((k) => ({ sheetId: "Time Tracker sheet", questSheetId: "XP sheet", theme: "theme", layout: "layout" })[k]).join(", "));
        const mine = (await store(env).get("user:" + who.email)) || {};
        for (const k of ["sheetId", "questSheetId"]) {
          if (!(k in body)) continue;
          const v = String(body[k] || "").trim();
          if (v && !/^[\w-]{20,100}$/.test(v)) return fail(400, "That doesn't look like a Google Sheet id");
          mine[k] = v;
        }
        // Each person's dashboard theme: accent colour and whether deadlines are red.
        if (body.theme && typeof body.theme === "object") {
          const a = String(body.theme.accent || "");
          if (a && !/^#[0-9a-f]{6}$/i.test(a)) return fail(400, "bad colour");
          mine.theme = { accent: a, redDeadlines: body.theme.redDeadlines !== false };
        }
        // Dashboard widget layout: order, widths and hidden panels.
        if (body.layout && typeof body.layout === "object") {
          const ids = (a) => (Array.isArray(a) ? a : []).map(String).filter((x) => /^[\w-]{1,30}$/.test(x)).slice(0, 30);
          const span = {};
          for (const [k, v] of Object.entries(body.layout.span || {})) if (/^[\w-]{1,30}$/.test(k) && [3, 4, 6, 8, 9, 12].includes(+v)) span[k] = +v;
          const h = {};
          for (const [k, v] of Object.entries(body.layout.h || {})) if (/^[\w-]{1,30}$/.test(k) && ["s", "m", "l"].includes(v)) h[k] = v;
          mine.layout = { order: ids(body.layout.order), span, h, hidden: ids(body.layout.hidden) };
        }
        await store(env).put("user:" + who.email, mine);
        return json({ ok: true });
      }

      // Questions for Claude Code on the owner's laptop, and the answers coming back. Owner only:
      // it runs on the owner's Claude plan.
      if (url.pathname === "/relay/ask" || url.pathname === "/relay/answer" || url.pathname === "/relay/status") {
        if (!who.owner) return fail(403, "The laptop relay is only for the dashboard owner");
        return withCors(await relay(env).fetch(req), cors);
      }

      // Anki due counts and review history, last sent by the owner's laptop.
      if (url.pathname === "/anki" && req.method === "GET") {
        if (!who.owner) return json({});
        return withCors(await relay(env).fetch("https://internal/relay/anki"), cors);
      }

      if (url.pathname === "/ticktick/start" && req.method === "POST") {
        const state = crypto.randomUUID();
        await store(env).put("tt_state:" + state, who.email, { expirationTtl: 600 });
        const q = new URLSearchParams({ client_id: String(env.TICKTICK_CLIENT_ID || "").trim(), scope: "tasks:read tasks:write", state, redirect_uri: callbackUrl(url), response_type: "code" });
        return json({ url: `${TT_AUTH}?${q}` });
      }

      if (url.pathname === "/ticktick/tasks" && req.method === "GET") {
        const token = await store(env).get(ttKey(who.email));
        if (!token) return fail(409, "TickTick isn't connected");
        const from = Date.parse(url.searchParams.get("from") || "") || 0;
        const to = Date.parse(url.searchParams.get("to") || "") || Infinity;
        const tt = (path) => ticktick(token, path);
        const projects = (await tt("/project")).filter((p) => !p.closed);
        const ids = ["inbox", ...projects.map((p) => p.id)];
        const datas = await Promise.all(ids.map((id) => tt(`/project/${id}/data`).catch(() => null)));
        const tasks = [];
        for (const d of datas) {
          for (const t of (d && d.tasks) || []) {
            if (t.status !== 0 || !t.dueDate) continue;
            const due = Date.parse(String(t.dueDate).replace(/([+-]\d\d)(\d\d)$/, "$1:$2"));
            if (due >= from && due < to) tasks.push(t);
          }
        }
        return json({ projects: projects.map((p) => ({ id: p.id, name: p.name, color: p.color || "" })), tasks });
      }

      if (url.pathname === "/ticktick/complete" && req.method === "POST") {
        const token = await store(env).get(ttKey(who.email));
        if (!token) return fail(409, "TickTick isn't connected");
        const { projectId, taskId, title, list, tags } = await req.json();
        if (!/^[\w-]+$/.test(String(projectId)) || !/^[\w-]+$/.test(String(taskId))) return fail(400, "bad task id");
        await ticktick(token, `/project/${projectId}/task/${taskId}/complete`, { method: "POST" });
        await audit(env, who.email, "completed a task", title ? `${title}${list ? " (" + list + ")" : ""}` : taskId);
        // The owner's completions are queued for the laptop relay, which marks the matching TODO
        // DONE in the org files.
        if (who.owner && title) {
          await relay(env).fetch("https://internal/relay/done-add", { method: "POST", body: JSON.stringify({ taskId, title: String(title).slice(0, 500), list: String(list || ""), tags: Array.isArray(tags) ? tags.map(String) : [] }) });
        }
        return json({ ok: true });
      }

      if (url.pathname === "/claude" && req.method === "POST") {
        if (!env.ANTHROPIC_API_KEY) return fail(501, "No Claude API key on the server");
        const { system, messages, tools } = await req.json();
        if (!Array.isArray(messages) || !messages.length) return fail(400, "messages required");
        const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY });
        const msg = await client.beta.messages.create({
          model: MODEL,
          max_tokens: 4000,
          system: String(system || "").slice(0, 60000),
          messages,
          tools: Array.isArray(tools) ? tools : undefined,
          output_config: { effort: "low" },
          // On a safety decline, let the API retry on its recommended fallback model.
          betas: ["server-side-fallback-2026-07-01"],
          fallbacks: "default",
        });
        return json({ content: msg.content, stop_reason: msg.stop_reason });
      }

      return fail(404, "not found");
    } catch (e) {
      if (e instanceof Anthropic.RateLimitError) return fail(429, "Claude is rate limited. Try again in a minute.");
      if (e instanceof Anthropic.AuthenticationError) return fail(502, "The Claude API key on the server is invalid.");
      if (e instanceof Anthropic.APIError) return fail(502, "Claude API error: " + e.message);
      if (e && e.status === 401) {
        await store(env).delete(ttKey(who.email));
        return fail(409, "TickTick sign-in expired");
      }
      return fail(502, (e && e.message) || "server error");
    }
  },
};

function withCors(res, cors) {
  const r = new Response(res.body, res);
  for (const [k, v] of Object.entries(cors)) r.headers.set(k, v);
  return r;
}

const relay = (env) => env.RELAY.get(env.RELAY.idFromName("relay"));

// Small key-value store (TickTick token, sign-in state) kept in the same Durable Object.
// Activity log: who did what and when (sign-ins, settings, TickTick, completed tasks). Kept in the
// Durable Object, newest 2000 entries.
async function audit(env, email, action, detail = "") {
  try { await relay(env).fetch("https://internal/log-add", { method: "POST", body: JSON.stringify({ email, action, detail: String(detail).slice(0, 300) }) }); } catch {}
}

function store(env) {
  const op = async (body) => (await (await relay(env).fetch("https://internal/_kv", { method: "POST", body: JSON.stringify(body) })).json()).value;
  return {
    get: (key) => op({ op: "get", key }),
    put: (key, value, opts = {}) => op({ op: "put", key, value, ttl: opts.expirationTtl }),
    delete: (key) => op({ op: "delete", key }),
  };
}

// One Durable Object holds the question queue, so the phone and the laptop always see the same state.
// Questions expire after 3 minutes, answers after 10.
export class Relay {
  constructor(ctx) { this.ctx = ctx; }
  async fetch(req) {
    const url = new URL(req.url);
    const st = this.ctx.storage;
    const now = Date.now();
    const json = (d, status = 200) => new Response(JSON.stringify(d), { status, headers: { "Content-Type": "application/json" } });
    const queue = ((await st.get("queue")) || []).filter((q) => now - q.at < 180e3);

    if (url.pathname === "/_kv") {
      const { op, key, value, ttl } = await req.json();
      const k = "kv:" + key;
      if (op === "put") { await st.put(k, { v: value, exp: ttl ? now + ttl * 1000 : 0 }); return json({}); }
      if (op === "delete") { await st.delete(k); return json({}); }
      const e = await st.get(k);
      if (e && e.exp && e.exp < now) { await st.delete(k); return json({ value: null }); }
      return json({ value: e ? e.v : null });
    }

    if (url.pathname === "/log-add" && req.method === "POST") {
      const e = await req.json(); const log = (await st.get("log")) || [];
      log.push({ at: now, email: String(e.email || ""), action: String(e.action || ""), detail: String(e.detail || "") });
      await st.put("log", log.slice(-2000)); return json({ ok: true });
    }
    if (url.pathname === "/log-get") return json({ log: (await st.get("log")) || [] });

    if (url.pathname === "/relay/status") return json({ online: now - ((await st.get("seen")) || 0) < 30e3 });

    if (url.pathname === "/relay/ask" && req.method === "POST") {
      const { prompt } = await req.json();
      if (!prompt || String(prompt).length > 40000) return json({ error: { message: "bad prompt" } }, 400);
      const id = crypto.randomUUID();
      queue.push({ id, prompt: String(prompt), at: now });
      await st.put("queue", queue.slice(-10));
      return json({ id });
    }

    if (url.pathname === "/relay/answer") {
      const id = url.searchParams.get("id") || "";
      const a = await st.get("a:" + id);
      if (a) return json({ state: "done", text: a.text, error: a.error || "" });
      if (queue.some((q) => q.id === id)) return json({ state: "queued" });
      if ((await st.get("taken")) === id) return json({ state: "working" });
      return json({ state: "gone" });
    }

    // Tasks completed on the dashboard, waiting for the laptop to mark them DONE in the org files.
    if (url.pathname === "/relay/done-add" && req.method === "POST") {
      const d = await req.json();
      const done = (await st.get("done")) || [];
      done.push({ ...d, at: now });
      await st.put("done", done.slice(-200));
      return json({ ok: true });
    }
    if (url.pathname === "/relay/done") {
      const done = (await st.get("done")) || [];
      if (req.method === "POST") {
        // The laptop confirms which ones it handled.
        const { ids } = await req.json();
        await st.put("done", done.filter((d) => !(ids || []).includes(d.taskId)));
        return json({ ok: true });
      }
      return json({ done });
    }

    // Anki snapshot from the laptop (due counts per deck and reviews per day).
    if (url.pathname === "/relay/anki") {
      if (req.method === "POST") { await st.put("anki", { ...(await req.json()), at: now }); return json({ ok: true }); }
      return json((await st.get("anki")) || {});
    }

    if (url.pathname === "/relay/next") {
      await st.put("seen", now);
      const q = queue.shift();
      await st.put("queue", queue);
      if (q) await st.put("taken", q.id);
      return json(q ? { id: q.id, prompt: q.prompt } : {});
    }

    if (url.pathname === "/relay/reply" && req.method === "POST") {
      const { id, text, error } = await req.json();
      await st.put("a:" + id, { text: String(text || ""), error: String(error || ""), at: now });
      await st.delete("taken");
      // Drop answers older than 10 minutes.
      for (const [k, v] of await st.list({ prefix: "a:" })) if (now - v.at > 600e3) await st.delete(k);
      return json({ ok: true });
    }
    return json({ error: { message: "not found" } }, 404);
  }
}

const GOOGLE_SCOPES = "openid email https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/spreadsheets";
const SESSION_DAYS = 180;
// The web client for the code flow: the one the page asks for if it is allowed, else GOOGLE_WEB_CLIENT_ID or the first allowed client.
const webClientId = (env, wanted) => {
  const list = String(env.GOOGLE_CLIENT_ID || "").split(/[\s,]+/).filter(Boolean);
  return list.includes(wanted) ? wanted : String(env.GOOGLE_WEB_CLIENT_ID || list[0] || "").trim();
};
async function sha256(text) {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)))].map((b) => b.toString(16).padStart(2, "0")).join("");
}

const ttKey = (email) => "tt_token:" + email;

function callbackUrl(url) {
  return url.origin + "/ticktick/callback";
}

async function ticktick(token, path, opts = {}) {
  const r = await fetch(TT_API + path, { ...opts, headers: { Authorization: "Bearer " + token, ...(opts.headers || {}) } });
  if (!r.ok) { const e = new Error(`TickTick ${r.status}`); e.status = r.status; throw e; }
  const text = await r.text();
  return text ? JSON.parse(text) : null;
}

// Validates the Google access token and returns the signed-in email, or {status, message}.
async function checkGoogle(req, env) {
  const h = req.headers.get("Authorization") || "";
  const token = h.startsWith("Bearer ") ? h.slice(7) : "";
  if (!token) return { status: 401, message: "sign in required" };
  const r = await fetch("https://oauth2.googleapis.com/tokeninfo?access_token=" + encodeURIComponent(token));
  if (!r.ok) return { status: 401, message: "sign-in expired" };
  const info = await r.json();
  // GOOGLE_CLIENT_ID may list several clients (web, Android, iOS), comma-separated.
  const clients = String(env.GOOGLE_CLIENT_ID || "").split(/[\s,]+/).filter(Boolean);
  if (!clients.includes(info.aud) && !clients.includes(info.azp)) return { status: 401, message: "token is for another app" };
  const allowed = String(env.ALLOWED_EMAIL || "").toLowerCase().split(/[\s,]+/).filter(Boolean);
  const email = String(info.email || "").toLowerCase();
  if (String(info.email_verified) !== "true" || !allowed.includes(email)) {
    return { status: 403, message: "this account isn't allowed" };
  }
  return { email, owner: email === allowed[0] };
}
