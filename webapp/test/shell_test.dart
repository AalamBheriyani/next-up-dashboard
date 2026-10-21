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

  test('the address picks the page, including the current site\'s names', () {
    expect(pageForHash(''), 0);
    expect(pageForHash('#track'), 3);
    expect(pageForHash('#/quests'), 5);
    expect(pageForHash('#departures'), 1);
    expect(pageForHash('#hours'), 4);
    expect(pageForHash('#nu_session=nu_abc'), 0);
  });

  testWidgets('opens on the page in the address, and short labels fit the phone bar', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Shell(auth: _Auth(), services: fakeServices(signedIn: false), hash: '#settings')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Your sheets'.toUpperCase()), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Adherence'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
