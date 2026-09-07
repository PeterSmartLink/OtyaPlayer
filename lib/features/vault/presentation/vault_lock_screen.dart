import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/vault_item.dart';
import '../../../core/services/vault_service.dart';
import '../../../shared/widgets/wallpaper_scaffold.dart';
import '../../player/presentation/mini_player.dart';
import '../../player/presentation/queue_screen.dart';

const _pinKey = 'vault_pin_hash';
const _pinAttemptsKey = 'vault_pin_failed_attempts';
const _pinBlockedUntilKey = 'vault_pin_blocked_until_ms';
const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);
const _sessionTtl = Duration(minutes: 5);
const _pinMaxAttempts = 5;
const _pinBlockDuration = Duration(seconds: 30);

final vaultUnlockedProvider = StateProvider<bool>((_) => false);

class VaultLockScreen extends ConsumerStatefulWidget {
  const VaultLockScreen({super.key});

  @override
  ConsumerState<VaultLockScreen> createState() => _VaultLockScreenState();
}

class _VaultLockScreenState extends ConsumerState<VaultLockScreen>
    with WidgetsBindingObserver {
  static DateTime? _lastUnlock;

  final _localAuth = LocalAuthentication();
  bool _checking = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_expired) ref.read(vaultUnlockedProvider.notifier).state = false;
      if (!ref.read(vaultUnlockedProvider)) _unlockWithDevice();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get _expired =>
      _lastUnlock == null || DateTime.now().difference(_lastUnlock!) > _sessionTtl;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _expired) {
      ref.read(vaultUnlockedProvider.notifier).state = false;
    }
  }

  void _markUnlocked() {
    _lastUnlock = DateTime.now();
    ref.read(vaultUnlockedProvider.notifier).state = true;
  }

  Future<void> _unlockWithDevice() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _message = null;
    });
    try {
      final supported = await _localAuth.isDeviceSupported();
      if (!supported) {
        if (mounted) {
          setState(() => _message = 'Use your Private PIN to continue.');
        }
        return;
      }
      final ok = await _localAuth.authenticate(
        localizedReason: 'Unlock OTYA Private',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (ok) {
        HapticFeedback.mediumImpact();
        _markUnlocked();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Device authentication was unavailable. Use your Private PIN instead.');
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _unlockWithPin() async {
    final stored = await _storage.read(key: _pinKey);
    if (!mounted) return;
    final created = stored == null;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _PrivatePinDialog(create: created),
    );
    if (result == true) _markUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(vaultUnlockedProvider)) {
      return const _PrivateLibrary();
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) ref.read(vaultUnlockedProvider.notifier).state = false;
      },
      child: WallpaperScaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/myspace'),
          ),
          title: const Text('Private'),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        AppColors.brandBlue.withValues(alpha: .24),
                        AppColors.brandCyan.withValues(alpha: .10),
                      ],
                    ),
                    border: Border.all(
                      color: AppColors.brandCyan.withValues(alpha: .32),
                    ),
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    size: 42,
                    color: AppColors.brandCyan,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Otya Private',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Protected media stays inside Otya app-private storage until you restore it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _checking ? null : _unlockWithDevice,
                    icon: _checking
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.fingerprint_rounded),
                    label: const Text('Unlock with device security'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _unlockWithPin,
                  child: const Text('Use Private PIN'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivatePinDialog extends StatefulWidget {
  const _PrivatePinDialog({required this.create});
  final bool create;

  @override
  State<_PrivatePinDialog> createState() => _PrivatePinDialogState();
}

class _PrivatePinDialogState extends State<_PrivatePinDialog> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;

    if (!widget.create) {
      final blockedUntil = await _readBlockedUntil();
      if (blockedUntil != null && DateTime.now().isBefore(blockedUntil)) {
        final seconds = blockedUntil.difference(DateTime.now()).inSeconds + 1;
        if (mounted) {
          setState(() => _error =
              'Too many attempts. Try again in about $seconds seconds.');
        }
        return;
      }
      if (blockedUntil != null) await _clearExpiredPinBlock();
    }

    final pin = _pin.text;
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      setState(() => _error = 'Use a 4–6 digit PIN.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.create) {
        if (pin != _confirm.text) {
          if (mounted) setState(() => _error = 'PINs do not match.');
          return;
        }
        await _savePin(pin);
        await _clearPinThrottle();
        if (mounted) Navigator.pop(context, true);
        return;
      }

      final ok = await _verifyPin(pin);
      if (ok) {
        await _clearPinThrottle();
        if (mounted) Navigator.pop(context, true);
      } else {
        final blocked = await _registerPinFailure();
        _pin.clear();
        if (mounted) {
          setState(() => _error = blocked
              ? 'Too many attempts. Private PIN is locked for 30 seconds.'
              : 'Incorrect PIN.');
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.create ? 'Create Private PIN' : 'Enter Private PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _pin,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: InputDecoration(
                labelText: widget.create ? 'New PIN' : 'PIN',
                errorText: _error,
              ),
              onSubmitted: (_) => widget.create ? null : _submit(),
            ),
            if (widget.create) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _confirm,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(labelText: 'Confirm PIN'),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(widget.create ? 'Create' : 'Unlock'),
          ),
        ],
      );
}

