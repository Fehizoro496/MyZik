import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/library_provider.dart';
import '../providers/liked_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/playback_provider.dart';
import '../theme.dart';
import '../widgets.dart';

/// The "Liked" library: liked-songs hero card + the list of liked tracks.
class LikedScreen extends ConsumerStatefulWidget {
  const LikedScreen({super.key});

  @override
  ConsumerState<LikedScreen> createState() => _LikedScreenState();
}

class _LikedScreenState extends ConsumerState<LikedScreen> {
  @override
  Widget build(BuildContext context) {
    final likedIds = ref.watch(likedProvider);
    final songs = ref
        .watch(libraryProvider.select((s) => s.songs))
        .where((s) => likedIds.contains(s.id))
        .toList();
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.musicBackground),
      child: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GlassIconButton(
                        icon: IconlyLight.arrowLeft2,
                        size: 44,
                        iconSize: 22,
                        onTap: () =>
                            ref.read(navigationProvider.notifier).back(),
                      ),
                      const Text(
                        'Liked',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      GlassIconButton(
                        icon: IconlyLight.search,
                        size: 44,
                        onTap: () => ref
                            .read(navigationProvider.notifier)
                            .goTo(AppScreen.search),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 170),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _likedCard(songs),
                      const SizedBox(height: 26),
                      if (songs.isEmpty)
                        _emptyState()
                      else
                        for (var i = 0; i < songs.length; i++) ...[
                          TrackRow(
                            song: songs[i],
                            onTap: () => ref
                                .read(playbackProvider.notifier)
                                .playSong(songs[i], context: songs),
                          ),
                          if (i != songs.length - 1) const SizedBox(height: 20),
                        ],
                    ],
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

  Widget _likedCard(List<Song> songs) {
    return GestureDetector(
      onTap: () => songs.isEmpty
          ? null
          : ref
                .read(playbackProvider.notifier)
                .playSong(songs.first, context: songs),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF6F91), Color(0xFF8A4FFF)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8A4FFF).withValues(alpha: 0.3),
              blurRadius: 36,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.whiteAlpha(0.18),
              ),
              child: const Icon(
                IconlyBold.heart,
                size: 26,
                color: AppColors.white,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Liked Songs',
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${songs.length} songs · Auto playlist',
                    style: TextStyle(
                      color: AppColors.whiteAlpha(0.85),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF0B1220),
              ),
              child: const Icon(
                IconlyBold.play,
                size: 20,
                color: AppColors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown when nothing has been liked yet — the list would otherwise be an
  /// empty gap under the hero card.
  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Icon(IconlyLight.heart, size: 48, color: AppColors.whiteAlpha(0.3)),
          const SizedBox(height: 16),
          Text(
            'No liked songs yet.\nTap the heart on any track to add it here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.whiteAlpha(0.5),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
