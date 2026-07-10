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
}

class AppTheme {
  const AppTheme._();

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    // "Plus Jakarta Sans" (the design's typeface) via google_fonts. Applying
    // it to the theme's textTheme means inline TextStyles that don't override
    // fontFamily inherit it through DefaultTextStyle.
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
      bodyColor: AppColors.white,
      displayColor: AppColors.white,
    );
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.homeBackground,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.accentA,
        secondary: AppColors.accentB,
        surface: AppColors.musicBackground,
      ),
      textTheme: textTheme,
    );
  }
}
