import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_zik/data/lyrics_repository.dart';
import 'package:my_zik/data/sample_music_repository.dart';
import 'package:my_zik/models.dart';
import 'package:my_zik/providers/app_database_provider.dart';
import 'package:my_zik/providers/library_provider.dart';
import 'package:my_zik/providers/lyrics_provider.dart';
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

/// Opens the app with a button showing the lyrics sheet for [_first];
/// returns how to change the track playing.
Future<void Function(Song)> _pumpSheet(WidgetTester tester) async {
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
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => LyricsSheet.show(context, _first),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.text('Open')),
  );
  void play(Song song) {
    // Sets the track without loading audio, which tests can't play.
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    container.read(playbackProvider.notifier).state = PlaybackState(
      current: song,
      queue: const [_first, _second, _third],
    );
  }

  return play;
}

void main() {
  testWidgets('the lyrics sheet follows the track playing', (tester) async {
    final play = await _pumpSheet(tester);
    play(_first);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('First Song'), findsOneWidget);
    expect(find.text('Words of First Song'), findsOneWidget);

    // The next track starts: the sheet moves to it.
    play(_second);
    await tester.pumpAndSettle();
    expect(find.text('Second Song'), findsOneWidget);
    expect(find.text('Words of Second Song'), findsOneWidget);
    expect(find.text('First Song'), findsNothing);

    // While its lyrics are being timed, the sheet keeps the track.
    await tester.tap(find.text('Synchronize'));
    await tester.pumpAndSettle();
    play(_third);
    await tester.pumpAndSettle();
    expect(find.text('Second Song'), findsOneWidget);
    expect(find.text('Third Song'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a new track\'s lyrics open at the top', (tester) async {
    final play = await _pumpSheet(tester);
    play(_first);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

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

    // The next track's lyrics are already loaded, as Now Playing's preview
    // loads them: the sheet swaps lyrics without a loading state between.
    final container = ProviderScope.containerOf(
      tester.element(find.text('Open')),
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
