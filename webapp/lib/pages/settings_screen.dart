// Settings: which sheets to use, and who is signed in. Saved with the Worker, so they follow the person
// to any device and are shared with the current site.
import 'package:flutter/material.dart';
import 'package:next_up_core/deadline_source.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:next_up_core/theme.dart';
import 'package:next_up_core/worker_api.dart';

import '../dashboard/panel.dart';
import '../motion.dart';
import '../services.dart';

/// Accepts a pasted sheet link or a bare id and returns the id, or null when it doesn't look like one.
/// The link people expect to see and open for a saved sheet id (empty when none is set).
String sheetLinkFor(String id) => id.isEmpty ? '' : 'https://docs.google.com/spreadsheets/d/$id/edit';

String? sheetIdFrom(String input) {
  final t = input.trim();
  if (t.isEmpty) return '';
  final m = RegExp(r'/d/([\w-]{20,100})').firstMatch(t) ?? RegExp(r'^([\w-]{20,100})$').firstMatch(t);
  return m?[1];
}

/// "07:30" for the saved setting, and "7:30 AM" for people.
String clockText(int minutes) => '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
String clockLabel(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  return '${h % 12 == 0 ? 12 : h % 12}:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.services, required this.config, required this.onSaved, required this.onSignOut});
  final Services services;
  final AppConfig config;
  final void Function(AppConfig) onSaved;
  final VoidCallback onSignOut;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _time = TextEditingController(text: sheetLinkFor(widget.config.sheetId));
  late final _xp = TextEditingController(text: sheetLinkFor(widget.config.questSheetId));
  String? _msg;
  bool _bad = false;
  bool _saving = false;
  late int _wake = widget.config.wakeMinutes, _windDown = widget.config.windDownMinutes;
  late String _accent = widget.config.accent;
  late bool _red = widget.config.redDeadlines;

  static const _swatches = ['', '#8b7bff', '#2dd4bf', '#ff6fb5', '#ffb020', '#3ddc84'];

  /// Theme saves straight away so the change is visible, like the site's colour picker.
  Future<void> _saveTheme({String? accent, bool? red}) async {
    setState(() {
      _accent = accent ?? _accent;
      _red = red ?? _red;
    });
    try {
      await widget.services.config.save(accent: _accent, redDeadlines: _red);
      widget.onSaved(await widget.services.config.load());
    } on SourceException catch (e) {
      if (mounted) setState(() => _msg = e.message);
    }
  }

  /// Your waking day drives the "left until wind-down" bar; it saves as soon as you pick a time.
  Future<void> _saveHours({int? wake, int? windDown}) async {
    setState(() {
      _wake = wake ?? _wake;
      _windDown = windDown ?? _windDown;
    });
    try {
      await widget.services.config.save(wake: clockText(_wake), windDown: clockText(_windDown));
      widget.onSaved(await widget.services.config.load());
    } on SourceException catch (e) {
      if (mounted) setState(() => _msg = e.message);
    }
  }

  Future<void> _pick(int current, void Function(int) set) async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60));
    if (t != null) set(t.hour * 60 + t.minute);
  }

  @override
  void dispose() {
    _time.dispose();
    _xp.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = sheetIdFrom(_time.text), x = sheetIdFrom(_xp.text);
    if (t == null || x == null) {
      setState(() {
        _msg = "That doesn't look like a Google Sheet link. Paste the whole link from your browser.";
        _bad = true;
      });
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.services.config.save(sheetId: t, questSheetId: x);
      widget.onSaved(await widget.services.config.load());
      if (mounted) {
        setState(() {
          _msg = 'Saved.';
          _bad = false;
        });
      }
    } on SourceException catch (e) {
      if (mounted) {
        setState(() {
          _msg = e.message;
          _bad = true;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Opens the sheet named in [c] in a new tab (works for a pasted link or a saved id).
  Widget _openButton(TextEditingController c) => IconButton(
        tooltip: 'Open this sheet',
        icon: const Icon(Icons.open_in_new_rounded, size: 18),
        onPressed: () {
          final id = sheetIdFrom(c.text);
          if (id != null && id.isNotEmpty) launchUrl(Uri.parse(sheetLinkFor(id)));
        },
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      children: [
        const Reveal(child: Text('Settings', style: TextStyle(fontSize: NextUpType.heading, fontWeight: FontWeight.w800))),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(children: [
              Reveal(index: 1, child: Panel(title: 'Your sheets', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Paste the link to each Google Sheet. They stay private to you.', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.body)),
                const SizedBox(height: 12),
                TextField(controller: _time, keyboardType: TextInputType.url, decoration: InputDecoration(labelText: 'Weekly Time Tracker (Adherence) sheet', helperText: 'Used by Track and Adherence', suffixIcon: _openButton(_time))),
                const SizedBox(height: 12),
                TextField(controller: _xp, keyboardType: TextInputType.url, decoration: InputDecoration(labelText: 'XP Tracker sheet', helperText: 'Used by the Quest Log', suffixIcon: _openButton(_xp))),
                const SizedBox(height: 16),
                Row(children: [
                  FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
                  const SizedBox(width: 12),
                  if (_msg != null) Flexible(child: Text(_msg!, style: TextStyle(fontSize: NextUpType.body, color: _bad ? NextUpColors.deadline : NextUpColors.ok))),
                ]),
              ]))),
              const SizedBox(height: 16),
              Reveal(index: 2, child: Panel(title: 'Look', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Accent colour', style: TextStyle(fontSize: NextUpType.body, color: NextUpColors.muted)),
                const SizedBox(height: 10),
                Wrap(spacing: 12, runSpacing: 8, children: [
                  for (final hex in [..._swatches, if (!_swatches.contains(_accent)) _accent])
                    Semantics(
                      button: true,
                      selected: hex == _accent,
                      label: hex.isEmpty ? 'Default blue' : 'Accent $hex',
                      child: GestureDetector(
                        onTap: () => _saveTheme(accent: hex),
                        child: AnimatedContainer(
                          duration: motionFast,
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hex.isEmpty ? NextUpColors.defaultAccent : Color(0xFF000000 | int.parse(hex.substring(1), radix: 16)),
                            border: Border.all(color: hex == _accent ? Colors.white : Colors.transparent, width: 2),
                          ),
                        ),
                      ),
                    ),
                  // Any colour, like the old site's picker.
                  IconButton.outlined(
                    tooltip: 'Pick any colour',
                    constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    onPressed: () async {
                      final hex = await showDialog<String>(context: context, builder: (_) => _ColourPicker(start: _accent));
                      if (hex != null) _saveTheme(accent: hex);
                    },
                    icon: const Icon(Icons.colorize_rounded),
                  ),
                ]),
                Row(children: [const Expanded(child: Text('Show deadlines in red', style: TextStyle(fontSize: NextUpType.body))), Switch(value: _red, onChanged: (v) => _saveTheme(red: v))]),
              ]))),
              const SizedBox(height: 16),
              Reveal(index: 3, child: Panel(title: 'Your day', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('The dashboard counts your day from waking up to wind-down.', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.body)),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 8, children: [
                  OutlinedButton.icon(onPressed: () => _pick(_wake, (m) => _saveHours(wake: m)), icon: const Icon(Icons.wb_sunny_outlined, size: 16), label: Text('Wake ${clockLabel(_wake)}')),
                  OutlinedButton.icon(onPressed: () => _pick(_windDown, (m) => _saveHours(windDown: m)), icon: const Icon(Icons.bedtime_outlined, size: 16), label: Text('Wind-down ${clockLabel(_windDown)}')),
                ]),
              ]))),
              const SizedBox(height: 16),
              Reveal(index: 3, child: Panel(title: 'Account', child: Row(children: [
                Expanded(child: Text(widget.config.email.isEmpty ? 'Signed in' : 'Signed in as ${widget.config.email}', style: const TextStyle(fontSize: NextUpType.body))),
                OutlinedButton(onPressed: widget.onSignOut, child: const Text('Sign out')),
              ]))),
              const SizedBox(height: 16),
              Reveal(index: 3, child: Panel(title: 'TickTick', child: Row(children: [
                Expanded(child: Text(widget.config.ticktick ? 'Connected. Your deadlines come from TickTick.' : 'Not connected yet. Connect it to see and edit your deadlines.', style: TextStyle(fontSize: NextUpType.body, color: widget.config.ticktick ? NextUpColors.ok : NextUpColors.muted))),
                const SizedBox(width: 12),
                if (widget.services.deadlines is TickTickConnector)
                  OutlinedButton(
                    onPressed: () async {
                      try {
                        await launchUrl(Uri.parse(await (widget.services.deadlines as TickTickConnector).connectUrl()), webOnlyWindowName: '_self');
                      } on SourceException catch (e) {
                        if (mounted) setState(() => _msg = e.message);
                      }
                    },
                    child: Text(widget.config.ticktick ? 'Reconnect' : 'Connect'),
                  ),
              ]))),
              const SizedBox(height: 16),
              Reveal(index: 4, child: Panel(title: 'Old site', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('The original site is archived and still works, with the same account and the same sheets.', style: TextStyle(fontSize: NextUpType.body, color: NextUpColors.muted)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(onPressed: () => launchUrl(Uri.parse(classicSite)), icon: const Icon(Icons.open_in_new_rounded, size: 16), label: const Text('Open old site')),
                  // Every released version stays online, as the old site's menu linked.
                  TextButton(onPressed: () => launchUrl(Uri.parse('https://aalambheriyani.github.io/next-up-dashboard/v/')), child: const Text('All versions')),
                ]),
              ]))),
            ]),
          ),
        ),
      ],
    );
  }
}


