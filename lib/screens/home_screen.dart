import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons.dart';
import '../models.dart';
import '../providers/library_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/playback_provider.dart';
import '../theme.dart';
import '../widgets.dart';

/// The landing page: a greeting, a shuffled run through the library, then
/// shelves of its albums and artists and a few of its songs.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const _padding = 22.0;

  // Album / artist groupings, recomputed only when the library list changes
  // rather than on every rebuild.
  List<Song>? _groupedFrom;
  List<MusicCollection> _albums = const [];
  List<MusicCollection> _artists = const [];

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);
    final songs = library.songs;
    if (!identical(songs, _groupedFrom)) {
      _groupedFrom = songs;
      _albums = albumsFrom(songs);
      _artists = artistsFrom(songs);
    }
    final topSongs = songs.take(4).toList();
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.homeBackground),
      child: Stack(
        children: [
          // Ambient glows top-left / top-right.
          _glow(
            top: -60,
            left: -40,
            w: 280,
            h: 240,
            color: const Color(0x8C785AFF),
          ),
          _glow(
            top: -40,
            right: -40,
            w: 220,
            h: 200,
            color: const Color(0x734F8CFF),
          ),
          SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 170),
              physics: const BouncingScrollPhysics(),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _padding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _header(),
                      const SizedBox(height: 22),
                      const Text(
                        'Hi, Fehizoro',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _DiscoverCard(songs: songs),
                    ],
                  ),
                ),
                if (_albums.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  CollectionShelf(title: 'Albums', collections: _albums),
                ],
                if (_artists.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  CollectionShelf(title: 'Artists', collections: _artists),
                ],
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _padding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Flexible(child: SectionTitle('Songs')),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () => ref
                                .read(navigationProvider.notifier)
                                .goTo(AppScreen.myMusic),
                            child: const Text(
                              'See all',
                              style: TextStyle(
                                color: AppColors.playing,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (topSongs.isEmpty)
                        _emptyHint(library.status)
                      else
                        for (var i = 0; i < topSongs.length; i++) ...[
                          TrackRow(
                            song: topSongs[i],
                            onTap: () => ref
                                .read(playbackProvider.notifier)
                                .playSong(topSongs[i], context: topSongs),
                          ),
                          if (i != topSongs.length - 1)
                            const SizedBox(height: 16),
                        ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const BottomFade(color: AppColors.homeBackground),
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
    );
  }

  Widget _glow({
    double? top,
    double? left,
    double? right,
    required double w,
    required double h,
    required Color color,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const CircleAvatar(
            radius: 22,
            backgroundColor: Color(0xFF1A1730),
            backgroundImage: AssetImage('assets/images/avatar.png'),
          ),
          Row(
            children: [
              GlassIconButton(
                icon: AppIcons.sync,
                onTap: () =>
                    ref.read(navigationProvider.notifier).goTo(AppScreen.sync),
              ),
              GlassIconButton(
                icon: AppIcons.search,
                onTap: () => ref
                    .read(navigationProvider.notifier)
                    .goTo(AppScreen.search),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyHint(LibraryStatus status) {
    final text = switch (status) {
      LibraryStatus.loading => 'Loading your library…',
      LibraryStatus.permissionDenied =>
        'Grant storage access to see your music.',
      LibraryStatus.empty => 'No music found on this device.',
      LibraryStatus.error => 'Could not read your library.',
      LibraryStatus.ready => 'No tracks yet.',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: TextStyle(color: AppColors.whiteAlpha(0.5), fontSize: 14),
      ),
    );
  }
}

/// The home's lead: a shuffled run through the whole library, shown as a
/// fan of the records it will play.
class _DiscoverCard extends ConsumerWidget {
  const _DiscoverCard({required this.songs});

  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A few distinct covers for the fan: one track per album.
    final seen = <String?>{};
    final fan = [
      for (final s in songs)
        if (seen.add(s.album ?? s.title)) s,
    ].take(3).toList();
    final count = songs.length;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: songs.isEmpty ? null : () => playShuffled(ref, songs),
      child: Container(
        height: 172,
        padding: const EdgeInsets.fromLTRB(22, 22, 0, 22),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4F8CFF), Color(0xFF3B6FE0), Color(0xFF6F5CFF)],
            stops: [0, 0.55, 1],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4F8CFF).withValues(alpha: 0.3),
              blurRadius: 40,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Discover weekly',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    count == 0
                        ? 'Your library, shuffled.'
                        : 'All $count of your tracks, shuffled.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.whiteAlpha(0.85),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.white,
                    ),
                    child: const Icon(
                      AppIcons.shuffle,
                      size: 20,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
            // The records, fanned out and bleeding off the card's edge.
            SizedBox(
              width: 150,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = fan.length - 1; i >= 0; i--)
                    Positioned(
                      left: 10.0 + i * 34,
                      top: 18.0 - i * 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 18,
                              offset: const Offset(-6, 8),
                            ),
                          ],
                        ),
                        child: SongArtwork(
                          song: fan[i],
                          size: 110,
                          circle: true,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
