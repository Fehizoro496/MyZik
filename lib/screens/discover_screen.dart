import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/navigation_provider.dart';
import '../theme.dart';
import '../widgets.dart';

/// "Discover": search the web for tracks and download them (audio + lyrics).
///
/// UI only — the results below are placeholder data and the download buttons
/// just simulate progress. The real search / download service is wired in
/// later; this screen defines the interface it will drive.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

enum _DownloadStatus { idle, downloading, done }

/// A placeholder search result from "the internet".
class _OnlineTrack {
  const _OnlineTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    required this.gradient,
    this.hasLyrics = true,
  });

  final String id;
  final String title;
  final String artist;
  final String duration;
  final List<Color> gradient;
  final bool hasLyrics;
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _controller = TextEditingController();
  String _query = '';
  final Map<String, _DownloadStatus> _status = {};

  static final _catalog = <_OnlineTrack>[
    _OnlineTrack(
      id: 'o1',
      title: 'Neon Skyline',
      artist: 'Aurora Vale',
      duration: '3:42',
      gradient: AppArt.gradients[0],
    ),
    _OnlineTrack(
      id: 'o2',
      title: 'Paper Moon',
      artist: 'The Lantern Club',
      duration: '4:05',
      gradient: AppArt.gradients[1],
    ),
    _OnlineTrack(
      id: 'o3',
      title: 'Velvet Rain',
      artist: 'Mira Sol',
      duration: '2:58',
      gradient: AppArt.gradients[2],
      hasLyrics: false,
    ),
    _OnlineTrack(
      id: 'o4',
      title: 'Golden Hour',
      artist: 'KAI',
      duration: '3:20',
      gradient: AppArt.gradients[3],
    ),
    _OnlineTrack(
      id: 'o5',
      title: 'Midnight Tram',
      artist: 'Odette',
      duration: '3:51',
      gradient: AppArt.gradients[4],
    ),
    _OnlineTrack(
      id: 'o6',
      title: 'Sea of Static',
      artist: 'Halcyon',
      duration: '4:33',
      gradient: AppArt.gradients[5],
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_OnlineTrack> _results() {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _catalog;
    return _catalog
        .where(
          (t) =>
              t.title.toLowerCase().contains(q) ||
              t.artist.toLowerCase().contains(q),
        )
        .toList();
  }

  // Placeholder for the future download service: flip through the visual
  // states so the interface reads as a real download.
  void _download(String id) {
    if ((_status[id] ?? _DownloadStatus.idle) != _DownloadStatus.idle) return;
    setState(() => _status[id] = _DownloadStatus.downloading);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() => _status[id] = _DownloadStatus.done);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _query.trim().isNotEmpty;
    final results = _results();
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
                        icon: IconlyLight.arrowLeft2,
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
                Expanded(
                  child: results.isEmpty
                      ? _noResults()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 170),
                          physics: const BouncingScrollPhysics(),
                          itemCount: results.length + 1,
                          itemBuilder: (context, i) {
                            if (i == 0) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  hasQuery
                                      ? '${results.length} ${results.length == 1 ? 'result' : 'results'}'
                                      : 'Trending now',
                                  style: TextStyle(
                                    color: AppColors.whiteAlpha(0.5),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              );
                            }
                            return _resultRow(results[i - 1]);
                          },
                          separatorBuilder: (_, i) =>
                              SizedBox(height: i == 0 ? 14 : 20),
                        ),
                ),
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
          Icon(IconlyLight.search, size: 20, color: AppColors.whiteAlpha(0.5)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: (v) => setState(() => _query = v),
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
                hintText: 'Search songs, artists, lyrics…',
                hintStyle: TextStyle(
                  color: AppColors.whiteAlpha(0.4),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _controller.clear();
                setState(() => _query = '');
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: AppColors.whiteAlpha(0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _resultRow(_OnlineTrack track) {
    final status = _status[track.id] ?? _DownloadStatus.idle;
    return Row(
      children: [
        AlbumArt(gradient: track.gradient, size: 54, radius: 14),
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
              Row(
                children: [
                  Flexible(
                    child: Text(
                      '${track.artist} · ${track.duration}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.whiteAlpha(0.5),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (track.hasLyrics) ...[
                    const SizedBox(width: 8),
                    _lyricsChip(),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _downloadButton(status, () => _download(track.id)),
      ],
    );
  }

  Widget _lyricsChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.whiteAlpha(0.07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lyrics_outlined,
            size: 12,
            color: AppColors.whiteAlpha(0.6),
          ),
          const SizedBox(width: 4),
          Text(
            'Lyrics',
            style: TextStyle(
              color: AppColors.whiteAlpha(0.6),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _downloadButton(_DownloadStatus status, VoidCallback onTap) {
    switch (status) {
      case _DownloadStatus.downloading:
        return Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.whiteAlpha(0.06),
            border: Border.all(color: AppColors.whiteAlpha(0.08)),
          ),
          padding: const EdgeInsets.all(11),
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.accentA,
          ),
        );
      case _DownloadStatus.done:
        return Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.accentGradient,
          ),
          child: const Icon(
            Icons.download_done_rounded,
            size: 20,
            color: AppColors.white,
          ),
        );
      case _DownloadStatus.idle:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.whiteAlpha(0.06),
              border: Border.all(color: AppColors.whiteAlpha(0.1)),
            ),
            child: Icon(IconlyLight.download, size: 20, color: AppColors.white),
          ),
        );
    }
  }

  Widget _noResults() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 170),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(IconlyLight.search, size: 46, color: AppColors.whiteAlpha(0.3)),
          const SizedBox(height: 16),
          Text(
            'Nothing matched "${_query.trim()}".',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.whiteAlpha(0.55), fontSize: 14),
          ),
        ],
      ),
    );
  }
}
