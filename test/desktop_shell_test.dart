import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_zik/data/sample_music_repository.dart';
import 'package:my_zik/desktop/desktop_shell.dart';
import 'package:my_zik/main.dart';
import 'package:my_zik/providers/library_provider.dart';
import 'package:my_zik/providers/shared_preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpDesktop(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        musicRepositoryProvider.overrideWithValue(SampleMusicRepository()),
      ],
      child: const MyZikApp(desktop: true),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('desktop gets its own shell, not the phone screens', (
    tester,
  ) async {
    await _pumpDesktop(tester);

    expect(find.byType(DesktopShell), findsOneWidget);
    expect(find.byType(PlayerShell), findsNothing);
    expect(find.text('Liked songs'), findsWidgets);
    expect(find.text('Nothing playing'), findsOneWidget);
    expect(find.text('Play a song to see its lyrics.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('sidebar, library search and history navigate pages', (
    tester,
  ) async {
    await _pumpDesktop(tester);

    await tester.tap(find.text('Songs').first);
    await tester.pumpAndSettle();
    expect(find.text('TITLE'), findsOneWidget);
    expect(find.text('Starlit Reverie'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'echo');
    await tester.pumpAndSettle();
    expect(find.text('Results for “echo”'), findsOneWidget);
    expect(find.text('Lost in the Echo'), findsOneWidget);
    expect(find.text('Starlit Reverie'), findsNothing);

    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nightfall'));
    await tester.pumpAndSettle();
    // The album page lists only that album's songs.
    expect(find.text('Starlit Reverie'), findsOneWidget);
    expect(find.text('Echoes'), findsNothing);

    await tester.tap(find.byTooltip('Back (Alt+←)'));
    await tester.pumpAndSettle();
    expect(find.text('Starlit Reverie'), findsNothing);
    expect(find.text('Echoes'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Ctrl+L toggles the lyrics panel', (tester) async {
    await _pumpDesktop(tester);
    const lyricsHint = 'Play a song to see its lyrics.';
    expect(find.text(lyricsHint), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text(lyricsHint), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
