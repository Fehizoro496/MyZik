import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
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
import '../screens/lyrics_view.dart';
import '../theme.dart';
import '../widgets.dart';
import 'desktop_style.dart';

enum _Mode { edit, live }

/// The desktop lyrics workspace, in two modes.
///
/// *Edit & time* shows the text and its timed lines side by side: text edits
/// re-time the lines as you type (unchanged and corrected lines keep their
/// time), and line edits rewrite the text. An inspector acts on the selected
/// lines, and a timeline along the bottom shows every line as a marker that
/// can be dragged to retime it.
///
/// *Live sync* times the lyrics by hand while the song plays (Space as each
/// line starts), or with AI (Auto-sync). Both only fill the timed lines; the
/// lyrics are saved from the editor, after checking.
class DesktopLyricsEditor extends ConsumerStatefulWidget {
  const DesktopLyricsEditor({
    super.key,
    required this.song,
    this.lyrics,
    this.liveSync = false,
  });

  final Song song;

  /// Null to write lyrics from scratch.
  final Lyrics? lyrics;

  /// Opens in Live sync rather than Edit & time.
  final bool liveSync;

  static Future<void> open(
    BuildContext context,
    Song song,
    Lyrics? lyrics, {
    bool liveSync = false,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            DesktopLyricsEditor(song: song, lyrics: lyrics, liveSync: liveSync),
      ),
    );
  }

  @override
  ConsumerState<DesktopLyricsEditor> createState() =>
      _DesktopLyricsEditorState();
}

class _DesktopLyricsEditorState extends ConsumerState<DesktopLyricsEditor> {
  late final TextEditingController _text;
  final _focus = FocusNode();
  Timer? _retimeDebounce;

  /// Timed lines, null until the lyrics are synchronized.
  List<TimedRow>? _rows;
  final _history = <({List<TimedRow>? rows, String text})>[];
  final _selected = <int>{};

  /// Where a Shift-click range starts.
  int? _anchor;

  /// Text the rows were last in step with.
  late String _textOfRows;
  late _Mode _mode;
  bool _dirty = false;
  bool _saving = false;
  String? _message;
  bool _messageIsError = false;

  /// Live sync: lines timed so far. Empty text marks an instrumental break.
  final _marks = <LyricLine>[];

  bool _autoSyncing = false;
  String? _autoResult;

  /// Playback speed before the editor changed it, restored on close.
  late final double _initialSpeed;
  late final PlaybackNotifier _playback;

  static const _reactionDelay = Duration(milliseconds: 150);
  static const _nudge = Duration(milliseconds: 100);

  @override
  void initState() {
    super.initState();
    final lyrics = widget.lyrics;
    if (lyrics != null && lyrics.synced) {
      _rows = rowsOf(lyrics);
      _textOfRows = plainOf(_rows!);
    } else {
      _textOfRows = lyrics?.plain ?? '';
    }
    _text = TextEditingController(text: _textOfRows);
    _text.addListener(_onTextChanged);
    _mode = widget.liveSync && _canLiveSync ? _Mode.live : _Mode.edit;
    _playback = ref.read(playbackProvider.notifier);
    _initialSpeed = _playback.speed;
  }

  @override
  void dispose() {
    _retimeDebounce?.cancel();
    _text.dispose();
    _focus.dispose();
    if (_playback.speed != _initialSpeed) _playback.setSpeed(_initialSpeed);
    super.dispose();
  }

  List<String> get _textLines => lyricLinesOf(_text.text);

  bool get _canLiveSync => lyricLinesOf(_text.text).isNotEmpty;

  /// Whether a text field has the keyboard, so keys type instead of acting.
  bool get _typing =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorStateOfType<EditableTextState>() !=
      null;

  bool get _isCurrent =>
      ref.read(playbackProvider).current?.id == widget.song.id;

  void _say(String? message, {bool error = false}) {
    setState(() {
      _message = message;
      _messageIsError = error;
    });
  }

