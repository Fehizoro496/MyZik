import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/collection_provider.dart';
import '../providers/playback_provider.dart';
import '../theme.dart';
import '../widgets.dart';

/// Detail view for one album or artist, lit by its cover: the cover, its name
/// and Play / Shuffle over its tracks. An album's tracks are numbered (they
/// share its cover); an artist's show each cover. The collection to show is
/// read from [selectedCollectionProvider], set by whoever navigated here.
class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collection = ref.watch(selectedCollectionProvider);
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.musicBackground),
      child: Stack(
        children: [
          if (collection != null)
            CoverGlow(color: coverLight(ref, collection.cover)),
          Positioned.fill(
            child: FrostedHeaderLayout(
              header: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                child: PageHeader(
                  title: collection?.isArtist == true ? 'Artist' : 'Album',
                ),
              ),
              body: (context, top) => collection == null
                  ? Padding(
                      padding: EdgeInsets.only(top: top),
                      child: _empty(),
                    )
                  : _content(ref, collection, top),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(WidgetRef ref, MusicCollection collection, double top) {
    final songs = collection.songs;
    final album = !collection.isArtist;
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(24, top + 8, 24, 40),
      physics: const BouncingScrollPhysics(),
      // One extra leading item for the hero header.
      itemCount: songs.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _hero(ref, collection);
        final song = songs[i - 1];
        return TrackRow(
          song: song,
          leading: album ? _TrackNumber(i) : null,
          onTap: () => ref
              .read(playbackProvider.notifier)
              .playSong(song, context: songs),
        );
      },
      separatorBuilder: (context, i) =>
          SizedBox(height: i == 0 ? 30 : (album ? 22 : 20)),
    );
  }

  Widget _hero(WidgetRef ref, MusicCollection collection) {
    final isArtist = collection.isArtist;
    return PageHero(
      cover: SongArtwork(
        song: collection.cover,
        size: 220,
        radius: 28,
        circle: isArtist,
      ),
      circle: isArtist,
      title: collection.title,
      // An artist's subtitle is already its song count.
      subtitle: isArtist ? null : collection.subtitle,
      meta: songsSummary(collection.songs),
      actions: playActions(ref, collection.songs),
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

/// A track's position on its album, in place of the cover it shares with
/// every other row.
class _TrackNumber extends StatelessWidget {
  const _TrackNumber(this.number);

  final int number;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      child: Text(
        '$number',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.whiteAlpha(0.45),
          fontSize: 15,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
