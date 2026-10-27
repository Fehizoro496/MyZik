import 'lyrics_repository.dart';

/// A stanza of plain lyrics: the lines between two blank lines, with the
/// section [label] that introduced it ("Chorus", "Couplet 2"…), if any.
class LyricsStanza {
  const LyricsStanza(this.lines, {this.label});

  final String? label;
  final List<String> lines;
}

/// Cleans lyrics text as found on web pages: HTML line breaks and entities,
/// non-breaking spaces, Windows newlines, runs of spaces and of blank lines.
/// Stanza breaks (a single blank line) are kept.
String normalizeLyricsText(String text) {
  final decoded = _decodeEntities(
    text
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(
            r'</?(?:p|div|span|i|b|em|strong)\b[^>]*>',
            caseSensitive: false,
          ),
          '',
        ),
  ).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = <String>[];
  for (final raw in decoded.split('\n')) {
    final line = raw
        .replaceAll(RegExp('[   \t ]+'), ' ')
        .replaceAll(RegExp('[​‌‍﻿]'), '')
        .trim();
    if (line.isEmpty && (lines.isEmpty || lines.last.isEmpty)) continue;
    lines.add(line);
  }
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines.join('\n');
}

/// Splits plain lyrics into stanzas. Blank lines end a stanza; section labels
/// (`[Chorus]`, `Refrain :`, `Couplet 2`) start one and are kept apart from
/// the lyric lines, so they are never timed or sung.
List<LyricsStanza> parseLyricsStructure(String plain) {
  final stanzas = <LyricsStanza>[];
  String? label;
  var lines = <String>[];
  void close() {
    if (lines.isNotEmpty) stanzas.add(LyricsStanza(lines, label: label));
    label = null;
    lines = [];
  }

  for (final line in normalizeLyricsText(plain).split('\n')) {
    if (line.isEmpty) {
      close();
      continue;
    }
    final section = _sectionOf(line);
    if (section == null) {
      lines.add(line);
      continue;
    }
    // A label right after another one (or after nothing) just replaces it.
    if (lines.isNotEmpty) close();
    label = section.label;
    if (section.rest.isNotEmpty) lines.add(section.rest);
  }
  close();
  return stanzas;
}

/// The lines actually sung, in order, without labels or blank lines.
List<String> lyricLinesOf(String plain) => [
  for (final stanza in parseLyricsStructure(plain)) ...stanza.lines,
];

/// Whether [line] is only a section label, like timed lines saved before
/// labels were recognised.
bool isSectionLabel(String line) {
  final section = _sectionOf(line.trim());
  return section != null && section.rest.isEmpty;
}

/// For timed [lines], which ones open a stanza of [plain], mapped to the
/// stanza's label (null when it has none). Lines are matched to the plain
/// text in order, so repeated choruses in the LRC still line up; a line that
/// can't be matched simply gets no stanza break.
Map<int, String?> stanzaStarts(List<LyricLine> lines, String? plain) {
  if (plain == null || plain.trim().isEmpty) return const {};
  final flat = <({String key, bool first, String? label})>[
    for (final stanza in parseLyricsStructure(plain))
      for (var k = 0; k < stanza.lines.length; k++)
        (
          key: _key(stanza.lines[k]),
          first: k == 0,
          label: k == 0 ? stanza.label : null,
        ),
  ];
  const lookAhead = 8;
  final starts = <int, String?>{};
  var p = 0;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].text.isEmpty) continue;
    final key = _key(lines[i].text);
    final end = p + lookAhead < flat.length ? p + lookAhead : flat.length;
    for (var q = p; q < end; q++) {
      if (flat[q].key != key) continue;
      if (flat[q].first) starts[i] = flat[q].label;
      p = q + 1;
      break;
    }
  }
  return starts;
}

String _key(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

final _bracketLabel = RegExp(r'^\[([^\]]{1,48})\]\s*(.*)$');
final _wordLabel = RegExp(
  r'^((?:pre-?|pré-?)?(?:chorus|refrain|verse|couplet|bridge|pont|intro|'
  r'outro|hook|interlude|post-?chorus)(?:\s*\d+)?(?:\s*[\(\[][^\)\]]*[\)\]])?)'
  r'\s*:?$',
  caseSensitive: false,
);
final _timestamp = RegExp(r'^\d+:\d');

({String label, String rest})? _sectionOf(String line) {
  final bracket = _bracketLabel.firstMatch(line);
  if (bracket != null && !_timestamp.hasMatch(bracket[1]!)) {
    return (label: bracket[1]!.trim(), rest: bracket[2]!.trim());
  }
  final word = _wordLabel.firstMatch(line);
  if (word != null) return (label: word[1]!.trim(), rest: '');
  return null;
}

const _namedEntities = {
  'amp': '&',
  'quot': '"',
  'apos': "'",
  'lt': '<',
  'gt': '>',
  'nbsp': ' ',
  'rsquo': '’',
  'lsquo': '‘',
  'rdquo': '”',
  'ldquo': '“',
  'hellip': '…',
  'mdash': '—',
  'ndash': '–',
};

String _decodeEntities(String text) =>
    text.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
      final name = m[1]!;
      if (name.startsWith('#x') || name.startsWith('#X')) {
        final code = int.tryParse(name.substring(2), radix: 16);
        return code == null ? m[0]! : String.fromCharCode(code);
      }
      if (name.startsWith('#')) {
        final code = int.tryParse(name.substring(1));
        return code == null ? m[0]! : String.fromCharCode(code);
      }
      return _namedEntities[name.toLowerCase()] ?? m[0]!;
    });
