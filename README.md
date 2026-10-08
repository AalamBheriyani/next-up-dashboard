# Next Up

A personal departures-board dashboard: next deadline countdown, the calendar block you're in,
TickTick tasks with live countdowns, Weekly Time Tracker hours, a Pomodoro timer with a Time Timer
style dial (finished pomodoros and breaks log XP automatically), the Quest Log XP tracker and an
Ask Claude chat. Works on phone, iPad and laptop (add it to your home screen).

## How it fits together

- `docs/` is the website, served by **GitHub Pages**. It holds code only, no personal data.
- **Sign in with Google** gives the page a short-lived token to read your Google Calendar and
  read/write your Time Tracker sheet directly from the browser.
- `worker/` is a small **Cloudflare Worker** (free plan). It keeps the secrets the browser must
  never see: the TickTick app secret and token, and the Claude API key. It accepts a request only
  when it carries a Google sign-in for the one email address you allow.

Your email, sheet id, routine and private links live in Worker secrets, not in this repo.

## One-time setup

### 1. GitHub Pages
Repo **Settings → Pages → Build and deployment**: Source *Deploy from a branch*, branch `main`,
folder `/docs`. The site appears at https://aalambheriyani.github.io/next-up-dashboard/.

### 2. Google sign-in (Google Cloud Console)
1. Create a project at https://console.cloud.google.com/. Google Cloud requires 2-step
   verification on the account first; turn it on at https://myaccount.google.com/signinoptions/twosv.
2. **APIs & Services → Library**: enable *Google Calendar API* and *Google Sheets API*.
3. **OAuth consent screen**: External, app name "Next Up", add yourself as a **test user**.
   Leave it in *Testing*; only test users can sign in.
4. **Credentials → Create credentials → OAuth client ID → Web application**.
   Authorized JavaScript origin: `https://aalambheriyani.github.io` (no path).
5. Copy the client ID.

### 3. TickTick app
1. Go to https://developer.ticktick.com/manage and create an app.
2. Redirect URL: `https://next-up-dashboard.<your-subdomain>.workers.dev/ticktick/callback`.
3. Copy the client ID and client secret.

### 4. Ask Claude: laptop relay (free) or API key (paid)
**Laptop relay (recommended).** Questions typed on the dashboard, from any device, are answered by
Claude Code on your laptop, on your Claude plan. Claude can still mark tasks done and start the timer.
1. Install Claude Code on the laptop and sign in once (`claude`).
2. Set a long random `RELAY_TOKEN` Worker secret (step 5).
3. Copy `relay/config.example.json` to `relay/config.json` and fill in the Worker URL and token.
4. Optional: list your org files under `"orgFiles"` in `relay/config.json`. Tasks you tick off
   with the dashboard's **Done** button are then marked DONE (with a CLOSED timestamp) in the org
   heading with the same title, once a minute. If `claude` isn't on your PATH, set `"claudeBin"`.
5. Run `node relay/laptop.mjs` and leave it running (Node 18+). To start it at login, add it to
   macOS Login Items / launchd or Windows Task Scheduler.

When the laptop is off, **Ask Claude** opens a new chat in the Claude app or claude.ai with your
tasks and calendar filled in, running on your Claude plan and its TickTick/Calendar connectors.
To chat inside the page instead, create a key at https://console.anthropic.com/settings/keys and
set the `ANTHROPIC_API_KEY` secret; the page switches over by itself. API usage is billed
separately from a Claude.ai subscription.

### 5. Deploy the Worker (Cloudflare)
No terminal needed. In the Cloudflare dashboard: **Workers & Pages → Create → Import a repository**,
pick this repo, then set root directory `worker`, build command empty, deploy command
`npx wrangler deploy`, and turn off non-production builds. Every push to `main` redeploys it.

Then open the Worker → **Settings → Variables and Secrets** and add:

