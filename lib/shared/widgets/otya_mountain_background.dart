import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Offline-first default Otya backdrop.
///
/// The historical class name is retained for compatibility. The default is a
/// quiet product canvas rather than decorative light trails; media, not chrome,
/// supplies the visual richness.
class OtyaMountainBackground extends StatelessWidget {
  final double darkness;
  final bool showGlow;

  const OtyaMountainBackground({
    super.key,
    this.darkness = 0.16,
    this.showGlow = false,
  });

  @override
  Widget build(BuildContext context) {
    final overlay = (darkness * .28).clamp(0.0, .12);
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AppColors.background),
          if (showGlow)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(1.0, -1.0),
                  radius: 1.2,
                  colors: [
                    Color(0x128B6CFF),
                    Color(0x008B6CFF),
                  ],
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  AppColors.background.withValues(alpha: overlay),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
