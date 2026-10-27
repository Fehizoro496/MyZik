import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons.dart';
import '../models.dart';
import '../providers/library_provider.dart';
import '../providers/liked_provider.dart';
import '../providers/playback_provider.dart';
import '../providers/playlists_provider.dart';
import '../theme.dart';
import '../widgets.dart';
import 'desktop_navigation.dart';
import 'dialogs.dart';
import 'track_table.dart';

/// Title block at the top of a page, with optional trailing actions.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: AppColors.whiteAlpha(0.5),
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Plays [songs] from the first one, with the list as the queue.
class PlayAllButton extends ConsumerWidget {
  const PlayAllButton({super.key, required this.songs});

  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilledButton.icon(
      onPressed: songs.isEmpty
          ? null
          : () => ref
                .read(playbackProvider.notifier)
                .playSong(songs.first, context: songs),
      icon: const Icon(AppIcons.playFilled, size: 16),
      label: const Text('Play'),
    );
  }
}

/// Shows [child] once the library is loaded, a status message otherwise.
class _LibraryGate extends ConsumerWidget {
  const _LibraryGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(libraryProvider.select((s) => s.status));
    final message = switch (status) {
      LibraryStatus.loading => 'Loading your library…',
      LibraryStatus.permissionDenied => 'Music access was denied.',
      LibraryStatus.error => 'Your library could not be read.',
      LibraryStatus.ready || LibraryStatus.empty => null,
    };
    if (message == null) return child;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: TextStyle(color: AppColors.whiteAlpha(0.55))),
          if (status != LibraryStatus.loading) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => ref.read(libraryProvider.notifier).load(),
              child: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(libraryProvider.select((s) => s.songs));
    final albums = albumsFrom(songs);
    final playlists = ref.watch(playlistsProvider);
    final liked = ref.watch(likedProvider);
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
        ? 'Good afternoon'
        : 'Good evening';
    final navigator = ref.read(desktopNavigatorProvider.notifier);
    return _LibraryGate(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          PageHeader(
            title: greeting,
            subtitle:
                '${songs.length} songs · ${albums.length} albums · '
                '${liked.length} liked',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ShortcutTile(
                  label: 'Liked songs',
                  icon: AppIcons.heartFilled,
                  colors: const [AppColors.liked, AppColors.accentB],
                  onTap: () => navigator.openSection(DesktopSection.liked),
                ),
                for (final playlist in playlists.take(5))
                  _ShortcutTile(
                    label: playlist.name,
                    icon: AppIcons.queue,
                    colors:
                        AppArt.gradients[playlist.name.hashCode.abs() %
                            AppArt.gradients.length],
                    onTap: () => navigator.open(
                      DesktopRoute(
                        DesktopSection.playlists,
                        playlistId: playlist.id,
                      ),
                    ),
                  ),
                _ShortcutTile(
                  label: 'Discover',
                  icon: AppIcons.search,
                  colors: const [AppColors.accentA, AppColors.accentB],
                  onTap: () => navigator.openSection(DesktopSection.discover),
                ),
              ],
            ),
          ),
          if (albums.isNotEmpty) ...[
            const _SectionTitle('Albums'),
            SizedBox(
              height: 236,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                scrollDirection: Axis.horizontal,
                itemCount: albums.length,
                separatorBuilder: (_, _) => const SizedBox(width: 18),
                itemBuilder: (context, i) =>
                    SizedBox(width: 176, child: CollectionCard(albums[i])),
              ),
            ),
          ],
          if (songs.isNotEmpty) ...[
            const _SectionTitle('Songs'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  for (final song in songs.take(12))
                    SizedBox(
                      width: 320,
                      child: _CompactSongTile(song: song, queue: songs),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 14),
      child: Text(
        title,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({
    required this.label,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.whiteAlpha(0.06),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 260,
          height: 64,
          child: Row(
            children: [
              Container(
                width: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors,
                  ),
                ),
                child: Icon(icon, color: AppColors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactSongTile extends ConsumerWidget {
  const _CompactSongTile({required this.song, required this.queue});

  final Song song;
  final List<Song> queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            ref.read(playbackProvider.notifier).playSong(song, context: queue),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              SongArtwork(song: song, size: 44, radius: 6),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      song.artist,
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Album or artist card: cover (circle for artists), title and subtitle.
class CollectionCard extends ConsumerStatefulWidget {
  const CollectionCard(this.collection, {super.key});

  final MusicCollection collection;

  @override
  ConsumerState<CollectionCard> createState() => _CollectionCardState();
}

class _CollectionCardState extends ConsumerState<CollectionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final collection = widget.collection;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => ref
            .read(desktopNavigatorProvider.notifier)
            .open(
              DesktopRoute(
                collection.isArtist
                    ? DesktopSection.artists
                    : DesktopSection.albums,
                collection: collection,
              ),
            ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.whiteAlpha(_hovered ? 0.08 : 0.03),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: collection.isArtist
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
                    SongArtwork(
                      song: collection.cover,
                      size: constraints.maxWidth,
                      radius: 8,
                      circle: collection.isArtist,
                    ),
                    if (_hovered)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: FloatingActionButton.small(
                          heroTag: null,
                          tooltip: 'Play',
                          backgroundColor: AppColors.accentA,
                          onPressed: () => ref
                              .read(playbackProvider.notifier)
                              .playSong(
                                collection.songs.first,
                                context: collection.songs,
                              ),
                          child: const Icon(
                            AppIcons.playFilled,
                            color: AppColors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                collection.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                collection.subtitle,
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
      ),
    );
  }
}

/// The whole library, or the songs matching [query] (title, artist, album).
class SongsPage extends ConsumerWidget {
  const SongsPage({super.key, this.query});

  final String? query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider.select((s) => s.songs));
    final q = query?.toLowerCase();
    final songs = q == null
        ? library
        : [
            for (final s in library)
              if (s.title.toLowerCase().contains(q) ||
                  s.artist.toLowerCase().contains(q) ||
                  (s.album?.toLowerCase().contains(q) ?? false))
                s,
          ];
    return _LibraryGate(
      child: TrackTable(
        key: ValueKey(query),
        songs: songs,
        emptyMessage: q == null
            ? 'Your library is empty.'
            : 'Nothing in your library matches “$query”.',
        header: PageHeader(
          title: q == null ? 'Songs' : 'Results for “$query”',
          subtitle: '${songs.length} songs',
          actions: [PlayAllButton(songs: songs)],
        ),
      ),
    );
  }
}

/// Grid of albums or artists.
class CollectionsPage extends ConsumerWidget {
  const CollectionsPage({super.key, required this.artists});

  final bool artists;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(libraryProvider.select((s) => s.songs));
    final collections = artists ? artistsFrom(songs) : albumsFrom(songs);
    return _LibraryGate(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: PageHeader(
              title: artists ? 'Artists' : 'Albums',
              subtitle:
                  '${collections.length} ${artists ? 'artists' : 'albums'}',
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.76,
              ),
              itemCount: collections.length,
              itemBuilder: (context, i) => CollectionCard(collections[i]),
            ),
          ),
        ],
      ),
    );
  }
}

