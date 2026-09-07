import 'package:flutter/material.dart';

/// Canonical Otya visual system.
///
/// Otya is a luminous navy/cyan/blue product, not a flat black interface.
/// Dark surfaces retain comfortable media contrast while carrying enough blue
/// lift that cards, navigation and the flowing brand background remain visible.
abstract class AppColors {
  static const Color background = Color(0xFF07152D);
  static const Color surface = Color(0xFF0B1E3A);
  static const Color surfaceElevated = Color(0xFF102A4D);
  static const Color surfaceHighlight = Color(0xFF173B66);
  static const Color border = Color(0xFF285887);
  static const Color borderSubtle = Color(0xFF173A61);

  // Core Otya product identity, sampled from the current cyan/blue mark.
  static const Color brandCyan = Color(0xFF27E8FF);
  static const Color brandBlue = Color(0xFF126BFF);
  static const Color brandDeepBlue = Color(0xFF173BFF);

  // Functional / assistant colors retained for compatibility and meaning.
  static const Color brandRed = Color(0xFFFF3B30);
  static const Color brandYellow = Color(0xFFFFD60A);

  static const Color accent = brandBlue;
  static const Color accentBlue = brandBlue;
  static const Color accentCyan = brandCyan;
  static const Color accentViolet = brandDeepBlue;
  static const Color accentPink = brandRed;
  static const Color accentOrange = Color(0xFFFF8A32);

  static const Color accentGreen = Color(0xFF39D98A);
  static const Color accentAmber = brandYellow;

  static const Color glowBlue = Color(0x52126BFF);
  static const Color glowViolet = Color(0x4027E8FF);

  static const LinearGradient accentGradient = LinearGradient(
    colors: [brandCyan, brandBlue, brandDeepBlue],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient accentGradientDiag = LinearGradient(
    colors: [brandCyan, brandBlue, brandDeepBlue],
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF0B1E3A), Color(0xFF102A4D)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkOverlay = LinearGradient(
    colors: [Colors.transparent, Color(0xD907152D)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const Color textPrimary = Color(0xFFF8FBFF);
  static const Color textSecondary = Color(0xFFC3D5EA);
  static const Color textMuted = Color(0xFF8FA8C4);

  static const Color error = Color(0xFFFF5B52);
  static const Color success = Color(0xFF39D98A);
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
          : const Color(0xFFE2E7EE);

  static Color cardOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? surfaceElevated
          : Colors.white;
}
