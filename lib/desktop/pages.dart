import 'dart:math';

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
import 'desktop_style.dart';
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
  const PlayAllButton({super.key, required this.songs, this.size = 56});

  final List<Song> songs;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AccentPlayButton(
      size: size,
      onPressed: songs.isEmpty
          ? null
          : () => ref
                .read(playbackProvider.notifier)
                .playSong(songs.first, context: songs),
    );
  }
}

/// Turns shuffle on and plays a random song of [songs].
class ShuffleAllButton extends ConsumerWidget {
  const ShuffleAllButton({super.key, required this.songs});

  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Shuffle',
      iconSize: 20,
      onPressed: songs.isEmpty
          ? null
          : () {
              final notifier = ref.read(playbackProvider.notifier);
              if (!ref.read(playbackProvider).shuffle) notifier.toggleShuffle();
              notifier.playSong(
                songs[Random().nextInt(songs.length)],
                context: songs,
              );
            },
      icon: const Icon(AppIcons.shuffle),
    );
  }
}

/// "12 songs · 43 min".
String songsSummary(List<Song> songs) {
  final total = songs.fold(Duration.zero, (sum, s) => sum + s.duration);
  final count = '${songs.length} song${songs.length == 1 ? '' : 's'}';
  return total.inMinutes == 0 ? count : '$count · ${total.inMinutes} min';
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
    final shortcuts = [
      _ShortcutTile(
        label: 'Liked songs',
        icon: AppIcons.heartFilled,
        colors: const [AppColors.liked, AppColors.accentB],
        onTap: () => navigator.openSection(DesktopSection.liked),
      ),
      for (final playlist in playlists.take(4))
        _ShortcutTile(
          label: playlist.name,
          cover: PlaylistCover(
            songs: ref.watch(playlistSongsProvider(playlist.id)),
            size: 64,
            radius: 0,
            probeLimit: 4,
          ),
          onTap: () => navigator.open(
            DesktopRoute(DesktopSection.playlists, playlistId: playlist.id),
          ),
        ),
      _ShortcutTile(
        label: 'Discover',
        icon: AppIcons.search,
        colors: const [AppColors.accentA, AppColors.accentB],
        onTap: () => navigator.openSection(DesktopSection.discover),
      ),
    ];
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
          const _ContinueListening(),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                const gap = 12.0;
                final columns = max(
                  1,
                  ((constraints.maxWidth + gap) / (220 + gap)).floor(),
                );
                final width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final tile in shortcuts)
                      SizedBox(width: width, child: tile),
                  ],
                );
              },
            ),
          ),
          if (albums.isNotEmpty) ...[
            _SectionTitle(
              'Albums',
              onShowAll: () => navigator.openSection(DesktopSection.albums),
            ),
            SizedBox(
              height: 244,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                scrollDirection: Axis.horizontal,
                itemCount: albums.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) =>
                    SizedBox(width: 184, child: CollectionCard(albums[i])),
              ),
            ),
          ],
          if (songs.isNotEmpty) ...[
            _SectionTitle(
              'Songs',
              onShowAll: () => navigator.openSection(DesktopSection.songs),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
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

/// The playing (or last played) track in a large card: resume it, see how
/// far along it is, or open it full screen.
class _ContinueListening extends ConsumerWidget {
  const _ContinueListening();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackProvider);
    final track = playback.current;
    if (track == null) return const SizedBox.shrink();
    final notifier = ref.read(playbackProvider.notifier);
    final details = [track.artist, ?track.album].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: DesktopColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.whiteAlpha(0.06)),
        ),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accentA.withValues(alpha: 0.35),
                    blurRadius: 48,
                    offset: const Offset(0, 24),
                    spreadRadius: -16,
                  ),
                ],
              ),
              child: SongArtwork(song: track, size: 168, radius: 16),
            ),
            const SizedBox(width: 28),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playback.playing ? 'NOW PLAYING' : 'CONTINUE LISTENING',
                    style: DesktopText.overline.copyWith(
                      color: DesktopColors.accentText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    details,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.whiteAlpha(0.7),
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      DesktopPill(
                        primary: true,
                        icon: playback.playing
                            ? AppIcons.pause
                            : AppIcons.playFilled,
                        label: playback.playing ? 'Pause' : 'Resume',
                        onPressed: notifier.togglePlay,
                      ),
                      const SizedBox(width: 8),
                      DesktopPill(
                        label: 'Full screen',
                        onPressed: () =>
                            ref.read(desktopFullscreenProvider.notifier).state =
                                true,
                      ),
                      const SizedBox(width: 20),
                      Flexible(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: playback.progress,
                                  minHeight: 4,
                                  color: AppColors.accentA,
                                  backgroundColor: AppColors.whiteAlpha(0.12),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${playback.remaining} left',
                                style: TextStyle(
                                  color: AppColors.whiteAlpha(0.6),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.onShowAll});

  final String title;
  final VoidCallback? onShowAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 32, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          if (onShowAll != null)
            TextButton(
              onPressed: onShowAll,
              style: TextButton.styleFrom(
                foregroundColor: DesktopColors.accentText,
              ),
              child: const Text('Show all'),
            ),
        ],
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({
    required this.label,
    required this.onTap,
    this.icon,
    this.colors,
    this.cover,
  });

  final String label;
  final VoidCallback onTap;

  /// Either a gradient square with [icon], or a [cover].
  final IconData? icon;
  final List<Color>? colors;
  final Widget? cover;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.whiteAlpha(0.04),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.whiteAlpha(0.04),
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              SizedBox.square(
                dimension: 64,
                child:
                    cover ??
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: colors!,
                        ),
                      ),
                      child: Icon(icon, color: AppColors.white, size: 22),
                    ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
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
          subtitle: songsSummary(songs),
          actions: [PlayAllButton(songs: songs, size: 48)],
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
          size: 208,
          radius: 18,
          circle: collection.isArtist,
        ),
        kind: collection.isArtist ? 'ARTIST' : 'ALBUM',
        title: collection.title,
        subtitle: collection.isArtist
            ? songsSummary(collection.songs)
            : '${collection.subtitle} · ${songsSummary(collection.songs)}',
        songs: collection.songs,
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
    required this.songs,
    this.actions = const [],
  });

  final Widget cover;
  final String kind;
  final String title;
  final String subtitle;

  /// What the play and shuffle buttons play.
  final List<Song> songs;

  /// Extra buttons after play and shuffle (rename, delete…).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accentA.withValues(alpha: 0.4),
                      blurRadius: 60,
                      offset: const Offset(0, 30),
                      spreadRadius: -20,
                    ),
                  ],
                ),
                child: cover,
              ),
              const SizedBox(width: 28),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(kind, style: DesktopText.overline),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.6,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppColors.whiteAlpha(0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              PlayAllButton(songs: songs),
              const SizedBox(width: 12),
              ShuffleAllButton(songs: songs),
              for (final action in actions) ...[
                const SizedBox(width: 8),
                action,
              ],
            ],
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
        if (liked.contains(s.songKey)) s,
    ];
    return _LibraryGate(
      child: TrackTable(
        songs: songs,
        emptyMessage: 'Songs you like appear here.',
        onRemove: (song) => ref.read(likedProvider.notifier).toggle(song),
        removeLabel: 'Remove from liked',
        header: _Hero(
          cover: Container(
            width: 208,
            height: 208,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.liked, AppColors.accentB],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              AppIcons.heartFilled,
              size: 72,
              color: AppColors.white,
            ),
          ),
          kind: 'PLAYLIST',
          title: 'Liked songs',
          subtitle: songsSummary(songs),
          songs: songs,
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
                '${playlist.songKeys.length} songs',
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
      onRemove: (song) => notifier.removeSong(playlistId, song),
      removeLabel: 'Remove from playlist',
      header: _Hero(
        cover: PlaylistCover(songs: songs, size: 208, radius: 18),
        kind: 'PLAYLIST',
        title: playlist.name,
        subtitle: songsSummary(songs),
        songs: songs,
        actions: [
          DesktopPill(
            onPressed: () async {
              final name = await showNameDialog(
                context,
                title: 'Rename playlist',
                actionLabel: 'Rename',
                initialValue: playlist.name,
              );
              if (name != null) notifier.rename(playlistId, name);
            },
            icon: AppIcons.edit,
            label: 'Rename',
          ),
          DesktopPill(
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
            icon: AppIcons.delete,
            label: 'Delete',
          ),
        ],
      ),
    );
  }
}
