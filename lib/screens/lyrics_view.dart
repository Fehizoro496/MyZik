import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/lyrics_repository.dart';
import '../data/lyrics_structure.dart';
import '../icons.dart';
import '../models.dart';
import '../providers/lyrics_provider.dart';
import '../providers/playback_provider.dart';
import '../providers/shared_preferences_provider.dart';
import '../theme.dart';
import 'lyrics_editor_screen.dart';

/// Three-line lyrics teaser on the Now Playing screen: previous, current and
/// next line around the playhead. Tapping it opens the full [LyricsSheet].
/// Has a fixed height so the layout doesn't jump as lyrics load.
class LyricsPreview extends ConsumerWidget {
  const LyricsPreview({super.key, required this.song});

  final Song song;

  static const _height = 96.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyrics = ref.watch(lyricsProvider(song));
    return SizedBox(
      height: _height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: lyrics.when(
          loading: () => _status('Looking for lyrics…'),
          error: (error, _) => _missing(context, ref, error: error),
          data: (lyrics) {
            if (lyrics == null) return _missing(context, ref);
            if (lyrics.instrumental) return _status('Instrumental');
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => LyricsSheet.show(context, song),
              child: lyrics.synced
                  ? _SyncedPreview(lyrics: lyrics)
                  : _plainPreview(lyrics.plain ?? ''),
            );
          },
        ),
      ),
    );
  }

  /// No lyrics (or a failed lookup): say so, and offer the sheet where the
  /// user can search again.
  Widget _missing(BuildContext context, WidgetRef ref, {Object? error}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _missingMessage(error),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.whiteAlpha(0.4), fontSize: 14),
        ),
        const SizedBox(height: 10),
        LyricsPill(
          label: 'Get lyrics',
          onTap: () => LyricsSheet.show(context, song),
        ),
      ],
    );
  }

  Widget _status(String text) {
    return Center(
      child: Text(
        text,
        style: TextStyle(color: AppColors.whiteAlpha(0.4), fontSize: 14),
      ),
    );
  }

  Widget _plainPreview(String plain) {
    final lines = lyricLinesOf(plain).take(3).join('\n');
    return Center(
      child: Text(
        lines,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppColors.whiteAlpha(0.55),
          fontSize: 15,
          height: 1.5,
        ),
      ),
    );
  }
}

/// The synced teaser. Selects only the current line index from playback so it
/// rebuilds once per line change, not on every position tick.
class _SyncedPreview extends ConsumerWidget {
  const _SyncedPreview({required this.lyrics});

  final Lyrics lyrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(
      playbackProvider.select((p) => lyrics.indexAt(p.position)),
    );
    String at(int i) =>
        (i < 0 || i >= lyrics.lines.length) ? '' : _display(lyrics.lines[i]);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Column(
        key: ValueKey(index),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            at(index - 1),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.whiteAlpha(0.3), fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            index < 0 ? '♪' : at(index),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            at(index + 1),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.whiteAlpha(0.3), fontSize: 15),
          ),
        ],
      ),
    );
  }
}

String _missingMessage(Object? error) => switch (error) {
  null => 'No lyrics found.',
  LyricsException(:final message) => message,
  _ => 'Lyrics unavailable.',
};

/// Credit line for lyrics found by the web search: they come from a page an
/// LLM read, so they may be partial or wrong.
String _webCredit(String? url) {
  final host = url == null ? null : Uri.tryParse(url)?.host;
  final from = (host == null || host.isEmpty)
      ? 'the web'
      : host.replaceFirst(RegExp(r'^www\.'), '');
  return 'Found on $from by AI — may be incomplete or inaccurate';
}

/// Where the lyrics come from, when the listener should know: found by AI
/// on the web, and/or edited by hand.
String? _credit(Lyrics lyrics) => switch ((lyrics.source, lyrics.edited)) {
  (LyricsSource.web, false) => _webCredit(lyrics.sourceUrl),
  (LyricsSource.web, true) =>
    '${_webCredit(lyrics.sourceUrl).split(' — ').first} · edited by you',
  (LyricsSource.manual, _) => 'Written by you',
  (_, true) => 'Edited by you',
  _ => null,
};

