import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_zik/data/desktop_music_repository.dart';
import 'package:my_zik/data/music_repository.dart';
import 'package:my_zik/data/sample_music_repository.dart';
import 'package:my_zik/desktop/desktop_navigation.dart';
import 'package:my_zik/desktop/desktop_shell.dart';
import 'package:my_zik/desktop/desktop_style.dart';
import 'package:my_zik/desktop/now_playing.dart';
import 'package:my_zik/main.dart';
import 'package:my_zik/providers/library_provider.dart';
import 'package:my_zik/providers/playback_provider.dart';
import 'package:my_zik/providers/shared_preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpDesktop(
  WidgetTester tester, {
  MusicRepository Function(SharedPreferences prefs)? repository,
}) async {
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
        musicRepositoryProvider.overrideWithValue(
          repository?.call(prefs) ?? SampleMusicRepository(),
        ),
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

  testWidgets('every sidebar page lays out at a desktop size', (tester) async {
    await _pumpDesktop(tester);

    for (final page in [
      'Discover',
      'Songs',
      'Albums',
      'Artists',
      'Liked songs',
      'Home',
    ]) {
      await tester.tap(find.text(page).first);
      await tester.pumpAndSettle();
    }
    // Home also titles a section "Albums": the sidebar entry comes first.
    await tester.tap(find.text('Albums').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Echoes'));
    await tester.pumpAndSettle();
    // The album hero: play and shuffle above the track table.
    expect(find.byType(AccentPlayButton), findsOneWidget);
    expect(find.text('Lost in the Echo'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('full-screen Now Playing replaces the layout until Esc', (
    tester,
  ) async {
    await _pumpDesktop(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DesktopShell)),
    );

    container.read(desktopFullscreenProvider.notifier).state = true;
    await tester.pumpAndSettle();
    expect(find.byType(DesktopNowPlaying), findsOneWidget);
    expect(find.text('NOW PLAYING'), findsOneWidget);
    expect(find.text('LIBRARY'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopNowPlaying), findsNothing);
    expect(find.text('LIBRARY'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a current track fills Home and full screen', (tester) async {
    await _pumpDesktop(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DesktopShell)),
    );
    final songs = container.read(libraryProvider).songs;
    // Sets the track without loading audio, which tests can't play.
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    container.read(playbackProvider.notifier).state = PlaybackState(
      current: songs.first,
      queue: songs,
      duration: songs.first.duration,
    );
    // The lyrics keep loading (and spinning): pump frames, don't settle.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('CONTINUE LISTENING'), findsOneWidget);

    await tester.tap(find.text('Full screen').first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DesktopNowPlaying), findsOneWidget);
    expect(find.text(songs.first.title), findsWidgets);
    expect(find.byTooltip('Exit full screen (Esc)'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('without a music folder, the desktop asks for one', (
    tester,
  ) async {
    await _pumpDesktop(
      tester,
      repository: (prefs) => DesktopMusicRepository(preferences: prefs),
    );

    await tester.tap(find.text('Songs').first);
    await tester.pumpAndSettle();
    expect(find.text('Add your music'), findsOneWidget);
    expect(find.text('Choose a folder…'), findsOneWidget);

    await tester.tap(find.byTooltip('Music folders'));
    await tester.pumpAndSettle();
    expect(find.text('Music folders'), findsWidgets);
    expect(find.text('No folder yet.'), findsOneWidget);
    expect(find.text('Add folder…'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
