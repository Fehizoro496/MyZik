import 'package:flutter_test/flutter_test.dart';
import 'package:my_zik/data/lyrics_editing.dart';
import 'package:my_zik/data/lyrics_repository.dart';

TimedRow row(int s, String text, {bool stanza = false, String? label}) =>
    TimedRow(
      Duration(seconds: s),
      text,
      stanzaStart: stanza,
      label: label,
    );

List<(int, String)> summary(List<TimedRow> rows) => [
  for (final r in rows) (r.time.inMilliseconds, r.text),
];

void main() {
  final rows = [
    row(1, 'Hello', stanza: true, label: 'Verse'),
    row(3, 'there'),
    row(5, ''),
    row(8, 'Chorus line', stanza: true, label: 'Chorus'),
    row(10, 'Last'),
  ];

  test('rows rebuild plain text with stanzas and labels', () {
    expect(
      plainOf(rows),
      '[Verse]\nHello\nthere\n\n[Chorus]\nChorus line\nLast',
    );
  });

  test('rows keep stanzas from the plain text and old timed labels', () {
    final lyrics = Lyrics(
      source: LyricsSource.lrclib,
      plain: 'A\n\n[Chorus]\nB',
      lines: [
        const LyricLine(Duration(seconds: 1), 'A'),
        const LyricLine(Duration(seconds: 2), '[Bridge]'),
        const LyricLine(Duration(seconds: 3), 'B'),
      ],
    );
    final result = rowsOf(lyrics);
    expect(result.map((r) => r.text), ['A', 'B']);
    expect(result[1].stanzaStart, isTrue);
    expect(result[1].label, 'Bridge');
  });

  test('merge joins lines at the first time and drops breaks between', () {
    final merged = mergeRows(rows, {1, 3})!;
    expect(summary(merged), [
      (1000, 'Hello'),
      (3000, 'there Chorus line'),
      (10000, 'Last'),
    ]);
    expect(mergeRows(rows, {1}), isNull);
  });

  test('editing a row with several lines splits it up to the next row', () {
    final split = editRow(rows, 3, 'Chorus\nline')!;
    expect(summary(split).sublist(3, 5), [(8000, 'Chorus'), (9000, 'line')]);
    expect(split[3].label, 'Chorus');
    expect(editRow(rows, 0, '  Hi  ')![0].text, 'Hi');
  });

  test('delete hands the stanza to the next line and tidies breaks', () {
    final result = deleteRows(rows, {3})!;
    expect(summary(result), [
      (1000, 'Hello'),
      (3000, 'there'),
      (5000, ''),
      (10000, 'Last'),
    ]);
    expect(result.last.stanzaStart, isTrue);
    expect(result.last.label, 'Chorus');
    expect(summary(deleteRows(rows, {0, 1})!).first, (8000, 'Chorus line'));
    expect(deleteRows([row(1, 'Only')], {0}), isNull);
  });

  test('shifting or setting times never breaks the order', () {
    expect(
      shiftRows(rows, {3, 4}, const Duration(milliseconds: -500))![3].time,
      const Duration(milliseconds: 7500),
    );
    expect(shiftRows(rows, {3}, const Duration(seconds: -3)), isNull);
    expect(shiftRows(rows, {0}, const Duration(seconds: -2)), isNull);
    expect(
      setRowTime(rows, 1, const Duration(seconds: 4))![1].time.inSeconds,
      4,
    );
    expect(setRowTime(rows, 1, const Duration(seconds: 6)), isNull);
  });

  test('breaks go halfway to the next line, never twice in a row', () {
    expect(insertBreakAfter(rows, 0)![1].time, const Duration(seconds: 2));
    expect(insertBreakAfter(rows, 1), isNull);
    expect(insertBreakAfter(rows, 4)!.last.time, const Duration(seconds: 14));
  });

  test('retiming keeps unchanged and corrected lines, spreads new ones', () {
    final old = linesOf(rows);
    final result = retimeLyrics(
      old,
      '[Verse]\nHello\nthere, fixed\n\n[Chorus]\nChorus line\nNew line\nLast',
    );
    expect(summary(result.rows), [
      (1000, 'Hello'),
      (3000, 'there, fixed'),
      (5000, ''),
      (8000, 'Chorus line'),
      (9000, 'New line'),
      (10000, 'Last'),
    ]);
    expect(result.estimated, 1);
    expect(result.rows[3].label, 'Chorus');
  });
}
