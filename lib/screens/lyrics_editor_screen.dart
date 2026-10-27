import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/lyrics_editing.dart';
import '../data/lyrics_repository.dart';
import '../data/lyrics_structure.dart';
import '../icons.dart';
import '../models.dart';
import '../providers/lyrics_provider.dart';
import '../providers/playback_provider.dart';
import '../theme.dart';
import 'lyrics_view.dart';

enum _Mode { text, timing }

/// Full-screen editor for a track's lyrics.
///
/// *Text* corrects the words freely (or writes lyrics when none were found);
/// on synced lyrics, unchanged and corrected lines keep their timing.
/// *Timing* (synced lyrics only) works on the timed lines: select some to
/// merge, edit or split, delete, nudge, re-time at the playhead or follow by
/// a break, with undo.
class LyricsEditorScreen extends ConsumerStatefulWidget {
  const LyricsEditorScreen({super.key, required this.song, this.lyrics});

  final Song song;

  /// Null to write lyrics from scratch.
  final Lyrics? lyrics;

  static Future<void> open(BuildContext context, Song song, Lyrics? lyrics) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LyricsEditorScreen(song: song, lyrics: lyrics),
      ),
    );
  }

  @override
  ConsumerState<LyricsEditorScreen> createState() => _LyricsEditorState();
}

class _LyricsEditorState extends ConsumerState<LyricsEditorScreen> {
  late final TextEditingController _text;

  /// Timed lines, null when the lyrics aren't synced.
  List<TimedRow>? _rows;
  final _history = <List<TimedRow>>[];
  final _selected = <int>{};
  late _Mode _mode;

  /// Text the rows were last in step with: a different text means the rows
  /// must be re-timed from it.
  late String _textOfRows;

  /// Rows edited since the text was last rebuilt from them.
  bool _rowsChanged = false;
  bool _dirty = false;
  bool _saving = false;
  String? _message;
  bool _messageIsError = false;

  static const _reactionDelay = Duration(milliseconds: 150);
  static const _nudge = Duration(milliseconds: 100);

