import 'package:flutter/material.dart';

import '../icons.dart';
import '../theme.dart';

/// Surfaces and status colors of the desktop layout, on top of [AppColors].
class DesktopColors {
  const DesktopColors._();

  /// Sidebar and side panels.
  static const Color panel = Color(0xFF0C0C12);

  /// Player bar and timelines along the bottom.
  static const Color bar = Color(0xFF0E0E15);

  /// Cards and text fields.
  static const Color surface = Color(0xFF111119);
  static const Color field = Color(0xFF13131B);

  /// Accent for text and icons, lighter than [AppColors.accentA] so it reads
  /// on the dark surfaces.
  static const Color accentText = Color(0xFF9DB8FF);

  /// Lyric timings guessed rather than heard or tapped.
  static const Color estimated = Color(0xFFFFC992);
  static const Color success = Color(0xFF6FE0B4);
  static const Color error = Color(0xFFFF9DB4);
}

class DesktopText {
  const DesktopText._();

  /// Small uppercase section titles ("LIBRARY", "NOW PLAYING").
  static TextStyle get overline => TextStyle(
    color: AppColors.whiteAlpha(0.6),
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
  );

  static const TextStyle mono = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// The round accent-gradient play button of album, playlist and home heroes.
class AccentPlayButton extends StatelessWidget {
  const AccentPlayButton({
    super.key,
    required this.onPressed,
    this.size = 56,
    this.tooltip = 'Play',
  });

  final VoidCallback? onPressed;
  final double size;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onPressed == null ? 0.4 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppColors.accentGradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.accentB.withValues(alpha: 0.45),
                blurRadius: 28,
                offset: const Offset(0, 12),
                spreadRadius: -8,
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: SizedBox.square(
                dimension: size,
                child: Icon(
                  AppIcons.playFilled,
                  size: size * 0.4,
                  color: AppColors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded button used for secondary actions in headers and the lyrics
/// editor: outlined, or filled with the accent gradient when [primary].
class DesktopPill extends StatelessWidget {
  const DesktopPill({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.primary = false,
    this.shortcut,
    this.tooltip,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;

  /// Key hint shown inside the pill, e.g. "Ctrl S".
  final String? shortcut;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final pill = Opacity(
      opacity: enabled ? 1 : 0.4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: primary ? AppColors.accentGradient : null,
          borderRadius: BorderRadius.circular(18),
          border: primary
              ? null
              : Border.all(color: AppColors.whiteAlpha(0.14)),
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onPressed,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 15, color: AppColors.white),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (shortcut != null) ...[
                    const SizedBox(width: 8),
                    KeyHint(shortcut!, onAccent: primary),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}

/// A keyboard key, as in "Space" or "Ctrl F".
class KeyHint extends StatelessWidget {
  const KeyHint(this.keys, {super.key, this.onAccent = false});

  final String keys;
  final bool onAccent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.whiteAlpha(onAccent ? 0.2 : 0.08),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        keys,
        style: TextStyle(
          color: onAccent ? AppColors.white : AppColors.whiteAlpha(0.75),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Two to four mutually exclusive options in a rounded track ("Lyrics |
/// Queue", "Edit & time | Live sync", playback speeds).
class DesktopSegmented<T> extends StatelessWidget {
  const DesktopSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.dense = false,
  });

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T>? onSelected;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.whiteAlpha(0.06),
        borderRadius: BorderRadius.circular(dense ? 10 : 20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, label) in options)
            Material(
              color: value == selected
                  ? AppColors.whiteAlpha(0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(dense ? 7 : 16),
              child: InkWell(
                borderRadius: BorderRadius.circular(dense ? 7 : 16),
                onTap: onSelected == null ? null : () => onSelected!(value),
                child: Container(
                  height: dense ? 26 : 32,
                  padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 16),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: value == selected
                          ? AppColors.white
                          : AppColors.whiteAlpha(0.66),
                      fontSize: dense ? 12 : 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
