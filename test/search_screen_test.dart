// Verifies library search: filtering by query, the result count, and that
// playing a result queues the current results (not the whole library).

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
import 'package:my_zik/screens/search_screen.dart';

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
  testWidgets('search filters the library and queues the results',
      (tester) async {
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
        child: const MaterialApp(home: Scaffold(body: SearchScreen())),
      ),
    );
    final ctx = tester.element(find.byType(SearchScreen));
    final container = ProviderScope.containerOf(ctx, listen: false);
    await container.read(libraryProvider.notifier).load();
    await tester.pumpAndSettle();

    // Empty query shows the hint, no tracks.
    expect(find.text('Search your library'), findsOneWidget);
    expect(find.text('Midnight Confessions'), findsNothing);

    // Title match.
    await tester.enterText(find.byType(TextField), 'midnight');
    await tester.pumpAndSettle();
    expect(find.text('1 result'), findsOneWidget);
    expect(find.text('Midnight Confessions'), findsOneWidget);
    expect(find.text('Starlit Reverie'), findsNothing);

    // Artist match returns both of Alexiao's tracks.
    await tester.enterText(find.byType(TextField), 'alexiao');
    await tester.pumpAndSettle();
    expect(find.text('2 results'), findsOneWidget);
    expect(find.text('Midnight Confessions'), findsOneWidget);
    expect(find.text('Lost in the Echo'), findsOneWidget);

    // No match.
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);

    // Playing a result queues only the current results.
    await tester.enterText(find.byType(TextField), 'alexiao');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lost in the Echo'));
    await tester.pumpAndSettle();

    final playback = container.read(playbackProvider);
    expect(playback.current?.id, 3);
    expect(playback.queue.map((s) => s.id).toList(), [2, 3]);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
