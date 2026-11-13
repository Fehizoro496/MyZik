// Verifies the Now Playing queue button: tapping it gives the stage to the
// queue panel, which lists what plays next and lets it be reordered.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_zik/icons.dart';
import 'package:my_zik/data/music_repository.dart';
import 'package:my_zik/models.dart';
import 'package:my_zik/providers/library_provider.dart';
import 'package:my_zik/providers/playback_provider.dart';
import 'package:my_zik/providers/shared_preferences_provider.dart';
import 'package:my_zik/screens/now_playing_screen.dart';
import 'package:my_zik/providers/app_database_provider.dart';

import 'support/test_database.dart';

class _FakeRepo implements MusicRepository {
  @override
  bool get isSupported => true;

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<Uint8List?> artworkFor(int id) async => null;

  @override
  Future<List<Song>> fetchSongs() async => const [
    Song(id: 1, title: 'Starlit Reverie', artist: 'Budiarti'),
    Song(id: 2, title: 'Midnight Confessions', artist: 'Alexiao'),
    Song(id: 3, title: 'Lost in the Echo', artist: 'Alexiao'),
  ];
}

void main() {
  testWidgets('queue button gives the stage to the play queue', (tester) async {
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
          musicRepositoryProvider.overrideWithValue(_FakeRepo()),
        ],
        child: const MaterialApp(home: NowPlayingScreen()),
      ),
    );
    await tester.pump();

    // Play the first track so Up Next has two entries to show and reorder.
    final ctx = tester.element(find.byType(NowPlayingScreen));
    final container = ProviderScope.containerOf(ctx, listen: false);
    await container.read(libraryProvider.notifier).load();
    final songs = container.read(libraryProvider).songs;
    await container.read(playbackProvider.notifier).playSong(songs[0]);
    await tester.pumpAndSettle();

    // The top-bar queue button is visible; the queue is not shown yet.
    expect(find.byIcon(AppIcons.queue), findsOneWidget);
    expect(find.text('Up next'), findsNothing);

    await tester.tap(find.byIcon(AppIcons.queue));
    await tester.pumpAndSettle();

    // The current track moved up into the header row; the tracks after it
    // are listed in queue order, each with a drag handle.
    expect(find.text('Up next'), findsOneWidget);
    expect(find.text('2 tracks'), findsOneWidget);
    expect(find.text('Starlit Reverie'), findsOneWidget);
    expect(find.text('Midnight Confessions'), findsOneWidget);
    expect(find.text('Lost in the Echo'), findsOneWidget);
    expect(find.byIcon(AppIcons.dragHandle), findsNWidgets(2));

    // Tapping a queued track jumps to it (preserving the queue); the queue
    // stays on screen, now with nothing after it.
    await tester.tap(find.text('Lost in the Echo'));
    await tester.pumpAndSettle();
    expect(container.read(playbackProvider).currentIndex, 2);
    expect(find.text('Up next'), findsOneWidget);
    expect(find.text('Nothing queued after this track.'), findsOneWidget);

    // The lit queue button gives the stage back to the cover.
    await tester.tap(find.byIcon(AppIcons.queue));
    await tester.pumpAndSettle();
    expect(find.text('Up next'), findsNothing);

    // Unmount so the notifier's periodic persist timer is cancelled before the
    // binding's end-of-test check.
    await tester.pumpWidget(const SizedBox.shrink());
    // The lyrics lookup's SQLite query can't finish under the fake clock;
    // let sqflite's 10 s lock warning timer run out.
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('dragging a handle reorders the queue', (tester) async {
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
          musicRepositoryProvider.overrideWithValue(_FakeRepo()),
        ],
        child: const MaterialApp(home: NowPlayingScreen()),
      ),
    );
    await tester.pump();

    final ctx = tester.element(find.byType(NowPlayingScreen));
    final container = ProviderScope.containerOf(ctx, listen: false);
    await container.read(libraryProvider.notifier).load();
    final songs = container.read(libraryProvider).songs;
    await container.read(playbackProvider.notifier).playSong(songs[0]);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(AppIcons.queue));
    await tester.pumpAndSettle();

    // Queue starts [1, 2, 3]; up next is [2, 3]. Drag the first handle down
    // past the second row to move id 2 below id 3.
    final handle = find.byIcon(AppIcons.dragHandle).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(container.read(playbackProvider).queue.map((s) => s.id).toList(), [
      1,
      3,
      2,
    ]);
    // The playing track (id 1) is still current.
    expect(container.read(playbackProvider).currentIndex, 0);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
