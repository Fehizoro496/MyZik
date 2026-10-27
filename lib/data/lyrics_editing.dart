import 'dart:math';

import 'lyrics_repository.dart';
import 'lyrics_structure.dart';

/// One timed line in the lyrics editor. Remembers the stanza it opens (and
/// that stanza's label) so the plain text can be rebuilt with its structure
/// once lines are merged, split or deleted. Empty [text] is a break.
class TimedRow {
  const TimedRow(this.time, this.text, {this.stanzaStart = false, this.label});

  final Duration time;
  final String text;
  final bool stanzaStart;
  final String? label;

  bool get isBreak => text.isEmpty;

  TimedRow withTime(Duration time) =>
      TimedRow(time, text, stanzaStart: stanzaStart, label: label);

  TimedRow withText(String text) =>
      TimedRow(time, text, stanzaStart: stanzaStart, label: label);

  TimedRow withStanza(bool stanzaStart, String? label) =>
      TimedRow(time, text, stanzaStart: stanzaStart, label: label);
}

/// Editor rows for synced [lyrics]. Section labels timed as lines by older
/// synchronizations become the label of the stanza they introduce.
List<TimedRow> rowsOf(Lyrics lyrics) {
  final starts = stanzaStarts(lyrics.lines, lyrics.plain);
  final rows = <TimedRow>[];
  String? pendingLabel;
  for (var i = 0; i < lyrics.lines.length; i++) {
    final line = lyrics.lines[i];
    if (isSectionLabel(line.text)) {
      pendingLabel = line.text.replaceAll(RegExp(r'^\[|\]$|:$'), '').trim();
      continue;
    }
    final label = pendingLabel ?? starts[i];
    rows.add(
      TimedRow(
        line.time,
        line.text,
        stanzaStart:
            line.text.isNotEmpty &&
            (pendingLabel != null || starts.containsKey(i)),
        label: line.text.isEmpty ? null : label,
      ),
    );
    if (line.text.isNotEmpty) pendingLabel = null;
  }
  return rows;
}

List<LyricLine> linesOf(List<TimedRow> rows) => [
  for (final row in rows) LyricLine(row.time, row.text),
];

/// Plain text for [rows]: a blank line before each stanza and its label in
/// brackets, so it parses back to the same structure.
String plainOf(List<TimedRow> rows) {
  final out = <String>[];
  for (final row in rows) {
    if (row.isBreak) continue;
    if (row.stanzaStart && out.isNotEmpty) out.add('');
    if (row.stanzaStart && row.label != null) out.add('[${row.label}]');
    out.add(row.text);
  }
  return out.join('\n');
}

/// Merges the rows from the first to the last of [selected] into one line
/// sung at the first one's time; breaks in between are dropped. Null when
/// there is nothing to merge.
List<TimedRow>? mergeRows(List<TimedRow> rows, Set<int> selected) {
  if (selected.length < 2) return null;
  final from = selected.reduce(min);
  final to = selected.reduce(max);
  final texts = [
    for (var i = from; i <= to; i++)
      if (!rows[i].isBreak) rows[i].text.trim(),
  ];
  if (texts.isEmpty) return null;
  final first = rows.sublist(from, to + 1).firstWhere((r) => !r.isBreak);
  final merged = TimedRow(
    rows[from].time,
    texts.join(' '),
    stanzaStart: first.stanzaStart,
    label: first.label,
  );
  return [...rows.sublist(0, from), merged, ...rows.sublist(to + 1)];
}

/// Replaces row [index]'s text. Each extra line of [text] becomes a row of
/// its own (a split), timed evenly up to the next row. Empty text deletes
/// the row. Null when there isn't room between the two timestamps.
List<TimedRow>? editRow(List<TimedRow> rows, int index, String text) {
  final texts = [
    for (final line in text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];
  if (texts.isEmpty) return deleteRows(rows, {index});
  final row = rows[index];
  final start = row.time;
  final end = index + 1 < rows.length
      ? rows[index + 1].time
      : start + const Duration(seconds: 2) * texts.length;
  final step = (end - start) ~/ texts.length;
  if (step < const Duration(milliseconds: 50)) return null;
  return [
    ...rows.sublist(0, index),
    for (var k = 0; k < texts.length; k++)
      k == 0
          ? TimedRow(
              start,
              texts[0],
              stanzaStart: row.stanzaStart,
              label: row.label,
            )
          : TimedRow(start + step * k, texts[k]),
    ...rows.sublist(index + 1),
  ];
}

/// Removes [selected] rows. A deleted stanza opening passes its stanza (and
/// label) to the next remaining line. Null when no lyric line would be left.
List<TimedRow>? deleteRows(List<TimedRow> rows, Set<int> selected) {
  final result = <TimedRow>[];
  ({String? label})? carry;
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    if (selected.contains(i)) {
      if (row.stanzaStart) carry = (label: row.label);
      continue;
    }
    if (carry != null && !row.isBreak) {
      result.add(row.stanzaStart ? row : row.withStanza(true, carry.label));
      carry = null;
    } else {
      result.add(row);
    }
  }
  if (result.every((row) => row.isBreak)) return null;
  // A break can't open the lyrics or follow another break.
  return [
    for (var i = 0; i < result.length; i++)
      if (!result[i].isBreak || (i > 0 && !result[i - 1].isBreak)) result[i],
  ];
}

/// Moves [selected] rows by [delta]. Null when that would put them before
/// zero or out of order with their neighbours.
List<TimedRow>? shiftRows(
  List<TimedRow> rows,
  Set<int> selected,
  Duration delta,
) {
  final shifted = [
    for (var i = 0; i < rows.length; i++)
      selected.contains(i) ? rows[i].withTime(rows[i].time + delta) : rows[i],
  ];
  return _ordered(shifted) ? shifted : null;
}

