// Verifies YouTube downloads driven by the background engine: progress and
// interruptions are reflected, a completed file joins the library, downloads
// that finished while the app was closed are picked up on start, and failures
// can be retried or dismissed.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_zik/data/download_engine.dart';
import 'package:my_zik/data/music_repository.dart';
import 'package:my_zik/data/youtube_repository.dart';
import 'package:my_zik/models.dart';
import 'package:my_zik/providers/downloads_provider.dart';
import 'package:my_zik/providers/library_provider.dart';
import 'package:my_zik/providers/shared_preferences_provider.dart';
import 'package:my_zik/providers/youtube_provider.dart';
import 'package:my_zik/data/app_database.dart';
import 'package:my_zik/providers/app_database_provider.dart';

import 'support/test_database.dart';

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
  _FakeYouTube({this.failResolution = false});

  bool failResolution;
  int resolutions = 0;

  @override
  Future<YouTubeAudioSource> resolveAudioSource(String videoId) async {
    resolutions++;
    if (failResolution) throw const SocketException('offline');
    return YouTubeAudioSource(
      url: Uri.parse('https://example.test/$videoId'),
      extension: 'm4a',
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

/// Records jobs and lets the test play the native side: emitting events and
/// writing the file the plugin would have moved into place.
class _FakeEngine implements DownloadEngine {
  _FakeEngine(this.dir, {this.pendingOnStart = const []});

  final Directory dir;
  final List<DownloadEvent> pendingOnStart;
  final jobs = <DownloadJob>[];
  final canceled = <String>[];
  final forgotten = <String>[];
  final _events = StreamController<DownloadEvent>.broadcast();

  @override
  Stream<DownloadEvent> get events => _events.stream;
  @override
  Future<void> start() async {}
  @override
  Future<List<DownloadEvent>> pending() async => pendingOnStart;
  @override
  Future<void> ensureNotificationPermission() async {}
  @override
  Future<bool> enqueue(DownloadJob job) async {
    jobs.add(job);
    return true;
  }

  @override
  Future<void> cancel(String id) async => canceled.add(id);
  @override
  Future<void> forget(String id) async => forgotten.add(id);

  Future<void> emit(DownloadEvent event) async {
    _events.add(event);
    await pumpEventQueue();
  }

  /// Simulates the plugin finishing [job].
  Future<void> complete(DownloadJob job) async {
    File('${dir.path}/${job.filename}').writeAsBytesSync(List.filled(1000, 1));
    await emit(
      DownloadEvent(
        job.id,
        phase: DownloadPhase.complete,
        metaData: job.metaData,
      ),
    );
  }
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
  // Shared by every app session of a test, like the database on disk.
  late AppDatabase database;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('myzik_downloads_test');
    SharedPreferences.setMockInitialValues({});
    database = await testDatabase();
  });
  tearDown(() => dir.delete(recursive: true));

  Future<ProviderContainer> makeContainer(
    DownloadEngine engine, {
    YouTubeRepository? youtube,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(database),
        musicRepositoryProvider.overrideWithValue(_DeviceRepo()),
        youtubeRepositoryProvider.overrideWithValue(youtube ?? _FakeYouTube()),
        downloadsDirectoryProvider.overrideWith((ref) async => dir),
        downloadEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);
    // Keep the library alive and let its first scan finish.
    final libraryReady = Completer<void>();
    container.listen(libraryProvider, (_, next) {
      if (next.status != LibraryStatus.loading && !libraryReady.isCompleted) {
        libraryReady.complete();
      }
    });
    await container.read(downloadsProvider.notifier).engineReady;
    await libraryReady.future;
    return container;
  }

  List<String> titles(ProviderContainer c) =>
      c.read(libraryProvider).songs.map((s) => s.title).toList();

  test('a download progresses, completes and joins the library', () async {
    final engine = _FakeEngine(dir);
    final container = await makeContainer(engine);
    final notifier = container.read(downloadsProvider.notifier);

    await notifier.download(_track);
    expect(engine.jobs, hasLength(1));
    final job = engine.jobs.single;
    expect(job.filename, 'abc123.m4a');
    expect(job.url.toString(), 'https://example.test/abc123');
    expect(
      container.read(downloadsProvider).active['abc123']?.phase,
      DownloadPhase.queued,
    );

    await engine.emit(const DownloadEvent('abc123', progress: 0.42));
    final running = container.read(downloadsProvider).active['abc123']!;
    expect(running.phase, DownloadPhase.running);
    expect(running.progress, 0.42);

    // Connection lost: the engine holds the task until it can resume.
    await engine.emit(
      const DownloadEvent('abc123', phase: DownloadPhase.waiting),
    );
    expect(
      container.read(downloadsProvider).active['abc123']?.phase,
      DownloadPhase.waiting,
    );

    await engine.complete(job);
    final state = container.read(downloadsProvider);
    expect(state.active, isEmpty);
    final saved = state.saved['abc123']!;
    expect(File(saved.audioPath).lengthSync(), 1000);
    expect(engine.forgotten, ['abc123']);

    expect(titles(container), ['Local', 'Offline Song']);
    final song = container.read(libraryProvider).songs.last;
    expect(song.id, youtubeSongId('abc123'));
    expect(Uri.parse(song.uri!).toFilePath(), saved.audioPath);

    // A fresh app session reads the download back from the database.
    final restarted = await makeContainer(_FakeEngine(dir));
    expect(restarted.read(downloadsProvider).saved.keys, ['abc123']);
    expect(titles(restarted), contains('Offline Song'));
  });

  test(
    'a download that finished while the app was closed is picked up',
    () async {
      // The job's metadata is all the app gets back from the engine.
      final metaData = jsonEncode({
        'videoId': 'abc123',
        'title': 'Offline Song',
        'artist': 'Some Artist',
        'durationMs': 180000,
        'thumbnailUrl': 'https://example.test/cover.jpg',
        'audioFile': 'abc123.m4a',
      });
      File('${dir.path}/abc123.m4a').writeAsBytesSync(List.filled(10, 1));
      final engine = _FakeEngine(
        dir,
        pendingOnStart: [
          DownloadEvent(
            'abc123',
            phase: DownloadPhase.complete,
            metaData: metaData,
          ),
          DownloadEvent(
            'def456',
            phase: DownloadPhase.running,
            progress: 0.5,
            metaData: jsonEncode({
              'videoId': 'def456',
              'title': 'Still Going',
              'artist': 'Someone',
              'durationMs': 1000,
              'thumbnailUrl': '',
              'audioFile': 'def456.webm',
            }),
          ),
        ],
      );

      final container = await makeContainer(engine);

      final state = container.read(downloadsProvider);
      expect(state.saved.keys, ['abc123']);
      expect(state.active['def456']?.track.title, 'Still Going');
      expect(state.active['def456']?.progress, 0.5);
      expect(titles(container), contains('Offline Song'));
    },
  );

  test('a failed download can be retried with a fresh URL', () async {
    final engine = _FakeEngine(dir);
    final youtube = _FakeYouTube(failResolution: true);
    final container = await makeContainer(engine, youtube: youtube);
    final notifier = container.read(downloadsProvider.notifier);

    await expectLater(
      notifier.download(_track),
      throwsA(isA<SocketException>()),
    );
    expect(engine.jobs, isEmpty);
    expect(container.read(downloadsProvider).active['abc123']?.isFailed, true);

    youtube.failResolution = false;
    await notifier.download(_track);
    expect(engine.jobs, hasLength(1));
    expect(youtube.resolutions, 2);

    // The engine gives up (e.g. the URL expired): retrying re-resolves it.
    await engine.emit(
      DownloadEvent(
        'abc123',
        phase: DownloadPhase.failed,
        metaData: engine.jobs.single.metaData,
      ),
    );
    expect(container.read(downloadsProvider).active['abc123']?.isFailed, true);
    await notifier.download(_track);
    expect(engine.jobs, hasLength(2));
    expect(youtube.resolutions, 3);
  });

  test('canceling and dismissing clear the download', () async {
    final engine = _FakeEngine(dir);
    final container = await makeContainer(engine);
    final notifier = container.read(downloadsProvider.notifier);

    await notifier.download(_track);
    await notifier.cancel('abc123');
    expect(engine.canceled, ['abc123']);
    expect(container.read(downloadsProvider).active, isEmpty);

    // A failed download is only forgotten, there is nothing left to cancel.
    await notifier.download(_track);
    await engine.emit(
      const DownloadEvent('abc123', phase: DownloadPhase.failed),
    );
    await notifier.cancel('abc123');
    expect(engine.canceled, ['abc123']);
    expect(container.read(downloadsProvider).active, isEmpty);
  });

  test('removing a download deletes its file and library entry', () async {
    final engine = _FakeEngine(dir);
    final container = await makeContainer(engine);
    final notifier = container.read(downloadsProvider.notifier);
    await notifier.download(_track);
    await engine.complete(engine.jobs.single);
    final path = container.read(downloadsProvider).saved['abc123']!.audioPath;

    await notifier.remove('abc123');

    expect(File(path).existsSync(), isFalse);
    expect(container.read(downloadsProvider).saved, isEmpty);
    expect(titles(container), ['Local']);
    expect(database.downloadRecords, isEmpty);
  });
}
