# Next Up app (Android and iOS)

A Flutter app that shows the Next Up dashboard (the GitHub Pages site) full screen, and does natively
what a web page can't do well:

- **Google sign-in.** Google blocks sign-in inside embedded web views, so the app signs in with the
  native Google SDK and hands the page an access token.
- **Timer notifications.** When a pomodoro or break ends you get a notification, even with the app closed.
- **Links** to other sites (TickTick web, Calendar, Claude) open in the browser.

Everything else (tasks, Track, Quest Log, Ask Claude) is the same page as the website, so changes to
`docs/` show up in the app without a new build.

## Install on Android

Every push to `main` that touches `app/` builds a signed APK and attaches it to the
[app-latest release](../../releases/tag/app-latest). On the phone, open that page, download
`next-up.apk`, and allow installs from your browser when asked.

## iOS

CI checks that the iOS app builds. Installing it on an iPhone or iPad needs an Apple Developer
account (US$99/year, for TestFlight) or a Mac with Xcode and a free account (the app expires after 7 days).

## One-time setup

1. **Android signing:** add the repo secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
   `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` (Settings > Secrets and variables > Actions).
   Keep the keystore safe: updates must be signed with the same key.
2. **Android Google sign-in:** in Google Cloud > Google Auth Platform > Clients, create an
   **Android** client with package `io.github.aalambheriyani.next_up` and the SHA-1 of the signing key.
3. **iOS Google sign-in:** create an **iOS** client with bundle id `io.github.aalambheriyani.nextUp`,
   then set its client id in `lib/main.dart` (`GOOGLE_IOS_CLIENT_ID`) and its reversed id as a URL
   scheme in `ios/Runner/Info.plist`.
4. **Worker:** add the Android and iOS client ids to the Worker's `GOOGLE_CLIENT_ID`, comma-separated
   after the web one, so it accepts the app's sign-ins.

## Develop

```sh
cd app
flutter pub get
flutter run            # with a phone connected or an emulator running
```
