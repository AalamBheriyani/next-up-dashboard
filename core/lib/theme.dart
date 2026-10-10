// Next Up look: the website's departures-board theme (black, blue accent, red for deadlines),
// shared by the native screens. Colours match :root in docs/index.html.
import 'package:flutter/material.dart';

class NextUpColors {
  static const bg = Color(0xFF000000);
  static const panel = Color(0xFF0B0B0D);
  static const raised = Color(0xFF14161B);
  static const line = Color(0xFF1C1F26);
  static const ink = Color(0xFFFFFFFF);
  static const accent = Color(0xFF4D8DFF);
  static const muted = Color(0xFF9DBDFF); // accent mixed 65% with white, like --muted
  static const deadline = Color(0xFFFF3B3B);
  static const soon = Color(0xFFFF6A3D);
  static const ok = Color(0xFF3DDC84);
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
