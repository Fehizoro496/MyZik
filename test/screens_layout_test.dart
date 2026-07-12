import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_zik/providers/shared_preferences_provider.dart';
import 'package:my_zik/screens/home_screen.dart';
import 'package:my_zik/screens/my_music_screen.dart';
import 'package:my_zik/screens/now_playing_screen.dart';

Future<void> _pumpAt(WidgetTester tester, Widget child) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(home: child),
    ),
  );
  await tester.pump();
  // Unmount before the harness checks for pending timers at tree teardown.
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  testWidgets('Home fits', (t) async {
    await _pumpAt(t, const HomeScreen());
  });
  testWidgets('NowPlaying fits', (t) async {
    await _pumpAt(t, const NowPlayingScreen());
  });
  testWidgets('MyMusic fits', (t) async {
    await _pumpAt(t, const MyMusicScreen());
  });
}
