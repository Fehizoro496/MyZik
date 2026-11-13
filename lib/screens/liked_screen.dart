import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons.dart';
import '../providers/library_provider.dart';
import '../providers/liked_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/playback_provider.dart';
import '../theme.dart';
import '../widgets.dart';

/// The "Liked" library, lit in the heart's pink: a hero like a playlist's,
/// with Play / Shuffle, over the list of liked tracks.
class LikedScreen extends ConsumerStatefulWidget {
  const LikedScreen({super.key});

  @override
  ConsumerState<LikedScreen> createState() => _LikedScreenState();
}

class _LikedScreenState extends ConsumerState<LikedScreen> {
  @override
  Widget build(BuildContext context) {
    final likedKeys = ref.watch(likedProvider);
    final songs = ref
        .watch(libraryProvider.select((s) => s.songs))
        .where((s) => likedKeys.contains(s.songKey))
        .toList();
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.musicBackground),
      // Header, mini-player and nav bar all blur the list scrolling under
      // them: grouping lets them share a single backdrop read per frame.
      child: BackdropGroup(
        child: Stack(
          children: [
            const CoverGlow(color: AppColors.liked),
            Positioned.fill(
              child: FrostedHeaderLayout(
                header: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                  child: PageHeader(
                    title: 'Liked',
                    trailing: GlassIconButton(
                      icon: AppIcons.search,
                      size: 44,
                      onTap: () => ref
                          .read(navigationProvider.notifier)
                          .goTo(AppScreen.search),
                    ),
                  ),
                ),
                body: (context, top) => ListView(
                  padding: EdgeInsets.fromLTRB(24, top + 8, 24, 170),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    PageHero(
                      cover: const _HeartCover(),
                      coverSize: 180,
                      title: 'Liked Songs',
                      meta: songsSummary(songs),
                      actions: playActions(ref, songs),
                    ),
                    const SizedBox(height: 30),
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
            ),
            const BottomFade(),
            const Positioned(
              left: 22,
              right: 22,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: MiniPlayer(),
                  ),
                  NavBar(),
                ],
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
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          Icon(AppIcons.heart, size: 48, color: AppColors.whiteAlpha(0.3)),
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

/// Liked Songs' cover: the heart, on the pink-to-violet of the likes.
class _HeartCover extends StatelessWidget {
  const _HeartCover();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.liked, Color(0xFF8A4FFF)],
        ),
      ),
      child: const Icon(AppIcons.heartFilled, size: 64, color: AppColors.white),
    );
  }
}
