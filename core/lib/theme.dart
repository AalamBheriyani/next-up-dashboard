// Next Up look: the website's dark theme (black, blue accent, red for deadlines),
// shared by the native screens. Colours match :root in docs/index.html.
import 'package:flutter/material.dart';

class NextUpColors {
  static const bg = Color(0xFF000000);
  static const panel = Color(0xFF0B0B0D);
  static const raised = Color(0xFF14161B);
  static const line = Color(0xFF1C1F26);
  static const ink = Color(0xFFFFFFFF);
  static const defaultAccent = Color(0xFF4D8DFF);
  static Color accent = defaultAccent;
  static Color muted = const Color(0xFF9DBDFF); // accent mixed 65% with white, like --muted
  static Color deadline = const Color(0xFFFF3B3B);
  static const soon = Color(0xFFFF6A3D);
  static const ok = Color(0xFF3DDC84);

  /// Applies a person's saved theme: '#rrggbb' (or empty for the default) and whether deadlines stay red.
  /// Callers rebuild the app afterwards, as the site does when the theme changes.
  static void apply({String accentHex = '', bool redDeadlines = true}) {
    final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(accentHex.trim());
    accent = m == null ? defaultAccent : Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
    muted = Color.lerp(accent, Colors.white, .65)!;
    deadline = redDeadlines ? const Color(0xFFFF3B3B) : accent;
  }
}

/// The one type scale. Sizes elsewhere come from here (the flap-digit graphic is the only exception).
/// label: uppercase section labels; caption: hints and dates; body: text and list rows; subtitle: lead-ins;
/// title: panel headlines; heading: the next deadline; display: timer digits; clock: the big clock.
class NextUpType {
  static const double label = 11;
  static const double caption = 12;
  static const double body = 14;
  static const double subtitle = 16;
  static const double title = 20;
  static const double heading = 24;
  static const double display = 40;
  static const double clock = 56;
}

const monoFeatures = [FontFeature.tabularFigures()];

ThemeData buildNextUpTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: NextUpColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    surface: NextUpColors.bg,
    onSurface: NextUpColors.ink,
    primary: NextUpColors.accent,
    error: NextUpColors.deadline,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: NextUpColors.bg,
    appBarTheme: const AppBarTheme(backgroundColor: NextUpColors.bg, elevation: 0, scrolledUnderElevation: 0),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: NextUpColors.panel,
      indicatorColor: NextUpColors.accent.withValues(alpha: 0.22),
      labelTextStyle: WidgetStatePropertyAll(
        const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
