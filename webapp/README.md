# Next Up on the web (Flutter)

The Flutter version of the website. It is published at `/next-up-dashboard/beta/` next to the current
site, which stays at the root, so nothing breaks while pages move over one by one.

Now: the Today page (next-deadline countdown, overdue, today, this week, later; finish a deadline),
with a side rail on wide screens and a bottom bar on narrow ones. A link in the rail opens the
current site for everything else. The theme, deadline model and Today screen come from `../core`,
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
