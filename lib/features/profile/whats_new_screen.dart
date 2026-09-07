import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/services/update_service.dart';
import '../../shared/widgets/wallpaper_scaffold.dart';

class WhatsNewScreen extends StatefulWidget {
  const WhatsNewScreen({super.key});

  @override
  State<WhatsNewScreen> createState() => _WhatsNewScreenState();
}

class _WhatsNewScreenState extends State<WhatsNewScreen> {
  String? _text;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await UpdateService.instance.checkForUpdate(force: true);
      if (!mounted) return;
      final service = UpdateService.instance;
      setState(() {
        if (info != null && info.changelog.isNotEmpty) {
          _text = info.changelog;
        } else if (service.lastState == UpdateCheckState.current) {
          _text = 'You have the latest published Otya build.';
        } else {
          _text = service.lastError ?? 'No published release notes are available.';
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load update information.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return WallpaperScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text("What's new"),
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.textSecondary)))
          : _text == null
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(_text!, style: const TextStyle(height: 1.6)),
                  ),
                ),
    );
  }
}
