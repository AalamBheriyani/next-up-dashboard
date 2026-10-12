// Next Up on the web, built with Flutter. Published beside the current site (under /beta/) so nothing
// breaks while it grows page by page. It shares its theme, deadline model and Today screen with the
// phone app in ../core.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:next_up_core/ask_claude.dart';
import 'package:next_up_core/board_layout.dart';
import 'package:next_up_core/deadline.dart';
import 'package:next_up_core/deadline_source.dart';
import 'package:next_up_core/quest.dart';
import 'package:next_up_core/theme.dart';
import 'package:next_up_core/today_screen.dart';
import 'package:next_up_core/worker_api.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dashboard/dashboard_screen.dart';
import 'dashboard/deadline_editor.dart';
import 'dashboard/focus_controller.dart';
import 'board/widget_board.dart';
import 'dashboard/anki_panel.dart';
import 'dashboard/habits_panel.dart';
import 'dashboard/links_panel.dart';
import 'pages/lists_screen.dart';
import 'pages/quest_screen.dart';
import 'format.dart';
import 'motion.dart';
import 'platform/platform.dart';
import 'scale.dart';
import 'pages/adherence_screen.dart';
import 'pages/settings_screen.dart';
import 'pages/track_screen.dart';
import 'services.dart';
import 'web_auth.dart';

void main() {
  WebAuth.ready.ignore(); // starts loading Google's sign-in; failures surface when someone signs in
  runApp(const NextUpWeb());
}

/// Bumped whenever the saved accent or deadline colour changes, so the whole app is rebuilt with it.
final themeRevision = ValueNotifier<int>(0);

class NextUpWeb extends StatelessWidget {
  const NextUpWeb({super.key, this.services});
  /// Replaced only by the local preview (lib/demo); the real site builds its own from the sign-in.
  final Services? services;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: themeRevision,
        builder: (context, _, _) => MaterialApp(
          title: 'Next Up',
          debugShowCheckedModeBanner: false,
          theme: buildNextUpTheme(),
          themeMode: ThemeMode.dark,
          builder: (context, child) => ScaleToScreen(child: child!),
          home: Shell(services: services),
        ),
      );
}

/// A rail on wide screens and a bottom bar on narrow ones; pages ease in as you move between them.
class Shell extends StatefulWidget {
  const Shell({super.key, this.auth, this.services, this.hash});
  final WebAuth? auth;
  final String? hash; // tests pass the starting address
  final Services? services; // tests pass fakes

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late final WebAuth _auth = widget.auth ?? WebAuth();
  late final Services _svc = widget.services ?? Services.live(_auth, _signIn);
  AppConfig _config = const AppConfig();
  BoardLayout _layout = const BoardLayout();
  Timer? _layoutTimer;
  // The focus timer lives here so it keeps running while you move between pages, and so a finished session
  // can earn XP and a running one can track your time.
  late final FocusController _focus = FocusController(store: _svc.store, hooks: FocusHooks(onFinished: _timerFinished, onFocusRunning: _followTimer));
  // The page shows in the address (#track, #quests, ...) so a reload or a bookmark opens the same page.
  late int _page = pageForHash(widget.hash ?? currentHash());
  // Bumped on sign-in or out so every page reloads.
  int _session = 0;

