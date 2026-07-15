// Verifies the playlist system end-to-end through the UI: creating a playlist
// from the Playlists tab, adding tracks via the detail sheet and via a track's
// long-press "add to playlist" sheet, and that playlists persist to prefs.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_zik/data/music_repository.dart';
import 'package:my_zik/main.dart';
import 'package:my_zik/models.dart';
import 'package:my_zik/providers/library_provider.dart';
import 'package:my_zik/providers/navigation_provider.dart';
import 'package:my_zik/providers/playlists_provider.dart';
import 'package:my_zik/providers/shared_preferences_provider.dart';
import 'package:my_zik/screens/playlist_screen.dart';

class _FakeRepo implements MusicRepository {
  @override
  bool get isSupported => true;
  @override
  Future<bool> ensurePermission() async => true;
  @override
  Future<Uint8List?> artworkFor(int id) async => null;
  @override
  Future<List<Song>> fetchSongs() async => const [
    Song(
      id: 1,
      title: 'Starlit Reverie',
      artist: 'Budiarti',
      album: 'Nightfall',
    ),
    Song(
      id: 2,
      title: 'Midnight Confessions',
      artist: 'Alexiao',
      album: 'Echoes',
    ),
    Song(id: 3, title: 'Lost in the Echo', artist: 'Alexiao', album: 'Echoes'),
  ];
}

void main() {
  testWidgets('create a playlist, add tracks, and it persists', (tester) async {
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
        child: const MaterialApp(home: PlayerShell()),
      ),
    );

    final ctx = tester.element(find.byType(PlayerShell));
    final container = ProviderScope.containerOf(ctx, listen: false);
    await container.read(libraryProvider.notifier).load();
    container.read(navigationProvider.notifier).goTo(AppScreen.myMusic);
    await tester.pumpAndSettle();

    // Playlists tab: empty, with a "New playlist" button.
    await tester.tap(find.text('Playlists'));
    await tester.pumpAndSettle();
    expect(find.text('New playlist'), findsOneWidget);

    // Create a playlist -> lands on its (empty) detail screen.
    await tester.tap(find.text('New playlist'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Road trip');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.byType(PlaylistScreen), findsOneWidget);
    expect(find.text('Road trip'), findsOneWidget);
    expect(find.text('0 songs'), findsOneWidget);
    expect(container.read(playlistsProvider).length, 1);

    // Add a track via the "Add songs" sheet, using its search field to filter.
    await tester.tap(find.text('Add songs'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'midnight');
    await tester.pumpAndSettle();
    // Only the matching track remains listed.
    expect(find.text('Midnight Confessions'), findsOneWidget);
    expect(find.text('Lost in the Echo'), findsNothing);
    await tester.tap(find.text('Midnight Confessions'));
    await tester.pumpAndSettle();
    expect(container.read(playlistsProvider).first.songIds, [2]);

    // Persisted to prefs.
    expect(prefs.getString('playlists.v1'), isNotNull);

    // Close the "Add songs" sheet (tap its barrier), then return to My Music.
    await tester.tapAt(const Offset(195, 10));
    await tester.pumpAndSettle();
    container.read(navigationProvider.notifier).back();
    await tester.pumpAndSettle();

    // Long-pressing any track offers "add to playlist".
    await tester.tap(find.text('Songs'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Lost in the Echo'));
    await tester.pumpAndSettle();
    expect(find.text('Add to playlist'), findsOneWidget);
    await tester.tap(find.text('Road trip'));
    await tester.pumpAndSettle();
    expect(container.read(playlistsProvider).first.songIds, [2, 3]);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