/// Sets row [index]'s timestamp. Null when it would break the order.
List<TimedRow>? setRowTime(List<TimedRow> rows, int index, Duration time) {
  final updated = [...rows]..[index] = rows[index].withTime(time);
  return _ordered(updated) ? updated : null;
}

/// Adds a break after row [index], halfway to the next line (or 4 s later
/// for the last one). Null after a break or without room.
List<TimedRow>? insertBreakAfter(List<TimedRow> rows, int index) {
  final row = rows[index];
  final next = index + 1 < rows.length ? rows[index + 1] : null;
  if (row.isBreak || (next?.isBreak ?? false)) return null;
  final time = next == null
      ? row.time + const Duration(seconds: 4)
      : row.time + (next.time - row.time) ~/ 2;
  if (time <= row.time || (next != null && time >= next.time)) return null;
  return [
    ...rows.sublist(0, index + 1),
    TimedRow(time, ''),
    ...rows.sublist(index + 1),
  ];
}

bool _ordered(List<TimedRow> rows) {
  if (rows.isNotEmpty && rows.first.time < Duration.zero) return false;
  for (var i = 1; i < rows.length; i++) {
    if (rows[i].time <= rows[i - 1].time) return false;
  }
  return true;
}

/// Carries the timings of [old] lines over to an edited [plain] text: lines
/// left unchanged keep their time, lines corrected in place take the time of
/// the line they replace, and added lines are spread between their
/// neighbours ([estimated] counts those). Breaks keep their time.
({List<TimedRow> rows, int estimated}) retimeLyrics(
  List<LyricLine> old,
  String plain,
) {
  final newRows = <TimedRow>[
    for (final stanza in parseLyricsStructure(plain))
      for (var k = 0; k < stanza.lines.length; k++)
        TimedRow(
          Duration.zero,
          stanza.lines[k],
          stanzaStart: k == 0,
          label: k == 0 ? stanza.label : null,
        ),
  ];
  final sung = [
    for (final line in old)
      if (line.text.isNotEmpty && !isSectionLabel(line.text)) line,
  ];
  final breaks = [
    for (final line in old)
      if (line.text.isEmpty) line.time,
  ];
  if (newRows.isEmpty) return (rows: const [], estimated: 0);

  final pairs = _commonLines(
    [for (final l in sung) _key(l.text)],
    [for (final r in newRows) _key(r.text)],
  );
  final times = List<Duration?>.filled(newRows.length, null);
  var estimated = 0;
  // Gaps between matched lines, plus before the first and after the last.
  final anchors = [(-1, -1), ...pairs, (sung.length, newRows.length)];
  for (var a = 0; a + 1 < anchors.length; a++) {
    final (oldFrom, newFrom) = anchors[a];
    final (oldTo, newTo) = anchors[a + 1];
    if (newTo < newRows.length && oldTo < sung.length) {
      times[newTo] = sung[oldTo].time;
    }
    final oldGap = sung.sublist(oldFrom + 1, oldTo);
    final count = newTo - newFrom - 1;
    if (count <= 0) continue;
    if (oldGap.length == count) {
      // Same number of lines: corrected in place.
      for (var k = 0; k < count; k++) {
        times[newFrom + 1 + k] = oldGap[k].time;
      }
      continue;
    }
    estimated += count;
    final lo = oldFrom >= 0 ? sung[oldFrom].time : null;
    final hi = oldTo < sung.length ? sung[oldTo].time : null;
    const spacing = Duration(seconds: 3);
    final Duration from;
    final Duration to;
    if (oldGap.isNotEmpty) {
      from = oldGap.first.time;
      to = hi ?? oldGap.last.time + spacing;
    } else {
      to = hi ?? (lo ?? Duration.zero) + spacing * (count + 1);
      final fallback = to - spacing * (count + 1);
      from = lo ?? (fallback < Duration.zero ? Duration.zero : fallback);
    }
    for (var k = 0; k < count; k++) {
      final fraction = oldGap.isNotEmpty ? k / count : (k + 1) / (count + 1);
      times[newFrom + 1 + k] = from + (to - from) * fraction;
    }
  }

  final rows = <TimedRow>[
    for (var i = 0; i < newRows.length; i++) newRows[i].withTime(times[i]!),
  ];
  // Put the breaks back where they fall between two lines.
  for (final time in breaks) {
    final at = rows.indexWhere((row) => row.time >= time);
    if (at <= 0 || rows[at].time == time) continue;
    if (rows[at - 1].isBreak || rows[at].isBreak) continue;
    rows.insert(at, TimedRow(time, ''));
  }
  for (var i = 1; i < rows.length; i++) {
    if (rows[i].time <= rows[i - 1].time) {
      rows[i] = rows[i].withTime(
        rows[i - 1].time + const Duration(milliseconds: 10),
      );
    }
  }
  return (rows: rows, estimated: estimated);
}

/// Pairs (old index, new index) of the longest run of identical lines kept
/// in order.
List<(int, int)> _commonLines(List<String> a, List<String> b) {
  final width = b.length + 1;
  final score = List<int>.filled((a.length + 1) * width, 0);
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      score[i * width + j] = a[i] == b[j]
          ? score[(i + 1) * width + j + 1] + 1
          : max(score[(i + 1) * width + j], score[i * width + j + 1]);
    }
  }
  final pairs = <(int, int)>[];
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
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

String _key(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');
