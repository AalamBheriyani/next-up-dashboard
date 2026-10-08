# Next Up

A personal departures-board dashboard: next deadline countdown, the calendar block you're in,
TickTick tasks with live countdowns, Weekly Time Tracker hours, a Time Timer style focus dial
and an Ask Claude chat. Works on phone, iPad and laptop (add it to your home screen).

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
1. Create a project at https://console.cloud.google.com/.
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

### 4. Claude API key
Create a key at https://console.anthropic.com/settings/keys. Chat usage is billed to that API
account, separately from a Claude.ai subscription.

### 5. Deploy the Worker (Cloudflare)
```sh
cd worker
npm install
npx wrangler login
npx wrangler kv namespace create NEXTUP_KV     # paste the id into wrangler.toml
# edit wrangler.toml: WORKER_URL (your workers.dev subdomain), GOOGLE_CLIENT_ID
npx wrangler secret put ALLOWED_EMAIL          # the Google account allowed to sign in
npx wrangler secret put SHEET_ID               # Weekly Time Tracker spreadsheet id
npx wrangler secret put TICKTICK_CLIENT_ID
npx wrangler secret put TICKTICK_CLIENT_SECRET
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put PROFILE                # optional, JSON: {"name":"...","place":"...","wake":"06:35","windDown":"21:55","sleep":"22:35","rules":"..."}
npx wrangler secret put LINKS                  # optional, JSON: [{"name":"Quest Log","note":"log XP","url":"https://..."}]
npx wrangler deploy
```

### 6. Point the site at it
Edit `docs/config.js` with the Google client ID and the Worker URL, commit, push.

### 7. First run
Open the site, **Sign in with Google**, then press **Connect TickTick** on the task board once.

## What runs where

| Feature | Data source | Path |
|---|---|---|
| Deadlines board, Done button | TickTick | browser → Worker → TickTick Open API |
| Now / next block | Google Calendar (primary) | browser → Google |
| Hours this week, Rate your blocks | Weekly Time Tracker sheet | browser → Google Sheets |
| Ask Claude | Claude API (`claude-opus-5-5`) | browser → Worker → Claude API |
| Focus timer | none (stored in the browser) | browser only |

## License

MIT, see [LICENSE](LICENSE).