/// Small frosted pill used for the lyrics actions.
class LyricsPill extends StatelessWidget {
  const LyricsPill({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;

  /// Null disables (and dims) the button.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: onTap == null ? 0.5 : 1,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.whiteAlpha(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.whiteAlpha(0.14)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: AppColors.white),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small caption naming a section of the song ("Chorus", "Couplet 2").
class LyricsSectionLabel extends StatelessWidget {
  const LyricsSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final text = label.replaceAll(RegExp(r'^\[|\]$|:$'), '').trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: AppColors.whiteAlpha(0.38),
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.3,
        ),
      ),
    );
  }
}

/// A lyric line where parts in parentheses (backing vocals, ad-libs) are
/// set in a lighter italic, so the lead line reads first.
class _LyricText extends StatelessWidget {
  const _LyricText(this.text, {this.style});

  final String text;
  final TextStyle? style;

  static final _aside = RegExp(r'\([^)]*\)');

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in _aside.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start)));
      }
      spans.add(
        TextSpan(
          text: match[0],
          style: const TextStyle(
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
      last = match.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(children: spans), style: style);
  }
}

/// Empty LRC lines mark instrumental breaks; show a note instead of a gap.
String _display(LyricLine line) => line.text.isEmpty ? '♪' : line.text;

/// Full lyrics as a frosted bottom sheet. Synced lyrics follow the playhead
/// (pausing for a few seconds after the user scrolls by hand) and tapping a
/// line seeks to it.
class LyricsSheet extends ConsumerStatefulWidget {
  const LyricsSheet({super.key, required this.song});

  final Song song;

