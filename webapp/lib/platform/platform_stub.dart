import 'platform_base.dart';

LocalStore openLocalStore() => MemoryStore();

/// No sound outside the browser.
void playBeep(List<double> freqs) {}

/// The page address's `#...` part, empty outside the browser.
String currentHash() => '';

void clearHash() {}

/// Leaves this page for [url] (the sign-in page).
void navigateTo(String url) {}

/// Shows [hash] after the '#' in the address without reloading or adding a history entry.
void setHash(String hash) {}

/// Asks once for permission to show "timer done" notifications; nothing outside the browser.
void askNotifyPermission() {}

/// A short buzz on phones that allow it.
void vibrate() {}

/// A system notification, shown only while the page is in the background.
void notify(String title, String body) {}

/// True inside the Android/iOS app, which wraps this site and signs in natively. Never outside the browser.
bool get inNativeApp => false;

/// Sends a message to the Android/iOS app around the page.
void postNative(Map<String, Object?> msg) {}

/// Where the app's native sign-in answers (an access token and its lifetime in seconds, or an error).
void onNativeAuth(void Function(String? token, int expiresIn, String? error) handler) {}
