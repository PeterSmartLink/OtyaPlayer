import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/config/environment.dart';
import '../../../core/services/update_service.dart';
import '../../../core/widgets/rate_us_sheet.dart';
import '../../../core/widgets/update_dialog.dart';
import '../../../shared/widgets/otya_logo.dart';
import '../../../shared/widgets/wallpaper_scaffold.dart';

/// Product information and support entry points that stay useful offline.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';
  String _build = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() {
        _version = info.version;
        _build = info.buildNumber;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return WallpaperScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('About Otya'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/myspace'),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.paddingOf(context).bottom + 32,
        ),
        children: [
          _ProductCard(version: _version, buildNumber: _build),
          const SizedBox(height: 24),
          const _SectionHeader('Support'),
          _GroupCard(
            children: [
              _NavTile(
                icon: Icons.bug_report_outlined,
                label: 'Report a problem',
                subtitle: 'Email Otya Support with a problem report',
                onTap: () => _launchEmail(
                  context,
                  subject: 'Otya Problem Report',
                ),
              ),
              const _Divider(),
              _NavTile(
                icon: Icons.email_outlined,
                label: 'Email support',
                subtitle: 'support@petersmartlink.com',
                onTap: () => _launchEmail(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionHeader('Product'),
          _GroupCard(
            children: [
              _NavTile(
                icon: Icons.language_rounded,
                label: 'Otya website',
                subtitle: 'Official product website',
                onTap: () => context.push(
                  '/webview',
                  extra: {'url': Environment.websiteUrl, 'title': 'Otya'},
                ),
              ),
              const _Divider(),
              _NavTile(
                icon: Icons.description_outlined,
                label: 'Help & docs',
                subtitle: 'Guides, account, privacy and support',
                onTap: () => context.push(
                  '/webview',
                  extra: {'url': Environment.docsUrl, 'title': 'Otya Docs'},
                ),
              ),
              const _Divider(),
              _NavTile(
                icon: Icons.system_update_outlined,
                label: 'Check for updates',
                subtitle: 'Check the official Otya release service',
                onTap: () => _checkForUpdates(context),
              ),
              const _Divider(),
              _NavTile(
                icon: Icons.new_releases_outlined,
                label: 'What’s new',
                subtitle: 'See what changed in this build',
                onTap: () => context.push('/whats-new'),
              ),
              const _Divider(),
              _NavTile(
                icon: Icons.share_rounded,
                label: 'Share Otya',
                subtitle: 'Send the official download page to a friend',
                onTap: () => _shareApp(context),
              ),
              const _Divider(),
              _NavTile(
                icon: Icons.privacy_tip_outlined,
                label: 'Privacy',
                subtitle: 'How Otya handles account and service data',
                onTap: () => context.push('/privacy'),
              ),
              const _Divider(),
              _NavTile(
                icon: Icons.star_outline_rounded,
                label: 'Rate Otya',
                subtitle: 'Send product feedback and a rating',
                onTap: () => RateUsSheet.show(context),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Center(
            child: Text(
              _version.isEmpty ? 'Otya' : 'Otya v$_version · build $_build',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
                fontFamily: 'Inter',
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text(
              '© 2026 PeterSmart Link',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                fontFamily: 'Inter',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Checking for updates…'),
          ],
        ),
        duration: Duration(seconds: 30),
      ),
    );
    try {
      final info = await UpdateService.instance.checkForUpdate(force: true);
      messenger.hideCurrentSnackBar();
      if (!context.mounted) return;
      if (info == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Otya is up to date.')),
        );
      } else {
        await UpdateDialog.checkAndShow(context);
      }
    } catch (_) {
      messenger.hideCurrentSnackBar();
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not check for updates. Check your connection and try again.'),
        ),
      );
    }
  }

  Future<void> _launchEmail(
    BuildContext context, {
    String subject = 'Otya Support',
  }) async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@petersmartlink.com',
      queryParameters: {'subject': subject},
    );
    if (!await launchUrl(uri) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open an email app.')),
      );
    }
  }

  Future<void> _shareApp(BuildContext context) async {
    try {
      final info = await PackageInfo.fromPlatform();
      await Share.share(
        'Otya v${info.version} is an offline-first media player for Android. Download it from the official page:\n${Environment.downloadPageUrl}',
        subject: 'Otya',
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open sharing right now.')),
      );
    }
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final versionLabel = version.isEmpty
        ? 'Reading version…'
        : 'Version $version · build $buildNumber';

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(28),
            ),
            child: const OtyaMark(size: 68),
          ),
          const SizedBox(height: 16),
          const Text(
            'Otya',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              fontFamily: 'Inter',
              letterSpacing: -.6,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Your media. Your way.',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              versionLabel,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
                fontFamily: 'Inter',
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Play and organize local music and video, send supported media nearby, protect private media and use practical tools. Core playback stays offline-first.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.55,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 9),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            fontFamily: 'Inter',
          ),
        ),
      );
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        indent: 58,
        color: AppColors.borderOf(context),
      );
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        leading: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.accent, size: 21),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right_rounded),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      );
}