  static void show(BuildContext context, Song song) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => LyricsSheet(song: song),
    );
  }

  @override
  ConsumerState<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends ConsumerState<LyricsSheet> {
  final _lineKeys = <int, GlobalKey>{};
  final _syncKeys = <int, GlobalKey>{};

  /// Lines timed so far while synchronizing. Empty text marks an
  /// instrumental break.
  final _synchronizedLines = <LyricLine>[];
  DateTime _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _firstScroll = true;
  bool _isSynchronizing = false;
  bool _saving = false;
  String? _saveError;

  /// Whisper is listening to the track (see [_autoSynchronize]).
  bool _autoSyncing = false;

  /// Outcome of the last auto-sync, shown under the title.
  String? _notice;

  /// Replaces the synchronizer's instructions after an auto-sync that needs
  /// checking by hand.
  String? _syncNote;

  /// Auto-synced timings matching at least this share of the lyric words are
  /// saved directly; below, they open in the synchronizer to be checked.
  static const _autoSaveConfidence = 0.8;

  static const _kAutoSyncConsent = 'lyrics.autoSyncConsent';

  /// Taps land a little after the line actually starts; this is taken off
  /// every mark so lines light up on time.
  static const _reactionDelay = Duration(milliseconds: 150);

  GlobalKey _keyFor(int i) => _lineKeys.putIfAbsent(i, GlobalKey.new);

  /// The sheet's route, read here rather than in the post-frame scroll
  /// callbacks: looking up inherited widgets outside build/dependency
  /// changes leaves dangling dependencies (`_dependents.isEmpty` asserts).
  ModalRoute<Object?>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  Lyrics? _stanzasOf;
  Map<int, String?> _stanzas = const {};

  /// [stanzaStarts] for [lyrics], computed once rather than on every line
  /// change.
  Map<int, String?> _stanzaStartsFor(Lyrics lyrics) {
    if (!identical(lyrics, _stanzasOf)) {
      _stanzasOf = lyrics;
      _stanzas = stanzaStarts(lyrics.lines, lyrics.plain);
    }
    return _stanzas;
  }

  bool get _hasUnsavedSync => _isSynchronizing && _synchronizedLines.isNotEmpty;

  void _follow(int index, {required bool animate}) {
    if (index < 0) return;
    if (DateTime.now().difference(_userScrolledAt) <
        const Duration(seconds: 3)) {
      return;
    }
    final ctx = _keyFor(index).currentContext;
    if (ctx == null || !_canScrollTo(ctx)) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.4,
      duration: animate ? const Duration(milliseconds: 350) : Duration.zero,
      curve: Curves.easeOutCubic,
    );
  }

  /// Whether [line] can be scrolled into view now. The sheet keeps
  /// following playback while covered (the lyrics editor is pushed on top),
  /// and its lines may then have no attached render object, which
  /// [Scrollable.ensureVisible] asserts on.
  bool _canScrollTo(BuildContext line) {
    if (!(_route?.isCurrent ?? true)) return false;
    final object = line.findRenderObject();
    return object != null && object.attached;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lyricsProvider(widget.song));
    final lyrics = state.asData?.value;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    // The sheet stays on the song it was opened for, while playback may move
    // on to another track: following, seeking and timing only apply while
    // this song is the one playing.
    final isCurrent = ref.watch(
      playbackProvider.select((p) => p.current?.id == widget.song.id),
    );
    final canResync =
        lyrics != null &&
        lyrics.synced &&
        !_isSynchronizing &&
        !_autoSyncing &&
        (lyrics.plain?.trim().isNotEmpty ?? false);
    // Only for audio files on the device: streamed tracks are never sent.
    final canAutoSync =
        lyrics != null &&
        !_isSynchronizing &&
        !_autoSyncing &&
        ref
            .read(lyricsRepositoryProvider)
            .canAutoSynchronize(widget.song, lyrics);

    // Unsaved timings must not vanish with a stray back gesture, barrier tap
    // or swipe down.
    return PopScope(
      canPop: !_hasUnsavedSync,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      // The sheet's own drag-to-dismiss calls Navigator.pop directly,
      // bypassing PopScope; an inner vertical drag recognizer wins the
      // gesture arena and swallows it.
      child: GestureDetector(
        onVerticalDragStart: _hasUnsavedSync ? (_) {} : null,
        child: _sheet(
          state,
          lyrics,
          maxHeight,
          isCurrent,
          canResync,
          canAutoSync,
        ),
      ),
    );
  }

  Widget _sheet(
    AsyncValue<Lyrics?> state,
    Lyrics? lyrics,
    double maxHeight,
    bool isCurrent,
    bool canResync,
    bool canAutoSync,
  ) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          height: maxHeight,
          decoration: BoxDecoration(
            color: const Color.fromRGBO(15, 15, 21, 0.88),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            border: Border(top: BorderSide(color: AppColors.whiteAlpha(0.09))),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.whiteAlpha(0.22),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  child: Column(
                    children: [
                      Text(
                        widget.song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.whiteAlpha(0.5),
                          fontSize: 13,
                        ),
                      ),
                      if (_notice != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _notice!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.whiteAlpha(0.6),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: state.isLoading
                      ? _loading()
                      : _autoSyncing
                      ? _loading('Listening to the track…')
                      : lyrics == null
                      ? _empty(state.error)
                      : lyrics.instrumental
                      ? _message('Instrumental')
                      : _isSynchronizing
                      ? _synchronizer(lyrics, isCurrent)
                      : lyrics.synced
                      ? _synced(lyrics, isCurrent)
                      : _plain(lyrics, canAutoSync),
                ),
                if (canResync)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Wrap(
                      spacing: 10,
                      children: [
                        LyricsPill(
                          label: 'Edit',
                          icon: AppIcons.edit,
                          onTap: () => LyricsEditorScreen.open(
                            context,
                            widget.song,
                            lyrics,
                          ),
                        ),
                        LyricsPill(
                          label: 'Resynchronize',
                          icon: AppIcons.timer,
                          onTap: _startSynchronization,
                        ),
                        if (canAutoSync) _autoSyncButton(lyrics!),
                      ],
                    ),
                  ),
                if (lyrics != null && _credit(lyrics) != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                    child: Text(
                      _credit(lyrics)!,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(
                        color: AppColors.whiteAlpha(0.35),
                        fontSize: 11.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _synced(Lyrics lyrics, bool isCurrent) {
    final index = ref.watch(
      playbackProvider.select(
        (p) =>
            p.current?.id == widget.song.id ? lyrics.indexAt(p.position) : -1,
      ),
    );
    final stanzas = _stanzaStartsFor(lyrics);
    // Scroll after layout so the target line has a render object. The first
    // jump is instant so the sheet opens already on the current line.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _follow(index, animate: !_firstScroll);
      _firstScroll = false;
    });

    return NotificationListener<UserScrollNotification>(
      onNotification: (_) {
        _userScrolledAt = DateTime.now();
        return false;
      },
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 200),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < lyrics.lines.length; i++)
              GestureDetector(
                key: _keyFor(i),
                behavior: HitTestBehavior.opaque,
                onTap: isCurrent
                    ? () {
                        _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(
                          0,
                        );
                        ref
                            .read(playbackProvider.notifier)
                            .seek(lyrics.lines[i].time);
                      }
                    : null,
                child: Padding(
                  // A new stanza gets some air, and its label if it has one.
                  padding: EdgeInsets.only(
                    top: stanzas.containsKey(i) && i > 0 ? 27 : 9,
                    bottom: 9,
                  ),
                  child: isSectionLabel(lyrics.lines[i].text)
                      // Timed labels from older synchronizations.
                      ? LyricsSectionLabel(lyrics.lines[i].text)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (stanzas[i] != null)
                              LyricsSectionLabel(stanzas[i]!),
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 250),
                              style: TextStyle(
                                color: i == index
                                    ? AppColors.white
                                    : AppColors.whiteAlpha(
                                        i < index ? 0.3 : 0.5,
                                      ),
                                fontSize: 22,
                                height: 1.3,
                                fontWeight: i == index
                                    ? FontWeight.w800
                                    : FontWeight.w700,
                              ),
                              child: _LyricText(_display(lyrics.lines[i])),
                            ),
                          ],
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _loading([String text = 'Looking for lyrics…']) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.whiteAlpha(0.7),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            text,
            style: TextStyle(color: AppColors.whiteAlpha(0.5), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _message(String text) {
    return Center(
      child: Text(
        text,
        style: TextStyle(color: AppColors.whiteAlpha(0.5), fontSize: 15),
      ),
    );
  }

  /// Nothing found (or the last attempt failed): search again (LRCLIB, then
  /// the web), and explain when the web search is unavailable.
  Widget _empty(Object? error) {
    final notifier = ref.read(lyricsProvider(widget.song).notifier);
    final hint = ref.read(lyricsRepositoryProvider).canSearchWeb
        ? null
        : 'Add a Groq API key to also search the web for lyrics.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.lyrics, size: 40, color: AppColors.whiteAlpha(0.3)),
            const SizedBox(height: 14),
            Text(
              _missingMessage(error),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.whiteAlpha(0.6), fontSize: 15),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                LyricsPill(
                  label: 'Search again',
                  icon: AppIcons.retry,
                  onTap: notifier.retry,
                ),
                LyricsPill(
                  label: 'Write lyrics',
                  icon: AppIcons.edit,
                  onTap: () =>
                      LyricsEditorScreen.open(context, widget.song, null),
                ),
              ],
            ),
            if (hint != null) ...[
              const SizedBox(height: 14),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.whiteAlpha(0.35),
                  fontSize: 12.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _plain(Lyrics lyrics, bool canAutoSync) {
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            LyricsPill(
              label: 'Edit',
              icon: AppIcons.edit,
              onTap: () =>
                  LyricsEditorScreen.open(context, widget.song, lyrics),
            ),
            LyricsPill(
              label: 'Synchronize',
              icon: AppIcons.timer,
              onTap: _startSynchronization,
            ),
            if (canAutoSync) _autoSyncButton(lyrics),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, stanza) in parseLyricsStructure(
                  lyrics.plain ?? '',
                ).indexed) ...[
                  if (i > 0) const SizedBox(height: 22),
                  if (stanza.label != null) LyricsSectionLabel(stanza.label!),
                  for (final line in stanza.lines)
                    _LyricText(
                      line,
                      style: TextStyle(
                        color: AppColors.whiteAlpha(0.8),
                        fontSize: 18,
                        height: 1.6,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _startSynchronization() {
    setState(() {
      _synchronizedLines.clear();
      _syncKeys.clear();
      _saveError = null;
      _syncNote = null;
      _notice = null;
      _isSynchronizing = true;
    });
  }

  Widget _autoSyncButton(Lyrics lyrics) => LyricsPill(
    label: 'Auto-sync',
    icon: AppIcons.sparkles,
    onTap: () => _autoSynchronize(lyrics),
  );

  /// Times the lyrics with Whisper. A confident result is saved right away;
  /// otherwise it opens in the synchronizer, prefilled, to be checked.
  Future<void> _autoSynchronize(Lyrics lyrics) async {
    if (!await _confirmAutoSync() || !mounted) return;
    setState(() {
      _autoSyncing = true;
      _notice = null;
    });
    try {
      final alignment = await ref
          .read(lyricsRepositoryProvider)
          .autoSynchronize(widget.song, lyrics);
      if (!mounted) return;
      final percent = (alignment.confidence * 100).round();
      if (alignment.confidence >= _autoSaveConfidence) {
        await ref
            .read(lyricsProvider(widget.song).notifier)
            .saveSynchronization(alignment.lines);
        if (!mounted) return;
        setState(() {
          _firstScroll = true;
          _notice =
              'Synchronized by AI ($percent% of the words heard). '
              'Use Resynchronize if a line is off.';
        });
      } else {
        setState(() {
          _synchronizedLines
            ..clear()
            ..addAll(alignment.lines);
          _syncKeys.clear();
          _saveError = null;
          _syncNote =
              'Only $percent% of the words were heard, so some timings may '
              'be off. Tap a line to jump to it and Mark line to retime from '
              'there, then save.';
          _isSynchronizing = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _notice = error is LyricsException
              ? error.message
              : 'Synchronization failed. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _autoSyncing = false);
    }
  }

  /// The audio leaves the device: say so once, and remember the answer.
  Future<bool> _confirmAutoSync() async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getBool(_kAutoSyncConsent) ?? false) return true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Synchronize with AI?'),
        content: const Text(
          'The audio file of this track is sent to Groq, whose speech '
          'recognition finds when each line is sung. Only files on this '
          'device are sent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (accepted != true) return false;
    await prefs.setBool(_kAutoSyncConsent, true);
    return true;
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard synchronization?'),
        content: const Text('The lines timed so far will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
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

  /// The lines to time: section labels are left out, they are never sung.
  static List<String> _textLines(Lyrics lyrics) =>
      lyricLinesOf(lyrics.plain ?? '');

  /// Times the next lyric line, or an instrumental break when [isBreak], at
  /// the live playhead. After the user rewinds, the marks past the playhead
  /// are dropped so that part can be timed again.
  void _mark(List<String> textLines, {bool isBreak = false}) {
    var position =
        ref.read(playbackProvider.notifier).livePosition - _reactionDelay;
    if (position < Duration.zero) position = Duration.zero;
    final marks = _synchronizedLines;
    setState(() {
      _saveError = null;
      _syncNote = null;
      marks.removeWhere((line) => line.time > position);
      if (marks.isNotEmpty && marks.last.time >= position) return;
      if (isBreak) {
        if (marks.isEmpty || marks.last.text.isEmpty) return;
        marks.add(LyricLine(position, ''));
      } else {
        final next = marks.where((line) => line.text.isNotEmpty).length;
        if (next >= textLines.length) return;
        marks.add(LyricLine(position, textLines[next]));
      }
    });
    HapticFeedback.selectionClick();
    _scrollToMark();
  }

  void _undo() {
    setState(_synchronizedLines.removeLast);
    _scrollToMark();
  }

  void _rewind() {
    final notifier = ref.read(playbackProvider.notifier);
    final target = notifier.livePosition - const Duration(seconds: 5);
    notifier.seek(target < Duration.zero ? Duration.zero : target);
  }

  /// Keeps the line to tap next in view as marks are added or undone.
  void _scrollToMark() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx =
          (_syncKeys[_synchronizedLines.length] ??
                  _syncKeys[_synchronizedLines.length - 1])
              ?.currentContext;
      if (ctx == null || !_canScrollTo(ctx)) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.4,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await ref
          .read(lyricsProvider(widget.song).notifier)
          .saveSynchronization(List.of(_synchronizedLines));
      if (!mounted) return;
      setState(() {
        _isSynchronizing = false;
        _synchronizedLines.clear();
        _firstScroll = true;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _saveError =
              'Could not save the synchronization. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _synchronizer(Lyrics lyrics, bool isCurrent) {
    final textLines = _textLines(lyrics);
    final marks = _synchronizedLines;
    final next = marks.where((line) => line.text.isNotEmpty).length;
    final complete = next == textLines.length;
    // Only the play/pause label depends on playback; marks read the live
    // position when tapped, so the sheet doesn't rebuild on every tick.
    final playing = ref.watch(playbackProvider.select((p) => p.playing));
    // Timed lines (breaks included) first, then the lines still to time.
    final entries = <({Duration? time, String text})>[
      for (final line in marks) (time: line.time, text: _display(line)),
      for (final text in textLines.skip(next)) (time: null, text: text),
    ];

    final hint =
        _saveError ??
        _syncNote ??
        (!isCurrent
            ? 'Another track is playing. Play "${widget.song.title}" to '
                  'continue timing it.'
            : complete
            ? 'All lines are timed. Mark a final break if the song ends '
                  'instrumentally, then save.'
            : 'Play the song and tap Mark line as each line starts. Use '
                  'Break for instrumental parts, −5 s to redo a passage.');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 4, 28, 12),
          child: Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _saveError != null
                  ? const Color(0xFFFF8A80)
                  : AppColors.whiteAlpha(0.55),
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < entries.length; i++)
                  GestureDetector(
                    key: _syncKeys.putIfAbsent(i, GlobalKey.new),
                    behavior: HitTestBehavior.opaque,
                    // Jump to a timed line to check it; marking from there
                    // retimes it and everything after.
                    onTap: isCurrent && entries[i].time != null
                        ? () => ref
                              .read(playbackProvider.notifier)
                              .seek(entries[i].time!)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '${_timestampOrPending(entries[i].time)}  '
                        '${entries[i].text}',
                        style: TextStyle(
                          color: i == marks.length
                              ? AppColors.white
                              : AppColors.whiteAlpha(
                                  entries[i].time == null ? 0.32 : 0.65,
                                ),
                          fontSize: 18,
                          height: 1.35,
                          fontWeight: i == marks.length
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              if (marks.isNotEmpty)
                LyricsPill(label: 'Undo', icon: AppIcons.undo, onTap: _undo),
              if (isCurrent) ...[
                LyricsPill(
                  label: '−5 s',
                  icon: AppIcons.rewind,
                  onTap: _rewind,
                ),
                LyricsPill(
                  label: playing ? 'Pause' : 'Play',
                  icon: playing ? AppIcons.pause : AppIcons.playFilled,
                  onTap: () => ref.read(playbackProvider.notifier).togglePlay(),
                ),
                if (!complete)
                  LyricsPill(
                    label: 'Mark line',
                    icon: AppIcons.add,
                    onTap: () => _mark(textLines),
                  ),
                if (marks.isNotEmpty && marks.last.text.isNotEmpty)
                  LyricsPill(
                    label: 'Break',
                    icon: AppIcons.musicNote,
                    onTap: () => _mark(textLines, isBreak: true),
                  ),
              ],
              if (complete)
                LyricsPill(
                  label: _saving ? 'Saving…' : 'Save',
                  icon: AppIcons.checkCircle,
                  onTap: _saving ? null : _save,
                ),
              LyricsPill(
                label: 'Cancel',
                icon: AppIcons.close,
                onTap: () => setState(() {
                  _synchronizedLines.clear();
                  _saveError = null;
                  _isSynchronizing = false;
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _timestampOrPending(Duration? time) =>
    time == null ? '   ···' : _timestamp(time);

String _timestamp(Duration value) {
  final seconds = value.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
