import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons.dart';
import '../models.dart';
import '../providers/library_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/playback_provider.dart';
import '../providers/playlists_provider.dart';
import '../providers/song_detail_provider.dart';
import '../theme.dart';
import '../widgets.dart';
import 'delete_song_dialog.dart';

/// Detail view for a user playlist, lit by its cover: a cover hero with Play,
/// Shuffle and Add songs over its track list. Each track's ⋮ button opens a popover menu (add to
/// another playlist, remove); tracks can also be swiped away, and the handle
/// drags them to reorder. The header's ⋯ button opens a popover to rename or
/// delete the playlist. The playlist is read from [selectedPlaylistIdProvider].
class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(selectedPlaylistIdProvider);
    final playlist = id == null ? null : ref.watch(playlistByIdProvider(id));
    final songs = playlist == null
        ? const <Song>[]
        : ref.watch(playlistSongsProvider(playlist.id));
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.musicBackground),
      child: Stack(
        children: [
          CoverGlow(
            color: songs.isEmpty
                ? AppColors.accentB
                : coverLight(ref, songs.first),
          ),
          Positioned.fill(
            child: FrostedHeaderLayout(
              header: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                child: PageHeader(
                  title: 'Playlist',
                  trailing: playlist == null
                      ? null
                      : Builder(
                          builder: (buttonContext) => GlassIconButton(
                            icon: AppIcons.moreHoriz,
                            size: 44,
                            iconSize: 22,
                            onTap: () =>
                                _showMenu(buttonContext, ref, playlist),
                          ),
                        ),
                ),
              ),
              body: (context, top) => playlist == null
                  ? Padding(
                      padding: EdgeInsets.only(top: top),
                      child: _empty(),
                    )
                  : _content(context, ref, playlist, songs, top),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
    List<Song> songs,
    double top,
  ) {
    if (songs.isEmpty) {
      return ListView(
        padding: EdgeInsets.fromLTRB(24, top + 8, 24, 40),
        physics: const BouncingScrollPhysics(),
        children: [
          _hero(context, ref, playlist, songs),
          const SizedBox(height: 30),
          Padding(
            padding: const EdgeInsets.only(top: 30),
            child: Text(
              'No tracks yet.\nTap "Add songs" or long-press any track.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.whiteAlpha(0.5),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
        ],
      );
    }
    // Drag the handle on a row to reorder; swipe a row left to remove it. Only
    // the handle starts a reorder (buildDefaultDragHandles: false), so tap-to-
    // play and swipe-to-remove keep working.
    return ReorderableListView.builder(
      padding: EdgeInsets.fromLTRB(24, top + 8, 24, 40),
      physics: const BouncingScrollPhysics(),
      buildDefaultDragHandles: false,
      header: Column(
        children: [
          _hero(context, ref, playlist, songs),
          const SizedBox(height: 30),
        ],
      ),
      itemCount: songs.length,
      onReorderItem: (oldIndex, newIndex) {
        final ordered = List<Song>.of(songs);
        ordered.insert(newIndex, ordered.removeAt(oldIndex));
        ref.read(playlistsProvider.notifier).reorderSongs(playlist.id, ordered);
      },
      itemBuilder: (context, i) {
        final song = songs[i];
        return Padding(
          key: ValueKey(song.id),
          padding: const EdgeInsets.only(bottom: 20),
          child: Dismissible(
            key: ValueKey('dismiss-${song.id}'),
            direction: DismissDirection.endToStart,
            onDismissed: (_) => ref
                .read(playlistsProvider.notifier)
                .removeSong(playlist.id, song),
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFE0554F).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                AppIcons.deleteFilled,
                color: AppColors.white,
                size: 22,
              ),
            ),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      right: 12,
                      top: 8,
                      bottom: 8,
                    ),
                    child: Icon(
                      AppIcons.dragHandle,
                      size: 22,
                      color: AppColors.whiteAlpha(0.4),
                    ),
                  ),
                ),
                Expanded(
                  child: TrackRow(
                    song: song,
                    onTap: () => ref
                        .read(playbackProvider.notifier)
                        .playSong(song, context: songs),
                    trailing: Builder(
                      builder: (buttonContext) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () =>
                            _showTrackMenu(buttonContext, ref, playlist, song),
                        child: Icon(
                          AppIcons.moreVert,
                          size: 20,
                          color: AppColors.whiteAlpha(0.8),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _hero(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
    List<Song> songs,
  ) {
    return PageHero(
      cover: PlaylistCover(songs: songs, size: 220, radius: 28),
      title: playlist.name,
      meta: songsSummary(songs, count: playlist.songKeys.length),
      actions: [
        ...playActions(ref, songs),
        ActionPill(
          icon: AppIcons.add,
          label: 'Add songs',
          onTap: () => _showAddSongs(context, playlist.id),
        ),
      ],
    );
  }

  Future<void> _showMenu(
    BuildContext buttonContext,
    WidgetRef ref,
    Playlist playlist,
  ) async {
    final notifier = ref.read(playlistsProvider.notifier);
    final nav = ref.read(navigationProvider.notifier);
    final selected = await showPopoverMenu<String>(buttonContext, const [
      PopupMenuItem(
        value: 'rename',
        child: PopoverMenuRow(icon: AppIcons.edit, label: 'Rename playlist'),
      ),
      PopupMenuItem(
        value: 'delete',
        child: PopoverMenuRow(icon: AppIcons.delete, label: 'Delete playlist'),
      ),
    ]);
    switch (selected) {
      case 'rename':
        if (!buttonContext.mounted) return;
        final name = await showNameSheet(
          buttonContext,
          title: 'Rename playlist',
          initial: playlist.name,
          actionLabel: 'Save',
        );
        if (name != null) notifier.rename(playlist.id, name);
      case 'delete':
        notifier.delete(playlist.id);
        nav.back();
    }
  }

  Future<void> _showTrackMenu(
    BuildContext buttonContext,
    WidgetRef ref,
    Playlist playlist,
    Song song,
  ) async {
    final notifier = ref.read(playlistsProvider.notifier);
    final nav = ref.read(navigationProvider.notifier);
    final deletable = canDeleteSong(ref, song);
    final selected = await showPopoverMenu<String>(buttonContext, [
      ...queueMenuItems,
      const PopupMenuItem(
        value: 'details',
        child: PopoverMenuRow(icon: AppIcons.info, label: 'Song details'),
      ),
      const PopupMenuItem(
        value: 'add',
        child: PopoverMenuRow(
          icon: AppIcons.playlistAdd,
          label: 'Add to playlist',
        ),
      ),
      const PopupMenuItem(
        value: 'remove',
        child: PopoverMenuRow(
          icon: AppIcons.playlistRemove,
          label: 'Remove from playlist',
        ),
      ),
      if (deletable)
        const PopupMenuItem(
          value: 'delete',
          child: PopoverMenuRow(icon: AppIcons.delete, label: 'Delete'),
        ),
    ]);
    if (buttonContext.mounted &&
        handleQueueMenuChoice(buttonContext, ref, song, selected)) {
      return;
    }
    switch (selected) {
      case 'details':
        ref.read(selectedSongProvider.notifier).state = song;
        nav.goTo(AppScreen.songDetail);
      case 'add':
        if (buttonContext.mounted) {
          showAddToPlaylistSheet(buttonContext, song);
        }
      case 'delete':
        if (buttonContext.mounted) {
          await confirmDeleteSong(buttonContext, ref, song);
        }
      case 'remove':
        notifier.removeSong(playlist.id, song);
    }
  }

  void _showAddSongs(BuildContext context, String playlistId) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AddSongsSheet(playlistId: playlistId),
    );
  }

  Widget _empty() {
    return Center(
      child: Text(
        'Playlist not found.',
        style: TextStyle(color: AppColors.whiteAlpha(0.5), fontSize: 15),
      ),
    );
  }
}

/// Sheet to add tracks to a playlist: the library filtered by a search field,
/// each row toggling the track's membership (a check marks the ones already
/// in). Stays open so several tracks can be added in a row.
class _AddSongsSheet extends ConsumerStatefulWidget {
  const _AddSongsSheet({required this.playlistId});

  final String playlistId;

  @override
  ConsumerState<_AddSongsSheet> createState() => _AddSongsSheetState();
}

class _AddSongsSheetState extends ConsumerState<_AddSongsSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Case-insensitive match on title, artist or album — same rule as the main
  /// search screen. An empty query shows the whole library.
  List<Song> _filter(List<Song> songs) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return songs;
    return songs.where((s) {
      return s.title.toLowerCase().contains(q) ||
          s.artist.toLowerCase().contains(q) ||
          (s.album?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider.select((s) => s.songs));
    final playlist = ref.watch(playlistByIdProvider(widget.playlistId));
    final keys = playlist?.songKeys.toSet() ?? const <String>{};
    final results = _filter(library);
    return GlassSheet(
      maxHeightFactor: 0.8,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Add songs',
              style: TextStyle(
                color: AppColors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (library.isNotEmpty) ...[
              const SizedBox(height: 14),
              _searchField(),
            ],
          ],
        ),
      ),
      child: library.isEmpty
          ? _message('Your library is empty.')
          : results.isEmpty
          ? _message('Nothing matched "${_query.trim()}".')
          : ListView.builder(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 2, 24, 12),
              itemCount: results.length,
              itemBuilder: (context, i) {
                final song = results[i];
                final added = keys.contains(song.songKey);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final notifier = ref.read(playlistsProvider.notifier);
                    if (added) {
                      notifier.removeSong(widget.playlistId, song);
                    } else {
                      notifier.addSong(widget.playlistId, song);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        SongArtwork(song: song, size: 46, radius: 12),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.whiteAlpha(0.45),
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          added ? AppIcons.checkCircle : AppIcons.addCircle,
                          color: added
                              ? AppColors.accentA
                              : AppColors.whiteAlpha(0.4),
                          size: 26,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _searchField() {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.whiteAlpha(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.whiteAlpha(0.08)),
      ),
      child: Row(
        children: [
          Icon(AppIcons.search, size: 19, color: AppColors.whiteAlpha(0.5)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: (v) => setState(() => _query = v),
              cursorColor: AppColors.accentA,
              textInputAction: TextInputAction.search,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search your library',
                hintStyle: TextStyle(
                  color: AppColors.whiteAlpha(0.4),
                  fontSize: 14.5,
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
                  AppIcons.close,
                  size: 19,
                  color: AppColors.whiteAlpha(0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _message(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(color: AppColors.whiteAlpha(0.5), fontSize: 14),
        ),
      ),
    );
  }
}
