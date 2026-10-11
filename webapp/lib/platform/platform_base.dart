// The two browser features the pages use, behind plain interfaces so tests (and non-web builds) run without a
// browser: a tiny key-value store (this device only) and a short sound.

/// Remembers a few small things on this device (the focus timer, the sound switch). Never the source of truth
/// for anything that must follow the person: that goes to the account.
abstract class LocalStore {
  String? get(String key);
  void set(String key, String value);
}

class MemoryStore implements LocalStore {
  final _data = <String, String>{};
  @override
  String? get(String key) => _data[key];
  @override
  void set(String key, String value) => _data[key] = value;
}
