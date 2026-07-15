// Verifies the song detail page: opening it from a track's ⋮ menu, that it
// shows the track's info, and that the Album row jumps to the album collection.

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
import 'package:my_zik/providers/shared_preferences_provider.dart';
import 'package:my_zik/screens/collection_screen.dart';
import 'package:my_zik/screens/song_detail_screen.dart';

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
  ];
}

void main() {
  testWidgets('open song details from the ⋮ menu and jump to its album', (
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
        child: const MaterialApp(home: PlayerShell()),
      ),
    );

    final ctx = tester.element(find.byType(PlayerShell));
    final container = ProviderScope.containerOf(ctx, listen: false);
    await container.read(libraryProvider.notifier).load();
    container.read(navigationProvider.notifier).goTo(AppScreen.myMusic);
    await tester.pumpAndSettle();

    // Open the first track's ⋮ menu and pick "Song details".
    expect(find.byIcon(Icons.more_vert_rounded), findsNWidgets(2));
    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Song details'));
    await tester.pumpAndSettle();

    // The detail page shows the track's title, artist and album.
    expect(find.byType(SongDetailScreen), findsOneWidget);
    expect(find.text('Starlit Reverie'), findsOneWidget);
    expect(find.text('Nightfall'), findsOneWidget);

    // Tapping the album value navigates to its collection.
    await tester.tap(find.text('Nightfall'));
    await tester.pumpAndSettle();
    expect(find.byType(CollectionScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