  @override
  void initState() {
    super.initState();
    final lyrics = widget.lyrics;
    if (lyrics != null && lyrics.synced) {
      _rows = rowsOf(lyrics);
      _textOfRows = plainOf(_rows!);
      _text = TextEditingController(text: _textOfRows);
      _mode = _Mode.timing;
    } else {
      _textOfRows = lyrics?.plain ?? '';
      _text = TextEditingController(text: _textOfRows);
      _mode = _Mode.text;
    }
    _text.addListener(() {
      if (!_dirty && _text.text != _textOfRows) setState(() => _dirty = true);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _say(String message, {bool error = false}) {
    setState(() {
      _message = message;
      _messageIsError = error;
    });
  }

  /// Brings the rows in step with the text after it was edited.
  void _retimeFromText() {
    final rows = _rows;
    if (rows == null || _text.text == _textOfRows) return;
    final result = retimeLyrics(linesOf(rows), _text.text);
    if (result.rows.isEmpty) return;
    _history.add(rows);
    _rows = result.rows;
    _selected.clear();
    _textOfRows = _text.text;
    _rowsChanged = false;
    _message = result.estimated == 0
        ? null
        : '${result.estimated} new line${result.estimated == 1 ? '' : 's'} '
              'got an estimated time: check them below.';
    _messageIsError = false;
  }

  void _switchTo(_Mode mode) {
    if (mode == _mode) return;
    FocusScope.of(context).unfocus();
    setState(() {
      if (mode == _Mode.timing) {
        _retimeFromText();
      } else if (_rowsChanged) {
        _textOfRows = plainOf(_rows!);
        _text.text = _textOfRows;
        _rowsChanged = false;
      }
      _mode = mode;
    });
  }

  /// Applies an edit made in Timing; [next] is null when it isn't possible.
  void _apply(
    List<TimedRow>? next, {
    required String failure,
    bool keepSelection = false,
  }) {
    if (next == null) {
      HapticFeedback.mediumImpact();
      _say(failure, error: true);
      return;
    }
    setState(() {
      _history.add(_rows!);
      _rows = next;
      if (!keepSelection) _selected.clear();
      _rowsChanged = true;
      _dirty = true;
      _message = null;
    });
  }

  void _undo() {
    if (_history.isEmpty) return;
    setState(() {
      _rows = _history.removeLast();
      _selected.clear();
      _rowsChanged = true;
      _message = null;
    });
  }

  Future<void> _save() async {
    final original = widget.lyrics;
    final Lyrics edited;
    if (_rows != null) {
      if (_mode == _Mode.text) _retimeFromText();
      final rows = _rows!;
      edited = Lyrics(
        source: original!.source,
        lines: linesOf(rows),
        plain: plainOf(rows),
        sourceUrl: original.sourceUrl,
        edited: true,
      );
    } else {
      final plain = normalizeLyricsText(_text.text);
      if (lyricLinesOf(plain).isEmpty) {
        _say('Write some lyrics first.', error: true);
        return;
      }
      edited = Lyrics(
        source: original?.source ?? LyricsSource.manual,
        plain: plain,
        sourceUrl: original?.sourceUrl,
        edited: true,
      );
    }
    setState(() => _saving = true);
    try {
      await ref.read(lyricsProvider(widget.song).notifier).saveEdited(edited);
      if (!mounted) return;
      _dirty = false;
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        _say('Could not save the lyrics. Please try again.', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard your changes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the (auto-disposed) lyrics alive while editing.
    ref.watch(lyricsProvider(widget.song));

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          _dirty = false;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.musicBackground,
        body: SafeArea(
          child: Column(
            children: [
              _header(),
              if (_rows != null) _tabs(),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    _message!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _messageIsError
                          ? const Color(0xFFFF8A80)
                          : AppColors.whiteAlpha(0.6),
                      fontSize: 13,
                    ),
                  ),
                ),
              Expanded(
                child: _mode == _Mode.text ? _textEditor() : _timingEditor(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(AppIcons.close, color: AppColors.white),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.lyrics == null ? 'Write lyrics' : 'Edit lyrics',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  widget.song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.whiteAlpha(0.5),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (_mode == _Mode.timing && _history.isNotEmpty)
            IconButton(
              onPressed: _undo,
              tooltip: 'Undo',
              icon: const Icon(AppIcons.undo, color: AppColors.white),
            ),
          LyricsPill(
            label: _saving ? 'Saving…' : 'Save',
            icon: AppIcons.checkCircle,
            onTap: _saving || !_dirty ? null : _save,
          ),
        ],
      ),
    );
  }

  Widget _tabs() {
    Widget tab(String label, _Mode mode) {
      final active = _mode == mode;
      return Expanded(
        child: GestureDetector(
          onTap: () => _switchTo(mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: active ? AppColors.whiteAlpha(0.14) : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: active ? AppColors.white : AppColors.whiteAlpha(0.5),
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.whiteAlpha(0.06),
        borderRadius: BorderRadius.circular(21),
      ),
      child: Row(
        children: [tab('Text', _Mode.text), tab('Timing', _Mode.timing)],
      ),
    );
  }

  Widget _textEditor() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _rows == null
                ? 'One line per sung line. Leave an empty line between '
                      'stanzas and put section names in brackets: [Chorus].'
                : 'Lines you keep or correct in place keep their timing; new '
                      'lines get an estimated one.',
            style: TextStyle(color: AppColors.whiteAlpha(0.45), fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: _text,
              maxLines: null,
              expands: true,
              keyboardType: TextInputType.multiline,
              textAlignVertical: TextAlignVertical.top,
              cursorColor: AppColors.white,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 17,
                height: 1.5,
              ),
              decoration: InputDecoration(
                hintText: '[Verse 1]\nFirst line\nSecond line\n\n[Chorus]\n…',
                hintStyle: TextStyle(color: AppColors.whiteAlpha(0.25)),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timingEditor() {
    final rows = _rows!;
    final isCurrent = ref.watch(
      playbackProvider.select((p) => p.current?.id == widget.song.id),
    );
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: rows.length,
            itemBuilder: (context, i) => _timedRow(rows[i], i, isCurrent),
          ),
        ),
        _actions(rows, isCurrent),
      ],
    );
  }

  Widget _timedRow(TimedRow row, int i, bool isCurrent) {
    final selected = _selected.contains(i);
    return Padding(
      padding: EdgeInsets.only(top: row.stanzaStart && i > 0 ? 14 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (row.stanzaStart && row.label != null)
            Padding(
              padding: const EdgeInsets.only(left: 76, top: 4),
              child: LyricsSectionLabel(row.label!),
            ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              selected ? _selected.remove(i) : _selected.add(i);
              _message = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? AppColors.whiteAlpha(0.12) : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tapping the time plays from there, to check it.
                  GestureDetector(
                    onTap: isCurrent
                        ? () =>
                              ref.read(playbackProvider.notifier).seek(row.time)
                        : null,
                    child: SizedBox(
                      width: 60,
                      child: Text(
                        _preciseTimestamp(row.time),
                        style: TextStyle(
                          color: AppColors.whiteAlpha(isCurrent ? 0.6 : 0.4),
                          fontSize: 13,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          decoration: isCurrent
                              ? TextDecoration.underline
                              : null,
                          decorationColor: AppColors.whiteAlpha(0.3),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.isBreak ? '♪  break' : row.text,
                      style: TextStyle(
                        color: row.isBreak
                            ? AppColors.whiteAlpha(0.4)
                            : AppColors.white,
                        fontStyle: row.isBreak ? FontStyle.italic : null,
                        fontSize: 16,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(
                      AppIcons.checkCircle,
                      size: 18,
                      color: AppColors.whiteAlpha(0.8),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(List<TimedRow> rows, bool isCurrent) {
    final count = _selected.length;
    final single = count == 1 ? _selected.first : null;
    final playing = ref.watch(playbackProvider.select((p) => p.playing));
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.whiteAlpha(0.08))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (count == 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Tap lines to select them. Tap a time to play from there.',
                style: TextStyle(
                  color: AppColors.whiteAlpha(0.45),
                  fontSize: 12.5,
                ),
              ),
            ),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isCurrent)
                LyricsPill(
                  label: playing ? 'Pause' : 'Play',
                  icon: playing ? AppIcons.pause : AppIcons.playFilled,
                  onTap: () => ref.read(playbackProvider.notifier).togglePlay(),
                ),
              if (count == 0)
                LyricsPill(
                  label: 'Select all',
                  onTap: () => setState(
                    () =>
                        _selected.addAll(List.generate(rows.length, (i) => i)),
                  ),
                ),
              if (count >= 2)
                LyricsPill(
                  label: 'Merge',
                  icon: AppIcons.merge,
                  onTap: () => _apply(
                    mergeRows(rows, _selected),
                    failure: 'Select lines with some text to merge.',
                  ),
                ),
              if (single != null)
                LyricsPill(
                  label: rows[single].isBreak ? 'Write' : 'Edit',
                  icon: AppIcons.edit,
                  onTap: () => _editRow(rows, single),
                ),
              if (single != null && isCurrent)
                LyricsPill(
                  label: 'Set to now',
                  icon: AppIcons.timer,
                  onTap: () {
                    var now =
                        ref.read(playbackProvider.notifier).livePosition -
                        _reactionDelay;
                    if (now < Duration.zero) now = Duration.zero;
                    _apply(
                      setRowTime(rows, single, now),
                      failure:
                          'The playhead is outside this line\'s neighbours: '
                          'move it between them first.',
                    );
                  },
                ),
              if (single != null && !rows[single].isBreak)
                LyricsPill(
                  label: 'Break after',
                  icon: AppIcons.musicNote,
                  onTap: () => _apply(
                    insertBreakAfter(rows, single),
                    failure: 'There is already a break here.',
                  ),
                ),
              if (count >= 1) ...[
                LyricsPill(
                  label: '−0.1 s',
                  onTap: () => _apply(
                    shiftRows(rows, _selected, -_nudge),
                    failure: 'Lines can\'t move past their neighbours.',
                    keepSelection: true,
                  ),
                ),
                LyricsPill(
                  label: '+0.1 s',
                  onTap: () => _apply(
                    shiftRows(rows, _selected, _nudge),
                    failure: 'Lines can\'t move past their neighbours.',
                    keepSelection: true,
                  ),
                ),
                LyricsPill(
                  label: 'Delete',
                  icon: AppIcons.delete,
                  onTap: () => _apply(
                    deleteRows(rows, _selected),
                    failure: 'At least one line must remain.',
                  ),
                ),
                LyricsPill(
                  label: 'Clear',
                  icon: AppIcons.close,
                  onTap: () => setState(_selected.clear),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editRow(List<TimedRow> rows, int index) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _EditLineDialog(initial: rows[index].text),
    );
    if (text == null || !mounted) return;
    _apply(
      editRow(rows, index, text),
      failure: 'Not enough time before the next line to split this one.',
    );
  }
}

/// Edits one timed line. Owns its text controller so it is disposed with the
/// dialog, after the closing animation, not while the field still shows.
class _EditLineDialog extends StatefulWidget {
  const _EditLineDialog({required this.initial});

  final String initial;

  @override
  State<_EditLineDialog> createState() => _EditLineDialogState();
}

class _EditLineDialogState extends State<_EditLineDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit line'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        decoration: const InputDecoration(
          helperText:
              'Each new line becomes a line of its own, timed up to the '
              'next one. Empty deletes the line.',
          helperMaxLines: 3,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// `m:ss.d`, precise enough to see 0.1 s nudges.
String _preciseTimestamp(Duration value) {
  final tenths = value.inMilliseconds ~/ 100;
  final seconds = tenths ~/ 10;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}'
      '.${tenths % 10}';
}
