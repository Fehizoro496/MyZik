import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons.dart';
import '../models.dart';
import '../providers/library_provider.dart';
import '../providers/liked_provider.dart';
import '../providers/playback_provider.dart';
import '../theme.dart';
import '../widgets.dart';
import 'desktop_navigation.dart';
import 'desktop_style.dart';
import 'dialogs.dart';

enum _SortColumn { order, title, artist, album, duration }

/// A dense, sortable song table for mouse use: double-click (or Enter) plays
/// a row with the table as the queue, right-click opens the track menu, the
/// heart column likes in place. [header] scrolls above the column titles
/// (an album or playlist hero).
class TrackTable extends ConsumerStatefulWidget {
  const TrackTable({
    super.key,
    required this.songs,
    this.header,
    this.onRemove,
    this.removeLabel = 'Remove',
    this.emptyMessage = 'No songs',
  });

  final List<Song> songs;
  final Widget? header;

  /// Adds a removal entry to the track menu (e.g. "Remove from playlist").
  final void Function(Song song)? onRemove;
  final String removeLabel;
  final String emptyMessage;

  @override
  ConsumerState<TrackTable> createState() => _TrackTableState();
}

class _TrackTableState extends ConsumerState<TrackTable> {
  _SortColumn _sort = _SortColumn.order;
  bool _ascending = true;
  Song? _selected;

  List<Song> get _sorted {
    if (_sort == _SortColumn.order) {
      return _ascending ? widget.songs : widget.songs.reversed.toList();
    }
    int compare(Song a, Song b) => switch (_sort) {
      _SortColumn.title => a.title.toLowerCase().compareTo(
        b.title.toLowerCase(),
      ),
      _SortColumn.artist => a.artist.toLowerCase().compareTo(
        b.artist.toLowerCase(),
      ),
      _SortColumn.album => (a.album ?? '').toLowerCase().compareTo(
        (b.album ?? '').toLowerCase(),
      ),
      _SortColumn.duration => a.duration.compareTo(b.duration),
      _SortColumn.order => 0,
    };
    final sorted = List<Song>.of(widget.songs)..sort(compare);
    return _ascending ? sorted : sorted.reversed.toList();
  }

  void _sortBy(_SortColumn column) {
    setState(() {
      if (_sort == column) {
        _ascending = !_ascending;
      } else {
        _sort = column;
        _ascending = true;
      }
    });
  }

  void _play(Song song, List<Song> queue) {
    ref.read(playbackProvider.notifier).playSong(song, context: queue);
  }

