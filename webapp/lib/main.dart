// Next Up on the web, built with Flutter. Published beside the current site (under /beta/) so nothing
// breaks while it grows page by page. It shares its theme, deadline model and Today screen with the
// phone app in ../core.
import 'dart:async';

import 'package:flutter/material.dart';
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
import 'pages/quest_screen.dart';
import 'motion.dart';
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
  const NextUpWeb({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: themeRevision,
        builder: (context, _, _) => MaterialApp(
          title: 'Next Up',
          debugShowCheckedModeBanner: false,
          theme: buildNextUpTheme(),
          themeMode: ThemeMode.dark,
          home: const Shell(),
        ),
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
  BoardLayout _layout = const BoardLayout();
  Timer? _layoutTimer;
  // The focus timer lives here so it keeps running while you move between pages, and so a finished session
  // can earn XP and a running one can track your time.
  late final FocusController _focus = FocusController(hooks: FocusHooks(onFinished: _timerFinished, onFocusRunning: _followTimer));
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
    if (_config.questSheetId.isEmpty || !_svc.signedIn()) return;
    final q = defaultQuests.firstWhere((x) => x.id == (focus ? 'timer' : 'break'));
    final row = XpRow(t: DateTime.now().millisecondsSinceEpoch, q: q.id, name: q.name, base: q.xp.toDouble(), mult: 1, xp: q.xp, kind: 'auto');
    try {
      await _svc.xpFor(_config.questSheetId).append([row], const XpSettings().dayStartHour);
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('+${q.xp} XP · ${q.name}')));
    } catch (_) {
      // XP is a bonus; a failed write must never interrupt the timer.
    }
  }

  /// Starting a pomodoro starts tracking time (Study, or the first category); stopping it stops the block.
  Future<void> _followTimer(bool on, String label) async {
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
          focus: _focus,
          ask: _ask,
          extras: [
            if (_config.questSheetId.isNotEmpty) BoardItem(id: 'habits', name: 'Habits', span: 12, child: HabitsPanel(repo: _svc.xpFor(_config.questSheetId))),
            if (_config.owner && _svc.anki != null) BoardItem(id: 'anki', name: 'Anki', span: 12, child: AnkiPanel(source: _svc.anki!)),
          ],
        );
      case 1:
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: TodayScreen(source: _svc.deadlines, signedIn: _svc.signedIn, onSignIn: _signIn, onEdit: _svc.deadlines is DeadlineEditor ? _editDeadline : null),
          ),
        );
      case 2:
        return TrackScreen(services: _svc, config: _config);
      case 3:
        return AdherenceScreen(services: _svc, config: _config);
      case 4:
        return QuestScreen(services: _svc, config: _config);
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
