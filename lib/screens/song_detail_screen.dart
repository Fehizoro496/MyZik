import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/collection_provider.dart';
import '../providers/library_provider.dart';
import '../providers/liked_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/playback_provider.dart';
import '../providers/song_detail_provider.dart';
import '../theme.dart';
import '../widgets.dart';

/// A dedicated page for one track: large cover, title/artist, quick actions
/// (play, like, add to playlist) and an info section (album, artist, duration)
/// whose album/artist rows jump to the matching collection. The song is read
/// from [selectedSongProvider].
class SongDetailScreen extends ConsumerWidget {
  const SongDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(selectedSongProvider);
    final artwork = song == null
        ? null
        : ref.watch(artworkProvider(song.id)).asData?.value;
    // Dominant colour of the cover (falls back to the placeholder gradient
    // while it's still being extracted or when the track has no artwork).
    final accent = song == null
        ? null
        : ref.watch(coverAccentProvider(song.id)).asData?.value ??
              song.artGradient.first;
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.musicBackground),
      child: Stack(
        children: [
          if (song != null)
            Positioned.fill(child: _background(song, artwork, accent!)),
          SafeArea(
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
                        onTap: () =>
                            ref.read(navigationProvider.notifier).back(),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Song',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
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

  /// Ambient, per-track background, like Now Playing: the cover art scaled up
  /// and heavily blurred so it reads as atmosphere, over a gradient tinted by
  /// the cover's dominant colour, with a scrim on top for legibility. Falls back
  /// to the placeholder gradient when there's no embedded artwork. Cross-fades
  /// on [Song.id].
  Widget _background(Song song, Uint8List? artwork, Color accent) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: Container(
        key: ValueKey(song.id),
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
                  child: Image.memory(artwork, fit: BoxFit.cover),
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

  Widget _content(BuildContext context, WidgetRef ref, Song song) {
    final liked = ref.watch(isLikedProvider(song.id));
    final library = ref.watch(libraryProvider.select((s) => s.songs));
    final hasArtist = library.any((s) => s.artist == song.artist);
    final hasAlbum =
        song.album != null && library.any((s) => s.album == song.album);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
      physics: const BouncingScrollPhysics(),
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 50,
                  offset: const Offset(0, 24),
                ),
              ],
            ),
            child: SongArtwork(song: song, size: 220, radius: 28),
          ),
        ),
        const SizedBox(height: 26),
        Text(
          song.title,
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
          song.artist,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.whiteAlpha(0.6), fontSize: 15),
        ),
        const SizedBox(height: 22),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            _pill(
              icon: Icons.play_arrow_rounded,
              label: 'Play',
              filled: true,
              onTap: () => ref
                  .read(playbackProvider.notifier)
                  .playSong(song, context: library),
            ),
            _pill(
              icon: liked ? IconlyBold.heart : IconlyLight.heart,
              label: liked ? 'Liked' : 'Like',
              iconColor: liked ? AppColors.liked : AppColors.white,
              onTap: () => ref.read(likedProvider.notifier).toggle(song.id),
            ),
            _pill(
              icon: Icons.playlist_add_rounded,
              label: 'Add to playlist',
              onTap: () => showAddToPlaylistSheet(context, song.id),
            ),
          ],
        ),
        const SizedBox(height: 28),
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

  Widget _pill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool filled = false,
    Color? iconColor,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          gradient: filled ? AppColors.accentGradient : null,
          color: filled ? null : AppColors.whiteAlpha(0.06),
          borderRadius: BorderRadius.circular(24),
          border: filled ? null : Border.all(color: AppColors.whiteAlpha(0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor ?? AppColors.white, size: 20),
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
    );
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
                  IconlyLight.arrowRight2,
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
