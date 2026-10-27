import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/lyrics_repository.dart';
import '../data/lyrics_structure.dart';
import '../icons.dart';
import '../models.dart';
import '../providers/lyrics_provider.dart';
import '../providers/playback_provider.dart';
import '../screens/lyrics_view.dart';
import '../theme.dart';
import '../widgets.dart';
import 'desktop_navigation.dart';
import 'desktop_style.dart';
import 'lyrics_editor.dart';

/// Right-hand panel of the desktop shell: the playing track's lyrics or the
/// play queue, picked from the player bar.
class DesktopSidePanel extends ConsumerWidget {
  const DesktopSidePanel({super.key, required this.panel});

  final DesktopPanel panel;

  static const width = 340.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: DesktopColors.panel,
        border: Border(left: BorderSide(color: AppColors.whiteAlpha(0.06))),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
            child: Row(
              children: [
                for (final (tab, label) in const [
                  (DesktopPanel.lyrics, 'Lyrics'),
                  (DesktopPanel.queue, 'Queue'),
                ])
                  _PanelTab(
                    label: label,
                    selected: panel == tab,
                    onTap: () =>
                        ref.read(desktopPanelProvider.notifier).state = tab,
                  ),
                const Spacer(),
                IconButton(
                  tooltip: 'Close panel',
                  iconSize: 16,
                  onPressed: () =>
                      ref.read(desktopPanelProvider.notifier).state = null,
                  icon: const Icon(AppIcons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (panel) {
              DesktopPanel.lyrics => const _LyricsPanel(),
              DesktopPanel.queue => const _QueuePanel(),
            },
          ),
        ],
      ),
    );
  }
}

