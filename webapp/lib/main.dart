// Next Up on the web, built with Flutter. Published beside the current site (under /beta/) so nothing
// breaks while it grows page by page. It shares its theme, deadline model and Today screen with the
// phone app in ../core.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:next_up_core/calendar.dart';
import 'package:next_up_core/deadline_source.dart';
import 'package:next_up_core/theme.dart';
import 'package:next_up_core/today_screen.dart';
import 'dashboard/dashboard_screen.dart';
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

/// A rail on wide screens and a bottom bar on narrow ones, around a centred, readable column.
class Shell extends StatefulWidget {
  const Shell({super.key, this.auth, this.source, this.calendar});
  final WebAuth? auth;
  final DeadlineSource? source;
  final CalendarSource? calendar;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late final WebAuth _auth = widget.auth ?? WebAuth();
  late final DeadlineSource _source = widget.source ?? WorkerDeadlineSource(_auth.token);
  late final CalendarSource _calendar = widget.calendar ?? GoogleCalendarSource(_auth.token);
  int _page = 0;
  // Bumped on sign-in or out so the Today screen reloads.
  int _session = 0;

  Future<void> _signIn() async {
    await _auth.signIn();
    setState(() => _session++);
  }

  void _signOut() => setState(() {
        _auth.signOut();
        _session++;
      });

  Future<void> _openClassic() => launchUrl(Uri.parse(classicSite));

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final page = KeyedSubtree(
      key: ValueKey('$_page-$_session'),
      child: _page == 0
          ? DashboardScreen(deadlines: _source, calendar: _calendar, signedIn: () => _auth.signedIn, onSignIn: _signIn)
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: TodayScreen(source: _source, signedIn: () => _auth.signedIn, onSignIn: _signIn),
              ),
            ),
    );
    final destinations = <(IconData, String)>[
      (Icons.space_dashboard_outlined, 'DASHBOARD'),
      (Icons.flight_takeoff_rounded, 'DEADLINES'),
      (Icons.open_in_new_rounded, 'CLASSIC SITE'),
    ];
    void select(int i) => i == 2 ? _openClassic() : setState(() => _page = i);
    return Scaffold(
      body: wide
          ? Row(children: [
              NavigationRail(
                backgroundColor: NextUpColors.panel,
                selectedIndex: _page,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: select,
                trailing: Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: IconButton(tooltip: 'Sign out', onPressed: _signOut, icon: const Icon(Icons.logout_rounded)),
                    ),
                  ),
                ),
                destinations: [for (final d in destinations) NavigationRailDestination(icon: Icon(d.$1), label: Text(d.$2))],
              ),
              Expanded(child: page),
            ])
          : page,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _page,
              onDestinationSelected: select,
              destinations: [for (final d in destinations) NavigationDestination(icon: Icon(d.$1), label: d.$2)],
            ),
    );
  }
}
