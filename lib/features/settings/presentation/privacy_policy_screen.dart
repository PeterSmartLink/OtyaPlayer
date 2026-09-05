import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/wallpaper_scaffold.dart';

/// In-app Privacy Policy screen.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return WallpaperScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Privacy',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            fontFamily: 'Inter',
          ),
        ),
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 48),
        child: _PolicyBody(),
      ),
    );
  }
}

class _PolicyBody extends StatelessWidget {
  const _PolicyBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _PolicyHeading('Otya Privacy Policy'),
        _PolicyText('Effective date: September 5, 2026 · Version 1.0'),
        SizedBox(height: 24),
        _PolicySection(
          title: '1. Who we are',
          body:
              'Otya is developed and maintained by PeterSmart Link '
              '(petersmartlink.com). If you have any questions about this '
              'policy, contact us at support@petersmartlink.com.',
        ),
        _PolicySection(
          title: '2. What stays on your device',
          body:
              'Core playback and Smart Search are offline-first. Media paths '
              'and metadata, playback history, playlists, favourites, search '
              'history, settings and Private media normally stay on this '
              'device. Otya does not upload your raw music or video library as '
              'part of normal playback, local search, analytics or Drive '
              'recovery.',
        ),
        _PolicySection(
          title: '3. Information connected services process',
          body:
              'Depending on what you use, Otya may process account and '
              'security details, a randomly generated Otya device ID, '
              'device/app information, a push-notification token, ratings or '
              'problem reports, and diagnostic records containing truncated '
              'error details. Otya does not sell personal information or use '
              'your local media library for advertising.',
        ),
        _PolicySection(
          title: '4. Optional connected features',
          body:
              'An Otya account is optional for local playback, Smart Search '
              'and nearby Send. Google Sign-In and Google Drive recovery are '
              'used only when you choose them. Drive recovery stores supported '
              'playlist data in the hidden app data folder, not raw media or '
              'Private files. Send moves supported files directly between '
              'devices on the same Wi-Fi or hotspot. Together is a connected '
              'feature: Otya services may process account identity, room and '
              'short-lived setup/signaling data needed to connect participants. '
              'The Otya Together control plane does not store the shared movie '
              'or room chat content.',
        ),
        _PolicySection(
          title: '5. Service providers',
          body:
              'Otya uses Cloudflare for connected services and release '
              'delivery; Google Firebase for notifications, app attestation, '
              'analytics and performance measurement when enabled; Google '
              'Identity and Drive for features you choose; Resend for email; '
              'and Telegram when you choose a Telegram interaction. The '
              'current v1 Android build has no advertising SDK.',
        ),
        _PolicySection(
          title: '6. Permissions',
          body:
              'Otya may request media-read access, network and Wi-Fi state, '
              'camera access for QR pairing, biometric/device authentication, '
              'foreground media playback and notifications. Android performs '
              'biometric matching; Otya does not receive or store your '
              'biometric template. Otya v1 does not request all-files or '
              'package-installer access.',
        ),
        _PolicySection(
          title: '7. Retention and deletion',
          body:
              'Local information remains until you remove it, clear Otya '
              'storage or uninstall the app. You can delete an authenticated '
              'Otya cloud account from the account screen. Google Drive '
              'recovery data is controlled separately and can also be deleted. '
              'Visit space.petersmartlink.com or contact support for '
              'data-access or deletion help.',
        ),
        _PolicySection(
          title: '8. Children, changes and contact',
          body:
              'Otya is not directed to children under 13. Material policy '
              'changes will update the effective date and version shown '
              'above.\n\n'
              'Email: support@petersmartlink.com\n'
              'Website: https://petersmartlink.com',
        ),
        SizedBox(height: 32),
        _PolicyText('© 2026 PeterSmart Link. All rights reserved.'),
      ],
    );
  }
}

class _PolicyHeading extends StatelessWidget {
  final String text;
  const _PolicyHeading(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
          fontFamily: 'Inter',
        ),
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  final String title;
  final String body;
  const _PolicySection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.65,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicyText extends StatelessWidget {
  final String text;
  const _PolicyText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        color: AppColors.textMuted,
        fontFamily: 'Inter',
        height: 1.5,
      ),
    );
  }
}
