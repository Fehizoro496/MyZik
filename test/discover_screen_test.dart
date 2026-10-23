import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_zik/data/youtube_repository.dart';
import 'package:my_zik/providers/playback_provider.dart';
import 'package:my_zik/providers/shared_preferences_provider.dart';
import 'package:my_zik/providers/youtube_provider.dart';
import 'package:my_zik/screens/discover_screen.dart';

class _FakeYouTubeRepository implements YouTubeRepository {
  _FakeYouTubeRepository({this.failResolution = false});

  final bool failResolution;
  String? searchedFor;
  String? resolvedId;

  @override
  Future<List<YouTubeTrack>> search(String query, {int limit = 20}) async {
    searchedFor = query;
    return const [
      YouTubeTrack(
        videoId: 'video-1',
        title: 'Midnight Demo',
        artist: 'Prototype Artist',
        duration: Duration(minutes: 3, seconds: 12),
        thumbnailUrl: 'https://example.test/cover.jpg',
      ),
    ];
  }

  @override
  Future<Uri> resolveAudio(String videoId) async {
    resolvedId = videoId;
    if (failResolution) throw StateError('stream unavailable');
    return Uri.parse('https://example.test/audio.m4a');
  }

  @override
  Future<YouTubeAudioSource> resolveAudioSource(String videoId) async =>
      throw UnimplementedError();

  @override
  void close() {}
}

void main() {
  testWidgets('searches YouTube and resolves audio when play is tapped', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = _FakeYouTubeRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          youtubeRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: Scaffold(body: DiscoverScreen())),
      ),
    );

    expect(find.text('Search YouTube'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('youtube-search-field')),
      'midnight',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();

    expect(repository.searchedFor, 'midnight');
    expect(find.text('Midnight Demo'), findsOneWidget);
    expect(find.text('Prototype Artist · 3:12'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('youtube-play-video-1')));
    await tester.pump();

    expect(repository.resolvedId, 'video-1');
    final context = tester.element(find.byType(DiscoverScreen));
    final container = ProviderScope.containerOf(context, listen: false);
    final current = container.read(playbackProvider).current;
    expect(current?.title, 'Midnight Demo');
    expect(current?.uri, 'https://example.test/audio.m4a');
    expect(current?.artworkUrl, 'https://example.test/cover.jpg');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shows a useful error when the audio stream cannot be resolved', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = _FakeYouTubeRepository(failResolution: true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          youtubeRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: Scaffold(body: DiscoverScreen())),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('youtube-search-field')),
      'midnight',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('youtube-play-video-1')));
    await tester.pump();

    expect(repository.resolvedId, 'video-1');
    expect(find.textContaining('Impossible de lire'), findsOneWidget);
  });
}
