// Track on the dashboard: what you're tracking now and the category buttons, as on the old site, so starting
// a block doesn't need a trip to the Track page.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:next_up_core/deadline_source.dart';
import 'package:next_up_core/theme.dart';
import 'package:next_up_core/track.dart';

import '../pages/track_screen.dart' show TrackCategories, TrackNowBar;
import 'panel.dart';

class TrackPanel extends StatefulWidget {
  const TrackPanel({super.key, required this.repo, this.now});
  final TrackRepository repo;
  final DateTime Function()? now;

  @override
  State<TrackPanel> createState() => _TrackPanelState();
}

class _TrackPanelState extends State<TrackPanel> {
  TrackData? _data;
  String? _error;
  bool _busy = false;
  Timer? _tick, _reload;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _data?.running != null) setState(() {});
    });
    // The focus timer and the Track page also start and stop blocks; catch up now and then.
    _reload = Timer.periodic(const Duration(minutes: 2), (_) => _load());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _reload?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await widget.repo.load();
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } on SourceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _run(Future<void> Function(TrackData d) job) async {
    final d = _data;
    if (d == null || _busy) return;
    setState(() => _busy = true);
    try {
      await job(d);
      if (mounted) setState(() => _error = null);
    } on SourceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Panel(
      title: 'Track',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: TextStyle(color: NextUpColors.muted))),
        if (d == null && _error == null) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
        if (d != null) ...[
          TrackNowBar(data: d, now: _now(), onStop: () => _run((d) => widget.repo.stop(d, _now()))),
          const SizedBox(height: 12),
          TrackCategories(
            data: d,
            onTap: (cat) => _run((d) => d.running != null && d.running!.cat == cat ? widget.repo.stop(d, _now()) : widget.repo.start(d, cat, '', _now())),
          ),
        ],
      ]),
    );
  }
}