| Name | Type | Value |
|---|---|---|
| `GOOGLE_CLIENT_ID` | Text | the OAuth client ID from step 2 |
| `ALLOWED_EMAIL` | Secret | Google accounts allowed to sign in, comma-separated; the first is the owner |
| `SHEET_ID` | Secret | Weekly Time Tracker spreadsheet id |
| `QUEST_SHEET_ID` | Secret | XP Tracker (Quest Log) spreadsheet id |
| `TICKTICK_CLIENT_ID`, `TICKTICK_CLIENT_SECRET` | Secret | from step 3 |
| `RELAY_TOKEN` | Secret | a long random string, also put in `relay/config.json` |
| `ANTHROPIC_API_KEY` | Secret | optional, paid; replaces the laptop relay |
| `PROFILE` | Secret | optional JSON: `{"name":"...","place":"...","wake":"06:35","windDown":"21:55","sleep":"22:35","rules":"..."}` |
| `LINKS` | Secret | optional JSON: `[{"name":"Quest Log","note":"log XP","url":"https://..."}]` |

(Or from a terminal: `cd worker && npm install && npx wrangler login && npx wrangler secret put NAME`
for each, then `npx wrangler deploy`.)

If **Settings** says *Variables cannot be added to a Worker that only has static assets*, the root
directory is wrong (it deployed the repo root and found `docs/`). Set it to `worker`, then
**Deployments → Retry build**: changing build settings doesn't rebuild by itself. The log should list
`env.RELAY (Relay) Durable Object`. You can paste a `.env` file into the first *Key* box of
**Add variable**; empty lines are skipped, so add any blank ones later. Keep that file out of the repo.

### 6. Point the site at it
Edit `docs/config.js` with the Google client ID and the Worker URL, commit, push.

### 7. First run
Open the site, **Sign in with Google**, then press **Connect TickTick** on the task board once.
Google shows *"hasn't verified this app"*: press Continue (normal in Testing). *Error 403:
access_denied* means the account isn't on the test-user list yet; check it under
**Google Auth Platform → Audience → Test users** (the Save button there sometimes needs a second click).

## More than one person
Add each person's Gmail to `ALLOWED_EMAIL` and as a **test user** on the Google consent screen.
Everyone sees their own data: their Google Calendar, their own TickTick (each presses Connect
TickTick once), and the sheets they set under **My sheets**. The owner's sheet ids, profile and links
come from the Worker secrets; the laptop relay answers only the owner, and other people's
Ask Claude opens their own Claude app.

## Versions

Every push to `main` is published as a new version: a git tag (`v1.0.0`, `v1.0.1`, …) with a
GitHub Release listing the changes. Patch bumps by default; put `[minor]` or `[major]` in a commit
message to bump that part. The site keeps every version: open
<https://aalambheriyani.github.io/next-up-dashboard/v/> and pick one, or go straight to
`/next-up-dashboard/v/v1.2.3/`. Old versions use today's Worker and sheets, so very old ones may not
match newer data. The current version shows under the ⚙ menu.

Pages is deployed by `.github/workflows/site.yml` (repo Settings → Pages → Source: GitHub Actions).

## Roadmap

- **Track** (in the spirit of [Timelines](https://timelines.app/)): one-tap category timers, a day
  timeline of planned vs actual, edit or add blocks afterwards, pie and trend stats, daily and weekly
  targets with confetti. Blocks are stored as rows in a `Log` tab of the Time Tracker sheet, categories
  and targets in a `Categories` tab, so plan-vs-actual comes from tracked time.
- **Zen garden focus mode** and a **website blocker** for a chosen number of hours.
- **Flutter app**, later. The Worker, sheets, TickTick and relay stay as they are; Flutter replaces
  `docs/`. Needs iOS and Android OAuth clients (the Worker would accept several client ids), a Mac
  or a cloud macOS runner for iOS builds, and an Apple Developer account for TestFlight. Native
  extras worth it: home-screen widget, notifications, lock-screen timer. An Apple Watch app would
  be separate SwiftUI. Flutter's web build could replace this site too.

## What runs where

| Feature | Data source | Path |
|---|---|---|
| Deadlines board, Done button | TickTick | browser → Worker → TickTick Open API |
| Now / next block | Google Calendar (primary) | browser → Google |
| Hours this week, Rate your blocks | Weekly Time Tracker sheet | browser → Google Sheets |
| Ask Claude | Claude Code on your laptop (free), else a new Claude tab; Claude API (`claude-opus-5-5`) if a key is set | browser → Worker → laptop relay, or → Claude API |
| Focus timer | settings stored in the browser | browser only |
| Quest Log (`quest.html`), pomodoro XP | XP Tracker sheet | browser → Google Sheets |

## License

MIT, see [LICENSE](LICENSE).