  void _onTextChanged() {
    if (_text.text == _textOfRows) return;
    if (!_dirty) setState(() => _dirty = true);
    _retimeDebounce?.cancel();
    _retimeDebounce = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(_retimeFromText);
    });
  }

  /// Brings the timed lines in step with the text after it was edited.
  void _retimeFromText() {
    final rows = _rows;
    if (rows == null || _text.text == _textOfRows) return;
    final result = retimeLyrics(linesOf(rows), _text.text);
    if (result.rows.isEmpty) return;
    _history.add((rows: rows, text: _textOfRows));
    _rows = result.rows;
    _selected.clear();
    _textOfRows = _text.text;
    _message = result.estimated == 0
        ? null
        : '${result.estimated} new line${result.estimated == 1 ? '' : 's'} '
              'got an estimated time: check them in the timing.';
    _messageIsError = false;
  }

  /// Applies a change to the timed lines and rewrites the text from them;
  /// [next] is null when the change isn't possible.
  void _apply(
    List<TimedRow>? next, {
    required String failure,
    bool keepSelection = false,
  }) {
    if (next == null) {
      _say(failure, error: true);
      return;
    }
    _retimeDebounce?.cancel();
    setState(() {
      _history.add((rows: _rows, text: _text.text));
      _setRows(next);
      if (!keepSelection) _selected.clear();
      _dirty = true;
      _message = null;
    });
  }

  void _setRows(List<TimedRow> rows) {
    _rows = rows;
    _textOfRows = plainOf(rows);
    if (_text.text != _textOfRows) _text.text = _textOfRows;
  }

  void _undo() {
    if (_history.isEmpty) return;
    _retimeDebounce?.cancel();
    setState(() {
      final previous = _history.removeLast();
      _rows = previous.rows;
      _textOfRows = previous.text;
      _text.text = previous.text;
      _selected.clear();
      _message = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    _retimeDebounce?.cancel();
    _retimeFromText();
    final original = widget.lyrics;
    final source = original?.source ?? LyricsSource.manual;
    final Lyrics edited;
    final rows = _rows;
    if (rows != null) {
      edited = Lyrics(
        source: source,
        lines: linesOf(rows),
        plain: plainOf(rows),
        sourceUrl: original?.sourceUrl,
        edited: true,
      );
    } else {
      final plain = normalizeLyricsText(_text.text);
      if (lyricLinesOf(plain).isEmpty) {
        _say('Write some lyrics first.', error: true);
        return;
      }
      edited = Lyrics(
        source: source,
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

  static const _lrcFiles = XTypeGroup(
    label: 'LRC lyrics',
    extensions: ['lrc', 'txt'],
  );

  /// Replaces the lyrics with an LRC file: its timed lines, or its text when
  /// it has no timestamps. Undoable.
  Future<void> _importLrc() async {
    final file = await openFile(acceptedTypeGroups: const [_lrcFiles]);
    if (file == null || !mounted) return;
    final String content;
    try {
      content = await file.readAsString();
    } catch (_) {
      _say('Could not read ${file.name}.', error: true);
      return;
    }
    if (!mounted) return;
    final lines = importLrc(content);
    if (lines.any((line) => line.text.isNotEmpty)) {
      _apply(
        rowsOf(Lyrics(source: LyricsSource.manual, lines: lines)),
        failure: 'Could not import ${file.name}.',
      );
      _say(
        'Imported ${lines.where((l) => l.text.isNotEmpty).length} timed '
        'lines from ${file.name}.',
      );
      return;
    }
    // No timestamps: plain lyrics, minus LRC tags like [ar:Artist].
    final plain = normalizeLyricsText(
      content
          .split('\n')
          .where((line) => !RegExp(r'^\s*\[[a-z]+:.*\]\s*$').hasMatch(line))
          .join('\n'),
    );
    if (lyricLinesOf(plain).isEmpty) {
      _say('${file.name} holds no lyrics.', error: true);
      return;
    }
    _retimeDebounce?.cancel();
    setState(() {
      _history.add((rows: _rows, text: _text.text));
      _rows = null;
      _selected.clear();
      _textOfRows = plain;
      _text.text = plain;
      _dirty = true;
      _message = 'Imported the text of ${file.name}: it has no timings.';
      _messageIsError = false;
    });
  }

  /// The timed lines as LRC, tagged with the song's details.
  String? get _lrc {
    final rows = _rows;
    if (rows == null) return null;
    final song = widget.song;
    return formatLrc(
      linesOf(rows),
      title: song.title,
      artist: song.artist,
      album: song.album,
      length: song.duration,
    );
  }

  Future<void> _exportLrc() async {
    final lrc = _lrc;
    if (lrc == null) return;
    final song = widget.song;
    final name = '${song.artist} - ${song.title}'
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    final location = await getSaveLocation(
      suggestedName: '$name.lrc',
      acceptedTypeGroups: const [_lrcFiles],
    );
    if (location == null || !mounted) return;
    var path = location.path;
    if (!path.toLowerCase().endsWith('.lrc')) path = '$path.lrc';
    try {
      await File(path).writeAsString(lrc);
      _say('Exported to $path.');
    } catch (_) {
      _say('Could not write $path.', error: true);
    }
  }

  Future<void> _copyLrc() async {
    final lrc = _lrc;
    if (lrc == null) return;
    await Clipboard.setData(ClipboardData(text: lrc));
    _say('Copied the timed lyrics as LRC.');
  }

  Future<void> _close() async {
    if (_dirty && !await _confirmDiscard()) return;
    if (!mounted) return;
    _dirty = false;
    Navigator.of(context).pop();
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16161E),
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

  void _switchTo(_Mode mode) {
    if (mode == _mode) return;
    FocusScope.of(context).unfocus();
    _retimeDebounce?.cancel();
    setState(() {
      _retimeFromText();
      if (mode == _Mode.live) _marks.clear();
      _mode = mode;
    });
  }

  // Selection.

  void _tapRow(int index) {
    final keys = HardwareKeyboard.instance;
    setState(() {
      _message = null;
      if (keys.isShiftPressed && _anchor != null) {
        _selected
          ..clear()
          ..addAll([
            for (var i = min(_anchor!, index); i <= max(_anchor!, index); i++)
              i,
          ]);
      } else if (keys.isControlPressed || keys.isMetaPressed) {
        _selected.contains(index)
            ? _selected.remove(index)
            : _selected.add(index);
        _anchor = index;
      } else {
        _selected
          ..clear()
          ..add(index);
        _anchor = index;
      }
    });
  }

  void _moveSelection(int delta) {
    final rows = _rows;
    if (rows == null || rows.isEmpty) return;
    final from = _selected.isEmpty
        ? (delta > 0 ? -1 : rows.length)
        : (delta > 0 ? _selected.reduce(max) : _selected.reduce(min));
    final to = (from + delta).clamp(0, rows.length - 1);
    setState(() {
      _selected
        ..clear()
        ..add(to);
      _anchor = to;
    });
  }

  // Timing actions on the selection.

  int? get _single => _selected.length == 1 ? _selected.first : null;

  void _nudgeSelection(Duration delta) {
    if (_rows == null || _selected.isEmpty) return;
    _apply(
      shiftRows(_rows!, _selected, delta),
      failure: 'Lines can\'t move past their neighbours.',
      keepSelection: true,
    );
  }

  void _setToNow() {
    final single = _single;
    if (_rows == null || single == null) return;
    if (!_isCurrent) {
      _say('Play this song first to time its lines.', error: true);
      return;
    }
    var now = _playback.livePosition - _reactionDelay;
    if (now < Duration.zero) now = Duration.zero;
    _apply(
      setRowTime(_rows!, single, now),
      failure:
          'The playhead is outside this line\'s neighbours: move it between '
          'them first.',
      keepSelection: true,
    );
  }

  void _merge() {
    if (_rows == null || _selected.length < 2) return;
    _apply(
      mergeRows(_rows!, _selected),
      failure: 'Select lines with some text to merge.',
    );
  }

  void _breakAfter() {
    final single = _single;
    if (_rows == null || single == null || _rows![single].isBreak) return;
    _apply(
      insertBreakAfter(_rows!, single),
      failure: 'There is already a break here.',
    );
  }

  void _delete() {
    if (_rows == null || _selected.isEmpty) return;
    _apply(
      deleteRows(_rows!, _selected),
      failure: 'At least one line must remain.',
    );
  }

  Future<void> _editLine() async {
    final single = _single;
    final rows = _rows;
    if (rows == null || single == null) return;
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _EditLineDialog(initial: rows[single].text),
    );
    if (text == null || !mounted) return;
    _apply(
      editRow(rows, single, text),
      failure: 'Not enough time before the next line to split this one.',
    );
  }

  void _retimeRow(int index, Duration time) {
    final rows = _rows;
    if (rows == null) return;
    _apply(
      setRowTime(rows, index, time),
      failure: 'A line can\'t move past its neighbours.',
      keepSelection: true,
    );
  }

  // Playback.

  void _togglePlay() {
    if (_isCurrent) {
      _playback.togglePlay();
    } else {
      _playback.playSong(widget.song);
    }
  }

  void _seek(Duration position) {
    if (!_isCurrent) return;
    _playback.seek(position < Duration.zero ? Duration.zero : position);
  }

  void _rewind() => _seek(_playback.livePosition - const Duration(seconds: 5));

  void _forward() => _seek(_playback.livePosition + const Duration(seconds: 5));

  // Live sync.

  /// Times the next line, or an instrumental break when [isBreak], at the
  /// live playhead. After a rewind, the marks past the playhead are dropped
  /// so that part can be timed again.
  void _mark({bool isBreak = false}) {
    if (!_isCurrent) {
      _say('Play this song first to time its lines.', error: true);
      return;
    }
    final lines = _textLines;
    var position = _playback.livePosition - _reactionDelay;
    if (position < Duration.zero) position = Duration.zero;
    setState(() {
      _message = null;
      _marks.removeWhere((line) => line.time > position);
      if (_marks.isNotEmpty && _marks.last.time >= position) return;
      if (isBreak) {
        if (_marks.isEmpty || _marks.last.text.isEmpty) return;
        _marks.add(LyricLine(position, ''));
      } else {
        final next = _marks.where((line) => line.text.isNotEmpty).length;
        if (next >= lines.length) return;
        _marks.add(LyricLine(position, lines[next]));
      }
    });
  }

  void _undoMark() {
    if (_marks.isEmpty) return;
    setState(_marks.removeLast);
  }

  /// Hands the live timings over to Edit & time, to check and save.
  void _useMarks() {
    final plain = normalizeLyricsText(_text.text);
    final rows = rowsOf(
      Lyrics(source: LyricsSource.manual, lines: List.of(_marks), plain: plain),
    );
    _marks.clear();
    _apply(rows, failure: '');
    setState(() {
      _mode = _Mode.edit;
      _message = 'All lines are timed. Check them, then save.';
    });
  }

  Future<void> _autoSync() async {
    final plain = normalizeLyricsText(_text.text);
    final lyrics = Lyrics(
      source: widget.lyrics?.source ?? LyricsSource.manual,
      plain: plain,
    );
    if (!await confirmAutoSync(context, ref) || !mounted) return;
    setState(() {
      _autoSyncing = true;
      _autoResult = null;
      _message = null;
    });
    try {
      final alignment = await ref
          .read(lyricsRepositoryProvider)
          .autoSynchronize(widget.song, lyrics);
      if (!mounted) return;
      final percent = (alignment.confidence * 100).round();
      _apply(
        rowsOf(
          Lyrics(source: lyrics.source, lines: alignment.lines, plain: plain),
        ),
        failure: '',
      );
      setState(() {
        _autoResult = '$percent% of the words were heard.';
        _mode = _Mode.edit;
        _message =
            'Synchronized by AI ($percent% of the words heard). Check the '
            'lines, nudge any that are off, then save.';
      });
    } catch (error) {
      if (mounted) {
        _say(
          error is LyricsException
              ? error.message
              : 'Synchronization failed. Please try again.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _autoSyncing = false);
    }
  }

  /// Editor keys. Plain keys only act when no text field has the keyboard,
  /// and are otherwise left to it.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final control = keys.isControlPressed || keys.isMetaPressed;
    final key = event.logicalKey;
    if (control && key == LogicalKeyboardKey.keyS) {
      _save();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_typing) {
        FocusScope.of(context).unfocus();
        _focus.requestFocus();
      } else if (_mode == _Mode.live) {
        _switchTo(_Mode.edit);
      } else {
        _close();
      }
      return KeyEventResult.handled;
    }
    if (_typing || keys.isAltPressed) return KeyEventResult.ignored;
    final live = _mode == _Mode.live;
    final VoidCallback? action = control
        ? switch (key) {
            LogicalKeyboardKey.keyZ => live ? _undoMark : _undo,
            _ => null,
          }
        : switch (key) {
            LogicalKeyboardKey.space => live ? _mark : _togglePlay,
            LogicalKeyboardKey.keyP => _togglePlay,
            LogicalKeyboardKey.arrowLeft => _rewind,
            LogicalKeyboardKey.arrowRight => _forward,
            LogicalKeyboardKey.keyB =>
              live ? () => _mark(isBreak: true) : _breakAfter,
            LogicalKeyboardKey.enter when !live => _setToNow,
            LogicalKeyboardKey.bracketLeft when !live => () => _nudgeSelection(
              -_nudge,
            ),
            LogicalKeyboardKey.bracketRight when !live => () => _nudgeSelection(
              _nudge,
            ),
            LogicalKeyboardKey.keyM when !live => _merge,
            LogicalKeyboardKey.delete when !live => _delete,
            LogicalKeyboardKey.f2 when !live => _editLine,
            LogicalKeyboardKey.arrowUp when !live => () => _moveSelection(-1),
            LogicalKeyboardKey.arrowDown when !live => () => _moveSelection(1),
            _ => null,
          };
    if (action == null) return KeyEventResult.ignored;
    action();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the (auto-disposed) lyrics alive while editing.
    ref.watch(lyricsProvider(widget.song));
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: AppColors.musicBackground,
          body: Column(
            children: [
              _header(),
              if (_message != null) _banner(),
              Expanded(
                child: _mode == _Mode.edit ? _editWorkspace() : _liveSync(),
              ),
              _Timeline(
                song: widget.song,
                rows: _mode == _Mode.live
                    ? rowsOf(
                        Lyrics(
                          source: LyricsSource.manual,
                          lines: _marks,
                          plain: _text.text,
                        ),
                      )
                    : _rows ?? const [],
                selected: _mode == _Mode.live ? const {} : _selected,
                onRetime: _mode == _Mode.live ? null : _retimeRow,
                onTogglePlay: _togglePlay,
                onRewind: _rewind,
                onSeek: _seek,
                hint: _mode == _Mode.live
                    ? 'Space marks the highlighted line'
                    : 'Drag a marker to retime a line',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final lyrics = widget.lyrics;
    final canAutoSync =
        !_autoSyncing &&
        ref
            .read(lyricsRepositoryProvider)
            .canAutoSynchronize(
              widget.song,
              Lyrics(
                source: lyrics?.source ?? LyricsSource.manual,
                plain: _text.text,
                instrumental: lyrics?.instrumental ?? false,
              ),
            );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 24, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.whiteAlpha(0.06))),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close (Esc)',
            iconSize: 18,
            onPressed: _close,
            icon: const Icon(AppIcons.close),
          ),
          const SizedBox(width: 8),
          SongArtwork(song: widget.song, size: 44, radius: 10),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _mode == _Mode.live
                      ? 'Synchronize lyrics'
                      : lyrics == null
                      ? 'Write lyrics'
                      : 'Edit lyrics',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${widget.song.title} · ${widget.song.artist}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.whiteAlpha(0.6),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          DesktopSegmented<_Mode>(
            options: const [
              (_Mode.edit, 'Edit & time'),
              (_Mode.live, 'Live sync'),
            ],
            selected: _mode,
            onSelected: (mode) {
              if (mode == _Mode.live && !_canLiveSync) {
                _say('Write the lyrics first, then time them.', error: true);
                return;
              }
              _switchTo(mode);
            },
          ),
          const Spacer(),
          if (_mode == _Mode.live) ...[
            _LiveProgress(
              timed: _marks.where((l) => l.text.isNotEmpty).length,
              total: _textLines.length,
            ),
          ] else ...[
            if (_dirty)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  'Unsaved changes',
                  style: TextStyle(
                    color: AppColors.whiteAlpha(0.6),
                    fontSize: 12,
                  ),
                ),
              ),
            PopupMenuButton<String>(
              tooltip: 'LRC import and export',
              icon: const Icon(AppIcons.moreHoriz, size: 18),
              color: const Color(0xFF1C1C26),
              onSelected: (action) => switch (action) {
                'import' => _importLrc(),
                'export' => _exportLrc(),
                _ => _copyLrc(),
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'import',
                  child: Text('Import LRC…'),
                ),
                PopupMenuItem(
                  value: 'export',
                  enabled: _rows != null,
                  child: const Text('Export LRC…'),
                ),
                PopupMenuItem(
                  value: 'copy',
                  enabled: _rows != null,
                  child: const Text('Copy as LRC'),
                ),
              ],
            ),
            IconButton(
              tooltip: 'Undo (Ctrl+Z)',
              iconSize: 18,
              onPressed: _history.isEmpty ? null : _undo,
              icon: const Icon(AppIcons.undo),
            ),
            const SizedBox(width: 4),
            if (canAutoSync || _autoSyncing) ...[
              DesktopPill(
                icon: AppIcons.sparkles,
                label: _autoSyncing ? 'Listening…' : 'Auto-sync',
                tooltip: 'Time every line with AI',
                onPressed: _autoSyncing ? null : _autoSync,
              ),
              const SizedBox(width: 8),
            ],
            DesktopPill(
              primary: true,
              icon: AppIcons.checkCircle,
              label: _saving ? 'Saving…' : 'Save',
              shortcut: 'Ctrl S',
              onPressed: _saving || !_dirty ? null : _save,
            ),
          ],
        ],
      ),
    );
  }

  Widget _banner() {
    final color = _messageIsError
        ? DesktopColors.error
        : DesktopColors.estimated;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 10, 12, 10),
      color: color.withValues(alpha: 0.08),
      child: Row(
        children: [
          Icon(AppIcons.info, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _message!,
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            iconSize: 14,
            onPressed: () => _say(null),
            icon: const Icon(AppIcons.close),
          ),
        ],
      ),
    );
  }

  // Edit & time.

  Widget _editWorkspace() {
    final rows = _rows;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 380, child: _textPane()),
        VerticalDivider(width: 1, color: AppColors.whiteAlpha(0.06)),
        Expanded(child: rows == null ? _notSynced() : _timingPane(rows)),
        if (rows != null) _inspector(rows),
      ],
    );
  }

  Widget _textPane() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('TEXT', style: DesktopText.overline),
              const Spacer(),
              if (_rows != null)
                Text(
                  'Synced with timing →',
                  style: TextStyle(
                    color: AppColors.whiteAlpha(0.6),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _rows == null
                ? 'One line per sung line. Leave an empty line between '
                      'stanzas and put section names in brackets: [Chorus].'
                : 'Lines you keep or correct in place keep their timing; '
                      'new lines get an estimated one.',
            style: TextStyle(
              color: AppColors.whiteAlpha(0.6),
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: DesktopColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.whiteAlpha(0.08)),
              ),
              child: TextField(
                controller: _text,
                maxLines: null,
                expands: true,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                cursorColor: AppColors.white,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 14,
                  height: 1.75,
                ),
                decoration: InputDecoration(
                  hintText: '[Verse 1]\nFirst line\nSecond line\n\n[Chorus]\n…',
                  hintStyle: TextStyle(color: AppColors.whiteAlpha(0.3)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _notSynced() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.timer, size: 36, color: AppColors.whiteAlpha(0.4)),
            const SizedBox(height: 16),
            const Text(
              'Not synchronized yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Time the lines by hand while the song plays, or let AI '
              'listen to it. You can fine-tune every line afterwards.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.whiteAlpha(0.6), height: 1.5),
            ),
            const SizedBox(height: 20),
            DesktopPill(
              primary: true,
              icon: AppIcons.timer,
              label: 'Live sync',
              onPressed: _canLiveSync ? () => _switchTo(_Mode.live) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _timingPane(List<TimedRow> rows) {
    final current = ref.watch(
      playbackProvider.select(
        (p) =>
            p.current?.id == widget.song.id ? _indexAt(rows, p.position) : -1,
      ),
    );
    final isCurrent = ref.watch(
      playbackProvider.select((p) => p.current?.id == widget.song.id),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
          child: Row(
            children: [
              Text('TIMING', style: DesktopText.overline),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isCurrent
                      ? 'Click a time to play from there · Shift-click to '
                            'select a range'
                      : 'Play the song to check and time its lines',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.whiteAlpha(0.6),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: rows.length,
            itemBuilder: (context, i) => _TimedRowTile(
              row: rows[i],
              first: i == 0,
              selected: _selected.contains(i),
              playing: i == current,
              canSeek: isCurrent,
              onTap: () => _tapRow(i),
              onDoubleTap: () {
                _tapRow(i);
                _editLine();
              },
              onSeek: () => _seek(rows[i].time),
            ),
          ),
        ),
      ],
    );
  }

  Widget _inspector(List<TimedRow> rows) {
    final count = _selected.length;
    final single = _single;
    final sorted = _selected.toList()..sort();
    final range = count == 0
        ? 'Click a line to select it'
        : count == 1
        ? preciseTimestamp(rows[sorted.first].time)
        : '${preciseTimestamp(rows[sorted.first].time)} → '
              '${preciseTimestamp(rows[sorted.last].time)}';
    Widget action(
      String label,
      IconData icon,
      String keys,
      VoidCallback? onPressed, {
      Color? color,
    }) => _InspectorAction(
      label: label,
      icon: icon,
      keys: keys,
      onPressed: onPressed,
      color: color,
    );
    return Container(
      width: 290,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: DesktopColors.panel,
        border: Border(left: BorderSide(color: AppColors.whiteAlpha(0.06))),
      ),
      child: ListView(
        children: [
          Text('SELECTION', style: DesktopText.overline),
          const SizedBox(height: 6),
          Text(
            count == 0
                ? 'Nothing selected'
                : '$count line${count == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            range,
            style: DesktopText.mono.copyWith(
              color: AppColors.whiteAlpha(0.6),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Nudge timing',
            style: TextStyle(
              color: AppColors.whiteAlpha(0.7),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: action(
                  '−0.1 s',
                  AppIcons.back,
                  '[',
                  count == 0 ? null : () => _nudgeSelection(-_nudge),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: action(
                  '+0.1 s',
                  AppIcons.chevronRight,
                  ']',
                  count == 0 ? null : () => _nudgeSelection(_nudge),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          action(
            'Set to now',
            AppIcons.timer,
            'Enter',
            single == null ? null : _setToNow,
          ),
          const SizedBox(height: 20),
          Text(
            'Lines',
            style: TextStyle(
              color: AppColors.whiteAlpha(0.7),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          action('Merge', AppIcons.merge, 'M', count < 2 ? null : _merge),
          const SizedBox(height: 8),
          action(
            single != null && rows[single].isBreak ? 'Write line' : 'Edit line',
            AppIcons.edit,
            'F2',
            single == null ? null : _editLine,
          ),
          const SizedBox(height: 8),
          action(
            'Break after',
            AppIcons.musicNote,
            'B',
            single == null || rows[single].isBreak ? null : _breakAfter,
          ),
          const SizedBox(height: 8),
          action(
            'Delete',
            AppIcons.delete,
            'Del',
            count == 0 ? null : _delete,
            color: DesktopColors.error,
          ),
          const SizedBox(height: 24),
          const _KeyboardHelp(
            entries: [
              ('Play / pause', 'Space'),
              ('Previous / next line', '↑ ↓'),
              ('Seek ±5 s', '← →'),
              ('Undo', 'Ctrl Z'),
            ],
          ),
        ],
      ),
    );
  }

  // Live sync.

  Widget _liveSync() {
    final lines = _textLines;
    final timed = _marks.where((l) => l.text.isNotEmpty).length;
    final complete = timed >= lines.length;
    final labels = <int, String>{};
    var index = 0;
    for (final stanza in parseLyricsStructure(_text.text)) {
      if (stanza.label != null) labels[index] = stanza.label!;
      index += stanza.lines.length;
    }
    final done = _marks.length <= 3
        ? _marks
        : _marks.sublist(_marks.length - 3);
    final isCurrent = ref.watch(
      playbackProvider.select((p) => p.current?.id == widget.song.id),
    );
    final playing = ref.watch(playbackProvider.select((p) => p.playing));
    final hint = !isCurrent
        ? 'Play “${widget.song.title}” to start timing it.'
        : complete
        ? 'All lines are timed. Mark a final break if the song ends '
              'instrumentally, then use these timings.'
        : 'Press Space the moment each highlighted line starts. Lower the '
              'speed if it goes too fast.';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      hint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.whiteAlpha(0.66),
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 32),
                    for (final line in done)
                      _LiveLine(
                        leading: preciseTimestamp(line.time),
                        text: line.text.isEmpty ? '♪ break' : line.text,
                        style: TextStyle(
                          color: AppColors.whiteAlpha(0.45),
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                        leadingColor: DesktopColors.accentText,
                      ),
                    if (!complete) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accentA.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppColors.accentA.withValues(alpha: 0.35),
                          ),
                        ),
                        child: _LiveLine(
                          leading: 'next →',
                          text: lines[timed],
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            height: 1.15,
                          ),
                          leadingColor: AppColors.white,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (
                        var i = timed + 1;
                        i < min(timed + 4, lines.length);
                        i++
                      )
                        _LiveLine(
                          leading: labels[i]?.toUpperCase() ?? '',
                          text: lines[i],
                          style: TextStyle(
                            color: AppColors.whiteAlpha(0.72),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                          leadingColor: DesktopColors.accentText,
                          small: true,
                        ),
                    ],
                    const SizedBox(height: 36),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _LiveKey(
                          label: 'Undo',
                          keys: 'Ctrl Z',
                          onPressed: _marks.isEmpty ? null : _undoMark,
                        ),
                        _LiveKey(
                          label: '−5 s',
                          keys: '←',
                          onPressed: isCurrent ? _rewind : null,
                        ),
                        _LiveKey(
                          label: isCurrent
                              ? (playing ? 'Pause' : 'Play')
                              : 'Play song',
                          keys: 'P',
                          onPressed: _togglePlay,
                        ),
                        if (!complete)
                          _LiveKey(
                            label: 'Mark line',
                            keys: 'Space',
                            primary: true,
                            onPressed: isCurrent ? _mark : null,
                          ),
                        _LiveKey(
                          label: 'Break',
                          keys: 'B',
                          onPressed:
                              isCurrent &&
                                  _marks.isNotEmpty &&
                                  _marks.last.text.isNotEmpty
                              ? () => _mark(isBreak: true)
                              : null,
                        ),
                        if (complete)
                          _LiveKey(
                            label: 'Use these timings',
                            keys: '✓',
                            primary: true,
                            onPressed: _useMarks,
                          ),
                        _LiveKey(
                          label: 'Cancel',
                          keys: 'Esc',
                          onPressed: () => _switchTo(_Mode.edit),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _autoSyncPanel(),
      ],
    );
  }

  Widget _autoSyncPanel() {
    final lyrics = widget.lyrics;
    final available = ref
        .read(lyricsRepositoryProvider)
        .canAutoSynchronize(
          widget.song,
          Lyrics(
            source: lyrics?.source ?? LyricsSource.manual,
            plain: _text.text,
            instrumental: lyrics?.instrumental ?? false,
          ),
        );
    return Container(
      width: 340,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: DesktopColors.panel,
        border: Border(left: BorderSide(color: AppColors.whiteAlpha(0.06))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(AppIcons.sparkles, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Auto-sync',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Whisper listens and times every line',
                      style: TextStyle(
                        color: AppColors.whiteAlpha(0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: DesktopColors.field,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.whiteAlpha(0.08)),
            ),
            child: _autoSyncing
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Listening to the track…',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          minHeight: 4,
                          color: AppColors.accentA,
                          backgroundColor: AppColors.whiteAlpha(0.1),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        available
                            ? 'Times the whole song in about a minute. The '
                                  'result opens in Edit & time to check.'
                            : 'Only songs stored on this device can be '
                                  'synchronized with AI.',
                        style: TextStyle(
                          color: AppColors.whiteAlpha(0.7),
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DesktopPill(
                        primary: true,
                        icon: AppIcons.sparkles,
                        label: 'Synchronize with AI',
                        onPressed: available ? _autoSync : null,
                      ),
                    ],
                  ),
          ),
          if (_autoResult != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: DesktopColors.success.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: DesktopColors.success.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    AppIcons.checkCircle,
                    size: 16,
                    color: DesktopColors.success,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Last run: ${_autoResult!}',
                      style: const TextStyle(
                        color: DesktopColors.success,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.whiteAlpha(0.03),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcons.info, size: 16, color: AppColors.whiteAlpha(0.6)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'The audio file is sent to Groq (Whisper) to be '
                    'transcribed. Your consent is asked once.',
                    style: TextStyle(
                      color: AppColors.whiteAlpha(0.66),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Index of the row sung at [position], or -1 before the first one.
int _indexAt(List<TimedRow> rows, Duration position) {
  var found = -1;
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].time > position) break;
    found = i;
  }
  return found;
}

/// `m:ss.d`, precise enough to see 0.1 s nudges.
String preciseTimestamp(Duration value) {
  final tenths = value.inMilliseconds ~/ 100;
  final seconds = tenths ~/ 10;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}'
      '.${tenths % 10}';
}

class _LiveProgress extends StatelessWidget {
  const _LiveProgress({required this.timed, required this.total});

  final int timed;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text.rich(
          TextSpan(
            text: '$timed ',
            style: const TextStyle(fontWeight: FontWeight.w700),
            children: [
              TextSpan(
                text: '/ $total lines timed',
                style: TextStyle(
                  color: AppColors.whiteAlpha(0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 140,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : timed / total,
              minHeight: 6,
              color: AppColors.accentA,
              backgroundColor: AppColors.whiteAlpha(0.1),
            ),
          ),
        ),
      ],
    );
  }
}

class _TimedRowTile extends StatefulWidget {
  const _TimedRowTile({
    required this.row,
    required this.first,
    required this.selected,
    required this.playing,
    required this.canSeek,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSeek,
  });

  final TimedRow row;
  final bool first;
  final bool selected;
  final bool playing;
  final bool canSeek;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onSeek;

  @override
  State<_TimedRowTile> createState() => _TimedRowTileState();
}

class _TimedRowTileState extends State<_TimedRowTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final selected = widget.selected;
    return Padding(
      padding: EdgeInsets.only(top: row.stanzaStart && !widget.first ? 12 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (row.stanzaStart && row.label != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Text(
                row.label!.toUpperCase(),
                style: DesktopText.overline.copyWith(
                  color: DesktopColors.accentText,
                ),
              ),
            ),
          MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              onDoubleTap: widget.onDoubleTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.accentA.withValues(alpha: 0.12)
                      : _hovered
                      ? AppColors.whiteAlpha(0.04)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border(
                    left: BorderSide(
                      color: widget.playing
                          ? AppColors.white
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.accentA : null,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: selected
                              ? AppColors.accentA
                              : AppColors.whiteAlpha(0.3),
                          width: 1.5,
                        ),
                      ),
                      child: selected
                          ? const Icon(
                              Icons.check_rounded,
                              size: 13,
                              color: AppColors.white,
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Tooltip(
                      message: widget.canSeek ? 'Play from here' : '',
                      child: Material(
                        color: AppColors.whiteAlpha(0.06),
                        borderRadius: BorderRadius.circular(7),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(7),
                          onTap: widget.canSeek ? widget.onSeek : null,
                          child: Container(
                            width: 76,
                            height: 28,
                            alignment: Alignment.center,
                            child: Text(
                              preciseTimestamp(row.time),
                              style: DesktopText.mono.copyWith(
                                color: selected
                                    ? const Color(0xFFC7D6FF)
                                    : AppColors.whiteAlpha(0.8),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        row.isBreak ? '♪  Instrumental' : row.text,
                        style: TextStyle(
                          color: row.isBreak
                              ? AppColors.whiteAlpha(0.6)
                              : AppColors.white,
                          fontStyle: row.isBreak ? FontStyle.italic : null,
                          fontSize: 15,
                          height: 1.35,
                          fontWeight: widget.playing
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorAction extends StatelessWidget {
  const _InspectorAction({
    required this.label,
    required this.icon,
    required this.keys,
    required this.onPressed,
    this.color,
  });

  final String label;
  final IconData icon;
  final String keys;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? AppColors.white;
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: Material(
        color: AppColors.whiteAlpha(0.04),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(icon, size: 15, color: foreground),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                KeyHint(keys),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyboardHelp extends StatelessWidget {
  const _KeyboardHelp({required this.entries});

  final List<(String, String)> entries;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.whiteAlpha(0.03),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Keyboard',
            style: TextStyle(
              color: AppColors.whiteAlpha(0.8),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          for (final (label, keys) in entries) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: AppColors.whiteAlpha(0.66),
                      fontSize: 12,
                    ),
                  ),
                ),
                KeyHint(keys),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LiveLine extends StatelessWidget {
  const _LiveLine({
    required this.leading,
    required this.text,
    required this.style,
    required this.leadingColor,
    this.small = false,
    this.padding = const EdgeInsets.symmetric(vertical: 7),
  });

  final String leading;
  final String text;
  final TextStyle style;
  final Color leadingColor;

  /// Leading set as a small caption (a section label) rather than a time.
  final bool small;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              leading,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: small
                  ? DesktopText.overline.copyWith(color: leadingColor)
                  : DesktopText.mono.copyWith(
                      color: leadingColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}

class _LiveKey extends StatelessWidget {
  const _LiveKey({
    required this.label,
    required this.keys,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final String keys;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: primary ? AppColors.accentGradient : null,
          color: primary ? null : AppColors.whiteAlpha(0.03),
          borderRadius: BorderRadius.circular(16),
          border: primary
              ? null
              : Border.all(color: AppColors.whiteAlpha(0.12)),
          boxShadow: [
            if (primary)
              BoxShadow(
                color: AppColors.accentB.withValues(alpha: 0.5),
                blurRadius: 36,
                offset: const Offset(0, 16),
                spreadRadius: -12,
              ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: Container(
              height: 72,
              constraints: BoxConstraints(minWidth: primary ? 220 : 104),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: primary ? 16 : 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  KeyHint(keys, onAccent: primary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Playback controls and the song's lines as markers along a track, with
/// the playhead. Markers can be dragged to retime their line ([onRetime]).
class _Timeline extends ConsumerStatefulWidget {
  const _Timeline({
    required this.song,
    required this.rows,
    required this.selected,
    required this.onRetime,
    required this.onTogglePlay,
    required this.onRewind,
    required this.onSeek,
    required this.hint,
  });

  final Song song;
  final List<TimedRow> rows;
  final Set<int> selected;
  final void Function(int index, Duration time)? onRetime;
  final VoidCallback onTogglePlay;
  final VoidCallback onRewind;
  final ValueChanged<Duration> onSeek;
  final String hint;

  @override
  ConsumerState<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends ConsumerState<_Timeline> {
  /// The marker being dragged and where it is, before it is applied.
  int? _dragging;
  Duration? _dragTime;

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(playbackProvider);
    final isCurrent = playback.current?.id == widget.song.id;
    final duration = isCurrent && playback.duration > Duration.zero
        ? playback.duration
        : widget.song.duration;
    final position = isCurrent ? playback.position : Duration.zero;
    final notifier = ref.read(playbackProvider.notifier);
    final speed = notifier.speed;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
      decoration: BoxDecoration(
        color: DesktopColors.bar,
        border: Border(top: BorderSide(color: AppColors.whiteAlpha(0.06))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back 5 seconds (←)',
                iconSize: 18,
                onPressed: isCurrent ? widget.onRewind : null,
                icon: const Icon(AppIcons.rewind),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: isCurrent
                    ? (playback.playing ? 'Pause' : 'Play')
                    : 'Play this song',
                child: Material(
                  color: AppColors.white,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: widget.onTogglePlay,
                    child: SizedBox.square(
                      dimension: 40,
                      child: Icon(
                        isCurrent && playback.playing
                            ? AppIcons.pause
                            : AppIcons.playFilled,
                        size: 16,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Text.rich(
                TextSpan(
                  text: preciseTimestamp(position),
                  children: [
                    TextSpan(
                      text: ' / ${preciseTimestamp(duration)}',
                      style: TextStyle(color: AppColors.whiteAlpha(0.5)),
                    ),
                  ],
                ),
                style: DesktopText.mono.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 20),
              DesktopSegmented<double>(
                dense: true,
                options: const [(0.5, '0.5×'), (0.75, '0.75×'), (1.0, '1×')],
                selected: speed,
                onSelected: (value) async {
                  await notifier.setSpeed(value);
                  if (mounted) setState(() {});
                },
              ),
              const Spacer(),
              Text(
                widget.hint,
                style: TextStyle(
                  color: AppColors.whiteAlpha(0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 56,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final total = duration.inMilliseconds;
                double xOf(Duration t) => total <= 0
                    ? 0
                    : (t.inMilliseconds / total).clamp(0, 1) * width;
                Duration timeAt(double x) =>
                    duration * (x / width).clamp(0.0, 1.0);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: isCurrent
                      ? (details) =>
                            widget.onSeek(timeAt(details.localPosition.dx))
                      : null,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: DesktopColors.field,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: xOf(position),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.accentA.withValues(alpha: 0.14),
                            borderRadius: const BorderRadius.horizontal(
                              left: Radius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      for (var i = 0; i < widget.rows.length; i++)
                        _marker(
                          i,
                          x: xOf(
                            _dragging == i ? _dragTime! : widget.rows[i].time,
                          ),
                          timeAt: timeAt,
                        ),
                      Positioned(
                        left: xOf(position) - 1,
                        top: 0,
                        bottom: 0,
                        width: 2,
                        child: const IgnorePointer(
                          child: ColoredBox(color: AppColors.white),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _marker(
    int i, {
    required double x,
    required Duration Function(double x) timeAt,
  }) {
    final row = widget.rows[i];
    final selected = widget.selected.contains(i);
    final color = selected || _dragging == i
        ? DesktopColors.accentText
        : row.isBreak
        ? AppColors.whiteAlpha(0.3)
        : AppColors.whiteAlpha(0.55);
    final number = widget.rows.take(i + 1).where((r) => !r.isBreak).length;
    return Positioned(
      left: x - 6,
      top: 0,
      bottom: 0,
      width: 12,
      child: MouseRegion(
        cursor: widget.onRetime == null
            ? MouseCursor.defer
            : SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: widget.onRetime == null
              ? null
              : (_) => setState(() {
                  _dragging = i;
                  _dragTime = row.time;
                }),
          onHorizontalDragUpdate: widget.onRetime == null
              ? null
              : (details) {
                  setState(() => _dragTime = timeAt(x + details.delta.dx));
                },
          onHorizontalDragEnd: widget.onRetime == null
              ? null
              : (_) {
                  final time = _dragTime;
                  setState(() {
                    _dragging = null;
                    _dragTime = null;
                  });
                  if (time != null) widget.onRetime!(i, time);
                },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 5,
                top: 6,
                bottom: 6,
                width: 2,
                child: ColoredBox(color: color),
              ),
              if (!row.isBreak)
                Positioned(
                  left: 9,
                  bottom: 4,
                  child: Text(
                    '$number',
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
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
      backgroundColor: const Color(0xFF16161E),
      title: const Text('Edit line'),
      content: SizedBox(
        width: 420,
        child: TextField(
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
