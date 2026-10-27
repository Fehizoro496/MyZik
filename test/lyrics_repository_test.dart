import 'dart:io';

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
    'lyrics cache falls back to normalized metadata across different files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'myzik_key_match_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final firstAudio = File('${directory.path}/first.mp3')
        ..writeAsBytesSync([1, 2, 3]);
      final secondAudio = File('${directory.path}/second.mp3')
        ..writeAsBytesSync([4, 5, 6]);
      final repository = LyricsRepository(
        cacheDirectory: () async => directory,
      );
      final first = Song(
        id: 12,
        title: 'A Song!',
        artist: 'An Artist',
        duration: const Duration(seconds: 200),
        filePath: firstAudio.path,
      );
      final second = Song(
        id: 90,
        title: 'a song',
        artist: 'AN ARTIST',
        duration: const Duration(seconds: 200),
        filePath: secondAudio.path,
      );
      const lyrics = Lyrics(source: LyricsSource.manual, plain: 'Saved words');
      await repository.saveLyrics(first, lyrics);
      expect((await repository.find(second))?.plain, 'Saved words');
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
}
