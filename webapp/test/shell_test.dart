import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_web/main.dart';
import 'package:next_up_web/web_auth.dart';

import 'fakes.dart';

class _Auth extends WebAuth {
  bool on = false;
  @override
  bool get signedIn => on;
  @override
  Future<void> signIn() async => on = true;
}

void main() {
  testWidgets('signed out: shows the sign-in prompt, and moves between pages', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Shell(auth: _Auth(), services: fakeServices(signedIn: false))));
    await tester.pump();
    await tester.pump();
    expect(find.text('DASHBOARD'), findsOneWidget);
    expect(find.textContaining('Sign in'), findsWidgets);
    await tester.tap(find.text('SETTINGS'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Your sheets'.toUpperCase()), findsOneWidget);
    await tester.tap(find.text('TRACK'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Track'), findsWidgets);
  });
}
