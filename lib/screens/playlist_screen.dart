import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/library_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/playback_provider.dart';
import '../providers/playlists_provider.dart';
import '../theme.dart';
import '../widgets.dart';

/// Detail view for a user playlist: a cover hero with Play / Add-songs actions
/// over its track list. Tracks swipe away to remove; the header menu renames or
/// deletes the playlist. The playlist to show is read from
/// [selectedPlaylistIdProvider].
class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(selectedPlaylistIdProvider);
    final playlist = id == null ? null : ref.watch(playlistByIdProvider(id));
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
                  const Expanded(
                    child: Text(
                      'Playlist',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (playlist != null)
                    GlassIconButton(
                      icon: Icons.more_horiz_rounded,
                      size: 44,
                      iconSize: 22,
                      onTap: () => _showMenu(context, ref, playlist),
                    ),
                ],
              ),
            ),
            Expanded(
              child: playlist == null
                  ? _empty()
                  : _content(
                      context,
                      ref,
                      playlist,
                      ref.watch(playlistSongsProvider(playlist.id)),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
    List<Song> songs,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
      physics: const BouncingScrollPhysics(),
      children: [
        _hero(context, ref, playlist, songs),
        const SizedBox(height: 24),
        if (songs.isEmpty)
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
          )
        else
          for (var i = 0; i < songs.length; i++) ...[
            Dismissible(
              key: ValueKey(songs[i].id),
              direction: DismissDirection.endToStart,
              onDismissed: (_) => ref
                  .read(playlistsProvider.notifier)
                  .removeSong(playlist.id, songs[i].id),
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0554F).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.delete_rounded,
                  color: AppColors.white,
                  size: 22,
                ),
              ),
              child: TrackRow(
                song: songs[i],
                onTap: () => ref
                    .read(playbackProvider.notifier)
                    .playSong(songs[i], context: songs),
              ),
            ),
            if (i != songs.length - 1) const SizedBox(height: 20),
          ],
      ],
    );
  }

  Widget _hero(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
    List<Song> songs,
  ) {
    final count = playlist.songIds.length;
    return Column(
      children: [
        const SizedBox(height: 8),
        PlaylistCover(songs: songs, size: 200, radius: 28),
        const SizedBox(height: 20),
        Text(
          playlist.name,
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
          '$count ${count == 1 ? 'song' : 'songs'}',
          style: TextStyle(color: AppColors.whiteAlpha(0.55), fontSize: 14),
        ),
        const SizedBox(height: 20),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _actionPill(
                icon: Icons.play_arrow_rounded,
                label: 'Play',
                filled: true,
                onTap: songs.isEmpty
                    ? null
                    : () => ref
                          .read(playbackProvider.notifier)
                          .playSong(songs.first, context: songs),
              ),
              const SizedBox(width: 12),
              _actionPill(
                icon: Icons.add_rounded,
                label: 'Add songs',
                filled: false,
                onTap: () => _showAddSongs(context, playlist.id),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionPill({
    required IconData icon,
    required String label,
    required bool filled,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
          decoration: BoxDecoration(
            gradient: filled ? AppColors.accentGradient : null,
            color: filled ? null : AppColors.whiteAlpha(0.06),
            borderRadius: BorderRadius.circular(24),
            border: filled
                ? null
                : Border.all(color: AppColors.whiteAlpha(0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.white, size: 20),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMenu(BuildContext context, WidgetRef ref, Playlist playlist) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => GlassSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetActionTile(
              icon: Icons.edit_rounded,
              label: 'Rename playlist',
              onTap: () async {
                final notifier = ref.read(playlistsProvider.notifier);
                Navigator.of(sheetContext).pop();
                final name = await showNameSheet(
                  context,
                  title: 'Rename playlist',
                  initial: playlist.name,
                  actionLabel: 'Save',
                );
                if (name != null) notifier.rename(playlist.id, name);
              },
            ),
            SheetActionTile(
              icon: Icons.delete_outline_rounded,
              label: 'Delete playlist',
              onTap: () {
                Navigator.of(sheetContext).pop();
                ref.read(playlistsProvider.notifier).delete(playlist.id);
                ref.read(navigationProvider.notifier).back();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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
    final ids = playlist?.songIds.toSet() ?? const <int>{};
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
                final added = ids.contains(song.id);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final notifier = ref.read(playlistsProvider.notifier);
                    if (added) {
                      notifier.removeSong(widget.playlistId, song.id);
                    } else {
                      notifier.addSong(widget.playlistId, song.id);
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
                          added
                              ? Icons.check_circle_rounded
                              : Icons.add_circle_outline_rounded,
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
          Icon(IconlyLight.search, size: 19, color: AppColors.whiteAlpha(0.5)),
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
                  Icons.close_rounded,
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
