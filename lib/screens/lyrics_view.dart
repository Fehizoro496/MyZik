import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/lyrics_repository.dart';
import '../icons.dart';
import '../models.dart';
import '../providers/lyrics_provider.dart';
import '../providers/playback_provider.dart';
import '../theme.dart';

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
        _PillButton(
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
    final lines = plain
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .take(3)
        .join('\n');
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

/// Small frosted pill used for the lyrics actions.
class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap, this.icon});

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
    );
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
  DateTime _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _firstScroll = true;

  GlobalKey _keyFor(int i) => _lineKeys.putIfAbsent(i, GlobalKey.new);

  void _follow(int index, {required bool animate}) {
    if (index < 0) return;
    if (DateTime.now().difference(_userScrolledAt) <
        const Duration(seconds: 3)) {
      return;
    }
    final ctx = _keyFor(index).currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.4,
      duration: animate ? const Duration(milliseconds: 350) : Duration.zero,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lyricsProvider(widget.song));
    final lyrics = state.asData?.value;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

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
                    ],
                  ),
                ),
                Expanded(
                  child: state.isLoading
                      ? _loading()
                      : lyrics == null
                      ? _empty(state.error)
                      : lyrics.instrumental
                      ? _message('Instrumental')
                      : lyrics.synced
                      ? _synced(lyrics)
                      : _plain(lyrics.plain ?? ''),
                ),
                if (lyrics?.source == LyricsSource.web)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                    child: Text(
                      _webCredit(lyrics!.sourceUrl),
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

  Widget _synced(Lyrics lyrics) {
    final index = ref.watch(
      playbackProvider.select((p) => lyrics.indexAt(p.position)),
    );
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
                onTap: () {
                  _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);
                  ref
                      .read(playbackProvider.notifier)
                      .seek(lyrics.lines[i].time);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 250),
                    style: TextStyle(
                      color: i == index
                          ? AppColors.white
                          : AppColors.whiteAlpha(i < index ? 0.3 : 0.5),
                      fontSize: 22,
                      height: 1.3,
                      fontWeight: i == index
                          ? FontWeight.w800
                          : FontWeight.w700,
                    ),
                    child: Text(_display(lyrics.lines[i])),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _loading() {
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
            'Looking for lyrics…',
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
            _PillButton(
              label: 'Search again',
              icon: AppIcons.retry,
              onTap: notifier.retry,
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

  Widget _plain(String plain) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Text(
        plain,
        style: TextStyle(
          color: AppColors.whiteAlpha(0.8),
          fontSize: 18,
          height: 1.6,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
