import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/download_engine.dart';
import '../data/youtube_repository.dart';
import '../icons.dart';
import '../models.dart';
import '../providers/downloads_provider.dart';
import '../providers/playback_provider.dart';
import '../providers/youtube_provider.dart';
import '../theme.dart';
import 'desktop_style.dart';
import 'pages.dart';
import 'track_table.dart';

/// YouTube search with play and download, and the downloaded tracks when no
/// search is running.
class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String? _resolvingId;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  Future<void> _play(YouTubeTrack track) async {
    if (_resolvingId != null) return;
    setState(() {
      _resolvingId = track.videoId;
      _error = null;
    });
    try {
      final saved = ref.read(downloadsProvider).saved[track.videoId];
      if (saved != null) {
        await ref
            .read(playbackProvider.notifier)
            .playSong(saved.song, throwOnLoadError: true);
        return;
      }
      final url = await ref
          .read(youtubeRepositoryProvider)
          .resolveAudio(track.videoId);
      await ref
          .read(playbackProvider.notifier)
          .playSong(
            Song(
              id: youtubeSongId(track.videoId),
              title: track.title,
              artist: track.artist,
              duration: track.duration,
              uri: url.toString(),
              artworkUrl: track.thumbnailUrl,
              youtubeVideoId: track.videoId,
            ),
            throwOnLoadError: true,
          );
    } catch (error) {
      debugPrint('Discover: failed to play ${track.videoId}: $error');
      if (mounted) setState(() => _error = 'This video could not be played.');
    } finally {
      if (mounted) setState(() => _resolvingId = null);
    }
  }

  Future<void> _download(YouTubeTrack track) async {
    setState(() => _error = null);
    try {
      await ref.read(downloadsProvider.notifier).download(track);
    } catch (error) {
      debugPrint('Discover: failed to download ${track.videoId}: $error');
      if (mounted) {
        setState(() => _error = 'Could not download “${track.title}”.');
      }
    }
  }

  void _submit() {
    _debounce?.cancel();
    setState(() => _query = _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The downloads get a column of their own when there is room.
        final wide = constraints.maxWidth >= 980;
        final main = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageHeader(
              title: 'Discover',
              subtitle:
                  'Search YouTube, stream instantly, or download for offline '
                  'listening.',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 8),
              child: _SearchField(
                controller: _controller,
                onChanged: _onChanged,
                onSubmitted: _submit,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 4, 28, 4),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: DesktopColors.error,
                    fontSize: 13,
                  ),
                ),
              ),
            Expanded(
              child: _query.isEmpty
                  ? _Downloads(showActive: !wide)
                  : _results(),
            ),
          ],
        );
        if (!wide) return main;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: main),
            _DownloadsPanel(onRetry: _download),
          ],
        );
      },
    );
  }

  Widget _results() {
    return ref
        .watch(youtubeSearchProvider(_query))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Text(
              'Search failed. Check your connection.',
              style: TextStyle(color: AppColors.whiteAlpha(0.5)),
            ),
          ),
          data: (tracks) => ListView.builder(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            itemCount: tracks.length,
            itemBuilder: (context, i) => _ResultRow(
              track: tracks[i],
              resolving: _resolvingId == tracks[i].videoId,
              onPlay: () => _play(tracks[i]),
              onDownload: () => _download(tracks[i]),
            ),
          ),
        );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 56,
      padding: const EdgeInsets.only(left: 18, right: 8),
      decoration: BoxDecoration(
        color: DesktopColors.field,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: focused
              ? AppColors.accentA.withValues(alpha: 0.5)
              : AppColors.whiteAlpha(0.08),
        ),
        boxShadow: [
          if (focused)
            BoxShadow(
              color: AppColors.accentA.withValues(alpha: 0.12),
              spreadRadius: 4,
            ),
        ],
      ),
      child: Row(
        children: [
          Icon(AppIcons.search, size: 20, color: AppColors.whiteAlpha(0.7)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              onChanged: widget.onChanged,
              onSubmitted: (_) => widget.onSubmitted(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Artists, songs, videos…',
                hintStyle: TextStyle(color: AppColors.whiteAlpha(0.5)),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          DesktopPill(
            primary: true,
            label: 'Search',
            onPressed: widget.onSubmitted,
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends ConsumerStatefulWidget {
  const _ResultRow({
    required this.track,
    required this.resolving,
    required this.onPlay,
    required this.onDownload,
  });

  final YouTubeTrack track;
  final bool resolving;
  final VoidCallback onPlay;
  final VoidCallback onDownload;

  @override
  ConsumerState<_ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends ConsumerState<_ResultRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final playing = ref.watch(
      playbackProvider.select(
        (p) => p.current?.id == youtubeSongId(track.videoId),
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onPlay,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: playing
                ? AppColors.accentA.withValues(alpha: 0.08)
                : _hovered
                ? AppColors.whiteAlpha(0.05)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: [
                    Image.network(
                      track.thumbnailUrl,
                      width: 120,
                      height: 68,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 120,
                        height: 68,
                        color: AppColors.whiteAlpha(0.08),
                      ),
                    ),
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          _duration(track.duration),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: playing
                            ? DesktopColors.accentText
                            : AppColors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.artist,
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
              const SizedBox(width: 12),
              widget.resolving
                  ? const SizedBox.square(
                      dimension: 40,
                      child: Center(
                        child: SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Stream now',
                      onPressed: widget.onPlay,
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.whiteAlpha(0.08),
                      ),
                      icon: const Icon(AppIcons.playFilled, size: 16),
                    ),
              const SizedBox(width: 12),
              SizedBox(
                width: 140,
                child: _DownloadState(
                  videoId: track.videoId,
                  onDownload: widget.onDownload,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _duration(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// A result's download: the button, its progress, or "In library".
class _DownloadState extends ConsumerWidget {
  const _DownloadState({required this.videoId, required this.onDownload});

  final String videoId;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(
      downloadsProvider.select((d) => d.saved.containsKey(videoId)),
    );
    final active = ref.watch(
      downloadsProvider.select((d) => d.active[videoId]),
    );
    if (saved) {
      return const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(AppIcons.downloaded, size: 16, color: DesktopColors.success),
          SizedBox(width: 8),
          Text(
            'In library',
            style: TextStyle(
              color: DesktopColors.success,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }
    if (active != null && !active.isFailed) {
      return DownloadProgressPill(download: active);
    }
    final failed = active?.isFailed ?? false;
    return DesktopPill(
      icon: failed ? AppIcons.retry : AppIcons.download,
      label: failed ? 'Retry' : 'Download',
      onPressed: onDownload,
    );
  }
}

/// Progress of a download in a pill-shaped box: percentage over a thin bar.
class DownloadProgressPill extends StatelessWidget {
  const DownloadProgressPill({super.key, required this.download});

  final ActiveDownload download;

  @override
  Widget build(BuildContext context) {
    final running = download.phase == DownloadPhase.running;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.accentA.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _downloadStatus(download),
            style: const TextStyle(
              color: DesktopColors.accentText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: running ? download.progress : null,
              minHeight: 3,
              color: AppColors.accentA,
              backgroundColor: AppColors.whiteAlpha(0.12),
            ),
          ),
        ],
      ),
    );
  }
}

String _downloadStatus(ActiveDownload download) => switch (download.phase) {
  DownloadPhase.running => '${(download.progress * 100).round()}%',
  DownloadPhase.queued => 'Queued',
  DownloadPhase.waiting => 'Waiting for network',
  DownloadPhase.failed => 'Failed',
  DownloadPhase.complete => 'Finishing',
  DownloadPhase.canceled => 'Canceled',
};

/// Downloads in progress, beside the results on wide windows.
class _DownloadsPanel extends ConsumerWidget {
  const _DownloadsPanel({required this.onRetry});

  final void Function(YouTubeTrack track) onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(downloadsProvider.select((d) => d.active));
    final running = active.values.where((d) => !d.isFailed).length;
    final notifier = ref.read(downloadsProvider.notifier);
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: DesktopColors.panel,
        border: Border(left: BorderSide(color: AppColors.whiteAlpha(0.06))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.whiteAlpha(0.06)),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Text(
                  'Downloads',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    running == 0
                        ? 'Nothing in progress'
                        : '$running active · runs in background',
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
            child: active.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Downloads you start appear here, and keep going '
                        'while you browse.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.whiteAlpha(0.6),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(8),
                    children: [
                      for (final download in active.values)
                        _ActiveDownloadRow(
                          download: download,
                          onCancel: () =>
                              notifier.cancel(download.track.videoId),
                          onRetry: () => onRetry(download.track),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ActiveDownloadRow extends StatelessWidget {
  const _ActiveDownloadRow({
    required this.download,
    required this.onCancel,
    required this.onRetry,
  });

  final ActiveDownload download;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = download.isFailed;
    final running = download.phase == DownloadPhase.running;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              download.track.thumbnailUrl,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 44,
                height: 44,
                color: AppColors.whiteAlpha(0.08),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  download.track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: failed ? 1 : (running ? download.progress : null),
                    minHeight: 3,
                    color: failed ? AppColors.liked : AppColors.accentA,
                    backgroundColor: AppColors.whiteAlpha(0.1),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _downloadStatus(download),
                  style: TextStyle(
                    color: failed
                        ? DesktopColors.error
                        : AppColors.whiteAlpha(0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          failed
              ? IconButton(
                  tooltip: 'Retry download',
                  iconSize: 16,
                  onPressed: onRetry,
                  icon: const Icon(AppIcons.retry),
                )
              : IconButton(
                  tooltip: 'Cancel',
                  iconSize: 16,
                  onPressed: onCancel,
                  icon: const Icon(AppIcons.close),
                ),
        ],
      ),
    );
  }
}

/// Downloaded tracks, as a table, plus a line per download in progress.
class _Downloads extends ConsumerWidget {
  const _Downloads({required this.showActive});

  /// Lists the downloads in progress above the table, when no panel does.
  final bool showActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(downloadsProvider.select((d) => d.songs));
    final active = ref.watch(downloadsProvider.select((d) => d.active));
    final notifier = ref.read(downloadsProvider.notifier);
    return TrackTable(
      songs: songs,
      emptyMessage: 'Downloaded tracks appear here.',
      removeLabel: 'Delete download',
      onRemove: (song) {
        final track = ref.read(downloadsProvider).bySongId(song.id);
        if (track != null) notifier.remove(track.videoId);
      },
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 4),
            child: Text(
              'Downloads',
              style: TextStyle(
                color: AppColors.whiteAlpha(0.9),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (showActive)
            for (final download in active.values)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 28),
                title: Text(download.track.title, maxLines: 1),
                subtitle: download.isFailed
                    ? const Text('Failed')
                    : LinearProgressIndicator(
                        value: download.phase == DownloadPhase.running
                            ? download.progress
                            : null,
                      ),
                trailing: IconButton(
                  tooltip: 'Cancel',
                  onPressed: () => notifier.cancel(download.track.videoId),
                  icon: const Icon(AppIcons.close, size: 16),
                ),
              ),
        ],
      ),
    );
  }
}