Future<DateTime?> _readBlockedUntil() async {
  final raw = await _storage.read(key: _pinBlockedUntilKey);
  final millis = int.tryParse(raw ?? '');
  return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
}

Future<void> _clearExpiredPinBlock() async {
  await _storage.delete(key: _pinBlockedUntilKey);
  await _storage.write(key: _pinAttemptsKey, value: '0');
}

Future<bool> _registerPinFailure() async {
  final currentRaw = await _storage.read(key: _pinAttemptsKey);
  final current = int.tryParse(currentRaw ?? '') ?? 0;
  final next = current + 1;
  if (next >= _pinMaxAttempts) {
    final blockedUntil = DateTime.now().add(_pinBlockDuration);
    await _storage.write(
      key: _pinBlockedUntilKey,
      value: blockedUntil.millisecondsSinceEpoch.toString(),
    );
    await _storage.write(key: _pinAttemptsKey, value: '0');
    return true;
  }
  await _storage.write(key: _pinAttemptsKey, value: next.toString());
  return false;
}

Future<void> _clearPinThrottle() async {
  await _storage.delete(key: _pinBlockedUntilKey);
  await _storage.delete(key: _pinAttemptsKey);
}

Future<void> _savePin(String pin) async {
  final random = Random.secure();
  final salt = List<int>.generate(16, (_) => random.nextInt(256));
  final digest = sha256.convert([...salt, ...utf8.encode(pin)]).toString();
  await _storage.write(
    key: _pinKey,
    value: '${base64UrlEncode(salt)}:$digest',
  );
}

Future<bool> _verifyPin(String pin) async {
  final stored = await _storage.read(key: _pinKey);
  if (stored == null) return false;

  if (!stored.contains(':')) {
    final legacy = sha256.convert(utf8.encode(pin)).toString();
    final ok = _constantTimeEqual(stored, legacy);
    if (ok) await _savePin(pin);
    return ok;
  }

  final parts = stored.split(':');
  if (parts.length != 2) return false;
  try {
    final salt = base64Url.decode(parts[0]);
    final digest = sha256.convert([...salt, ...utf8.encode(pin)]).toString();
    return _constantTimeEqual(parts[1], digest);
  } catch (_) {
    return false;
  }
}

