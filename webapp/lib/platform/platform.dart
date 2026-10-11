// Picks the browser versions on the web and harmless ones everywhere else (including tests).
export 'platform_base.dart';
export 'platform_stub.dart' if (dart.library.js_interop) 'platform_web.dart';
