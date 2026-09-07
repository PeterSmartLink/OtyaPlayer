import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Offline-first default Otya backdrop.
///
/// The historical class name is retained for source compatibility. The visual
/// follows the approved Otya identity: deep navy with broad luminous cyan and
/// electric-blue flows. It is painted locally, adds no network work, and user
/// Image/Story themes can still replace it through WallpaperScaffold.
class OtyaMountainBackground extends StatelessWidget {
  final double darkness;
  final bool showGlow;

  const OtyaMountainBackground({
    super.key,
    this.darkness = 0.16,
    this.showGlow = true,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AppColors.background),
          const CustomPaint(painter: _OtyaLightFlowPainter()),
          if (showGlow) ...[
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.76, -0.72),
                  radius: 1.08,
                  colors: [
                    Color(0x6627E8FF),
                    Color(0x46126BFF),
                    Color(0x00126BFF),
                  ],
                  stops: [0, .40, 1],
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.82, 0.82),
                  radius: .92,
                  colors: [
                    Color(0x43126BFF),
                    Color(0x2427E8FF),
                    Color(0x00173BFF),
                  ],
                  stops: [0, .48, 1],
                ),
              ),
            ),
          ],
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: darkness * .08),
                  Colors.transparent,
                  AppColors.background.withValues(alpha: darkness * .28),
                  const Color(0x8207152D),
                ],
                stops: const [0, .38, .76, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OtyaLightFlowPainter extends CustomPainter {
  const _OtyaLightFlowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final shortest = math.min(size.width, size.height);

    // Broad top-right ribbon. The larger stroke is intentional: the approved
    // visual system uses visible blue/cyan brand movement, not a nearly-black
    // background with a faint hairline.
    final topPath = Path()
      ..moveTo(size.width * .68, -shortest * .15)
      ..cubicTo(
        size.width * .98,
        size.height * .05,
        size.width * 1.04,
        size.height * .18,
        size.width * .83,
        size.height * .31,
      )
      ..cubicTo(
        size.width * .68,
        size.height * .41,
        size.width * .72,
        size.height * .51,
        size.width * 1.04,
        size.height * .60,
      );

    final topPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = shortest * .24
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [
          Color(0x0027E8FF),
          Color(0xA827E8FF),
          Color(0xA0126BFF),
          Color(0x5A173BFF),
          Color(0x00173BFF),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(topPath, topPaint);

    // Counter-flow across the lower half gives list and player screens the same
    // recognizable Otya identity without placing a literal logo behind content.
    final lowerPath = Path()
      ..moveTo(-shortest * .22, size.height * .82)
      ..cubicTo(
        size.width * .11,
        size.height * .64,
        size.width * .29,
        size.height * .67,
        size.width * .44,
        size.height * .84,
      )
      ..cubicTo(
        size.width * .56,
        size.height * .99,
        size.width * .72,
        size.height * 1.02,
        size.width * .90,
        size.height * .92,
      );
    final lowerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = shortest * .19
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [
          Color(0x00173BFF),
          Color(0x76126BFF),
          Color(0x7E27E8FF),
          Color(0x4D126BFF),
          Color(0x00126BFF),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(lowerPath, lowerPaint);

    // Bright edge definition mirrors the glossy cyan rim of the current mark.
    final hairline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..color = AppColors.brandCyan.withValues(alpha: .34);
    canvas.drawPath(topPath, hairline);

    final lowerEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = AppColors.brandBlue.withValues(alpha: .24);
    canvas.drawPath(lowerPath, lowerEdge);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
