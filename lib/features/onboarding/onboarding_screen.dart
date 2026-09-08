import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme/app_colors.dart';
import '../../shared/widgets/otya_logo.dart';

class OnboardingOverlay extends StatefulWidget {
  const OnboardingOverlay({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends State<OnboardingOverlay> {
  bool _busy = false;

  Future<void> _finish() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isFirstLaunch', false);
      if (mounted) widget.onDone();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const _BrandAtmosphere(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 44,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _Wordmark(),
                          const Spacer(),
                          const _Hero(),
                          const SizedBox(height: 34),
                          const _ProductPromise(),
                          const Spacer(),
                          const SizedBox(height: 32),
                          SizedBox(
                            height: 56,
                            child: FilledButton(
                              onPressed: _busy ? null : _finish,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.brandBlue,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    AppColors.brandBlue.withValues(alpha: .55),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: _busy
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Start using Otya',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 13),
                          const Text(
                            'No account is required to play media already on your phone.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11.5,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandAtmosphere extends StatelessWidget {
  const _BrandAtmosphere();

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(.72, -.92),
            radius: 1.2,
            colors: [
              Color(0x2927E8FF),
              Color(0x1F126BFF),
              AppColors.background,
            ],
            stops: [0, .34, 1],
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        OtyaMark(size: 32),
        SizedBox(width: 10),
        Text(
          'OTYA',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.1,
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 112,
          height: 112,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: .7),
            borderRadius: BorderRadius.circular(34),
            border: Border.all(
              color: AppColors.brandCyan.withValues(alpha: .16),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.brandBlue.withValues(alpha: .16),
                blurRadius: 44,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const OtyaMark(size: 78),
        ),
        const SizedBox(height: 26),
        const Text(
          'Your media, ready when you are.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 30,
            height: 1.08,
            fontWeight: FontWeight.w900,
            letterSpacing: -.75,
          ),
        ),
        const SizedBox(height: 13),
        const Text(
          'A focused player for the videos and music already on your phone — fast, private and easy to move between devices.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.55,
          ),
        ),
      ],
    );
  }
}

class _ProductPromise extends StatelessWidget {
  const _ProductPromise();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: const Column(
        children: [
          _PromiseRow(
            icon: Icons.play_circle_rounded,
            title: 'Video & Music',
            text: 'Play locally with background and system media controls.',
          ),
          SizedBox(height: 15),
          _PromiseRow(
            icon: Icons.swap_horiz_rounded,
            title: 'Send nearby',
            text: 'Move media directly when both devices are close.',
          ),
          SizedBox(height: 15),
          _PromiseRow(
            icon: Icons.shield_outlined,
            title: 'Private by default',
            text: 'Your local media stays on your device unless you choose otherwise.',
          ),
        ],
      ),
    );
  }
}

class _PromiseRow extends StatelessWidget {
  const _PromiseRow({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.brandBlue.withValues(alpha: .11),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: AppColors.brandCyan, size: 20),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                text,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
