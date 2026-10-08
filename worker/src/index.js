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
      if (!state || !code || !(await env.NEXTUP_KV.get("tt_state:" + state))) return new Response("Link expired. Start again from the dashboard.", { status: 400 });
      await env.NEXTUP_KV.delete("tt_state:" + state);
      const body = new URLSearchParams({ grant_type: "authorization_code", code, redirect_uri: callbackUrl(env), scope: "tasks:read tasks:write" });
      const r = await fetch(TT_TOKEN, {
        method: "POST",
        headers: { Authorization: "Basic " + btoa(env.TICKTICK_CLIENT_ID + ":" + env.TICKTICK_CLIENT_SECRET), "Content-Type": "application/x-www-form-urlencoded" },
        body,
      });
      if (!r.ok) return new Response("TickTick didn't accept the sign-in: " + (await r.text()), { status: 502 });
      const tok = await r.json();
      await env.NEXTUP_KV.put("tt_token", tok.access_token);
      return Response.redirect(env.SITE_URL + "?ticktick=connected", 302);
    }

    // The laptop relay script authenticates with the RELAY_TOKEN secret instead of Google.
    if (url.pathname === "/relay/next" || url.pathname === "/relay/reply") {
      const h = req.headers.get("Authorization") || "";
      if (!env.RELAY_TOKEN || h !== "Bearer " + env.RELAY_TOKEN) return fail(401, "bad relay token");
      return withCors(await relay(env).fetch(req), cors);
    }

    // Everything below needs a valid Google sign-in from the allowed account.
    const who = await checkGoogle(req, env);
    if (who.status) return fail(who.status, who.message);

    try {
      if (url.pathname === "/config" && req.method === "GET") {
        let links = [];
        try { links = JSON.parse(env.LINKS || "[]"); } catch {}
        let profile = {};
        try { profile = JSON.parse(env.PROFILE || "{}"); } catch {}
        return json({ email: who.email, sheetId: env.SHEET_ID || "", questSheetId: env.QUEST_SHEET_ID || "", links, profile, claudeApi: !!env.ANTHROPIC_API_KEY, relay: !!env.RELAY_TOKEN, ticktick: !!(await env.NEXTUP_KV.get("tt_token")) });
      }

      // Questions for Claude Code on the laptop, and the answers coming back.
      if (url.pathname === "/relay/ask" || url.pathname === "/relay/answer" || url.pathname === "/relay/status") {
        return withCors(await relay(env).fetch(req), cors);
      }

      if (url.pathname === "/ticktick/start" && req.method === "POST") {
        const state = crypto.randomUUID();
        await env.NEXTUP_KV.put("tt_state:" + state, "1", { expirationTtl: 600 });
        const q = new URLSearchParams({ client_id: env.TICKTICK_CLIENT_ID, scope: "tasks:read tasks:write", state, redirect_uri: callbackUrl(env), response_type: "code" });
        return json({ url: `${TT_AUTH}?${q}` });
      }

      if (url.pathname === "/ticktick/tasks" && req.method === "GET") {
        const token = await env.NEXTUP_KV.get("tt_token");
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
        return json({ projects: projects.map((p) => ({ id: p.id, name: p.name })), tasks });
      }

      if (url.pathname === "/ticktick/complete" && req.method === "POST") {
        const token = await env.NEXTUP_KV.get("tt_token");
        if (!token) return fail(409, "TickTick isn't connected");
        const { projectId, taskId } = await req.json();
        if (!/^[\w-]+$/.test(String(projectId)) || !/^[\w-]+$/.test(String(taskId))) return fail(400, "bad task id");
        await ticktick(token, `/project/${projectId}/task/${taskId}/complete`, { method: "POST" });
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
        await env.NEXTUP_KV.delete("tt_token");
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

function callbackUrl(env) {
  return env.WORKER_URL.replace(/\/$/, "") + "/ticktick/callback";
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
  if (info.aud !== env.GOOGLE_CLIENT_ID && info.azp !== env.GOOGLE_CLIENT_ID) return { status: 401, message: "token is for another app" };
  if (String(info.email_verified) !== "true" || String(info.email).toLowerCase() !== String(env.ALLOWED_EMAIL).toLowerCase()) {
    return { status: 403, message: "this account isn't allowed" };
  }
  return { email: info.email };
}