/// A hue slider and a hex box. Returns "#rrggbb", or null when cancelled.
class _ColourPicker extends StatefulWidget {
  const _ColourPicker({required this.start});
  final String start;

  @override
  State<_ColourPicker> createState() => _ColourPickerState();
}

class _ColourPickerState extends State<_ColourPicker> {
  late Color _c = parseHex(widget.start) ?? NextUpColors.defaultAccent;
  late final _hex = TextEditingController(text: toHex(_c));

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set(Color c) => setState(() {
        _c = c;
        _hex.text = toHex(c);
      });

  @override
  Widget build(BuildContext context) {
    final hue = HSVColor.fromColor(_c).hue;
    return AlertDialog(
      title: const Text('Accent colour'),
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(height: 48, decoration: BoxDecoration(color: _c, borderRadius: BorderRadius.circular(12))),
          const SizedBox(height: 12),
          Container(
            height: 10,
            margin: const EdgeInsets.symmetric(horizontal: 24), // lines up with the slider's track
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              gradient: LinearGradient(colors: [for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h.toDouble(), .7, .95).toColor()]),
            ),
          ),
          Slider(value: hue, max: 360, label: 'Hue', onChanged: (h) => _set(HSVColor.fromAHSV(1, h, .7, .95).toColor())),
          TextField(
            controller: _hex,
            decoration: const InputDecoration(labelText: 'Hex', hintText: '#4f8cff'),
            onChanged: (v) {
              final c = parseHex(v.trim());
              if (c != null) setState(() => _c = c);
            },
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.of(context).pop(''), child: const Text('Default blue')),
        FilledButton(onPressed: () => Navigator.of(context).pop(toHex(_c)), child: const Text('Use it')),
      ],
    );
  }
}

/// "#rrggbb" (or "rrggbb") as a colour; null if it isn't one.
Color? parseHex(String s) {
  final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(s);
  return m == null ? null : Color(0xFF000000 | int.parse(m[1]!, radix: 16));
}

String toHex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