/// One album or artist: a cover hero above its track table.
class CollectionPage extends StatelessWidget {
  const CollectionPage({super.key, required this.collection});

  final MusicCollection collection;

  @override
  Widget build(BuildContext context) {
    return TrackTable(
      songs: collection.songs,
      header: _Hero(
        cover: SongArtwork(
          song: collection.cover,
          size: 180,
          radius: 10,
          circle: collection.isArtist,
        ),
        kind: collection.isArtist ? 'ARTIST' : 'ALBUM',
        title: collection.title,
        subtitle: collection.isArtist
            ? collection.subtitle
            : '${collection.subtitle} · ${collection.songs.length} songs',
        actions: [PlayAllButton(songs: collection.songs)],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.cover,
    required this.kind,
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });

  final Widget cover;
  final String kind;
  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          cover,
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kind,
                  style: TextStyle(
                    color: AppColors.whiteAlpha(0.6),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: TextStyle(color: AppColors.whiteAlpha(0.6)),
                ),
                const SizedBox(height: 16),
                Wrap(spacing: 10, children: actions),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LikedPage extends ConsumerWidget {
  const LikedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(likedProvider);
    final songs = [
      for (final s in ref.watch(libraryProvider.select((s) => s.songs)))
        if (liked.contains(s.id)) s,
    ];
    return _LibraryGate(
      child: TrackTable(
        songs: songs,
        emptyMessage: 'Songs you like appear here.',
        onRemove: (song) => ref.read(likedProvider.notifier).toggle(song.id),
        removeLabel: 'Remove from liked',
        header: _Hero(
          cover: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.liked, AppColors.accentB],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              AppIcons.heartFilled,
              size: 64,
              color: AppColors.white,
            ),
          ),
          kind: 'PLAYLIST',
          title: 'Liked songs',
          subtitle: '${songs.length} songs',
          actions: [PlayAllButton(songs: songs)],
        ),
      ),
    );
  }
}

