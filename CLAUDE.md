# CLAUDE.md: guide for AI assistants working on Next Up

Read this first. It is the map of the project for Claude (or any coding assistant) helping
Aalam or Aaliya. Humans: see README.md (what it is, setup) and CONTRIBUTING.md (how we work).

## What this is

Next Up is a personal planning dashboard: next deadline countdown, today's calendar, TickTick tasks
("Departures"), Track (time tracking), focus timer, habit and Anki heatmaps, Ask Claude, adherence
from a Google Sheet. Two people use it (Aalam = owner, Aaliya), each with their own data.

- Live site: https://aalambheriyani.github.io/next-up-dashboard/ (GitHub Pages, built by
  `.github/workflows/site.yml`)
- Server: Cloudflare Worker `next-up-dashboard` at https://next-up-dashboard.aalambheriyani.workers.dev
  (Cloudflare builds and deploys `worker/` on every push to `main`)
- The repo is **public**. Never commit personal data: emails other than in docs examples, sheet ids,
  tokens, secrets, calendar contents.

## Repo map

| Path | What | Notes |
|---|---|---|
| `docs/index.html` | The whole dashboard: HTML, CSS (one `<style>`), JS (one IIFE `<script>` at the end) | ~2400 lines. No build step, no framework. |
| `docs/quest.html`, `docs/xp.js` | Quest Log (XP) page and the shared XP writer | XP goes to the user's XP Tracker sheet |
| `docs/config.js` | Public config: Google web client id, Worker URL | Not secret |
| `worker/src/index.js` | Cloudflare Worker: auth, per-user settings, TickTick proxy, relay queue, activity log | One file. Durable Object class `Relay` holds all state |
| `worker/wrangler.toml` | Worker config | `keep_vars = true`; secrets live in the Cloudflare dashboard |
| `relay/laptop.mjs`, `relay/org-done.mjs` | Runs on Aalam's laptop (systemd user service `nextup-relay`) | Answers Ask Claude with Claude Code, sends Anki stats, marks org TODOs DONE |
| `app/` | Flutter app (Android/iOS): native Google sign-in + notifications around the website in a web view | Built by `.github/workflows/app.yml` |
| `scripts/build-site.sh` | Builds Pages output: latest at `/`, every tag at `/v/<tag>/` | Called by site.yml |

## How `docs/index.html` is organised

The script is split by banner comments; search for them:
`time helpers`, `data shaping`, `errors`, `rendering`, `sign-in (Google) and data access`, `actions`,
`timer`, `Claude chat`, `Track`, `loading`, `Time Tracker sheet`, `widgets`.

Key ideas:
- `$(id)` is `document.getElementById`; `el(tag, class, text)` creates elements.
- `S` holds loaded data (tasks, events, sheet rows); `render*()` functions redraw from `S`.
- `api.*` wraps every network call; `http()` adds the Google token and refreshes it if needed.
- Pages are hash routes handled by `route()`: `#` Dashboard, `#departures`, `#hours` (Adherence),
  `#rate`, `#log` (Activity). Each page is a `<div id="...View" class="widgets">`.
- **Widgets:** every panel is a direct child of a `.widgets` container with `data-w="<id>"` and
  `data-name`. Layout (order, width span 3/4/6/8/9/12, height s/m/l, hidden) is per user, saved via
  `/settings`. Defaults: `WDEF` in the widgets section. A new panel needs a unique `data-w` and an entry
  in `WDEF`.
- **CSS:** one `<style>` block; later rules override earlier ones. Many tweaks are appended near the end.
  When a style "doesn't apply", look for a later rule with the same selector.
- **Theme:** CSS variables on `:root`; `--accent` (user's colour) and `--dl` (deadline colour, red by
  default). Saved per user. `<meta name="darkreader-lock">` keeps the Dark Reader extension off.

## The Worker (`worker/src/index.js`)

Every route except the auth/relay/callback ones requires a Google access token (`checkGoogle`), and the
email must be in `ALLOWED_EMAIL` (comma list; first email = owner).

Routes: `/config` (per-user settings + feature flags), `/settings` (save sheets/theme/layout),
`/ticktick/start|callback|tasks|complete`, `/claude` (only with `ANTHROPIC_API_KEY`), `/anki`, `/log`
(activity), `/auth/start|callback|token|logout|info` (permanent sign-in), `/relay/*` (laptop relay,
authenticated with `RELAY_TOKEN`).

State lives in the `Relay` Durable Object through `store(env)` (a small key/value API) with key
prefixes: `user:<email>` (settings), `tt_token:<email>`, `sess:<hash>` (sign-in sessions),
`rt:<email>` (Google refresh token), `au_state:`/`tt_state:` (one-time OAuth states), plus `log`,
`anki` and the relay queue.

Secrets and variables (Cloudflare → Worker → Settings → Variables and secrets, never in the repo):
`GOOGLE_CLIENT_ID` (text, comma list: web, Android, iOS), `GOOGLE_CLIENT_SECRET`, `ALLOWED_EMAIL`,
`SHEET_ID`, `QUEST_SHEET_ID` (owner defaults), `TICKTICK_CLIENT_ID`, `TICKTICK_CLIENT_SECRET`,
`RELAY_TOKEN`, optional `ANTHROPIC_API_KEY`, `PROFILE`, `LINKS`. `SITE_URL` is in wrangler.toml.

## Per-user data

Everything personal is keyed by the signed-in email: sheets (⚙ → My sheets), TickTick connection,
theme, widget layout. Owner-only: Ask Claude via the laptop relay, Anki, Done → org-file sync.
Browser `localStorage` keys (`nu.*`, `nextup.*`, `xp.*`, `track.*`) are only caches or per-device
conveniences.

## Workflow rules

1. `git pull` before starting; small, focused commits; first line says what the user will notice.
2. Aaliya (and her Claude): work on a branch, push, open a pull request; `main` requires one approving
   review. The owner may push to `main` directly.
3. Every merge to `main` creates a version tag `v0.x.y` and a GitHub Release (patch by default; put
   `[minor]` or `[major]` in a commit message). Old versions stay at `/next-up-dashboard/v/`.
4. Test in a browser before pushing: serve `docs/` locally (`python3 -m http.server 8799` in `docs/`)
   for layout; sign-in only works on the real site (Google allows the github.io origin only).
5. After a push, Pages deploys in ~1 minute (`gh run list -w Site`); the Worker deploys from Cloudflare
   Builds. Hard-refresh (Ctrl+Shift+R) to see changes.
6. Never put secrets or personal data in commits, issues or PR text. Never change Cloudflare secrets
   for the user; tell them what to set.
7. Keep the code style: plain DOM JS, short comments explaining why, no new libraries or build tools
   without agreement.

## Logs and history

- Activity tab (`#log`): sign-ins, settings/layout changes, TickTick connections, completed tasks
  (Worker `audit()`), plus recent commits from GitHub.
- Cloudflare Workers Logs (`[observability]` in wrangler.toml): requests and errors, 7 days.
- `git log`, GitHub Releases, and every old version at `/v/`.
