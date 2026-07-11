import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';

import 'models.dart';
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
