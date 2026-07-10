// Smoke tests for the My Zik music player.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_zik/main.dart';

void main() {
  testWidgets('Home screen renders and navigates to Now Playing',
      (WidgetTester tester) async {
    // Use a phone-sized surface so the app renders edge-to-edge (no frame).
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyZikApp());
    await tester.pump();

    // Home greeting is visible.
    expect(find.text('Hi, Samantha'), findsOneWidget);
    expect(find.text('Discover weekly'), findsOneWidget);

    // Tapping the discover card opens the Now Playing screen.
    await tester.tap(find.text('Discover weekly'));
    await tester.pumpAndSettle();

    expect(find.text('Now Playing'), findsOneWidget);
  });
}
