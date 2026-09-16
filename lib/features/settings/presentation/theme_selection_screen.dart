import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/services/custom_theme_manager.dart';
import '../../../core/services/online_theme_service.dart';
import '../../../shared/widgets/story_theme_background.dart';
import '../../../shared/widgets/wallpaper_scaffold.dart';

class ThemeSelectionScreen extends StatefulWidget {
  const ThemeSelectionScreen({super.key});

  @override
  State<ThemeSelectionScreen> createState() => _ThemeSelectionScreenState();
}

class _ThemeSelectionScreenState extends State<ThemeSelectionScreen> {
  String? _wallpaperPath;
  bool _saving = false;
  bool _loadingCatalog = true;
  bool _refreshingCatalog = false;
  int _catalogRequest = 0;
  String? _catalogError;
  List<OnlineTheme> _themes = const [];

  @override
  void initState() {
    super.initState();
    _wallpaperPath = CustomThemeManager.instance.wallpaperPath;
    _loadCatalog();
  }

  Future<void> _loadCatalog({bool forceRefresh = false}) async {
    // The first load starts with its spinner already visible. Later calls are
    // coalesced so a slow earlier response cannot replace a newer refresh.
    if (_refreshingCatalog || (_loadingCatalog && _themes.isNotEmpty)) return;
    final request = ++_catalogRequest;
    final isInitialLoad = _themes.isEmpty;
    setState(() {
      _loadingCatalog = isInitialLoad;
      _refreshingCatalog = !isInitialLoad;
      _catalogError = null;
    });

    try {
      final themes = await OnlineThemeService.fetchCatalog(
        forceRefresh: forceRefresh,
      );
      if (!mounted || request != _catalogRequest) return;
      setState(() {
        _themes = themes;
        _loadingCatalog = false;
        _refreshingCatalog = false;
        _catalogError = null;
      });
    } catch (_) {
      if (!mounted || request != _catalogRequest) return;
      setState(() {
        _loadingCatalog = false;
        _refreshingCatalog = false;
        if (_themes.isEmpty) {
          _catalogError = 'Backgrounds are unavailable right now';
        }
      });
      if (_themes.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not refresh backgrounds')),
        );
      }
    }
  }

  Future<void> _chooseImage() async {
    if (_saving) return;
    HapticFeedback.selectionClick();
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 2160,
    );
    if (picked == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await CustomThemeManager.instance.setTheme(
        id: 'otya-image',
        artworkPath: picked.path,
        opacity: 0.46,
        blur: 0,
      );
      if (!mounted) return;
      setState(() {
        _wallpaperPath = CustomThemeManager.instance.wallpaperPath;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your image theme is active')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not apply that image')),
      );
    }
  }

  Future<void> _install(OnlineTheme theme) async {
    HapticFeedback.selectionClick();
    await CustomThemeManager.instance.installOnlineTheme(theme);
    if (!mounted) return;
    setState(() => _wallpaperPath = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${theme.name} installed for offline use')),
    );
  }

  Future<void> _useDefault() async {
    await CustomThemeManager.instance.useDefaultMountainTheme();
    if (!mounted) return;
    setState(() => _wallpaperPath = null);
  }

  @override
  Widget build(BuildContext context) {
    final path = _wallpaperPath;
    final hasImage = path != null && path.isNotEmpty;
    final activeId = CustomThemeManager.instance.themeId;

    return WallpaperScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Image Theme',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          const Text(
            'BACKGROUND',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          _PhotoThemeCard(
            path: hasImage ? path : null,
            saving: _saving,
            active: activeId == 'otya-image',
            onTap: _chooseImage,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'CURATED BACKGROUNDS',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: (_loadingCatalog || _refreshingCatalog)
                    ? null
                    : () => _loadCatalog(forceRefresh: true),
                icon: _refreshingCatalog
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 16),
                label: Text(_refreshingCatalog ? 'Refreshing' : 'Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _DefaultThemeCard(
            active: activeId == 'otya-midnight',
            onTap: _useDefault,
          ),
          const SizedBox(height: 12),
          if (_loadingCatalog)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          else if (_catalogError != null)
            _CatalogError(
              message: _catalogError!,
              onRetry: () => _loadCatalog(forceRefresh: true),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.76,
              ),
              itemCount: _themes.length,
              itemBuilder: (context, index) {
                final theme = _themes[index];
                return _StoryThemeCard(
                  theme: theme,
                  active: activeId == theme.id,
                  onInstall: () => _install(theme),
                );
              },
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xA6101014),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.offline_pin_rounded, color: AppColors.accent, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Backgrounds are saved on your device for offline use. Your photo stays on your phone.',
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoThemeCard extends StatelessWidget {
  const _PhotoThemeCard({
    required this.path,
    required this.saving,
    required this.active,
    required this.onTap,
  });

  final String? path;
  final bool saving;
  final bool active;
  final VoidCallback onTap;

  Widget _fallback() => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E1430), Color(0xFF08080B)],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: active ? AppColors.accent : AppColors.border,
            width: active ? 1.5 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(21),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (path != null)
                Image.file(
                  File(path!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _fallback(),
                )
              else
                _fallback(),
              ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (saving)
                      const CircularProgressIndicator(strokeWidth: 2.5)
                    else
                      Icon(
                        path == null
                            ? Icons.add_photo_alternate_rounded
                            : Icons.wallpaper_rounded,
                        color: AppColors.accent,
                        size: 34,
                      ),
                    const SizedBox(height: 10),
                    Text(
                      path == null ? 'Choose a photo' : 'Change photo',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DefaultThemeCard extends StatelessWidget {
  const _DefaultThemeCard({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      tileColor: const Color(0xA6101014),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: active ? AppColors.accent : AppColors.border),
      ),
      leading: const Icon(Icons.landscape_rounded, color: AppColors.accent),
      title: const Text('Default', style: TextStyle(fontWeight: FontWeight.w700)),
      subtitle: const Text('A calm, low-distraction Otya canvas'),
      trailing: active
          ? const Icon(Icons.check_circle_rounded, color: AppColors.accent)
          : const Icon(Icons.chevron_right_rounded),
    );
  }
}

class _StoryThemeCard extends StatelessWidget {
  const _StoryThemeCard({
    required this.theme,
    required this.active,
    required this.onInstall,
  });

  final OnlineTheme theme;
  final bool active;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: active ? AppColors.accent : AppColors.border,
          width: active ? 1.5 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if ((theme.previewUrl ?? theme.wallpaperUrl) != null)
              Image.network(
                (theme.previewUrl ?? theme.wallpaperUrl)!,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) =>
                    StoryThemeBackground(theme: theme.toJson()),
              )
            else
              StoryThemeBackground(theme: theme.toJson()),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Text(
                    theme.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    theme.story,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      height: 1.4,
                      color: Color(0xFFD3D0DC),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: active ? null : onInstall,
                      icon: Icon(
                        active ? Icons.check_rounded : Icons.download_rounded,
                        size: 18,
                      ),
                      label: Text(active ? 'Installed' : 'Install'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogError extends StatelessWidget {
  const _CatalogError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xA6101014),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}