import 'platform_base.dart';

LocalStore openLocalStore() => MemoryStore();

/// No sound outside the browser.
void playBeep(List<double> freqs) {}
