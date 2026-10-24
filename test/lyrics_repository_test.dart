import 'package:flutter_test/flutter_test.dart';
import 'package:my_zik/data/lyrics_repository.dart';

void main() {
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
    expect(
      cleanTrackQuery('Blinding Lights [Lyrics]', 'The Weeknd - Topic'),
      (title: 'Blinding Lights', artist: 'The Weeknd'),
    );
  });
}
