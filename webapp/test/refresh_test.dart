import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_web/refresh.dart';

class _Page extends StatefulWidget {
  const _Page(this.loads);
  final List<int> loads;
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> with RefreshOnReturn {
  @override
  Duration get refreshAfter => Duration.zero;
  @override
  Future<void> refreshData() async => widget.loads.add(1);
  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets('coming back to the tab reloads the page', (tester) async {
    final loads = <int>[];
    await tester.pumpWidget(_Page(loads));
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    expect(loads, [1]);
  });
}
