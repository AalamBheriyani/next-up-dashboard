# Current look (October 2026)

A frozen reference of how the Next Up website looked before the Flutter redesign, so the old design
can be compared with or rebuilt later. Nothing here is served or built; the live site is `docs/`.

## Files

| File | What |
|---|---|
| `index.html.snapshot` | The whole dashboard page (HTML, CSS, JS) at commit `b9ae1e8` |
| `quest.html.snapshot` | The Quest Log page at the same commit |
| `flutter-redesign-proposal.html` | The proposed Flutter app design (three screens, feature ideas). Open it in a browser |

Every released version of the site also stays usable at `/next-up-dashboard/v/`, which shows the
working page. This folder keeps the source next to the redesign work.

## Design summary

- **Concept:** a departures board. The next deadline is a large countdown; tasks are "departures".
- **Theme:** one dark theme. Black background (`#000000`), panels `#0b0b0d`, white text, blue accent
  (`--accent: #4d8dff`, picked per user), red for deadlines (`--dl: #ff3b3b`), green for done
  (`#3ddc84`). Surfaces separate by tint, not outlines.
- **Type:** Big Shoulders Display for the clock and headings, IBM Plex Sans for text, IBM Plex Mono
  for labels and numbers (tabular figures).
- **Layout:** a header with the clock and day progress, then draggable, resizable widgets (spans 3 to
  12, heights s/m/l) on pages Dashboard, Departures, Adherence and Rate. Layout is saved per user.
- **Panels:** next deadline, today's calendar, TickTick departures, Track, focus timer with a dial,
  hours and adherence, Anki heatmap, Ask Claude.

No personal data is stored here.
