import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/collection_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/playback_provider.dart';
import '../theme.dart';
import '../widgets.dart';

/// Detail view for one album or artist: a cover hero with a Play button on top
/// of its track list. The collection to show is read from
/// [selectedCollectionProvider], set by whoever navigated here.
class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collection = ref.watch(selectedCollectionProvider);
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.musicBackground),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: Row(
                children: [
                  GlassIconButton(
                    icon: IconlyLight.arrowLeft2,
                    size: 44,
                    iconSize: 22,
                    onTap: () => ref.read(navigationProvider.notifier).back(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      collection?.isArtist == true ? 'Artist' : 'Album',
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: collection == null
                  ? _empty()
                  : _content(context, ref, collection),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref,
    MusicCollection collection,
  ) {
    final songs = collection.songs;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
      physics: const BouncingScrollPhysics(),
      // One extra leading item for the hero header.
      itemCount: songs.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _hero(ref, collection);
        final song = songs[i - 1];
        return TrackRow(
          song: song,
          onTap: () => ref
              .read(playbackProvider.notifier)
              .playSong(song, context: songs),
        );
      },
      separatorBuilder: (context, i) => SizedBox(height: i == 0 ? 24 : 20),
    );
  }

  Widget _hero(WidgetRef ref, MusicCollection collection) {
    final isArtist = collection.isArtist;
    final count = collection.songs.length;
    return Column(
      children: [
        const SizedBox(height: 8),
        SizedBox(
          width: 200,
          height: 200,
          child: SongArtwork(
            song: collection.cover,
            size: 200,
            radius: 26,
            circle: isArtist,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          collection.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.white,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isArtist
              ? collection.subtitle
              : '${collection.subtitle} · $count ${count == 1 ? 'song' : 'songs'}',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.whiteAlpha(0.55), fontSize: 14),
        ),
        const SizedBox(height: 20),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref
              .read(playbackProvider.notifier)
              .playSong(collection.cover, context: collection.songs),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 13),
            decoration: BoxDecoration(
              gradient: AppColors.accentGradient,
              borderRadius: BorderRadius.circular(26),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.play_arrow_rounded,
                  color: AppColors.white,
                  size: 22,
                ),
                SizedBox(width: 6),
                Text(
                  'Play',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _empty() {
    return Center(
      child: Text(
        'Nothing to show.',
        style: TextStyle(color: AppColors.whiteAlpha(0.5), fontSize: 15),
      ),
    );
  }
}
