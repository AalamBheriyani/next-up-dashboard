// Pages reload their data when you come back to the tab after a while, like the old site did on
// "visibilitychange", so a dashboard left open overnight isn't stale in the morning.
import 'package:flutter/widgets.dart';

mixin RefreshOnReturn<T extends StatefulWidget> on State<T> {
  late final AppLifecycleListener _life = AppLifecycleListener(onResume: _back);
  DateTime _last = DateTime.now();

  /// How long the tab must have been away before coming back reloads.
  Duration get refreshAfter => const Duration(minutes: 2);

  /// Reloads the page's data, keeping what is on screen until the new data arrives.
  Future<void> refreshData();

  @override
  void initState() {
    super.initState();
    _life; // start listening
  }

  void _back() {
    if (!mounted || DateTime.now().difference(_last) < refreshAfter) return;
    _last = DateTime.now();
    refreshData();
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }
}
