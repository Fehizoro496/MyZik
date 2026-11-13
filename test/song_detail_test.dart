// Verifies the song detail page: opening it from a track's ⋮ menu, that it
// shows the track's info, and that the Album row jumps to the album collection;
// then editing its info on its own page.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_zik/icons.dart';
import 'package:my_zik/data/music_repository.dart';
import 'package:my_zik/main.dart';
import 'package:my_zik/models.dart';
import 'package:my_zik/providers/library_provider.dart';
import 'package:my_zik/providers/navigation_provider.dart';
import 'package:my_zik/providers/shared_preferences_provider.dart';
import 'package:my_zik/providers/song_detail_provider.dart';
import 'package:my_zik/screens/collection_screen.dart';
import 'package:my_zik/screens/edit_song_screen.dart';
import 'package:my_zik/screens/song_detail_screen.dart';
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

/// Fingerprinted songs, whose info can be edited.
class _KeyedRepo extends _FakeRepo {
  @override
  Future<List<Song>> fetchSongs() async => [
    for (final song in await super.fetchSongs())
      song.withContentKey('fp:${song.id}'),
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
          appDatabaseProvider.overrideWithValue(await testDatabase(tester)),
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

    // Open "Starlit Reverie"'s ⋮ menu (second row: the list is sorted by
    // title) and pick "Song details".
    expect(find.byIcon(AppIcons.moreVert), findsNWidgets(2));
    await tester.tap(find.byIcon(AppIcons.moreVert).last);
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

  testWidgets('song info is edited on its own page', (tester) async {
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
          musicRepositoryProvider.overrideWithValue(_KeyedRepo()),
        ],
        child: const MaterialApp(home: PlayerShell()),
      ),
    );
    final ctx = tester.element(find.byType(PlayerShell));
    final container = ProviderScope.containerOf(ctx, listen: false);
    await container.read(libraryProvider.notifier).load();
    container.read(selectedSongProvider.notifier).state = container
        .read(libraryProvider)
        .songs
        .firstWhere((s) => s.id == 1);
    container.read(navigationProvider.notifier).goTo(AppScreen.songDetail);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit info'));
    await tester.pumpAndSettle();
    expect(find.byType(EditSongScreen), findsOneWidget);
    expect(find.text('Change cover'), findsNothing);
    // The cover's pen badge is what changes it.
    expect(find.byIcon(AppIcons.edit), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Starlit Reverie'),
      'Starlit Reverie (Live)',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Nightfall'), '');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Back on the details, which show the new info.
    expect(find.byType(SongDetailScreen), findsOneWidget);
    expect(find.text('Starlit Reverie (Live)'), findsOneWidget);
    expect(find.text('Unknown album'), findsOneWidget);
    final song = container
        .read(libraryProvider)
        .songs
        .firstWhere((s) => s.id == 1);
    expect(song.title, 'Starlit Reverie (Live)');
    expect(song.album, isNull);

    // An empty title can't be saved.
    await tester.tap(find.text('Edit info'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Starlit Reverie (Live)'),
      ' ',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(EditSongScreen), findsOneWidget);
  });
}
