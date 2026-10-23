// Verifies YouTube downloads: the audio lands on disk under its final name
// only once complete, is persisted, joins the library as a local file, and is
// cleaned up on failure or removal.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_zik/data/music_repository.dart';
import 'package:my_zik/data/youtube_repository.dart';
import 'package:my_zik/models.dart';
import 'package:my_zik/providers/downloads_provider.dart';
import 'package:my_zik/providers/library_provider.dart';
import 'package:my_zik/providers/shared_preferences_provider.dart';
import 'package:my_zik/providers/youtube_provider.dart';

class _DeviceRepo implements MusicRepository {
  @override
  bool get isSupported => true;
  @override
  Future<bool> ensurePermission() async => true;
  @override
  Future<List<Song>> fetchSongs() async => const [
    Song(id: 1, title: 'Local', artist: 'Device'),
  ];
  @override
  Future<Uint8List?> artworkFor(int id) async => null;
}

class _FakeYouTube implements YouTubeRepository {
  _FakeYouTube({this.failMidway = false});

  final bool failMidway;

  @override
  Future<YouTubeAudioStream> openAudio(String videoId) async {
    Stream<List<int>> bytes() async* {
      yield List.filled(600, 1);
      if (failMidway) throw const SocketException('connection lost');
      yield List.filled(400, 2);
    }

    return YouTubeAudioStream(
      extension: 'm4a',
      totalBytes: 1000,
      bytes: bytes(),
    );
  }

  @override
  Future<List<YouTubeTrack>> search(String query, {int limit = 20}) async =>
      const [];
  @override
  Future<Uri> resolveAudio(String videoId) async => throw UnimplementedError();
  @override
  void close() {}
}

const _track = YouTubeTrack(
  videoId: 'abc123',
  title: 'Offline Song',
  artist: 'Some Artist',
  duration: Duration(minutes: 3),
  thumbnailUrl: 'https://example.test/cover.jpg',
);

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('myzik_downloads_test');
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => dir.delete(recursive: true));

  Future<ProviderContainer> makeContainer(YouTubeRepository youtube) async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        musicRepositoryProvider.overrideWithValue(_DeviceRepo()),
        youtubeRepositoryProvider.overrideWithValue(youtube),
        downloadsDirectoryProvider.overrideWith((ref) async => dir),
      ],
    );
    addTearDown(container.dispose);
    // Keep the library alive and let its first scan finish.
    container.listen(libraryProvider, (_, _) {});
    await container.read(downloadsProvider.notifier).ready;
    await Future<void>.delayed(Duration.zero);
    return container;
  }

  test('a download is saved, persisted and joins the library', () async {
    final container = await makeContainer(_FakeYouTube());

    await container.read(downloadsProvider.notifier).download(_track);

    final saved = container.read(downloadsProvider).saved['abc123'];
    expect(saved, isNotNull);
    final file = File(saved!.audioPath);
    expect(file.lengthSync(), 1000);
    expect(dir.listSync().where((e) => e.path.endsWith('.part')), isEmpty);
    expect(container.read(downloadsProvider).progress, isEmpty);

    final songs = container.read(libraryProvider).songs;
    expect(songs.map((s) => s.title), ['Local', 'Offline Song']);
    final song = songs.last;
    expect(song.id, youtubeSongId('abc123'));
    expect(song.id, isNegative);
    expect(Uri.parse(song.uri!).toFilePath(), file.path);

    // A fresh app session reads the download back from preferences.
    final restarted = await makeContainer(_FakeYouTube());
    expect(restarted.read(downloadsProvider).saved.keys, ['abc123']);
    expect(
      restarted.read(libraryProvider).songs.map((s) => s.title),
      contains('Offline Song'),
    );
  });

  test('a failed download leaves no file behind', () async {
    final container = await makeContainer(_FakeYouTube(failMidway: true));

    await expectLater(
      container.read(downloadsProvider.notifier).download(_track),
      throwsA(isA<SocketException>()),
    );

    expect(dir.listSync(), isEmpty);
    expect(container.read(downloadsProvider).saved, isEmpty);
    expect(container.read(downloadsProvider).progress, isEmpty);
    expect(container.read(libraryProvider).songs.map((s) => s.title), [
      'Local',
    ]);
  });

  test('removing a download deletes its file and library entry', () async {
    final container = await makeContainer(_FakeYouTube());
    final notifier = container.read(downloadsProvider.notifier);
    await notifier.download(_track);
    final path = container.read(downloadsProvider).saved['abc123']!.audioPath;

    await notifier.remove('abc123');

    expect(File(path).existsSync(), isFalse);
    expect(container.read(downloadsProvider).saved, isEmpty);
    expect(container.read(libraryProvider).songs.map((s) => s.title), [
      'Local',
    ]);
    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getStringList('downloads.tracks'), isEmpty);
  });
}
