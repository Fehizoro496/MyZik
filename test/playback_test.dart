// Verifies the playback queue logic (next / previous / shuffle / repeat) of
// [PlaybackNotifier] against a fake library. Songs here carry no `uri`, so
// `playSong` sets the queue state and returns before touching the real
// AudioPlayer — the index math it drives is what we assert on.
//
// These are plain `test`s (real async, no fake clock) so the notifier's real
// 5s persist Timer and resume Future.delayed behave normally. We still need a
// Flutter test binding for just_audio's `AudioPlayer()` to construct, hence the
// `ensureInitialized` in setUpAll.

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_zik/data/music_repository.dart';
import 'package:my_zik/models.dart';
import 'package:my_zik/providers/library_provider.dart';
import 'package:my_zik/providers/playback_provider.dart';
import 'package:my_zik/providers/shared_preferences_provider.dart';

class _FakeRepo implements MusicRepository {
  @override
  bool get isSupported => true;

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<Uint8List?> artworkFor(int id) async => null;

  @override
  Future<List<Song>> fetchSongs() async => const [
    Song(id: 1, title: 'A', artist: 'x'),
    Song(id: 2, title: 'B', artist: 'x'),
    Song(id: 3, title: 'C', artist: 'x'),
  ];
}

Future<(ProviderContainer, List<Song>)> _bootstrap({
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final store = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(store),
      musicRepositoryProvider.overrideWithValue(_FakeRepo()),
    ],
  );
  // Dispose the container (cancels the 5s persist timer, disposes the player)
  // before the binding's end-of-test pending-timer check runs.
  addTearDown(container.dispose);
  await container.read(libraryProvider.notifier).load();
  final songs = container.read(libraryProvider).songs;
  expect(songs.length, 3);
  return (container, songs);
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  test('playSong sets the current track and its queue index', () async {
    final (container, songs) = await _bootstrap();
    final notifier = container.read(playbackProvider.notifier);

    await notifier.playSong(songs[1]);

    final state = container.read(playbackProvider);
    expect(state.current, songs[1]);
    expect(state.currentIndex, 1);
  });

  test('playSong scopes the queue to the given context', () async {
    final (container, songs) = await _bootstrap();
    final notifier = container.read(playbackProvider.notifier);

    // Play from a filtered subset (e.g. the liked list): ids 1 and 3 only.
    final subset = [songs[0], songs[2]];
    await notifier.playSong(songs[2], context: subset);

    final state = container.read(playbackProvider);
    expect(state.queue.map((s) => s.id).toList(), [1, 3]);
    expect(state.currentIndex, 1);

    // next stays within the subset and wraps — it never plays id 2.
    await notifier.next();
    expect(container.read(playbackProvider).current?.id, 1);
  });

  test('next advances and wraps around the library order', () async {
    final (container, songs) = await _bootstrap();
    final notifier = container.read(playbackProvider.notifier);

    await notifier.playSong(songs[0]);
    await notifier.next();
    expect(container.read(playbackProvider).currentIndex, 1);

    await notifier.next();
    await notifier.next();
    expect(container.read(playbackProvider).currentIndex, 0); // wrapped
  });

  test('previous wraps to the last track when near the start', () async {
    final (container, songs) = await _bootstrap();
    final notifier = container.read(playbackProvider.notifier);

    await notifier.playSong(songs[0]);
    // Position is 0 (no real player in tests), so previous goes to the prior
    // track rather than restarting the current one.
    await notifier.previous();
    expect(container.read(playbackProvider).currentIndex, 2);
  });

  test('cycleRepeatMode rotates all -> one -> off -> all', () async {
    final (container, _) = await _bootstrap();
    final notifier = container.read(playbackProvider.notifier);

    expect(container.read(playbackProvider).repeatMode, PlaybackRepeatMode.all);
    notifier.cycleRepeatMode();
    expect(container.read(playbackProvider).repeatMode, PlaybackRepeatMode.one);
    notifier.cycleRepeatMode();
    expect(container.read(playbackProvider).repeatMode, PlaybackRepeatMode.off);
    notifier.cycleRepeatMode();
    expect(container.read(playbackProvider).repeatMode, PlaybackRepeatMode.all);
  });

  test('reorderQueue moves an upcoming track and keeps the current one',
      () async {
    final (container, songs) = await _bootstrap();
    final notifier = container.read(playbackProvider.notifier);

    await notifier.playSong(songs[0]); // queue ids [1, 2, 3], current at 0
    // Move the last track (id 3, index 2) up to index 1.
    notifier.reorderQueue(2, 1);

    final state = container.read(playbackProvider);
    expect(state.queue.map((s) => s.id).toList(), [1, 3, 2]);
    expect(state.currentIndex, 0); // current (id 1) is untouched

    // next now follows the reordered queue: index 0 -> 1 -> id 3.
    await notifier.next();
    expect(container.read(playbackProvider).current?.id, 3);
  });

  test('toggleShuffle flips the shuffle flag', () async {
    final (container, _) = await _bootstrap();
    final notifier = container.read(playbackProvider.notifier);

    expect(container.read(playbackProvider).shuffle, false);
    notifier.toggleShuffle();
    expect(container.read(playbackProvider).shuffle, true);
    notifier.toggleShuffle();
    expect(container.read(playbackProvider).shuffle, false);
  });

  test('the last played track is restored once the library loads', () async {
    SharedPreferences.setMockInitialValues({
      'playback.lastSongId': 3,
      'playback.lastPositionMs': 1500,
    });
    final store = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(store),
        musicRepositoryProvider.overrideWithValue(_FakeRepo()),
      ],
    );
    addTearDown(container.dispose);

    // Build the notifier before the library finishes scanning, so restore is
    // driven by its ref.listen on the library rather than the initial read.
    container.read(playbackProvider.notifier);
    await container.read(libraryProvider.notifier).load();
    await Future<void>.delayed(Duration.zero);

    expect(container.read(playbackProvider).current?.id, 3);
  });
}
