import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/download_engine.dart';
import '../data/youtube_repository.dart';
import '../icons.dart';
import '../models.dart';
import '../providers/downloads_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/playback_provider.dart';
import '../providers/youtube_provider.dart';
import '../theme.dart';
import '../widgets.dart';

/// Searches YouTube on-device and hands a freshly resolved audio stream to the
/// existing just_audio player. Results can also be downloaded for offline
/// playback; a downloaded result plays from its local file.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String? _resolvingId;
  String? _playError;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _query = '';
        _playError = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      setState(() {
        _query = query;
        _playError = null;
      });
    });
  }

  void _submitSearch(String value) {
    _debounce?.cancel();
    setState(() {
      _query = value.trim();
      _playError = null;
    });
  }

  Future<void> _play(YouTubeTrack track) async {
    if (_resolvingId != null) return;
    setState(() {
      _resolvingId = track.videoId;
      _playError = null;
    });

    try {
      final saved = ref.read(downloadsProvider).saved[track.videoId];
      if (saved != null) {
        // Works offline: no stream to resolve.
        await ref
            .read(playbackProvider.notifier)
            .playSong(saved.song, throwOnLoadError: true);
        return;
      }
      final streamUrl = await ref
          .read(youtubeRepositoryProvider)
          .resolveAudio(track.videoId);
      if (!mounted) return;
      final song = Song(
        id: youtubeSongId(track.videoId),
        title: track.title,
        artist: track.artist,
        duration: track.duration,
        uri: streamUrl.toString(),
        artworkUrl: track.thumbnailUrl,
      );
      await ref
          .read(playbackProvider.notifier)
          .playSong(song, throwOnLoadError: true);
    } catch (error, stackTrace) {
      debugPrint('Discover: failed to play ${track.videoId}: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _playError =
            'Impossible de lire cette vidéo. Réessaie ou choisis un autre résultat.';
      });
    } finally {
      if (mounted) setState(() => _resolvingId = null);
    }
  }

  Future<void> _download(YouTubeTrack track) async {
    setState(() => _playError = null);
    try {
      await ref.read(downloadsProvider.notifier).download(track);
    } catch (error, stackTrace) {
      debugPrint('Discover: failed to download ${track.videoId}: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _playError =
            'Impossible de télécharger « ${track.title} ». Vérifie ta connexion et réessaie.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final search = _query.isEmpty
        ? null
        : ref.watch(youtubeSearchProvider(_query));

    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.musicBackground),
      child: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 6),
                  child: Row(
                    children: [
                      GlassIconButton(
                        icon: AppIcons.back,
                        size: 44,
                        iconSize: 22,
                        onTap: () =>
                            ref.read(navigationProvider.notifier).back(),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Discover',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 6, 24, 16),
                  child: _searchField(),
                ),
                if (_playError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                    child: Text(
                      _playError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFFF8A9B),
                        fontSize: 13,
                      ),
                    ),
                  ),
                Expanded(child: _results(search)),
              ],
            ),
          ),
          const Positioned(
            left: 22,
            right: 22,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: MiniPlayer(),
                ),
                NavBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.whiteAlpha(0.06),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: AppColors.whiteAlpha(0.08)),
      ),
      child: Row(
        children: [
          Icon(AppIcons.search, size: 20, color: AppColors.whiteAlpha(0.5)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const Key('youtube-search-field'),
              controller: _controller,
              onChanged: _onQueryChanged,
              onSubmitted: _submitSearch,
              cursorColor: AppColors.accentA,
              textInputAction: TextInputAction.search,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search YouTube…',
                hintStyle: TextStyle(
                  color: AppColors.whiteAlpha(0.4),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _controller.clear();
                _onQueryChanged('');
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  AppIcons.close,
                  size: 20,
                  color: AppColors.whiteAlpha(0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _results(AsyncValue<List<YouTubeTrack>>? search) {
    if (search == null) return _downloadsOrPrompt();
    return search.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.accentA),
      ),
      error: (_, _) => _searchError(),
      data: (tracks) {
        if (tracks.isEmpty) return _noResults();
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 170),
          physics: const BouncingScrollPhysics(),
          itemCount: tracks.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${tracks.length} ${tracks.length == 1 ? 'result' : 'results'}',
                  style: TextStyle(
                    color: AppColors.whiteAlpha(0.5),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              );
            }
            return _resultRow(tracks[index - 1]);
          },
          separatorBuilder: (_, index) =>
              SizedBox(height: index == 0 ? 14 : 20),
        );
      },
    );
  }

  /// With no query: in-flight and failed downloads, so they can be followed,
  /// retried or dismissed after leaving the search that started them.
  Widget _downloadsOrPrompt() {
    final active = ref.watch(downloadsProvider.select((d) => d.active));
    if (active.isEmpty) return _searchPrompt();
    final downloads = active.values.toList();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 170),
      physics: const BouncingScrollPhysics(),
      itemCount: downloads.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Downloads',
              style: TextStyle(
                color: AppColors.whiteAlpha(0.5),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          );
        }
        return _resultRow(downloads[index - 1].track, manage: true);
      },
      separatorBuilder: (_, index) => SizedBox(height: index == 0 ? 14 : 20),
    );
  }

  /// One search result, or with [manage] one entry of the downloads list,
  /// whose trailing action cancels or dismisses the download instead of
  /// playing it.
  Widget _resultRow(YouTubeTrack track, {bool manage = false}) {
    final download = ref.watch(
      downloadsProvider.select((d) => d.active[track.videoId]),
    );
    final resolving = _resolvingId == track.videoId;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            track.thumbnailUrl,
            width: 54,
            height: 54,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => AlbumArt(
              gradient:
                  AppArt.gradients[youtubeSongId(track.videoId).abs() %
                      AppArt.gradients.length],
              size: 54,
              radius: 14,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                switch (download?.phase) {
                  DownloadPhase.queued => 'Waiting to download…',
                  DownloadPhase.running =>
                    'Downloading · ${(download!.progress * 100).floor()}%',
                  DownloadPhase.waiting =>
                    'Interrupted · resumes when back online',
                  DownloadPhase.failed => 'Download failed',
                  _ => '${track.artist} · ${_durationLabel(track.duration)}',
                },
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
        const SizedBox(width: 12),
        _downloadButton(track),
        const SizedBox(width: 10),
        if (manage && download != null)
          _dismissButton(track, download)
        else
          _playButton(track, resolving),
      ],
    );
  }

  /// Idle → progress ring while downloading → check mark once saved, or a
  /// retry arrow after a failure. Removing a download lives on the song's
  /// detail page.
  Widget _downloadButton(YouTubeTrack track) {
    final saved = ref.watch(
      downloadsProvider.select((d) => d.saved.containsKey(track.videoId)),
    );
    final download = ref.watch(
      downloadsProvider.select((d) => d.active[track.videoId]),
    );
    final failed = download?.isFailed ?? false;
    final progress = download?.phase == DownloadPhase.running
        ? download!.progress
        : 0.0;
    final Widget child;
    if (saved) {
      child = const Icon(
        AppIcons.downloaded,
        size: 20,
        color: AppColors.accentA,
      );
    } else if (failed) {
      child = const Icon(AppIcons.retry, size: 20, color: Color(0xFFFF8A9B));
    } else if (download != null) {
      child = Padding(
        padding: const EdgeInsets.all(10),
        child: CircularProgressIndicator(
          // Indeterminate until the first bytes arrive.
          value: progress > 0 ? progress : null,
          strokeWidth: 2,
          color: AppColors.accentA,
          backgroundColor: AppColors.whiteAlpha(0.1),
        ),
      );
    } else {
      child = Icon(
        AppIcons.download,
        size: 20,
        color: AppColors.whiteAlpha(0.8),
      );
    }
    return GestureDetector(
      key: ValueKey('youtube-download-${track.videoId}'),
      behavior: HitTestBehavior.opaque,
      onTap: saved || (download != null && !failed)
          ? null
          : () => _download(track),
      child: SizedBox(width: 42, height: 42, child: Center(child: child)),
    );
  }

  /// Cancels an in-flight download, or clears a failed one from the list.
  Widget _dismissButton(YouTubeTrack track, ActiveDownload download) {
    return GestureDetector(
      key: ValueKey('youtube-dismiss-${track.videoId}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(downloadsProvider.notifier).cancel(track.videoId),
      child: SizedBox(
        width: 42,
        height: 42,
        child: Icon(AppIcons.close, size: 20, color: AppColors.whiteAlpha(0.8)),
      ),
    );
  }

  Widget _playButton(YouTubeTrack track, bool resolving) {
    return GestureDetector(
      key: ValueKey('youtube-play-${track.videoId}'),
      behavior: HitTestBehavior.opaque,
      onTap: resolving ? null : () => _play(track),
      child: Container(
        width: 42,
        height: 42,
        padding: resolving ? const EdgeInsets.all(11) : EdgeInsets.zero,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: resolving ? null : AppColors.accentGradient,
          color: resolving ? AppColors.whiteAlpha(0.06) : null,
          border: resolving
              ? Border.all(color: AppColors.whiteAlpha(0.08))
              : null,
        ),
        child: resolving
            ? const CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accentA,
              )
            : const Icon(AppIcons.playFilled, size: 24, color: AppColors.white),
      ),
    );
  }

  Widget _searchPrompt() => _message(
    icon: AppIcons.video,
    title: 'Search YouTube',
    detail:
        'Find a video and play its audio directly in MyZik, or download it '
        'to listen offline.',
  );

  Widget _searchError() => _message(
    icon: AppIcons.offline,
    title: 'Search failed',
    detail: 'Check your connection and try again.',
    action: TextButton(
      onPressed: () => ref.invalidate(youtubeSearchProvider(_query)),
      child: const Text('Retry'),
    ),
  );

  Widget _noResults() => _message(
    icon: AppIcons.search,
    title: 'No results',
    detail: 'Nothing matched "$_query".',
  );

  Widget _message({
    required IconData icon,
    required String title,
    required String detail,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 170),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 46, color: AppColors.whiteAlpha(0.3)),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.whiteAlpha(0.55), fontSize: 14),
          ),
          if (action != null) ...[const SizedBox(height: 10), action],
        ],
      ),
    );
  }

  String _durationLabel(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