class PlaylistsPage extends ConsumerWidget {
  const PlaylistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            title: 'Playlists',
            subtitle: '${playlists.length} playlists',
            actions: [
              FilledButton.icon(
                onPressed: () => createPlaylist(context, ref),
                icon: const Icon(AppIcons.add, size: 16),
                label: const Text('New playlist'),
              ),
            ],
          ),
        ),
        if (playlists.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Center(
                child: Text(
                  'Create a playlist to group your songs.',
                  style: TextStyle(color: AppColors.whiteAlpha(0.5)),
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.76,
            ),
            itemCount: playlists.length,
            itemBuilder: (context, i) => _PlaylistCard(playlists[i]),
          ),
        ),
      ],
    );
  }
}

/// Asks for a name, creates the playlist and opens it.
Future<void> createPlaylist(BuildContext context, WidgetRef ref) async {
  final name = await showNameDialog(
    context,
    title: 'New playlist',
    actionLabel: 'Create',
  );
  if (name == null) return;
  final playlist = ref.read(playlistsProvider.notifier).create(name);
  ref
      .read(desktopNavigatorProvider.notifier)
      .open(DesktopRoute(DesktopSection.playlists, playlistId: playlist.id));
}

class _PlaylistCard extends ConsumerWidget {
  const _PlaylistCard(this.playlist);

  final Playlist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.whiteAlpha(0.03),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => ref
            .read(desktopNavigatorProvider.notifier)
            .open(
              DesktopRoute(DesktopSection.playlists, playlistId: playlist.id),
            ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) => PlaylistCover(
                  songs: ref.watch(playlistSongsProvider(playlist.id)),
                  size: constraints.maxWidth,
                  radius: 8,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                '${playlist.songIds.length} songs',
                style: TextStyle(
                  color: AppColors.whiteAlpha(0.5),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlaylistPage extends ConsumerWidget {
  const PlaylistPage({super.key, required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref.watch(playlistByIdProvider(playlistId));
    if (playlist == null) {
      return Center(
        child: Text(
          'This playlist no longer exists.',
          style: TextStyle(color: AppColors.whiteAlpha(0.5)),
        ),
      );
    }
    final songs = ref.watch(playlistSongsProvider(playlistId));
    final notifier = ref.read(playlistsProvider.notifier);
    return TrackTable(
      songs: songs,
      emptyMessage:
          'This playlist is empty. Right-click a song to add it here.',
      onRemove: (song) => notifier.removeSong(playlistId, song.id),
      removeLabel: 'Remove from playlist',
      header: _Hero(
        cover: PlaylistCover(songs: songs, size: 180, radius: 10),
        kind: 'PLAYLIST',
        title: playlist.name,
        subtitle: '${songs.length} songs',
        actions: [
          PlayAllButton(songs: songs),
          OutlinedButton.icon(
            onPressed: () async {
              final name = await showNameDialog(
                context,
                title: 'Rename playlist',
                actionLabel: 'Rename',
                initialValue: playlist.name,
              );
              if (name != null) notifier.rename(playlistId, name);
            },
            icon: const Icon(AppIcons.edit, size: 16),
            label: const Text('Rename'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: const Color(0xFF16161E),
                  title: const Text('Delete playlist?'),
                  content: Text('“${playlist.name}” will be deleted.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              notifier.delete(playlistId);
              ref.read(desktopNavigatorProvider.notifier).back();
            },
            icon: const Icon(AppIcons.delete, size: 16),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
