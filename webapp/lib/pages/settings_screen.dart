// Settings: which sheets to use, and who is signed in. Saved with the Worker, so they follow the person
// to any device and are shared with the current site.
import 'package:flutter/material.dart';
import 'package:next_up_core/deadline_source.dart';
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
                const Text('Paste the link to each Google Sheet. They stay private to you.', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.body)),
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
              Reveal(index: 2, child: Panel(title: 'Account', child: Row(children: [
                Expanded(child: Text(widget.config.email.isEmpty ? 'Signed in' : 'Signed in as ${widget.config.email}', style: const TextStyle(fontSize: NextUpType.body))),
                OutlinedButton(onPressed: widget.onSignOut, child: const Text('Sign out')),
              ]))),
            ]),
          ),
        ),
      ],
    );
  }
}
