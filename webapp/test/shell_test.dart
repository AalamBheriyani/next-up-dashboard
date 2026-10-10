import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_web/main.dart';
import 'package:next_up_web/web_auth.dart';

import 'package:next_up_core/deadline.dart';
import 'package:next_up_core/deadline_source.dart';

class _Auth extends WebAuth {
  bool on = false;
  @override
  bool get signedIn => on;
  @override
  Future<void> signIn() async => on = true;
}

class _Source implements DeadlineSource {
  @override
  Future<List<Deadline>> load() async => [];
  @override
  Future<void> complete(Deadline d) async {}
}

void main() {
  testWidgets('shows the sign-in prompt, then the empty state after signing in', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Shell(auth: _Auth(), source: _Source())));
    await tester.pumpAndSettle();
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.textContaining('Sign in'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in with Google'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sign in with Google'), findsNothing);
  });
}
