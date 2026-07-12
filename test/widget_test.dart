// Smoke tests for the My Zik music player.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_zik/main.dart';
import 'package:my_zik/providers/shared_preferences_provider.dart';

void main() {
  testWidgets('Home screen renders and navigates to Now Playing',
      (WidgetTester tester) async {
    // Use a phone-sized surface so the app renders edge-to-edge (no frame).
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MyZikApp(),
      ),
    );
    await tester.pump();

    // Home greeting is visible.
    expect(find.text('Hi, Fehizoro'), findsOneWidget);
    expect(find.text('Discover weekly'), findsOneWidget);

    // Tapping the discover card opens the Now Playing screen.
    await tester.tap(find.text('Discover weekly'));
    await tester.pumpAndSettle();

    expect(find.text('Now Playing'), findsOneWidget);
  });
}