bool _constantTimeEqual(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

enum _PrivateView { files, folders }
enum _PrivateMediaFilter { all, videos, music }

class _PrivateLibrary extends ConsumerStatefulWidget {
  const _PrivateLibrary();

  @override
  ConsumerState<_PrivateLibrary> createState() => _PrivateLibraryState();
}

class _PrivateLibraryState extends ConsumerState<_PrivateLibrary>
    with WidgetsBindingObserver {
  List<VaultItem> _items = const [];
  int _size = 0;
  bool _loading = true;
  String? _message;
  _PrivateView _view = _PrivateView.files;
  _PrivateMediaFilter _filter = _PrivateMediaFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      ref.read(vaultUnlockedProvider.notifier).state = false;
    }
  }

  Future<void> _refresh() async {
    final items = VaultService.instance.getAllItems()
      ..sort((a, b) => b.lockedAt.compareTo(a.lockedAt));
    final size = await VaultService.instance.getVaultSize();
    if (!mounted) return;
    setState(() {
      _items = items;
      _size = size;
      _loading = false;
    });
  }

  String _name(VaultItem item) =>
      item.originalPath.replaceAll('\\', '/').split('/').last;

  String _folder(VaultItem item) {
    final normalized = item.originalPath.replaceAll('\\', '/');
    final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
    return parts.length > 1 ? parts[parts.length - 2] : 'Other';
  }

  List<VaultItem> get _filteredItems => switch (_filter) {
        _PrivateMediaFilter.all => _items,
        _PrivateMediaFilter.videos =>
          _items.where((item) => item.mediaType == 'video').toList(),
        _PrivateMediaFilter.music =>
          _items.where((item) => item.mediaType != 'video').toList(),
      };

  Map<String, List<VaultItem>> get _folders {
    final folders = <String, List<VaultItem>>{};
    for (final item in _filteredItems) {
      folders.putIfAbsent(_folder(item), () => <VaultItem>[]).add(item);
    }
    return Map.fromEntries(
      folders.entries.toList()
        ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase())),
    );
  }

  Future<void> _restore(VaultItem item) async {
    setState(() => _message = null);
    try {
      await VaultService.instance.unlockItem(item.mediaId);
      await _refresh();
      if (mounted) {
        setState(() => _message = 'Restored to ${_folder(item)}.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Otya could not restore that file.');
      }
    }
  }

  Future<void> _delete(VaultItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete protected file?'),
        content: const Text(
          'This permanently removes the copy stored in Otya Private. It cannot be restored after deletion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await VaultService.instance.deleteFromVault(item.mediaId);
      await _refresh();
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Otya could not delete that protected file.');
      }
    }
  }

  Future<void> _play(VaultItem item) async {
    final file = File(item.encryptedPath);
    if (!await file.exists()) {
      if (mounted) {
        setState(() => _message =
            'This protected file is missing from device storage.');
      }
      return;
    }
    final fileName = _name(item);
    final media = MediaItem(
      id: 'private:${item.mediaId}',
      title: fileName.replaceFirst(RegExp(r'\.[^.]+$'), ''),
      fileName: fileName,
      filePath: item.encryptedPath,
      isVideo: item.mediaType == 'video',
      addedAt: item.lockedAt,
      fileSizeBytes: await file.length(),
    );
    if (!mounted) return;
    if (media.isVideo) {
      context.push('/player/video', extra: media);
    } else {
      ref.read(queueProvider.notifier).setQueue([media]);
      ref.read(miniPlayerItemProvider.notifier).state = media;
      context.push('/player/audio', extra: media);
    }
  }

  Future<void> _openFolder(String folder, List<VaultItem> items) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: .98),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 8, 8),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.folder_rounded,
                      color: AppColors.brandCyan,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          folder,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '${items.length} protected file${items.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 7),
                itemBuilder: (_, index) => _PrivateFileRow(
                  item: items[index],
                  name: _name(items[index]),
                  folder: folder,
                  onPlay: () => _play(items[index]),
                  onRestore: () async {
                    Navigator.of(sheetContext).pop();
                    await _restore(items[index]);
                  },
                  onDelete: () async {
                    Navigator.of(sheetContext).pop();
                    await _delete(items[index]);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;
    final folders = _folders;
    final videoCount = _items.where((item) => item.mediaType == 'video').length;
    final musicCount = _items.length - videoCount;

    return WallpaperScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            ref.read(vaultUnlockedProvider.notifier).state = false;
            context.canPop() ? context.pop() : context.go('/myspace');
          },
        ),
        title: const Text('Private'),
        actions: [
          IconButton(
            tooltip: 'Lock now',
            onPressed: () => ref.read(vaultUnlockedProvider.notifier).state = false,
            icon: const Icon(Icons.lock_outline_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  16,
                  6,
                  16,
                  MediaQuery.paddingOf(context).bottom + 28,
                ),
                children: [
                  _PrivateSummary(
                    total: _items.length,
                    videos: videoCount,
                    music: musicCount,
                    sizeLabel: _formatBytes(_size),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _PrivateViewSwitch(
                    value: _view,
                    onChanged: (value) {
                      HapticFeedback.selectionClick();
                      setState(() => _view = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  _PrivateFilterBar(
                    value: _filter,
                    videoCount: videoCount,
                    musicCount: musicCount,
                    onChanged: (value) {
                      HapticFeedback.selectionClick();
                      setState(() => _filter = value);
                    },
                  ),
                  const SizedBox(height: 14),
                  if (_items.isEmpty)
                    const _PrivateEmpty()
                  else if (_view == _PrivateView.files && items.isEmpty)
                    const _PrivateEmpty(
                      title: 'Nothing in this category',
                      subtitle: 'Choose another filter to see your protected media.',
                    )
                  else if (_view == _PrivateView.files)
                    ...items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _PrivateFileRow(
                          item: item,
                          name: _name(item),
                          folder: _folder(item),
                          onPlay: () => _play(item),
                          onRestore: () => _restore(item),
                          onDelete: () => _delete(item),
                        ),
                      ),
                    )
                  else if (folders.isEmpty)
                    const _PrivateEmpty(
                      title: 'No folders here',
                      subtitle: 'Choose another media filter.',
                    )
                  else
                    ...folders.entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _PrivateFolderRow(
                          name: entry.key,
                          items: entry.value,
                          onTap: () => _openFolder(entry.key, entry.value),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _PrivateSummary extends StatelessWidget {
  const _PrivateSummary({
    required this.total,
    required this.videos,
    required this.music,
    required this.sizeLabel,
  });

  final int total;
  final int videos;
  final int music;
  final String sizeLabel;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.surfaceElevated.withValues(alpha: .90),
              AppColors.brandDeepBlue.withValues(alpha: .14),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.brandCyan.withValues(alpha: .18),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.brandCyan.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.shield_rounded,
                    color: AppColors.brandCyan,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$total protected file${total == 1 ? '' : 's'}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$videos videos · $music music',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  sizeLabel,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _PrivateViewSwitch extends StatelessWidget {
  const _PrivateViewSwitch({required this.value, required this.onChanged});

  final _PrivateView value;
  final ValueChanged<_PrivateView> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<_PrivateView>(
        segments: const [
          ButtonSegment(
            value: _PrivateView.files,
            icon: Icon(Icons.insert_drive_file_outlined),
            label: Text('Files'),
          ),
          ButtonSegment(
            value: _PrivateView.folders,
            icon: Icon(Icons.folder_outlined),
            label: Text('Folders'),
          ),
        ],
        selected: {value},
        showSelectedIcon: false,
        onSelectionChanged: (selection) => onChanged(selection.first),
      );
}

class _PrivateFilterBar extends StatelessWidget {
  const _PrivateFilterBar({
    required this.value,
    required this.videoCount,
    required this.musicCount,
    required this.onChanged,
  });

  final _PrivateMediaFilter value;
  final int videoCount;
  final int musicCount;
  final ValueChanged<_PrivateMediaFilter> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: Text('All ${videoCount + musicCount}'),
              selected: value == _PrivateMediaFilter.all,
              onSelected: (_) => onChanged(_PrivateMediaFilter.all),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              avatar: const Icon(Icons.movie_outlined, size: 16),
              label: Text('Videos $videoCount'),
              selected: value == _PrivateMediaFilter.videos,
              onSelected: (_) => onChanged(_PrivateMediaFilter.videos),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              avatar: const Icon(Icons.music_note_rounded, size: 16),
              label: Text('Music $musicCount'),
              selected: value == _PrivateMediaFilter.music,
              onSelected: (_) => onChanged(_PrivateMediaFilter.music),
            ),
          ],
        ),
      );
}

class _PrivateFileRow extends StatelessWidget {
  const _PrivateFileRow({
    required this.item,
    required this.name,
    required this.folder,
    required this.onPlay,
    required this.onRestore,
    required this.onDelete,
  });

  final VaultItem item;
  final String name;
  final String folder;
  final VoidCallback onPlay;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.cardOf(context).withValues(alpha: .90),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPlay,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    item.mediaType == 'video'
                        ? Icons.movie_rounded
                        : Icons.music_note_rounded,
                    color: AppColors.brandCyan,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$folder · Protected ${_shortDate(item.lockedAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.8,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Private file actions',
                  onSelected: (action) {
                    if (action == 'restore') onRestore();
                    if (action == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'restore',
                      child: Text('Restore to original folder'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete permanently'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _PrivateFolderRow extends StatelessWidget {
  const _PrivateFolderRow({
    required this.name,
    required this.items,
    required this.onTap,
  });

  final String name;
  final List<VaultItem> items;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final videos = items.where((item) => item.mediaType == 'video').length;
    final music = items.length - videos;
    return Material(
      color: AppColors.cardOf(context).withValues(alpha: .90),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.brandBlue.withValues(alpha: .22),
                      AppColors.brandCyan.withValues(alpha: .09),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.folder_rounded,
                  color: AppColors.brandCyan,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${items.length} files · $videos videos · $music music',
                      style: const TextStyle(
                        fontSize: 10.8,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivateEmpty extends StatelessWidget {
  const _PrivateEmpty({
    this.title = 'Private is empty',
    this.subtitle =
        'Move media to Private from the player or supported file actions.',
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
        child: Column(
          children: [
            const Icon(
              Icons.lock_open_rounded,
              size: 54,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

String _shortDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
