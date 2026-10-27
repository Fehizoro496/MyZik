import 'dart:math';
import 'dart:typed_data';

import 'lyrics_repository.dart';

/// A word heard in the audio, with when it is sung (Whisper word timestamps).
class TimedWord {
  const TimedWord(this.text, this.start, this.end);

  final String text;
  final Duration start;
  final Duration end;
}

/// Lyrics timed from a transcription, and how much of them could actually be
/// heard: [confidence] is the share of lyric words found in the audio.
class LyricsAlignment {
  const LyricsAlignment(this.lines, this.confidence);

  /// Strictly increasing timestamps; empty text marks an instrumental break.
  final List<LyricLine> lines;
  final double confidence;
}

/// Times known [lyrics] lines against the [words] a speech-to-text model
/// heard. The text always comes from [lyrics]: the transcription only says
/// *when* words are sung, so its mistakes cost timing, never wrong lyrics.
///
/// Words are matched in order (a longest-common-subsequence over normalized
/// words, tolerating one-letter slips), each line starts at its first matched
/// word, lines with no match are spread between their neighbours, and a
/// silence of at least [breakGap] after a line becomes a break.
LyricsAlignment alignLyrics(
  List<String> lyrics,
  List<TimedWord> words, {
  Duration breakGap = const Duration(seconds: 8),
}) {
  // Lyric words, each tagged with its line.
  final lyricWords = <String>[];
  final lineOf = <int>[];
  final indexInLine = <int>[];
  for (var line = 0; line < lyrics.length; line++) {
    final tokens = _tokens(lyrics[line]);
    for (var k = 0; k < tokens.length; k++) {
      lyricWords.add(tokens[k]);
      lineOf.add(line);
      indexInLine.add(k);
    }
  }
  // Heard words; a Whisper "word" may hold several tokens ("l'amour").
  final heard = <String>[];
  final heardAt = <TimedWord>[];
  for (final word in words) {
    for (final token in _tokens(word.text)) {
      heard.add(token);
      heardAt.add(word);
    }
  }

  final matches = _match(lyricWords, heard);
  final starts = List<Duration?>.filled(lyrics.length, null);
  final ends = List<Duration?>.filled(lyrics.length, null);
  for (final (i, j) in matches) {
    final line = lineOf[i];
    if (starts[line] == null) {
      // The line's first words may not have been heard: back up by a typical
      // sung word length for each of them, without overlapping the previous
      // line.
      var start = heardAt[j].start - _wordLength * indexInLine[i];
      final floor = line > 0 ? ends[line - 1] : null;
      if (floor != null && start < floor) start = floor;
      starts[line] = start < Duration.zero ? Duration.zero : start;
    }
    ends[line] = heardAt[j].end;
  }
  final confidence = lyricWords.isEmpty
      ? 0.0
      : matches.length / lyricWords.length;

  final anchors = [
    for (var i = 0; i < lyrics.length; i++)
      if (starts[i] != null) i,
  ];
  if (anchors.isEmpty) return const LyricsAlignment([], 0);

  // Lines nobody heard: spread evenly between the surrounding anchors, and
  // at the average line spacing before the first / after the last one.
  final first = anchors.first;
  final last = anchors.last;
  final spacing = anchors.length < 2
      ? const Duration(seconds: 3)
      : (starts[last]! - starts[first]!) ~/ (last - first);
  for (var i = 0; i < first; i++) {
    final t = starts[first]! - spacing * (first - i);
    starts[i] = t < Duration.zero ? Duration.zero : t;
  }
  for (var a = 0; a + 1 < anchors.length; a++) {
    final from = anchors[a];
    final to = anchors[a + 1];
    for (var i = from + 1; i < to; i++) {
      starts[i] =
          starts[from]! +
          (starts[to]! - starts[from]!) * ((i - from) / (to - from));
    }
  }
  for (var i = last + 1; i < lyrics.length; i++) {
    starts[i] = starts[last]! + spacing * (i - last);
  }

  const minStep = Duration(milliseconds: 100);
  final lines = <LyricLine>[];
  for (var i = 0; i < lyrics.length; i++) {
    var start = starts[i]!;
    if (lines.isNotEmpty && start <= lines.last.time) {
      start = lines.last.time + minStep;
    }
    lines.add(LyricLine(start, lyrics[i]));
    // A long silence after a line that was heard: mark the break so the
    // line doesn't stay lit through the instrumental part.
    final end = ends[i];
    if (end != null && i + 1 < lyrics.length) {
      final breakAt = end + const Duration(milliseconds: 500);
      if (breakAt > start && starts[i + 1]! - end >= breakGap) {
        lines.add(LyricLine(breakAt, ''));
      }
    }
  }
  return LyricsAlignment(lines, confidence);
}

const _wordLength = Duration(milliseconds: 350);

/// Pairs (lyric index, heard index) of the best in-order matching.
List<(int, int)> _match(List<String> a, List<String> b) {
  final n = a.length;
  final m = b.length;
  final width = m + 1;
  final score = Int32List((n + 1) * width);
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      final skip = max(score[(i + 1) * width + j], score[i * width + j + 1]);
      score[i * width + j] = _similar(a[i], b[j])
          ? max(skip, score[(i + 1) * width + j + 1] + 1)
          : skip;
    }
  }
  final pairs = <(int, int)>[];
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (_similar(a[i], b[j]) &&
        score[i * width + j] == score[(i + 1) * width + j + 1] + 1) {
      pairs.add((i, j));
      i++;
      j++;
    } else if (score[(i + 1) * width + j] >= score[i * width + j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return pairs;
}

/// Equal words, or one letter apart for words long enough that it can't be
/// a different short word ("tonight" / "tonite" style slips).
bool _similar(String a, String b) {
  if (a == b) return true;
  if (a.length < 4 || b.length < 4 || (a.length - b.length).abs() > 1) {
    return false;
  }
  return _withinOneEdit(a, b);
}

bool _withinOneEdit(String a, String b) {
  var i = 0;
  var j = 0;
  var edits = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      i++;
      j++;
      continue;
    }
    if (++edits > 1) return false;
    if (a.length > b.length) {
      i++;
    } else if (b.length > a.length) {
      j++;
    } else {
      i++;
      j++;
    }
  }
  return edits + (a.length - i) + (b.length - j) <= 1;
}

final _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Lowercase words without accents or punctuation, so "Ça va," matches "ca va".
List<String> _tokens(String text) => _stripAccents(
  text.toLowerCase(),
).split(_separators).where((t) => t.isNotEmpty).toList();

const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', //
  'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', //
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n', //
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', //
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y', //
  'œ': 'oe', 'æ': 'ae', 'ß': 'ss', '’': "'",
};

String _stripAccents(String text) {
  final buffer = StringBuffer();
  for (final char in text.split('')) {
    buffer.write(_accents[char] ?? char);
  }
  return buffer.toString();
}
