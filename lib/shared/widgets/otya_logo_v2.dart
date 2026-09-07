import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Canonical Otya lockup.
///
/// The current product mark is sourced from the single owner-approved cyan/blue
/// app icon. The WebP is the canonical binary because it is decoded and
/// validated by the app/release pipeline; older PNG/SVG logo copies are legacy
/// compatibility assets and must not be used for product UI.
class OtyaLogo extends StatelessWidget {
  const OtyaLogo({
    super.key,
    this.fontSize = 30,
    this.letterSpacing = -.6,
    this.borderRadius = 16,
    this.padding = EdgeInsets.zero,
    this.iconOnly = false,
  });

  final double fontSize;
  final double letterSpacing;
  final double borderRadius;
  final EdgeInsets padding;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final mark = OtyaMark(size: fontSize * 1.22);
    if (iconOnly) return mark;
    return Padding(
      padding: padding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          mark,
          SizedBox(width: fontSize * .18),
          Text(
            'Otya',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimaryOf(context),
              fontFamily: 'Inter',
              letterSpacing: letterSpacing,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Static Otya product identity used throughout the app UI.
class OtyaMark extends StatelessWidget {
  const OtyaMark({super.key, this.size = 52});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Otya',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * .22),
          child: Image.asset(
            'assets/branding/otya_app_icon.webp',
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => const _BrandFallback(),
          ),
        ),
      ),
    );
  }
}

/// Retained only for source compatibility with old direct imports. The public
/// `otya_logo.dart` export intentionally supplies the assistant-specific
/// OtyaThinkingMark from `otya_ai_mark.dart` instead.
class OtyaThinkingMark extends StatelessWidget {
  const OtyaThinkingMark({
    super.key,
    this.size = 52,
    this.thinking = true,
    this.duration = const Duration(milliseconds: 1800),
  });

  final double size;
  final bool thinking;
  final Duration duration;

  @override
  Widget build(BuildContext context) => OtyaMark(size: size);
}

class _BrandFallback extends StatelessWidget {
  const _BrandFallback();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.accentGradientDiag,
      ),
      child: const Center(
        child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
      ),
    );
  }
}
