# Next Up on the web (Flutter)

The Flutter version of the website. It is published at `/next-up-dashboard/beta/` next to the current
site, which stays at the root, so nothing breaks while pages move over one by one.

Now:
- **Dashboard**: clock and day progress, next deadline with a flip-clock countdown, Now and next from
  Google Calendar, a focus timer with a dial, a 7-day strip (booked hours and deadlines per day), and
  all deadlines grouped as overdue, today, this week and later (finish one with the circle or by
  swiping). Each panel loads on its own, so a calendar problem never hides the deadlines.
- **Track**: tap what you are doing; a day timeline next to your calendar plan; totals against daily and
  weekly targets (confetti when you hit one); add, edit and delete blocks. Stored in the Tracked tab of
  your Time Tracker sheet, the same place the current site uses.
- **Adherence**: this week's adherence numbers, courses, days and types, plus **Rate your blocks** from
  the Log tab.
- **Settings**: paste your Time Tracker and XP Tracker sheet links (saved with the Worker, shared with
  the current site).
- **Deadlines**: the same list as the phone app's Today tab.
- A side rail on wide screens and a bottom bar on narrow ones; a link opens the current site for
  everything else (Track, Adherence, Rate, Quest Log, Ask Claude, Anki, habits). The theme, deadline model and Today screen come from `../core`,
shared with the phone app.

Sign-in uses Google's pop-up (same web client and Worker as the current site), so it only works on the
real site, not on `localhost`.

```sh
cd webapp
flutter pub get
flutter test
flutter build web --release --no-web-resources-cdn --base-href /next-up-dashboard/beta/
```

`.github/workflows/site.yml` builds it on every push to `main`.
