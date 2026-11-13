import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_zik/data/lyrics_repository.dart';
import 'package:my_zik/data/sample_music_repository.dart';
import 'package:my_zik/icons.dart';
import 'package:my_zik/main.dart';
import 'package:my_zik/models.dart';
import 'package:my_zik/providers/app_database_provider.dart';
import 'package:my_zik/providers/library_provider.dart';
import 'package:my_zik/providers/lyrics_provider.dart';
import 'package:my_zik/providers/navigation_provider.dart';
import 'package:my_zik/providers/playback_provider.dart';
import 'package:my_zik/providers/shared_preferences_provider.dart';
import 'package:my_zik/screens/lyrics_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

const _first = Song(id: 1, title: 'First Song', artist: 'Artist');
const _second = Song(id: 2, title: 'Second Song', artist: 'Artist');
const _third = Song(id: 3, title: 'Third Song', artist: 'Artist');

/// Plain lyrics naming their song, long enough to scroll.
class _FakeLyrics extends LyricsNotifier {
  @override
  Future<Lyrics?> build(Song song) async => Lyrics(
    source: LyricsSource.manual,
    plain: [
      'Words of ${song.title}',
      for (var i = 1; i <= 60; i++) 'Line $i of ${song.title}',
    ].join('\n'),
  );
}

/// Opens the phone app on Now Playing with [_first] playing; returns how to
/// change the track playing.
Future<void Function(Song)> _pumpNowPlaying(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(await testDatabase(tester)),
        musicRepositoryProvider.overrideWithValue(SampleMusicRepository()),
        lyricsProvider.overrideWith(_FakeLyrics.new),
      ],
      child: const MyZikApp(desktop: false),
    ),
  );
  await tester.pump();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MyZikApp)),
  );
  void play(Song song) {
    // Sets the track without loading audio, which tests can't play.
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    container.read(playbackProvider.notifier).state = PlaybackState(
      current: song,
      queue: const [_first, _second, _third],
    );
  }

  play(_first);
  container.read(navigationProvider.notifier).goTo(AppScreen.nowPlaying);
  await tester.pumpAndSettle();
  return play;
}

Future<void> _openLyrics(WidgetTester tester) async {
  await tester.tap(find.textContaining('Words of First Song'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tapping the lyrics teaser gives the screen to the lyrics', (
    tester,
  ) async {
    await _pumpNowPlaying(tester);
    expect(find.byType(LyricsPanel), findsNothing);

    await _openLyrics(tester);
    expect(find.byType(LyricsPanel), findsOneWidget);
    expect(find.byType(LyricsPreview), findsNothing);
    expect(find.text('Line 20 of First Song'), findsOneWidget);
    // The title moved up into the header row, next to the small cover.
    expect(find.text('First Song'), findsOneWidget);

    // The lit lyrics button in the top bar gives the stage back to the cover.
    await tester.tap(find.byIcon(AppIcons.lyrics));
    await tester.pumpAndSettle();
    expect(find.byType(LyricsPanel), findsNothing);
    expect(find.byType(LyricsPreview), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('back closes the lyrics before leaving Now Playing', (
    tester,
  ) async {
    await _pumpNowPlaying(tester);
    await _openLyrics(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Now Playing'), findsOneWidget);
    expect(find.byType(LyricsPanel), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Now Playing'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unsaved timings are confirmed before closing the lyrics', (
    tester,
  ) async {
    await _pumpNowPlaying(tester);
    await _openLyrics(tester);
    await tester.tap(find.text('Synchronize'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark line'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(AppIcons.lyrics));
    await tester.pumpAndSettle();
    expect(find.text('Discard synchronization?'), findsOneWidget);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(find.byType(LyricsPanel), findsOneWidget);

    // Swapping to the queue would lose them as well.
    await tester.tap(find.byIcon(AppIcons.queue));
    await tester.pumpAndSettle();
    expect(find.text('Discard synchronization?'), findsOneWidget);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(find.byType(LyricsPanel), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(LyricsPanel), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the lyrics follow the track playing', (tester) async {
    final play = await _pumpNowPlaying(tester);
    await _openLyrics(tester);
    expect(find.text('Words of First Song'), findsOneWidget);

    // The next track starts: the lyrics move to it.
    play(_second);
    await tester.pumpAndSettle();
    expect(find.text('Words of Second Song'), findsOneWidget);
    expect(find.text('Words of First Song'), findsNothing);

    // While its lyrics are being timed, the panel keeps the track and says
    // so, as the header now names the one playing.
    await tester.tap(find.text('Synchronize'));
    await tester.pumpAndSettle();
    play(_third);
    await tester.pumpAndSettle();
    expect(find.text('Still on Second Song'), findsOneWidget);
    expect(find.text('Third Song'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a new track\'s lyrics open at the top', (tester) async {
    final play = await _pumpNowPlaying(tester);
    await _openLyrics(tester);

    ScrollPosition lyricsScroll() => tester
        .state<ScrollableState>(
          find
              .ancestor(
                of: find.textContaining('of First Song').first,
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    // Read to the bottom of the first track's lyrics.
    lyricsScroll().jumpTo(lyricsScroll().maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Line 60 of First Song'), findsOneWidget);

    // The next track's lyrics are already loaded, as Now Playing's teaser
    // loads them: the panel swaps lyrics without a loading state between.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MyZikApp)),
    );
    final preload = container.listen(lyricsProvider(_second), (_, _) {});
    addTearDown(preload.close);
    await tester.pumpAndSettle();
    expect(container.read(lyricsProvider(_second)).hasValue, isTrue);

    play(_second);
    await tester.pumpAndSettle();

    expect(find.text('Words of Second Song'), findsOneWidget);
    final position = tester
        .state<ScrollableState>(
          find
              .ancestor(
                of: find.text('Words of Second Song'),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    expect(position.pixels, 0);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
