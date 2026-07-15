// Verifies the Now Playing queue button: tapping it opens the queue sheet,
// which lists the library in play order and marks the current track.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_zik/data/music_repository.dart';
import 'package:my_zik/models.dart';
import 'package:my_zik/providers/library_provider.dart';
import 'package:my_zik/providers/playback_provider.dart';
import 'package:my_zik/providers/shared_preferences_provider.dart';
import 'package:my_zik/screens/now_playing_screen.dart';

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
  testWidgets('queue button opens a sheet listing the play queue', (
    tester,
  ) async {
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

    // The header queue button is now visible; the sheet is not yet open.
    expect(find.byIcon(Icons.queue_music_rounded), findsOneWidget);
    expect(find.text('NOW PLAYING'), findsNothing);

    await tester.tap(find.byIcon(Icons.queue_music_rounded));
    await tester.pumpAndSettle();

    // Sheet is open: hero shows the current track, the up-next tracks are
    // listed after it in queue order, each with a drag handle.
    expect(find.text('NOW PLAYING'), findsOneWidget);
    // The current track shows both in the screen body and the sheet hero.
    expect(find.text('Starlit Reverie'), findsNWidgets(2));
    expect(find.text('Midnight Confessions'), findsOneWidget); // up next
    expect(find.text('Lost in the Echo'), findsOneWidget); // up next
    expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(2));

    // Tapping a queued track jumps to it (preserving the queue) and dismisses
    // the sheet.
    await tester.tap(find.text('Lost in the Echo'));
    await tester.pumpAndSettle();
    expect(find.text('NOW PLAYING'), findsNothing);
    expect(container.read(playbackProvider).currentIndex, 2);

    // Unmount so the notifier's periodic persist timer is cancelled before the
    // binding's end-of-test check.
    await tester.pumpWidget(const SizedBox.shrink());
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

    await tester.tap(find.byIcon(Icons.queue_music_rounded));
    await tester.pumpAndSettle();

    // Queue starts [1, 2, 3]; up next is [2, 3]. Drag the first handle down
    // past the second row to move id 2 below id 3.
    final handle = find.byIcon(Icons.drag_handle_rounded).first;
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
