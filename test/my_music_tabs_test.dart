// Verifies the My Music tabs: the Songs list, the Albums/Artists groupings
// derived from the flat library, and that opening an album/artist navigates to
// its collection detail screen with the right tracks.

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
import 'package:my_zik/screens/collection_screen.dart';
import 'package:my_zik/screens/my_music_screen.dart';
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
    Song(
      id: 4,
      title: 'Letters I Never Sent',
      artist: 'Alexiao',
      album: 'Paper Hearts',
    ),
  ];
}

void main() {
  testWidgets('My Music tabs group the library and open a collection', (
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

    // Songs tab (default): a track title is shown.
    expect(find.byType(MyMusicScreen), findsOneWidget);
    expect(find.text('Midnight Confessions'), findsOneWidget);

    // Albums tab: one card per album, no raw track titles.
    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    expect(find.text('Echoes'), findsOneWidget);
    expect(find.text('Paper Hearts'), findsOneWidget);
    expect(find.text('Nightfall'), findsOneWidget);
    expect(find.text('Midnight Confessions'), findsNothing);

    // Opening an album drills into its collection detail with its tracks.
    await tester.tap(find.text('Echoes'));
    await tester.pumpAndSettle();
    expect(find.byType(CollectionScreen), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Midnight Confessions'), findsOneWidget);
    expect(find.text('Lost in the Echo'), findsOneWidget);
    // Not part of this album.
    expect(find.text('Letters I Never Sent'), findsNothing);

    // Back returns to My Music; the Artists tab groups by artist.
    container.read(navigationProvider.notifier).back();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Artists'));
    await tester.pumpAndSettle();
    expect(find.text('Alexiao'), findsOneWidget);
    expect(find.text('Budiarti'), findsOneWidget);
    expect(find.text('3 songs'), findsOneWidget);

    // Leaving and returning keeps the Artists tab selected, not resetting to
    // Songs (the tab index lives in a provider, not screen-local state).
    container.read(navigationProvider.notifier).goTo(AppScreen.home);
    await tester.pumpAndSettle();
    container.read(navigationProvider.notifier).goTo(AppScreen.myMusic);
    await tester.pumpAndSettle();
    expect(find.text('Alexiao'), findsOneWidget);
    expect(find.text('Midnight Confessions'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
