import 'package:flutter/material.dart';

/// Canonical Otya visual system.
///
/// The product canvas is deliberately quiet: content and media artwork carry
/// the personality, while surfaces establish calm hierarchy and readability.
abstract class AppColors {
  static const Color background = Color(0xFF101014);
  static const Color surface = Color(0xFF18181E);
  static const Color surfaceElevated = Color(0xFF202027);
  static const Color surfaceHighlight = Color(0xFF2A2934);
  static const Color border = Color(0xFF353442);
  static const Color borderSubtle = Color(0xFF282732);

  // Otya uses one restrained violet family. Cyan remains available only for
  // explicit media/connection status, never as decorative chrome.
  static const Color brandViolet = Color(0xFF8B6CFF);
  static const Color brandVioletDeep = Color(0xFF6547DB);
  static const Color brandCyan = Color(0xFF45D8E6);
  static const Color brandBlue = brandViolet;
  static const Color brandDeepBlue = brandVioletDeep;

  static const Color brandRed = Color(0xFFFF5A63);
  static const Color brandYellow = Color(0xFFF2C94C);

  static const Color accent = brandViolet;
  static const Color accentBlue = brandViolet;
  static const Color accentCyan = brandCyan;
  static const Color accentViolet = brandViolet;
  static const Color accentPink = brandRed;
  static const Color accentOrange = Color(0xFFFF9A62);
  static const Color accentGreen = Color(0xFF48C78E);
  static const Color accentAmber = brandYellow;

  static const Color glowBlue = Color(0x1F8B6CFF);
  static const Color glowViolet = Color(0x168B6CFF);

  static const LinearGradient accentGradient = LinearGradient(
    colors: [brandViolet, brandVioletDeep],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient accentGradientDiag = LinearGradient(
    colors: [brandViolet, brandVioletDeep],
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [surfaceElevated, surface],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkOverlay = LinearGradient(
    colors: [Colors.transparent, Color(0xE0101014)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const Color textPrimary = Color(0xFFF5F4FA);
  static const Color textSecondary = Color(0xFFC8C5D3);
  static const Color textMuted = Color(0xFF9793A5);

  static const Color error = Color(0xFFFF6B72);
  static const Color success = Color(0xFF48C78E);
  static const Color warning = brandYellow;

  static Color backgroundOf(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;

  static Color surfaceOf(BuildContext context) =>
      Theme.of(context).colorScheme.surface;

  static Color textPrimaryOf(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  static Color borderOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? border
          : const Color(0xFFE6E4EC);

  static Color cardOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? surfaceElevated
          : Colors.white;
}