class _PanelTab extends StatelessWidget {
  const _PanelTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: selected ? AppColors.whiteAlpha(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.white : AppColors.whiteAlpha(0.55),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LyricsPanel extends ConsumerWidget {
  const _LyricsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(playbackProvider.select((p) => p.current));
    if (song == null) {
      return const _PanelMessage('Play a song to see its lyrics.');
    }
    final state = ref.watch(lyricsProvider(song));
    final lyrics = state.asData?.value;
    final notifier = ref.read(lyricsProvider(song).notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (lyrics != null && lyrics.synced) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentA.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'SYNCED',
                    style: TextStyle(
                      color: DesktopColors.accentText,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              if (!state.isLoading) ...[
                IconButton(
                  tooltip: lyrics == null ? 'Write lyrics' : 'Edit lyrics',
                  iconSize: 16,
                  onPressed: () =>
                      DesktopLyricsEditor.open(context, song, lyrics),
                  icon: const Icon(AppIcons.edit),
                ),
                if (lyrics != null &&
                    !lyrics.instrumental &&
                    (lyrics.plain?.trim().isNotEmpty ?? false))
                  IconButton(
                    tooltip: 'Synchronize',
                    iconSize: 16,
                    onPressed: () => DesktopLyricsEditor.open(
                      context,
                      song,
                      lyrics,
                      liveSync: true,
                    ),
                    icon: const Icon(AppIcons.timer),
                  ),
                IconButton(
                  tooltip: 'Search again',
                  iconSize: 16,
                  onPressed: notifier.retry,
                  icon: const Icon(AppIcons.retry),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: state.when(
            loading: () => const Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (error, _) => _PanelMessage(
              error is LyricsException
                  ? error.message
                  : 'Lyrics are unavailable.',
            ),
            data: (lyrics) {
              if (lyrics == null) {
                return const _PanelMessage(
                  'No lyrics found. Search again or write them.',
                );
              }
              if (lyrics.instrumental) {
                return const _PanelMessage('Instrumental');
              }
              return lyrics.synced
                  ? DesktopSyncedLyrics(key: ValueKey(lyrics), lyrics: lyrics)
                  : _PlainLyrics(lyrics.plain ?? '');
            },
          ),
        ),
      ],
    );
  }
}

/// Timed lyrics following the playhead; clicking a line seeks to it. Hand
/// scrolling pauses the follow for a few seconds. The side panel's size by
/// default, larger in full screen.
class DesktopSyncedLyrics extends ConsumerStatefulWidget {
  const DesktopSyncedLyrics({
    super.key,
    required this.lyrics,
    this.fontSize = 20,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 160),
  });

  final Lyrics lyrics;
  final double fontSize;
  final EdgeInsets padding;

  @override
  ConsumerState<DesktopSyncedLyrics> createState() =>
      _DesktopSyncedLyricsState();
}

class _DesktopSyncedLyricsState extends ConsumerState<DesktopSyncedLyrics> {
  final _keys = <int, GlobalKey>{};
  late final Map<int, String?> _stanzas = stanzaStarts(
    widget.lyrics.lines,
    widget.lyrics.plain,
  );
  DateTime _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _follow(int index) {
    if (index < 0) return;
    if (DateTime.now().difference(_userScrolledAt) <
        const Duration(seconds: 3)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final line = _keys[index]?.currentContext;
      final object = line?.findRenderObject();
      if (line == null || object == null || !object.attached) return;
      Scrollable.ensureVisible(
        line,
        alignment: 0.4,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lyrics.lines;
    final current = ref.watch(
      playbackProvider.select((p) => widget.lyrics.indexAt(p.position)),
    );
    ref.listen(
      playbackProvider.select((p) => widget.lyrics.indexAt(p.position)),
      (_, index) => _follow(index),
    );
    return NotificationListener<UserScrollNotification>(
      onNotification: (_) {
        _userScrolledAt = DateTime.now();
        return false;
      },
      child: ListView.builder(
        padding: widget.padding,
        itemCount: lines.length,
        itemBuilder: (context, i) {
          final line = lines[i];
          if (isSectionLabel(line.text)) return const SizedBox.shrink();
          final label = _stanzas[i];
          final style = TextStyle(
            fontSize: i == current ? widget.fontSize * 1.1 : widget.fontSize,
            height: 1.3,
            fontWeight: FontWeight.w800,
            color: i == current
                ? AppColors.white
                : AppColors.whiteAlpha(i < current ? 0.4 : 0.62),
          );
          return Padding(
            key: _keys.putIfAbsent(i, GlobalKey.new),
            padding: EdgeInsets.only(
              top: _stanzas.containsKey(i) && i > 0 ? widget.fontSize * 1.1 : 0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null) LyricsSectionLabel(label),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () =>
                        ref.read(playbackProvider.notifier).seek(line.time),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: LyricText(
                        line.text.isEmpty ? '♪' : line.text,
                        style: style,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PlainLyrics extends StatelessWidget {
  const _PlainLyrics(this.plain);

  final String plain;

  @override
  Widget build(BuildContext context) {
    final stanzas = parseLyricsStructure(plain);
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(
            'Not synchronized',
            style: TextStyle(color: AppColors.whiteAlpha(0.4), fontSize: 12),
          ),
          const SizedBox(height: 14),
          for (final stanza in stanzas)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (stanza.label != null) LyricsSectionLabel(stanza.label!),
                  for (final line in stanza.lines)
                    LyricText(
                      line,
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.whiteAlpha(0.8),
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

class _QueuePanel extends ConsumerWidget {
  const _QueuePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(playbackProvider.select((p) => p.queue));
    final currentIndex = ref.watch(
      playbackProvider.select((p) => p.currentIndex),
    );
    if (queue.isEmpty) return const _PanelMessage('The queue is empty.');
    final notifier = ref.read(playbackProvider.notifier);
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
      itemCount: queue.length,
      // reorderQueue takes ReorderableListView's raw target index.
      onReorderItem: (oldIndex, newIndex) => notifier.reorderQueue(
        oldIndex,
        newIndex + (newIndex > oldIndex ? 1 : 0),
      ),
      itemBuilder: (context, i) {
        final song = queue[i];
        final current = i == currentIndex;
        return _QueueRow(
          key: ValueKey(Object.hash(song.id, i)),
          song: song,
          current: current,
          onPlay: () => notifier.playQueueIndex(i),
        );
      },
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    super.key,
    required this.song,
    required this.current,
    required this.onPlay,
  });

  final Song song;
  final bool current;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 8, right: 36),
      selected: current,
      selectedTileColor: AppColors.accentA.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: SongArtwork(song: song, size: 40, radius: 6),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: current ? DesktopColors.accentText : AppColors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        song.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: AppColors.whiteAlpha(0.6)),
      ),
      onTap: onPlay,
    );
  }
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.whiteAlpha(0.45), fontSize: 14),
        ),
      ),
    );
  }
}
