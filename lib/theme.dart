import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central palette + text styling for the music player, mirroring the
/// "Music Player" design (dark UI with a blue→violet accent gradient).
class AppColors {
  const AppColors._();

  static const Color accentA = Color(0xFF4F8CFF);
  static const Color accentB = Color(0xFF6F5CFF);

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentA, accentB],
  );

  static const Color homeBackground = Color(0xFF08080C);
  static const Color musicBackground = Color(0xFF0A0A0E);

  static const Color white = Colors.white;
  static Color whiteAlpha(double a) => Colors.white.withValues(alpha: a);

  /// Accent for the "liked" heart, matching the Liked Songs hero gradient.
  static const Color liked = Color(0xFFFF6F91);

  /// Text on the white primary buttons.
  static const Color ink = Color(0xFF0A0A0E);

  /// Raised dark surfaces: dialogs, snack bars, menus.
  static const Color surface = Color(0xFF17171F);

  /// The track playing, wherever it is listed: a light tint of the accent
  /// that stays legible on the dark background.
  static const Color playing = Color(0xFF8FB2FF);
}

class AppTheme {
  const AppTheme._();

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    // "Plus Jakarta Sans" (the design's typeface) via google_fonts. Applying
    // it to the theme's textTheme means inline TextStyles that don't override
    // fontFamily inherit it through DefaultTextStyle.
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(
      base.textTheme,
    ).apply(bodyColor: AppColors.white, displayColor: AppColors.white);
    // Material's own controls (buttons, segmented pickers, dialogs) speak the
    // app's language: a white pill for the main action, glass for the rest.
    const pill = StadiumBorder();
    // Derived from the text theme so buttons keep the app's typeface (a bare
    // TextStyle would fall back to the platform font).
    final label = textTheme.labelLarge!;
    final buttonText = label.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w700,
    );
    const buttonPadding = EdgeInsets.symmetric(horizontal: 24, vertical: 15);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.homeBackground,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.accentA,
        secondary: AppColors.accentB,
        surface: AppColors.musicBackground,
      ),
      textTheme: textTheme,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.white,
          foregroundColor: AppColors.ink,
          disabledBackgroundColor: AppColors.whiteAlpha(0.12),
          disabledForegroundColor: AppColors.whiteAlpha(0.4),
          shape: pill,
          padding: buttonPadding,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.white,
          backgroundColor: AppColors.whiteAlpha(0.05),
          side: BorderSide(color: AppColors.whiteAlpha(0.14)),
          shape: pill,
          padding: buttonPadding,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.white,
          shape: pill,
          textStyle: label.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.whiteAlpha(0.14)
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.white
                : AppColors.whiteAlpha(0.6),
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.white
                : AppColors.whiteAlpha(0.6),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: AppColors.whiteAlpha(0.12)),
          ),
          textStyle: WidgetStatePropertyAll(
            label.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.whiteAlpha(0.7),
          fontSize: 14,
          height: 1.45,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.white,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.white,
      ),
    );
  }
}
