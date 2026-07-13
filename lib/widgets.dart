import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'providers/library_provider.dart';
import 'providers/navigation_provider.dart';
import 'providers/playback_provider.dart';
import 'theme.dart';

/// A frosted, translucent circular icon button used throughout the design.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 46,
    this.iconSize = 20,
    this.iconColor = AppColors.white,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.whiteAlpha(0.06),
              border: Border.all(color: AppColors.whiteAlpha(0.1)),
            ),
            child: Icon(icon, size: iconSize, color: iconColor),
          ),
        ),
      ),
    );
  }
}

/// Album-art placeholder: a rounded gradient tile (or circle) with a subtle
/// note glyph, standing in for the design's image slots.
class AlbumArt extends StatelessWidget {
  const AlbumArt({
    super.key,
    required this.gradient,
    this.size = 56,
    this.radius = 16,
    this.circle = false,
    this.showGlyph = true,
  });

  final List<Color> gradient;
  final double size;
  final double radius;
  final bool circle;
  final bool showGlyph;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: circle ? null : BorderRadius.circular(radius),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
      ),
      child: showGlyph
          ? Icon(
              Icons.music_note_rounded,
              size: size * 0.34,
              color: AppColors.whiteAlpha(0.85),
            )
          : null,
    );
  }
}

/// Real album art for a [Song], loaded lazily from the library via
/// [artworkProvider]. Falls back to the song's gradient placeholder while
/// loading or when the track has no embedded cover. Keeps the artwork query
/// out of the [Song] model so the UI stays source-agnostic.
class SongArtwork extends ConsumerWidget {
  const SongArtwork({
    super.key,
    required this.song,
    this.size = 56,
    this.radius = 16,
    this.circle = false,
  });

  final Song song;
  final double size;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeholder = AlbumArt(
      gradient: song.artGradient,
      size: size,
      radius: radius,
      circle: circle,
    );
    final artwork = ref.watch(artworkProvider(song.id));
    final bytes = artwork.asData?.value;
    if (bytes == null) return placeholder;
    final image = Image.memory(
      bytes,
      width: size,
      height: size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => placeholder,
    );
    return circle
        ? ClipOval(
            child: SizedBox(width: size, height: size, child: image),
          )
        : ClipRRect(borderRadius: BorderRadius.circular(radius), child: image);
  }
}

/// A pill filter/category chip. Active chips use the accent gradient.
class CategoryChip extends StatelessWidget {
  const CategoryChip({
    super.key,
    required this.label,
    required this.active,
    this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        decoration: BoxDecoration(
          gradient: active ? AppColors.accentGradient : null,
          color: active ? null : AppColors.whiteAlpha(0.05),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.whiteAlpha(0.08)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? AppColors.white : AppColors.whiteAlpha(0.7),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// A horizontally-scrolling row of [CategoryChip]s with a selected index.
class CategoryChips extends StatelessWidget {
  const CategoryChips({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 22),
  });

  final List<Category> categories;
  final int selected;
  final ValueChanged<int> onSelected;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (var i = 0; i < categories.length; i++) ...[
            CategoryChip(
              label: categories[i].label,
              active: i == selected,
              onTap: () => onSelected(i),
            ),
            if (i != categories.length - 1) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

/// A song list row: art + title/subtitle + trailing play button.
class TrackRow extends StatelessWidget {
  const TrackRow({super.key, required this.song, this.onTap});

  final Song song;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        children: [
          SongArtwork(song: song),
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
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${song.artist} · ${song.durationLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.whiteAlpha(0.5),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.whiteAlpha(0.06),
              border: Border.all(color: AppColors.whiteAlpha(0.08)),
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              size: 18,
              color: AppColors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// The frosted bottom navigation bar. Meant to be anchored to the screen's
/// bottom edge (top corners rounded, bottom square) so a mini-player can float
/// above it. Shown on every screen except Now Playing. The active tab is
/// derived from [navigationProvider] and shows the accent pill.
class NavBar extends ConsumerWidget {
  const NavBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screen = ref.watch(navigationProvider);
    final goTo = ref.read(navigationProvider.notifier).goTo;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: const Color.fromRGBO(22, 22, 30, 0.5),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: AppColors.whiteAlpha(0.08))),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _tab(
                      screen,
                      goTo,
                      icon: IconlyLight.home,
                      activeIcon: IconlyBold.home,
                      target: AppScreen.home,
                    ),
                    _tab(
                      screen,
                      goTo,
                      icon: IconlyLight.category,
                      activeIcon: IconlyBold.category,
                      target: AppScreen.myMusic,
                    ),
                    // _action(
                    //   IconlyLight.swap,
                    //   () => goTo(AppScreen.nowPlaying),
                    // ),
                    _tab(
                      screen,
                      goTo,
                      icon: IconlyLight.heart,
                      activeIcon: IconlyBold.heart,
                      target: AppScreen.liked,
                    ),
                    _tab(
                      screen,
                      goTo,
                      icon: IconlyLight.setting,
                      activeIcon: IconlyBold.setting,
                      target: AppScreen.settings,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(
    AppScreen current,
    ValueChanged<AppScreen> goTo, {
    required IconData icon,
    required IconData activeIcon,
    required AppScreen target,
  }) {
    final active = current == target;
    if (active) {
      return Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.accentGradient,
        ),
        child: Icon(activeIcon, size: 22, color: AppColors.white),
      );
    }
    return _action(icon, () => goTo(target));
  }

  Widget _action(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Icon(icon, size: 24, color: AppColors.whiteAlpha(0.55)),
      ),
    );
  }
}

/// The frosted mini-player pill: floats above the [NavBar] whenever a
/// track is loaded, showing its art + title as a "playback in progress"
/// notice. Tapping it opens Now Playing; the play/pause button toggles
/// playback in place without navigating. Renders nothing when no track has
/// been played yet.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackProvider);
    final track = playback.current;
    if (track == null) return const SizedBox.shrink();
    final notifier = ref.read(playbackProvider.notifier);
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: GestureDetector(
          onTap: () =>
              ref.read(navigationProvider.notifier).goTo(AppScreen.nowPlaying),
          child: Container(
            height: 60,
            padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
            decoration: BoxDecoration(
              // Same tint + alpha as NavBar's frosted panel so the two floating
              // elements read as one consistent glass surface.
              color: const Color.fromRGBO(22, 22, 30, 0.5),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppColors.whiteAlpha(0.08)),
            ),
            child: Row(
              children: [
                SongArtwork(song: track, size: 44, circle: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.title,
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
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.whiteAlpha(0.55),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: notifier.togglePlay,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.whiteAlpha(0.08),
                      border: Border.all(color: AppColors.whiteAlpha(0.1)),
                    ),
                    child: Icon(
                      playback.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 18,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
