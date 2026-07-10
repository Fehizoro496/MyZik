import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_zik/player_controller.dart';
import 'package:my_zik/screens/home_screen.dart';
import 'package:my_zik/screens/my_music_screen.dart';
import 'package:my_zik/screens/now_playing_screen.dart';

Future<void> _pumpAt(
  WidgetTester tester,
  Widget Function(PlayerController) build,
) async {
  final controller = PlayerController();
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: build(controller)));
  await tester.pump();
  // Unmount, then dispose the controller (cancelling its timer) before the
  // harness checks for pending timers at tree teardown.
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
}

void main() {
  testWidgets('Home fits', (t) async {
    await _pumpAt(t, (c) => HomeScreen(controller: c));
  });
  testWidgets('NowPlaying fits', (t) async {
    await _pumpAt(t, (c) => NowPlayingScreen(controller: c));
  });
  testWidgets('MyMusic fits', (t) async {
    await _pumpAt(t, (c) => MyMusicScreen(controller: c));
  });
}
