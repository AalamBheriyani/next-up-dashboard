# Next Up on the web (Flutter)

The Flutter version of the website. It is published at `/next-up-dashboard/beta/` next to the current
site, which stays at the root, so nothing breaks while pages move over one by one.

Now:
- **Dashboard**: clock and day progress, next deadline with a flip-clock countdown, Now and next from
  Google Calendar, a focus timer with a dial, a 7-day strip (booked hours and deadlines per day), and
  all deadlines grouped as overdue, today, this week and later (finish one with the circle or by
  swiping). Each panel loads on its own, so a calendar problem never hides the deadlines.
- **Departures**: the same list as the phone app's Today tab.
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