  @override
  void initState() {
    super.initState();
    _focus.restore();
    _focus.addListener(_showTimerInTab);
    // Flutter resets the address as it starts; put the page's name back once it has.
    WidgetsBinding.instance.addPostFrameCallback((_) => Timer(const Duration(milliseconds: 300), () {
          if (mounted) setHash(pageHashes[_page]);
        }));
    if (_svc.signedIn()) _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final c = await _svc.config.load();
      if (mounted) _setConfig(c);
    } catch (_) {
      // Pages show their own sign-in or access messages.
    }
  }

  /// Keeps the arrangement on screen now and saves it to the account a moment after the last change.
  void _saveLayout(BoardLayout l) {
    _layout = l;
    _layoutTimer?.cancel();
    _layoutTimer = Timer(const Duration(milliseconds: 600), () => _svc.config.save(layout: l).catchError((Object _) {}));
  }

  @override
  void dispose() {
    _layoutTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  /// A finished pomodoro or break earns XP in the Quest Log automatically (quests "timer" and "break").
  Future<void> _timerFinished(bool focus) async {
    // A short chime, and a notification if the tab is in the background, like the old site's phone alert.
    if (_svc.store.get('nu.web.mute') != '1') playBeep(focus ? const [660, 880, 1320] : const [1320, 880, 660]); // the Quest Log's sound switch
    notify(focus ? 'Pomodoro done' : 'Break over', focus ? 'Time for a break.' : 'Back to focus.');
    if (_config.questSheetId.isEmpty || !_svc.signedIn()) return;
    final q = defaultQuests.firstWhere((x) => x.id == (focus ? 'timer' : 'break'));
    final row = XpRow(t: DateTime.now().millisecondsSinceEpoch, q: q.id, name: q.name, base: q.xp.toDouble(), mult: 1, xp: q.xp, kind: 'auto');
    try {
      final repo = _svc.xpFor(_config.questSheetId);
      // The day starts at the hour in the person's own XP sheet settings, so the row lands on the right day.
      await repo.append([row], (await repo.load()).settings.dayStartHour);
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('+${q.xp} XP · ${q.name}')));
    } catch (_) {
      // XP is a bonus; a failed write must never interrupt the timer.
    }
  }

  /// Starting a pomodoro starts tracking time (Study, or the first category); stopping it stops the block.
  Future<void> _followTimer(bool on, String label) async {
    if (on) askNotifyPermission();
    if (_config.sheetId.isEmpty || !_svc.signedIn()) return;
    try {
      final repo = _svc.trackFor(_config.sheetId);
      final data = await repo.load();
      final run = data.running;
      final now = DateTime.now();
      if (on && run == null) {
        final cats = data.categories;
        final cat = cats.firstWhere((c) => RegExp(r'^study$', caseSensitive: false).hasMatch(c), orElse: () => cats.first);
        await repo.start(data, cat, 'pomodoro${label.isEmpty ? '' : ': $label'}', now);
      } else if (!on && run != null && run.note.startsWith('pomodoro')) {
        await repo.stop(data, now);
      }
    } catch (_) {
      // Tracking follows the timer when it can; it never blocks it.
    }
  }

  AskService? get _ask {
    final t = _svc.askTransport;
    if (t == null || !_svc.signedIn()) return null;
    return AskService(transport: t, mode: askModeFor(claudeApi: _config.claudeApi, relay: _config.relay), name: _config.profileName, rules: _config.profileRules);
  }

  /// Edits a deadline from any page, then reloads the pages that show deadlines.
  Future<void> _editDeadline(Deadline d) async {
    final editor = _svc.deadlines;
    if (editor is! DeadlineEditor) return;
    if (await showDeadlineEditor(context, editor as DeadlineEditor, d: d)) setState(() => _session++);
  }

  /// Keeps the config and applies its accent and deadline colour to the whole app.
  void _setConfig(AppConfig c) {
    if (c.layout != null) _layout = c.layout!;
    NextUpColors.apply(accentHex: c.accent, redDeadlines: c.redDeadlines);
    setState(() => _config = c);
    themeRevision.value++;
  }

  Future<void> _signIn() async {
    await (widget.services != null ? _svc.signIn() : _auth.signIn());
    setState(() => _session++);
    await _loadConfig();
  }

  void _signOut() => setState(() {
        _auth.signOut();
        _config = const AppConfig();
        NextUpColors.apply();
        _session++;
      });

  // While the focus timer runs, the browser tab shows the time left, so it can be seen from another tab.
  String _tab = '';
  void _showTimerInTab() {
    final t = _focus.running ? '${clockDuration(_focus.left)} ${focusLabels[_focus.mode]} · Next Up' : 'Next Up';
    if (t == _tab) return;
    _tab = t;
    SystemChrome.setApplicationSwitcherDescription(ApplicationSwitcherDescription(label: t, primaryColor: 0xFF000000));
  }

  void _go(int i) {
    setState(() => _page = i);
    setHash(pageHashes[i]);
  }

  Future<void> _openClassic() => launchUrl(Uri.parse(classicSite));

  Widget _pageFor(int i) {
    switch (i) {
      case 0:
        return DashboardScreen(
          deadlines: _svc.deadlines,
          calendar: _svc.calendar,
          signedIn: _svc.signedIn,
          onSignIn: _signIn,
          layout: _layout,
          onLayout: _saveLayout,
          wakeMinutes: _config.wakeMinutes,
          windDownMinutes: _config.windDownMinutes,
          focus: _focus,
          ask: _ask,
          extras: [
            if (_config.questSheetId.isNotEmpty) BoardItem(id: 'habits', name: 'Habits', span: 12, child: HabitsPanel(repo: _svc.xpFor(_config.questSheetId))),
            if (_config.owner && _svc.anki != null) BoardItem(id: 'anki', name: 'Anki', span: 12, child: AnkiPanel(source: _svc.anki!)),
            if (_svc.signedIn()) BoardItem(id: 'links', name: 'Jump to', span: 12, child: LinksPanel(links: quickLinks(_config))),
          ],
        );
      case 1:
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: TodayScreen(heading: 'Deadlines', source: _svc.deadlines, signedIn: _svc.signedIn, onSignIn: _signIn, onEdit: _svc.deadlines is DeadlineEditor ? _editDeadline : null),
          ),
        );
      case 2:
        return ListsScreen(services: _svc, onEdit: _svc.deadlines is DeadlineEditor ? _editDeadline : null);
      case 3:
        return TrackScreen(services: _svc, config: _config, layout: _layout, onLayout: _saveLayout);
      case 4:
        return AdherenceScreen(services: _svc, config: _config, layout: _layout, onLayout: _saveLayout);
      case 5:
        return QuestScreen(services: _svc, config: _config, layout: _layout, onLayout: _saveLayout);
      default:
        return SettingsScreen(
          services: _svc,
          config: _config,
          onSaved: (c) => setState(() {
            _setConfig(c);
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
      child: KeyedSubtree(key: ValueKey('$_page-$_session-${_config.sheetId}-${_config.questSheetId}-${_config.accent}-${_config.redDeadlines}'), child: _pageFor(_page)),
    );
    const destinations = <(IconData, String)>[
      (Icons.space_dashboard_outlined, 'DASHBOARD'),
      (Icons.flight_takeoff_rounded, 'DEADLINES'),
      (Icons.checklist_rounded, 'LISTS'),
      (Icons.timer_outlined, 'TRACK'),
      (Icons.insights_outlined, 'ADHERENCE'),
      (Icons.military_tech_outlined, 'QUESTS'),
      (Icons.settings_outlined, 'SETTINGS'),
    ];
    return Scaffold(
      body: wide
          ? Row(children: [
              NavigationRail(
                backgroundColor: NextUpColors.panel,
                selectedIndex: _page,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: _go,
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
          // Seven items share a phone's width, so the labels are short and small enough to stay on one line.
          : NavigationBarTheme(
              data: NavigationBarThemeData(labelTextStyle: WidgetStatePropertyAll(const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)), height: 64),
              child: NavigationBar(
                selectedIndex: _page,
                onDestinationSelected: _go,
                destinations: [for (final d in destinations) NavigationDestination(icon: Icon(d.$1), label: _short(d.$2), tooltip: d.$2)],
              ),
            ),
    );
  }
}

/// 'DASHBOARD' -> 'Home', others in title case, for the phone's bottom bar.
String _short(String label) => label == 'DASHBOARD' ? 'Home' : label[0] + label.substring(1).toLowerCase();

/// Each page's name in the address, in the order of the navigation.
const pageHashes = ['', 'deadlines', 'lists', 'track', 'adherence', 'quests', 'settings'];

/// The page for an address like '#track' (or the current site's '#departures', '#hours', '#rate'); the dashboard otherwise.
int pageForHash(String hash) {
  final h = hash.replaceFirst(RegExp(r'^#/?'), '').toLowerCase();
  const old = {'departures': 1, 'hours': 4, 'rate': 4};
  final i = pageHashes.indexOf(h);
  return i > 0 ? i : old[h] ?? 0;
}
