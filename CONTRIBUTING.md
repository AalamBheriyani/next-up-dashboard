# Working on Next Up together

> Using Claude or another AI assistant? Point it at [CLAUDE.md](CLAUDE.md) first: it has the code map, routes, data model and rules.

Next Up is built by Aalam and Aaliya. Each of you has your own dashboard (same site, separate data),
and every change to the site is reviewed, versioned and logged.

## Your own dashboard

Sign in at <https://aalambheriyani.github.io/next-up-dashboard/> with your Google account. Everything
personal is saved to your account on the Worker, keyed by your email, so it never mixes with the other
person's:

- **My sheets** (⚙): your Time Tracker and XP Tracker spreadsheets
- **Connect TickTick**: your own tasks
- **Theme** (⚙ accent colour, red deadlines) and **layout** (Customise: move, resize, hide panels)

To add a person: put their Gmail in the Worker's `ALLOWED_EMAIL` (comma-separated, owner first) and as a
test user on the Google consent screen.

## Making changes

1. Pull first: `git pull` in your clone.
2. Make a branch: `git switch -c short-description`.
3. Commit small, clear changes. The first line says what changes for the person using the dashboard.
4. Push and open a pull request: `git push -u origin short-description`, then **Create pull request**
   on GitHub. Fill in the template.
5. The other person reviews and approves; then merge. `main` only changes through reviewed pull requests
   (the repo owner can still push directly for quick fixes).

Checks run on every pull request: the phone app builds for Android and iOS. Keep personal data
(emails, sheet ids, tokens) out of the repo: it is public. Secrets live in the Cloudflare Worker settings.

## Versions and history

- Every merge to `main` becomes a version (`v0.x.y`) with a GitHub Release listing the changes.
  Put `[minor]` or `[major]` in a commit message to bump that part.
- Every version stays usable at `/next-up-dashboard/v/` (pick one), so a change can always be compared
  with or rolled back to an earlier version.
- `git log` and GitHub Releases show what changed and who changed it.

## Local development

The site is plain HTML/JS in `docs/` (open it with any static server). The Worker is in `worker/`
(deployed automatically by Cloudflare from `main`). The phone app is in `app/` (Flutter). The laptop
relay (Ask Claude via Claude Code, Anki, org files) is in `relay/`.
