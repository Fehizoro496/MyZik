import 'package:flutter_test/flutter_test.dart';
import 'package:my_zik/data/lyrics_repository.dart';
import 'package:my_zik/data/lyrics_structure.dart';

void main() {
  test('normalizes web text and keeps single stanza breaks', () {
    expect(
      normalizeLyricsText(
        'I&#39;m here&nbsp; now<br>Rock &amp; roll\r\n\r\n\r\n  Next   one  \n\n',
      ),
      "I'm here now\nRock & roll\n\nNext one",
    );
  });

  test('splits stanzas and keeps labels out of the sung lines', () {
    final stanzas = parseLyricsStructure('''
[Verse 1]
Line one
Line two

Refrain :
Chorus line

[Bridge] Bridge line
Couplet 2
Last line''');
    expect(stanzas.map((s) => s.label), [
      'Verse 1',
      'Refrain',
      'Bridge',
      'Couplet 2',
    ]);
    expect(stanzas.map((s) => s.lines), [
      ['Line one', 'Line two'],
      ['Chorus line'],
      ['Bridge line'],
      ['Last line'],
    ]);
    expect(lyricLinesOf('[Chorus]\nA\n\nB'), ['A', 'B']);
  });

  test('timestamps in brackets are not section labels', () {
    expect(isSectionLabel('[00:12.00]'), isFalse);
    expect(isSectionLabel('[Chorus: Guest]'), isTrue);
    expect(isSectionLabel('Chorus girls dance'), isFalse);
  });

  test('stanza starts follow the plain text, repeated choruses included', () {
    const plain = '[Verse]\nA\nB\n\n[Chorus]\nC\nD';
    LyricLine at(int s, String text) => LyricLine(Duration(seconds: s), text);
    final starts = stanzaStarts([
      at(1, 'A'),
      at(2, 'B'),
      at(3, ''),
      at(4, 'C'),
      at(5, 'D'),
      at(6, 'Unknown ad-lib'),
    ], plain);
    expect(starts, {0: 'Verse', 3: 'Chorus'});
  });
}
