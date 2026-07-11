import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';

import 'models.dart';
import 'player_controller.dart';
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

/// A song / playlist list row: art + title/subtitle + trailing play button.
class TrackRow extends StatelessWidget {
  const TrackRow({super.key, required this.track, this.onTap});

  final Track track;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        children: [
          AlbumArt(gradient: track.gradient),
          const SizedBox(width: 14),
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
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'By ${track.artist} · ${track.count} Songs',
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
              IconlyBold.play,
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
/// derived from [controller].screen and shows the accent pill.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({super.key, required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
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
                      c,
                      icon: IconlyLight.home,
                      activeIcon: IconlyBold.home,
                      screen: AppScreen.home,
                    ),
                    _tab(
                      c,
                      icon: IconlyLight.category,
                      activeIcon: IconlyBold.category,
                      screen: AppScreen.myMusic,
                    ),
                    _action(
                      IconlyLight.swap,
                      () => c.goTo(AppScreen.nowPlaying),
                    ),
                    _tab(
                      c,
                      icon: IconlyLight.bookmark,
                      activeIcon: IconlyBold.bookmark,
                      screen: AppScreen.saved,
                    ),
                    _tab(
                      c,
                      icon: IconlyLight.setting,
                      activeIcon: IconlyBold.setting,
                      screen: AppScreen.settings,
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
    PlayerController c, {
    required IconData icon,
    required IconData activeIcon,
    required AppScreen screen,
  }) {
    final active = c.screen == screen;
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
    return _action(icon, () => c.goTo(screen));
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

/// The frosted mini-player pill: a quick playback shortcut that opens Now
/// Playing. Floats above the [FloatingNavBar] on library-style screens.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: GestureDetector(
          onTap: () => c.goTo(AppScreen.nowPlaying),
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xBF16161E),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.whiteAlpha(0.1)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: c.togglePlay,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(
                      c.playing ? IconlyBold.play : IconlyLight.play,
                      size: 22,
                      color: AppColors.white,
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 24,
                  color: AppColors.whiteAlpha(0.15),
                ),
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    IconlyLight.swap,
                    size: 20,
                    color: Color(0xFF4F8CFF),
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
