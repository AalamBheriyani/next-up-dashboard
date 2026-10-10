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
String? sheetIdFrom(String input) {
  final t = input.trim();
  if (t.isEmpty) return '';
  final m = RegExp(r'/d/([\w-]{20,100})').firstMatch(t) ?? RegExp(r'^([\w-]{20,100})$').firstMatch(t);
  return m?[1];
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
  late final _time = TextEditingController(text: widget.config.sheetId);
  late final _xp = TextEditingController(text: widget.config.questSheetId);
  String? _msg;
  bool _bad = false;
  bool _saving = false;
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
                TextField(controller: _time, decoration: const InputDecoration(labelText: 'Weekly Time Tracker sheet', helperText: 'Used by Track and Adherence')),
                const SizedBox(height: 12),
                TextField(controller: _xp, decoration: const InputDecoration(labelText: 'XP Tracker sheet', helperText: 'Used by the Quest Log')),
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
                Wrap(spacing: 12, children: [
                  for (final hex in _swatches)
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
                ]),
                Row(children: [const Expanded(child: Text('Show deadlines in red', style: TextStyle(fontSize: NextUpType.body))), Switch(value: _red, onChanged: (v) => _saveTheme(red: v))]),
              ]))),
              const SizedBox(height: 16),
              Reveal(index: 3, child: Panel(title: 'Account', child: Row(children: [
                Expanded(child: Text(widget.config.email.isEmpty ? 'Signed in' : 'Signed in as ${widget.config.email}', style: const TextStyle(fontSize: NextUpType.body))),
                OutlinedButton(onPressed: widget.onSignOut, child: const Text('Sign out')),
              ]))),
              const SizedBox(height: 16),
              Reveal(index: 4, child: Panel(title: 'Old site', child: Row(children: [
                Expanded(child: Text('Something not working here? The original site still runs with the same sign-in and the same sheets.', style: TextStyle(fontSize: NextUpType.body, color: NextUpColors.muted))),
                const SizedBox(width: 12),
                OutlinedButton.icon(onPressed: () => launchUrl(Uri.parse(classicSite)), icon: const Icon(Icons.open_in_new_rounded, size: 16), label: const Text('Open old site')),
              ]))),
            ]),
          ),
        ),
      ],
    );
  }
}
