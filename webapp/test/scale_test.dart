import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_web/scale.dart';

void main() {
  test('laptop windows are left alone and big screens scale up to a limit', () {
    expect(screenScale(1280), 1);
    expect(screenScale(1440), 1);
    expect(screenScale(1920), closeTo(1.333, 0.001));
    expect(screenScale(5000), 2);
  });

  testWidgets('on a big screen the page is laid out smaller and drawn larger', (t) async {
    t.view.physicalSize = const Size(2880, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    late Size seen;
    await t.pumpWidget(MaterialApp(builder: (context, child) => ScaleToScreen(child: child!), home: Builder(builder: (context) {
      seen = MediaQuery.sizeOf(context);
      return const Align(alignment: Alignment.topLeft, child: SizedBox(width: 100, height: 50, key: Key('box')));
    })));
    expect(seen.width, 1440);
    final box = find.byKey(const Key('box'));
    expect(t.getBottomRight(box).dx - t.getTopLeft(box).dx, 200);
  });
}
