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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          title: 'Discover',
          subtitle: 'Search YouTube, play right away or download for offline.',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
          child: TextField(
            controller: _controller,
            onChanged: _onChanged,
            onSubmitted: (value) {
              _debounce?.cancel();
              setState(() => _query = value.trim());
            },
            decoration: InputDecoration(
              hintText: 'Artists, songs, videos…',
              prefixIcon: const Icon(AppIcons.search, size: 18),
              filled: true,
              fillColor: AppColors.whiteAlpha(0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 4, 28, 4),
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFFFF8A9B), fontSize: 13),
            ),
          ),
        Expanded(child: _query.isEmpty ? const _Downloads() : _results()),
      ],
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
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
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

class _ResultRow extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(
      downloadsProvider.select((d) => d.saved.containsKey(track.videoId)),
    );
    final active = ref.watch(
      downloadsProvider.select((d) => d.active[track.videoId]),
    );
    final minutes = track.duration.inMinutes;
    final seconds = (track.duration.inSeconds % 60).toString().padLeft(2, '0');
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onDoubleTap: onPlay,
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                track.thumbnailUrl,
                width: 96,
                height: 54,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 96,
                  height: 54,
                  color: AppColors.whiteAlpha(0.08),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.whiteAlpha(0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$minutes:$seconds',
              style: TextStyle(color: AppColors.whiteAlpha(0.5), fontSize: 13),
            ),
            const SizedBox(width: 12),
            resolving
                ? const SizedBox(
                    width: 40,
                    child: Center(
                      child: SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : IconButton(
                    tooltip: 'Play',
                    onPressed: onPlay,
                    icon: const Icon(AppIcons.playFilled, size: 18),
                  ),
            SizedBox(width: 40, child: _downloadButton(saved, active)),
          ],
        ),
      ),
    );
  }

  Widget _downloadButton(bool saved, ActiveDownload? active) {
    if (saved) {
      return const Tooltip(
        message: 'Downloaded',
        child: Icon(AppIcons.downloaded, size: 18, color: AppColors.accentA),
      );
    }
    if (active != null && !active.isFailed) {
      return Center(
        child: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: active.phase == DownloadPhase.running
                ? active.progress
                : null,
          ),
        ),
      );
    }
    return IconButton(
      tooltip: active?.isFailed ?? false ? 'Retry download' : 'Download',
      onPressed: onDownload,
      icon: Icon(
        active?.isFailed ?? false ? AppIcons.retry : AppIcons.download,
        size: 18,
      ),
    );
  }
}

/// Downloaded tracks, as a table, plus a line per download in progress.
class _Downloads extends ConsumerWidget {
  const _Downloads();

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
