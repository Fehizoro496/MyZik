import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/collection_provider.dart';
import '../providers/library_provider.dart';
import '../providers/my_music_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/playback_provider.dart';
import '../providers/playlists_provider.dart';
import '../theme.dart';
import '../widgets.dart';

/// The user's on-device library, viewed through four tabs: a flat song list,
/// albums and artists grouped from that list, and a (still empty) playlists
/// section. Tapping an album or artist opens its detail screen.
class MyMusicScreen extends ConsumerStatefulWidget {
  const MyMusicScreen({super.key});

  @override
  ConsumerState<MyMusicScreen> createState() => _MyMusicScreenState();
}

class _MyMusicScreenState extends ConsumerState<MyMusicScreen> {
  static const _tabs = ['Songs', 'Albums', 'Artists', 'Playlists'];

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);
    // Kept in a provider so the selected tab survives leaving and returning to
    // this screen (e.g. after playing a track from the Artists tab).
    final tab = ref.watch(myMusicTabProvider);
    final ready =
        library.status == LibraryStatus.ready && library.songs.isNotEmpty;
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
                        'My Music',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      GlassIconButton(
                        icon: IconlyLight.search,
                        onTap: () => ref
                            .read(navigationProvider.notifier)
                            .goTo(AppScreen.search),
                      ),
                    ],
                  ),
                ),
                if (ready)
                  Expanded(
                    child: Stack(
                      children: [
                        // The list fills the area and scrolls *behind* the
                        // frosted tab capsule (its top padding clears the bar).
                        Positioned.fill(child: _tabBody(library.songs, tab)),
                        Positioned(
                          top: 4,
                          left: 24,
                          right: 24,
                          child: SegmentedTabs(
                            tabs: _tabs,
                            selected: tab,
                            onSelected: (i) =>
                                ref.read(myMusicTabProvider.notifier).state = i,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Expanded(child: _stateBody(library)),
              ],
            ),
          ),
          // Mini-player floats above the shared nav bar.
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

  Widget _tabBody(List<Song> songs, int tab) {
    return switch (tab) {
      1 => _AlbumsGrid(albums: albumsFrom(songs), onOpen: _openCollection),
      2 => _ArtistsList(artists: artistsFrom(songs), onOpen: _openCollection),
      3 => const _PlaylistsTab(),
      _ => _songsList(songs),
    };
  }

  void _openCollection(MusicCollection collection) {
    ref.read(selectedCollectionProvider.notifier).show(collection);
    ref.read(navigationProvider.notifier).goTo(AppScreen.collection);
  }

  Widget _songsList(List<Song> songs) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 70, 24, 170),
      physics: const BouncingScrollPhysics(),
      itemCount: songs.length,
      itemBuilder: (context, i) => TrackRow(
        song: songs[i],
        onTap: () => ref.read(playbackProvider.notifier).playSong(songs[i]),
      ),
      separatorBuilder: (_, _) => const SizedBox(height: 20),
    );
  }

  Widget _stateBody(LibraryState library) {
    if (library.status == LibraryStatus.loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accentA),
      );
    }
    return _emptyState(library.status);
  }

  Widget _emptyState(LibraryStatus status) {
    final denied = status == LibraryStatus.permissionDenied;
    final message = switch (status) {
      LibraryStatus.permissionDenied =>
        'MyZik needs access to your audio files to show your music.',
      LibraryStatus.error => 'Something went wrong reading your library.',
      _ => 'No music found on this device.',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 170),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(IconlyLight.folder, size: 48, color: AppColors.whiteAlpha(0.4)),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.whiteAlpha(0.6), fontSize: 14),
          ),
          if (denied) ...[
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => ref.read(libraryProvider.notifier).load(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradient,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Text(
                  'Grant access',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Albums as a two-column grid of cover + title + artist. Tapping a card opens
/// the album's detail screen.
class _AlbumsGrid extends StatelessWidget {
  const _AlbumsGrid({required this.albums, required this.onOpen});

  final List<MusicCollection> albums;
  final ValueChanged<MusicCollection> onOpen;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(24, 70, 24, 170),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 22,
        crossAxisSpacing: 18,
        childAspectRatio: 0.72,
      ),
      itemCount: albums.length,
      itemBuilder: (context, i) {
        final album = albums[i];
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onOpen(album),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) => SongArtwork(
                  song: album.cover,
                  size: constraints.maxWidth,
                  radius: 18,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                album.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.whiteAlpha(0.5),
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Artists as a list of circular avatar + name + song count. Tapping a row
/// opens the artist's detail screen.
class _ArtistsList extends StatelessWidget {
  const _ArtistsList({required this.artists, required this.onOpen});

  final List<MusicCollection> artists;
  final ValueChanged<MusicCollection> onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 70, 24, 170),
      physics: const BouncingScrollPhysics(),
      itemCount: artists.length,
      itemBuilder: (context, i) {
        final artist = artists[i];
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onOpen(artist),
          child: Row(
            children: [
              SongArtwork(song: artist.cover, size: 54, circle: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      artist.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      artist.subtitle,
                      style: TextStyle(
                        color: AppColors.whiteAlpha(0.5),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                IconlyLight.arrowRight2,
                size: 20,
                color: AppColors.whiteAlpha(0.35),
              ),
            ],
          ),
        );
      },
      separatorBuilder: (_, _) => const SizedBox(height: 20),
    );
  }
}

/// The Playlists tab: a "New playlist" button on top of the user's playlists.
/// Tapping a playlist opens its detail screen.
class _PlaylistsTab extends ConsumerWidget {
  const _PlaylistsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 70, 24, 170),
      physics: const BouncingScrollPhysics(),
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _create(context, ref),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.whiteAlpha(0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.whiteAlpha(0.1)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.accentGradient,
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: AppColors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'New playlist',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Group tracks your way',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.whiteAlpha(0.5),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Column(
              children: [
                Icon(
                  Icons.queue_music_rounded,
                  size: 46,
                  color: AppColors.whiteAlpha(0.3),
                ),
                const SizedBox(height: 14),
                Text(
                  'No playlists yet.\nCreate one, or long-press any track to add it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.whiteAlpha(0.5),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < playlists.length; i++) ...[
            _PlaylistRow(
              playlist: playlists[i],
              onTap: () => _open(ref, playlists[i].id),
            ),
            if (i != playlists.length - 1) const SizedBox(height: 18),
          ],
      ],
    );
  }

  void _open(WidgetRef ref, String id) {
    ref.read(selectedPlaylistIdProvider.notifier).state = id;
    ref.read(navigationProvider.notifier).goTo(AppScreen.playlist);
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final playlistsNotifier = ref.read(playlistsProvider.notifier);
    final selectedNotifier = ref.read(selectedPlaylistIdProvider.notifier);
    final nav = ref.read(navigationProvider.notifier);
    final name = await showNameSheet(
      context,
      title: 'New playlist',
      actionLabel: 'Create',
    );
    if (name == null) return;
    final playlist = playlistsNotifier.create(name);
    selectedNotifier.state = playlist.id;
    nav.goTo(AppScreen.playlist);
  }
}

/// One playlist in the list: cover + name + track count.
class _PlaylistRow extends ConsumerWidget {
  const _PlaylistRow({required this.playlist, required this.onTap});

  final Playlist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(playlistSongsProvider(playlist.id));
    final count = playlist.songIds.length;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        children: [
          PlaylistCover(songs: songs, size: 56, radius: 16),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$count ${count == 1 ? 'song' : 'songs'}',
                  style: TextStyle(
                    color: AppColors.whiteAlpha(0.5),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            IconlyLight.arrowRight2,
            size: 20,
            color: AppColors.whiteAlpha(0.35),
          ),
        ],
      ),
    );
  }
}
