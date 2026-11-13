import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons.dart';
import '../models.dart';
import '../providers/collection_provider.dart';
import '../providers/downloads_provider.dart';
import '../providers/library_provider.dart';
import '../providers/liked_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/playback_provider.dart';
import '../providers/song_detail_provider.dart';
import '../theme.dart';
import '../widgets.dart';

/// A dedicated page for one track: large cover, title/artist, quick actions
/// (play, like, add to playlist) and an info section (album, artist, duration)
/// whose album/artist rows jump to the matching collection. The song is
/// [shownSongProvider].
class SongDetailScreen extends ConsumerWidget {
  const SongDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(shownSongProvider);
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.musicBackground),
      child: Stack(
        children: [
          if (song != null) Positioned.fill(child: SongBackdrop(song: song)),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 12, 24, 8),
                  child: PageHeader(title: 'Song'),
                ),
                Expanded(
                  child: song == null ? _empty() : _content(context, ref, song),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, WidgetRef ref, Song song) {
    final liked = ref.watch(isLikedProvider(song.songKey));
    final library = ref.watch(libraryProvider.select((s) => s.songs));
    final hasArtist = library.any((s) => s.artist == song.artist);
    final hasAlbum =
        song.album != null && library.any((s) => s.album == song.album);
    final download = ref.watch(
      downloadsProvider.select((d) => d.bySongId(song.id)),
    );
    final editable =
        song.hasStableKey && library.any((s) => s.songKey == song.songKey);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
      physics: const BouncingScrollPhysics(),
      children: [
        PageHero(
          cover: SongArtwork(song: song, size: 220, radius: 28),
          title: song.title,
          subtitle: song.artist,
          actions: [
            ActionPill(
              icon: AppIcons.playFilled,
              label: 'Play',
              primary: true,
              onTap: () => ref
                  .read(playbackProvider.notifier)
                  .playSong(song, context: library),
            ),
            ActionPill(
              icon: liked ? AppIcons.heartFilled : AppIcons.heart,
              label: liked ? 'Liked' : 'Like',
              iconColor: liked ? AppColors.liked : AppColors.white,
              onTap: () => ref.read(likedProvider.notifier).toggle(song),
            ),
            ActionPill(
              icon: AppIcons.playlistAdd,
              label: 'Add to playlist',
              onTap: () => showAddToPlaylistSheet(context, song),
            ),
            if (editable)
              ActionPill(
                icon: AppIcons.edit,
                label: 'Edit info',
                onTap: () => ref
                    .read(navigationProvider.notifier)
                    .goTo(AppScreen.songEdit),
              ),
            if (download != null)
              ActionPill(
                icon: AppIcons.delete,
                label: 'Remove download',
                onTap: () => _confirmRemoveDownload(context, ref, download),
              ),
          ],
        ),
        const SizedBox(height: 30),
        _infoCard([
          _InfoRow(
            label: 'Album',
            value: song.album ?? 'Unknown album',
            onTap: hasAlbum ? () => _openAlbum(ref, song) : null,
          ),
          _InfoRow(
            label: 'Artist',
            value: song.artist,
            onTap: hasArtist ? () => _openArtist(ref, song) : null,
          ),
          _InfoRow(label: 'Duration', value: song.durationLabel),
        ]),
      ],
    );
  }

  Widget _infoCard(List<Widget> rows) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.whiteAlpha(0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.whiteAlpha(0.07)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i != rows.length - 1)
              Divider(height: 1, color: AppColors.whiteAlpha(0.06)),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmRemoveDownload(
    BuildContext context,
    WidgetRef ref,
    DownloadedTrack download,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove download?'),
        content: Text(
          '"${download.title}" will be deleted from this phone. You can '
          'download it again from Discover.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(downloadsProvider.notifier).remove(download.videoId);
    ref.read(navigationProvider.notifier).back();
  }

  void _openAlbum(WidgetRef ref, Song song) {
    for (final album in albumsFrom(ref.read(libraryProvider).songs)) {
      if (album.title == song.album) {
        ref.read(selectedCollectionProvider.notifier).show(album);
        ref.read(navigationProvider.notifier).goTo(AppScreen.collection);
        return;
      }
    }
  }

  void _openArtist(WidgetRef ref, Song song) {
    for (final artist in artistsFrom(ref.read(libraryProvider).songs)) {
      if (artist.title == song.artist) {
        ref.read(selectedCollectionProvider.notifier).show(artist);
        ref.read(navigationProvider.notifier).goTo(AppScreen.collection);
        return;
      }
    }
  }

  Widget _empty() {
    return Center(
      child: Text(
        'No song selected.',
        style: TextStyle(color: AppColors.whiteAlpha(0.5), fontSize: 15),
      ),
    );
  }
}

/// One line of the info card: a fixed label, the value on the right, and a
/// chevron when the row navigates somewhere.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(
                label,
                style: TextStyle(
                  color: AppColors.whiteAlpha(0.5),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (onTap != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  AppIcons.chevronRight,
                  size: 18,
                  color: AppColors.whiteAlpha(0.4),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Ambient, per-track background, like Now Playing: the cover art scaled up
/// and heavily blurred so it reads as atmosphere, over a gradient tinted by
/// the cover's dominant colour, with a scrim on top for legibility. Falls back
/// to the placeholder gradient when there's no artwork. [cover] (encoded
/// image bytes) stands in for the song's own, e.g. a picture being picked.
/// Cross-fades when the song or its cover changes.
class SongBackdrop extends ConsumerWidget {
  const SongBackdrop({super.key, required this.song, this.cover});

  final Song song;
  final Uint8List? cover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artwork =
        cover ?? ref.watch(coverArtProvider(song.coverKey)).asData?.value;
    // Dominant colour of the cover (falls back to the placeholder gradient
    // while it's still being extracted or when the track has no artwork).
    final accent =
        ref.watch(coverAccentProvider(song.coverKey)).asData?.value ??
        song.artGradient.first;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: Container(
        key: ValueKey((song.id, song.artworkUrl, cover)),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [accent.withValues(alpha: 0.55), AppColors.musicBackground],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (artwork != null)
              Transform.scale(
                scale: 1.3,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
                  // Blurred beyond recognition anyway: a small decode is
                  // enough and spares memory and GPU uploads.
                  child: Image(
                    image: ResizeImage(
                      MemoryImage(artwork),
                      width: 96,
                      policy: ResizeImagePolicy.fit,
                    ),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.35),
                    Colors.black.withValues(alpha: 0.30),
                    AppColors.musicBackground.withValues(alpha: 0.92),
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
