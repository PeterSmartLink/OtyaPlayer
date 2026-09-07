import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';

enum TogetherEntryChoice {
  nearbyStart,
  nearbyJoin,
  anywhereStart,
  anywhereJoin,
}

Future<TogetherEntryChoice?> showTogetherEntrySheet(BuildContext context) {
  return showModalBottomSheet<TogetherEntryChoice>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: AppColors.surface.withValues(alpha: .98),
    barrierColor: Colors.black.withValues(alpha: .42),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Watch Together',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'One room, two ways to connect. Choose what fits where you are.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          _TogetherPathCard(
            icon: Icons.wifi_tethering_rounded,
            title: 'Nearby',
            subtitle: 'Same Wi-Fi or hotspot · works without internet',
            onStart: () => Navigator.pop(
              sheetContext,
              TogetherEntryChoice.nearbyStart,
            ),
            onJoin: () => Navigator.pop(
              sheetContext,
              TogetherEntryChoice.nearbyJoin,
            ),
          ),
          const SizedBox(height: 10),
          _TogetherPathCard(
            icon: Icons.public_rounded,
            title: 'Anywhere',
            subtitle: 'Private internet peer connection · sign-in required',
            accent: true,
            onStart: () => Navigator.pop(
              sheetContext,
              TogetherEntryChoice.anywhereStart,
            ),
            onJoin: () => Navigator.pop(
              sheetContext,
              TogetherEntryChoice.anywhereJoin,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Anywhere uses the OTYA server only to connect the two phones. The movie itself is not uploaded to the room server.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ],
      ),
    ),
  );
}

class _TogetherPathCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onStart;
  final VoidCallback onJoin;
  final bool accent;

  const _TogetherPathCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onStart,
    required this.onJoin,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent
            ? AppColors.accent.withValues(alpha: .07)
            : Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: .50),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accent
              ? AppColors.accent.withValues(alpha: .16)
              : AppColors.border.withValues(alpha: .70),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: accent
                ? AppColors.accent.withValues(alpha: .12)
                : AppColors.surfaceElevated,
            child: Icon(
              icon,
              color: accent ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onJoin, child: const Text('Join')),
          FilledButton(onPressed: onStart, child: const Text('Start')),
        ],
      ),
    );
  }
}
