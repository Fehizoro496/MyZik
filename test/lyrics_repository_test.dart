import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_zik/data/lyrics_repository.dart';
import 'package:my_zik/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  group('parseLrc', () {
    test('parses timestamps, skips metadata and sorts', () {
      final lines = parseLrc('''
[ar:Someone]
[00:12.50] Second
[00:01.00]First
[01:02.345] Third
''');
      expect(lines.map((l) => l.text), ['First', 'Second', 'Third']);
      expect(lines[1].time, const Duration(milliseconds: 12500));
      expect(lines[2].time, const Duration(minutes: 1, milliseconds: 2345));
    });

    test('expands lines carrying several timestamps', () {
      final lines = parseLrc('[00:10.00][00:30.00] Chorus\n[00:20.00] Verse');
      expect(lines.map((l) => l.text), ['Chorus', 'Verse', 'Chorus']);
    });
  });

  group('LRC export and import', () {
    test('formatLrc writes tags and round-trips through parseLrc', () {
      const lines = [
        LyricLine(Duration(milliseconds: 1000), 'First'),
        LyricLine(Duration(milliseconds: 12500), ''),
        LyricLine(Duration(minutes: 1, milliseconds: 2345), 'Third'),
      ];
      final lrc = formatLrc(
        lines,
        title: 'Song [Live]',
        artist: 'Artist',
        length: const Duration(minutes: 3, seconds: 12),
      );
      expect(
        lrc,
        '[ti:Song Live]\n'
        '[ar:Artist]\n'
        '[length:03:12]\n'
        '[00:01.00]First\n'
        '[00:12.50]\n'
        '[01:02.35]Third\n',
      );
      expect(parseLrc(lrc).map((l) => (l.time.inMilliseconds, l.text)), [
        (1000, 'First'),
        (12500, ''),
        (62350, 'Third'),
      ]);
    });

    test('formatLrc carries rounded hundredths into the next minute', () {
      final lrc = formatLrc(const [
        LyricLine(Duration(milliseconds: 59996), 'Edge'),
      ]);
      expect(lrc, '[01:00.00]Edge\n');
    });

    test('importLrc keeps one line per timestamp, in order', () {
      final lines = importLrc('''
[ar:Someone]
[00:20.00]Second
[00:10.00][00:30.00]Chorus
[00:10.00]Duplicate time
plain line without a timestamp
''');
      expect(lines.map((l) => (l.time.inSeconds, l.text)), [
        (10, 'Chorus'),
        (20, 'Second'),
        (30, 'Chorus'),
      ]);
      expect(importLrc('Just words\nNo timings'), isEmpty);
    });
  });

  test('indexAt finds the line being sung', () {
    final lyrics = Lyrics(
      source: LyricsSource.lrclib,
      lines: parseLrc('[00:05.00]a\n[00:10.00]b\n[00:15.00]c'),
    );
    expect(lyrics.indexAt(const Duration(seconds: 2)), -1);
    expect(lyrics.indexAt(const Duration(seconds: 5)), 0);
    expect(lyrics.indexAt(const Duration(seconds: 12)), 1);
    expect(lyrics.indexAt(const Duration(minutes: 3)), 2);
  });

  test('cleanTrackQuery strips YouTube noise and splits artist', () {
    expect(
      cleanTrackQuery(
        'The Weeknd - Blinding Lights (Official Video) ft. Someone',
        'TheWeekndVEVO',
      ),
      (title: 'Blinding Lights', artist: 'The Weeknd'),
    );
    expect(cleanTrackQuery('Blinding Lights [Lyrics]', 'The Weeknd - Topic'), (
      title: 'Blinding Lights',
      artist: 'The Weeknd',
    ));
  });

  test('manual synchronization keeps the original text and source', () async {
    final directory = await Directory.systemTemp.createTemp('myzik_sync_test_');
    addTearDown(() => directory.delete(recursive: true));
    final repository = LyricsRepository(cacheDirectory: () async => directory);
    const song = Song(id: 6, title: 'Song', artist: 'Artist');
    const original = Lyrics(
      source: LyricsSource.web,
      plain: 'First line\nSecond line',
      sourceUrl: 'https://example.org/lyrics',
    );

    final saved = await repository.saveSynchronization(song, original, [
      const LyricLine(Duration(seconds: 2), 'First line'),
      const LyricLine(Duration(seconds: 5), 'Second line'),
    ]);

    expect(saved.synced, isTrue);
    expect(saved.plain, original.plain);
    expect(saved.sourceUrl, original.sourceUrl);
    final fromCache = await repository.find(song);
    expect(fromCache?.lines.map((line) => line.time.inSeconds), [2, 5]);
  });

  test('synchronized lyrics can be redone, with instrumental breaks', () async {
    final directory = await Directory.systemTemp.createTemp('myzik_sync_test_');
    addTearDown(() => directory.delete(recursive: true));
    final repository = LyricsRepository(cacheDirectory: () async => directory);
    const song = Song(id: 8, title: 'Song', artist: 'Artist');
    final synced = Lyrics(
      source: LyricsSource.lrclib,
      lines: parseLrc('[00:01.00]A\n[00:02.00]B'),
      plain: 'A\nB',
    );

    final redone = await repository.saveSynchronization(song, synced, const [
      LyricLine(Duration(seconds: 3), 'A'),
      LyricLine(Duration(seconds: 6), ''),
      LyricLine(Duration(seconds: 9), 'B'),
    ]);

    expect(redone.source, LyricsSource.lrclib);
    expect(redone.plain, 'A\nB');
    final fromCache = await repository.find(song);
    expect(fromCache?.lines.map((line) => line.text), ['A', '', 'B']);
    expect(fromCache?.indexAt(const Duration(seconds: 7)), 1);
  });

  test('manual synchronization rejects breaks without lyrics', () async {
    final directory = await Directory.systemTemp.createTemp('myzik_sync_test_');
    addTearDown(() => directory.delete(recursive: true));
    final repository = LyricsRepository(cacheDirectory: () async => directory);
    const song = Song(id: 9, title: 'Song', artist: 'Artist');
    const original = Lyrics(source: LyricsSource.web, plain: 'A');
    await expectLater(
      repository.saveSynchronization(song, original, const [
        LyricLine(Duration(seconds: 5), ''),
      ]),
      throwsArgumentError,
    );
  });

  test('edited and hand-written lyrics are kept, empty ones refused', () async {
    final directory = await Directory.systemTemp.createTemp('myzik_edit_test_');
    addTearDown(() => directory.delete(recursive: true));
    final repository = LyricsRepository(cacheDirectory: () async => directory);
    const song = Song(id: 10, title: 'Song', artist: 'Artist');

    await repository.saveLyrics(
      song,
      const Lyrics(source: LyricsSource.manual, plain: 'Mine', edited: true),
    );
    final fromCache = await repository.find(song);
    expect(fromCache?.source, LyricsSource.manual);
    expect(fromCache?.edited, isTrue);
    expect(fromCache?.plain, 'Mine');

    await expectLater(
      repository.saveLyrics(
        song,
        const Lyrics(source: LyricsSource.manual, plain: '  '),
      ),
      throwsArgumentError,
    );
  });

  test(
    'lyrics cache falls back to the same recording under another key',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'myzik_key_match_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = LyricsRepository(
        dio: _offlineDio(),
        apiKey: '',
        cacheDirectory: () async => directory,
      );
      const first = Song(
        id: 12,
        title: 'A Song!',
        artist: 'An Artist',
        duration: Duration(seconds: 200),
        contentKey: 'fp:first',
      );
      // Another encoding on another device: other fingerprint, durations a
      // second apart.
      const second = Song(
        id: 90,
        title: 'a song',
        artist: 'AN ARTIST',
        duration: Duration(seconds: 201),
        contentKey: 'fp:second',
      );
      const lyrics = Lyrics(source: LyricsSource.manual, plain: 'Saved words');
      await repository.saveLyrics(first, lyrics);
      expect((await repository.find(second))?.plain, 'Saved words');

      // A different recording of the same song is not a match.
      const live = Song(
        id: 91,
        title: 'A Song',
        artist: 'An Artist',
        duration: Duration(seconds: 260),
        contentKey: 'fp:live',
      );
      expect(await repository.find(live), isNull);
    },
  );

  test('manual synchronization rejects unordered timestamps', () async {
    final directory = await Directory.systemTemp.createTemp('myzik_sync_test_');
    addTearDown(() => directory.delete(recursive: true));
    final repository = LyricsRepository(cacheDirectory: () async => directory);
    const song = Song(id: 7, title: 'Song', artist: 'Artist');
    const original = Lyrics(source: LyricsSource.web, plain: 'A\nB');
    await expectLater(
      repository.saveSynchronization(song, original, const [
        LyricLine(Duration(seconds: 5), 'A'),
        LyricLine(Duration(seconds: 5), 'B'),
      ]),
      throwsArgumentError,
    );
  });

  test(
    'lyrics migrated from a legacy cache file survive a new fingerprint',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'myzik_legacy_cache_',
      );
      addTearDown(() => directory.delete(recursive: true));
      // Written before portable keys: named after the MediaStore id.
      File('${directory.path}/lyrics/12.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode(
            const Lyrics(
              source: LyricsSource.manual,
              plain: 'Saved words',
            ).toJson(),
          ),
        );
      final repository = LyricsRepository(
        dio: _offlineDio(),
        apiKey: '',
        cacheDirectory: () async => directory,
      );
      const song = Song(
        id: 12,
        title: 'A Song',
        artist: 'An Artist',
        duration: Duration(seconds: 200),
        contentKey: 'fp:before',
      );
      expect((await repository.find(song))?.plain, 'Saved words');
      expect(File('${directory.path}/lyrics/12.json').existsSync(), isFalse);

      // Retagging rewrites the head of the file, so its fingerprint changes.
      final retagged = song.withContentKey('fp:after');
      expect((await repository.find(retagged))?.plain, 'Saved words');
    },
  );

  test(
    'stored lyrics are reported for sync, found apart from hand-made',
    () async {
      final directory = await Directory.systemTemp.createTemp('myzik_stored_');
      addTearDown(() => directory.delete(recursive: true));
      final reported = <(String, bool)>[];
      final repository = LyricsRepository(
        dio: _offlineDio(),
        apiKey: '',
        cacheDirectory: () async => directory,
        onStored: (songKey, {required found}) => reported.add((songKey, found)),
      );
      // Found by an older version, cached under the device id.
      File('${directory.path}/lyrics/3.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode(
            const Lyrics(source: LyricsSource.lrclib, plain: 'Found').toJson(),
          ),
        );
      const found = Song(id: 3, title: 'A', artist: 'B', contentKey: 'fp:a');
      const timed = Song(id: 4, title: 'C', artist: 'D', contentKey: 'fp:c');
      const missing = Song(id: 5, title: 'E', artist: 'F', contentKey: 'fp:e');

      await repository.find(found);
      await repository.saveLyrics(
        timed,
        const Lyrics(source: LyricsSource.manual, plain: 'Mine'),
      );
      // A "not found" is not lyrics: nothing to sync.
      expect(await repository.find(missing), isNull);

      expect(reported, [('fp:a', true), ('fp:c', false)]);
      expect(await repository.storedLyrics(), {'fp:a': true, 'fp:c': false});
      expect((await repository.readStoredLyrics('fp:a'))?['plain'], 'Found');
      expect(await repository.readStoredLyrics('fp:e'), isNull);

      // Lyrics from the other device are stored without being reported back.
      await repository.writeSyncedLyrics(
        'fp:e',
        const Lyrics(source: LyricsSource.manual, plain: 'Synced').toJson(),
      );
      expect(reported, hasLength(2));
      expect((await repository.find(missing))?.plain, 'Synced');
    },
  );
}

/// LRCLIB answers "not found", so only the cache can provide lyrics.
Dio _offlineDio() => Dio()
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) => handler.reject(
        DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 404),
        ),
      ),
    ),
  );
