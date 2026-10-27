import 'package:flutter_test/flutter_test.dart';
import 'package:my_zik/data/lyrics_aligner.dart';

/// Heard words from (text, start seconds) pairs, each lasting 0.4 s.
List<TimedWord> heard(List<(String, double)> words) => [
  for (final (text, s) in words)
    TimedWord(
      text,
      Duration(milliseconds: (s * 1000).round()),
      Duration(milliseconds: ((s + 0.4) * 1000).round()),
    ),
];

void main() {
  test('lines start at their first heard word, text stays the lyrics', () {
    final result = alignLyrics(
      ['Ça va, mon ami', 'Tonight we dance'],
      heard([
        ('ca', 2.0),
        ('va', 2.4),
        ('mon', 2.8),
        ('ami', 3.2),
        ('tonigt', 5.0),
        ('we', 5.4),
        ('dance', 5.8),
      ]),
    );
    expect(result.lines.map((l) => l.text), [
      'Ça va, mon ami',
      'Tonight we dance',
    ]);
    expect(result.lines.map((l) => l.time.inMilliseconds), [2000, 5000]);
    expect(result.confidence, 1.0);
  });

  test('a line whose first words were missed starts a bit earlier', () {
    final result = alignLyrics([
      'hello there',
      'all my friends',
    ], heard([('hello', 1.0), ('there', 1.4), ('friends', 10.0)]));
    expect(result.lines.last.time, const Duration(milliseconds: 9300));
  });

  test('ignores hallucinated words and spreads unheard lines', () {
    final result = alignLyrics(
      ['one two', 'three four', 'five six'],
      heard([
        ('thanks', 0.5),
        ('for', 0.9),
        ('watching', 1.3),
        ('one', 10.0),
        ('two', 10.4),
        ('five', 20.0),
        ('six', 20.4),
      ]),
    );
    expect(result.lines.map((l) => l.time.inSeconds), [10, 15, 20]);
    expect(result.confidence, closeTo(4 / 6, 1e-9));
  });

  test('a long silence after a heard line becomes a break', () {
    final result = alignLyrics(
      ['first line', 'second line'],
      heard([('first', 1.0), ('line', 1.4), ('second', 30.0), ('line', 30.4)]),
    );
    expect(result.lines.map((l) => l.text), ['first line', '', 'second line']);
    expect(result.lines[1].time, const Duration(milliseconds: 2300));
  });

  test('timestamps always increase', () {
    final result = alignLyrics([
      'a b',
      'c d',
      'e f',
    ], heard([('a', 4.0), ('e', 4.0)]));
    for (var i = 1; i < result.lines.length; i++) {
      expect(result.lines[i].time > result.lines[i - 1].time, isTrue);
    }
  });

  test('nothing heard gives no lines', () {
    final result = alignLyrics(['la la la'], heard([('hello', 1.0)]));
    expect(result.lines, isEmpty);
    expect(result.confidence, 0);
  });
}
