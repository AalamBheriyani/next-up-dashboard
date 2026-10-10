// Next Up on the web, built with Flutter. Published beside the current site (under /beta/) so nothing
// breaks while it grows page by page. It shares its theme, deadline model and Today screen with the
// phone app in ../core.
import 'package:flutter/material.dart';
import 'package:next_up_core/theme.dart';
import 'package:next_up_core/today_screen.dart';
import 'package:next_up_core/worker_api.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dashboard/dashboard_screen.dart';
import 'motion.dart';
import 'pages/adherence_screen.dart';
import 'pages/settings_screen.dart';
import 'pages/track_screen.dart';
import 'services.dart';
import 'web_auth.dart';

const classicSite = String.fromEnvironment('CLASSIC_URL', defaultValue: 'https://aalambheriyani.github.io/next-up-dashboard/');

void main() {
  WebAuth.ready.ignore(); // starts loading Google's sign-in; failures surface when someone signs in
  runApp(const NextUpWeb());
}

class NextUpWeb extends StatelessWidget {
  const NextUpWeb({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Next Up',
        debugShowCheckedModeBanner: false,
        theme: buildNextUpTheme(),
        themeMode: ThemeMode.dark,
        home: const Shell(),
      );
}

/// A rail on wide screens and a bottom bar on narrow ones; pages ease in as you move between them.
class Shell extends StatefulWidget {
  const Shell({super.key, this.auth, this.services});
  final WebAuth? auth;
  final Services? services; // tests pass fakes

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late final WebAuth _auth = widget.auth ?? WebAuth();
  late final Services _svc = widget.services ?? Services.live(_auth, _signIn);
  AppConfig _config = const AppConfig();
  int _page = 0;
  // Bumped on sign-in or out so every page reloads.
  int _session = 0;

  @override
  void initState() {
    super.initState();
    if (_svc.signedIn()) _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final c = await _svc.config.load();
      if (mounted) setState(() => _config = c);
    } catch (_) {
      // Pages show their own sign-in or access messages.
    }
  }

  Future<void> _signIn() async {
    await (widget.services != null ? _svc.signIn() : _auth.signIn());
    setState(() => _session++);
    await _loadConfig();
  }

  void _signOut() => setState(() {
        _auth.signOut();
        _config = const AppConfig();
        _session++;
      });

  Future<void> _openClassic() => launchUrl(Uri.parse(classicSite));

  Widget _pageFor(int i) {
    switch (i) {
      case 0:
        return DashboardScreen(deadlines: _svc.deadlines, calendar: _svc.calendar, signedIn: _svc.signedIn, onSignIn: _signIn);
      case 1:
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: TodayScreen(source: _svc.deadlines, signedIn: _svc.signedIn, onSignIn: _signIn),
          ),
        );
      case 2:
        return TrackScreen(services: _svc, config: _config);
      case 3:
        return AdherenceScreen(services: _svc, config: _config);
      default:
        return SettingsScreen(
          services: _svc,
          config: _config,
          onSaved: (c) => setState(() {
            _config = c;
            _session++;
          }),
          onSignOut: _signOut,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final page = AnimatedSwitcher(
      duration: motionBase,
      switchInCurve: motionCurve,
      transitionBuilder: (child, anim) => pageTransition(child, anim),
      child: KeyedSubtree(key: ValueKey('$_page-$_session-${_config.sheetId}'), child: _pageFor(_page)),
    );
    const destinations = <(IconData, String)>[
      (Icons.space_dashboard_outlined, 'DASHBOARD'),
      (Icons.flight_takeoff_rounded, 'DEADLINES'),
      (Icons.timer_outlined, 'TRACK'),
      (Icons.insights_outlined, 'ADHERENCE'),
      (Icons.settings_outlined, 'SETTINGS'),
    ];
    return Scaffold(
      body: wide
          ? Row(children: [
              NavigationRail(
                backgroundColor: NextUpColors.panel,
                selectedIndex: _page,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: (i) => setState(() => _page = i),
                trailing: Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(tooltip: 'Open the current site', onPressed: _openClassic, icon: const Icon(Icons.open_in_new_rounded)),
                        IconButton(tooltip: 'Sign out', onPressed: _signOut, icon: const Icon(Icons.logout_rounded)),
                      ]),
                    ),
                  ),
                ),
                destinations: [for (final d in destinations) NavigationRailDestination(icon: Icon(d.$1), label: Text(d.$2, style: const TextStyle(fontSize: NextUpType.label)))],
              ),
              Expanded(child: page),
            ])
          : page,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _page,
              onDestinationSelected: (i) => setState(() => _page = i),
              destinations: [for (final d in destinations) NavigationDestination(icon: Icon(d.$1), label: d.$2)],
            ),
    );
  }
}
