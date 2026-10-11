import 'platform_base.dart';

LocalStore openLocalStore() => MemoryStore();

/// No sound outside the browser.
void playBeep(List<double> freqs) {}

/// The page address's `#...` part, empty outside the browser.
String currentHash() => '';

void clearHash() {}

/// Leaves this page for [url] (the sign-in page).
void navigateTo(String url) {}