  Future<void> _openMenu(Offset position, Song song, List<Song> queue) async {
    setState(() => _selected = song);
    final liked = ref.read(isLikedProvider(song.songKey));
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      color: const Color(0xFF1C1C26),
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(
          value: 'play',
          child: PopoverMenuRow(icon: AppIcons.playFilled, label: 'Play'),
        ),
        const PopupMenuItem(
          value: 'playlist',
          child: PopoverMenuRow(
            icon: AppIcons.playlistAdd,
            label: 'Add to playlist…',
          ),
        ),
        PopupMenuItem(
          value: 'like',
          child: PopoverMenuRow(
            icon: liked ? AppIcons.heartFilled : AppIcons.heart,
            label: liked ? 'Remove from liked' : 'Add to liked',
          ),
        ),
        if (song.album != null)
          const PopupMenuItem(
            value: 'album',
            child: PopoverMenuRow(
              icon: AppIcons.category,
              label: 'Go to album',
            ),
          ),
        const PopupMenuItem(
          value: 'artist',
          child: PopoverMenuRow(
            icon: AppIcons.musicNote,
            label: 'Go to artist',
          ),
        ),
        if (widget.onRemove != null)
          PopupMenuItem(
            value: 'remove',
            child: PopoverMenuRow(
              icon: AppIcons.playlistRemove,
              label: widget.removeLabel,
            ),
          ),
      ],
    );
    if (!mounted) return;
    final library = ref.read(libraryProvider).songs;
    switch (selected) {
      case 'play':
        _play(song, queue);
      case 'playlist':
        await showAddToPlaylistDialog(context, song);
      case 'like':
        ref.read(likedProvider.notifier).toggle(song);
      case 'album':
        _openCollection(albumsFrom(library), song.album!);
      case 'artist':
        _openCollection(artistsFrom(library), song.artist);
      case 'remove':
        widget.onRemove?.call(song);
    }
  }

  void _openCollection(List<MusicCollection> collections, String title) {
    final match = collections.where((c) => c.title == title).firstOrNull;
    if (match == null) return;
    ref
        .read(desktopNavigatorProvider.notifier)
        .open(
          DesktopRoute(
            match.isArtist ? DesktopSection.artists : DesktopSection.albums,
            collection: match,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final songs = _sorted;
    final currentId = ref.watch(playbackProvider.select((p) => p.current?.id));
    return CustomScrollView(
      slivers: [
        if (widget.header != null) SliverToBoxAdapter(child: widget.header),
        SliverToBoxAdapter(child: _columnHeader()),
        if (songs.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Text(
                  widget.emptyMessage,
                  style: TextStyle(color: AppColors.whiteAlpha(0.45)),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList.builder(
              itemCount: songs.length,
              itemBuilder: (context, i) {
                final song = songs[i];
                return _TrackTableRow(
                  index: i + 1,
                  song: song,
                  playing: song.id == currentId,
                  selected: identical(song, _selected),
                  onSelect: () => setState(() => _selected = song),
                  onPlay: () => _play(song, songs),
                  onMenu: (position) => _openMenu(position, song, songs),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _columnHeader() {
    Widget cell(String label, _SortColumn column, {TextAlign? align}) {
      final active = _sort == column;
      return InkWell(
        onTap: () => _sortBy(column),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            active ? '$label ${_ascending ? '↑' : '↓'}' : label,
            textAlign: align,
            style: TextStyle(
              color: AppColors.whiteAlpha(active ? 0.9 : 0.6),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.whiteAlpha(0.08))),
      ),
      child: Row(
        children: [
          SizedBox(width: 40, child: cell('#', _SortColumn.order)),
          Expanded(flex: 5, child: cell('TITLE', _SortColumn.title)),
          Expanded(flex: 3, child: cell('ARTIST', _SortColumn.artist)),
          Expanded(flex: 3, child: cell('ALBUM', _SortColumn.album)),
          const SizedBox(width: 44),
          SizedBox(
            width: 64,
            child: cell('TIME', _SortColumn.duration, align: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _TrackTableRow extends ConsumerStatefulWidget {
  const _TrackTableRow({
    required this.index,
    required this.song,
    required this.playing,
    required this.selected,
    required this.onSelect,
    required this.onPlay,
    required this.onMenu,
  });

  final int index;
  final Song song;
  final bool playing;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onPlay;
  final void Function(Offset globalPosition) onMenu;

  @override
  ConsumerState<_TrackTableRow> createState() => _TrackTableRowState();
}

class _TrackTableRowState extends ConsumerState<_TrackTableRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final liked = ref.watch(isLikedProvider(song.songKey));
    final accent = widget.playing ? DesktopColors.accentText : AppColors.white;
    final secondary = TextStyle(
      color: AppColors.whiteAlpha(0.66),
      fontSize: 13,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        onDoubleTap: widget.onPlay,
        onSecondaryTapUp: (details) => widget.onMenu(details.globalPosition),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.whiteAlpha(0.10)
                : _hovered
                ? AppColors.whiteAlpha(0.05)
                : widget.playing
                ? AppColors.accentA.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: _hovered
                    ? GestureDetector(
                        onTap: widget.onPlay,
                        child: const Icon(
                          AppIcons.playFilled,
                          size: 16,
                          color: AppColors.white,
                        ),
                      )
                    : widget.playing
                    ? const Icon(
                        AppIcons.musicNote,
                        size: 16,
                        color: DesktopColors.accentText,
                      )
                    : Text('${widget.index}', style: secondary),
              ),
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    SongArtwork(song: song, size: 40, radius: 8),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: secondary,
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  song.album ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: secondary,
                ),
              ),
              SizedBox(
                width: 44,
                child: (liked || _hovered)
                    ? IconButton(
                        tooltip: liked ? 'Remove from liked' : 'Add to liked',
                        iconSize: 16,
                        onPressed: () =>
                            ref.read(likedProvider.notifier).toggle(song),
                        icon: Icon(
                          liked ? AppIcons.heartFilled : AppIcons.heart,
                          color: liked
                              ? AppColors.liked
                              : AppColors.whiteAlpha(0.6),
                        ),
                      )
                    : null,
              ),
              SizedBox(
                width: 64,
                child: Text(
                  song.durationLabel,
                  textAlign: TextAlign.right,
                  style: secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
