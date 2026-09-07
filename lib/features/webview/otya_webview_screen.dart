// lib/features/webview/otya_webview_screen.dart
//
// Trusted full-screen OTYA WebView. Only official PeterSmart Link HTTPS pages
// are allowed to execute inside the in-app JavaScript context. Off-domain links
// are handed to the system browser and never inherit OTYA's authenticated page.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/theme/app_colors.dart';
import '../../core/config/environment.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/connectivity_service.dart';

class OtyaWebViewScreen extends StatefulWidget {
  final String url;
  final String? title;

  const OtyaWebViewScreen({
    super.key,
    required this.url,
    this.title,
  });

  @override
  State<OtyaWebViewScreen> createState() => _OtyaWebViewScreenState();
}

class _OtyaWebViewScreenState extends State<OtyaWebViewScreen> {
  static const _trustedHosts = <String>{
    'petersmartlink.com',
    'www.petersmartlink.com',
    'space.petersmartlink.com',
    'docs.petersmartlink.com',
    'status.petersmartlink.com',
  };

  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isOffline = false;
  String? _errorDescription;
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _isOffline = ConnectivityService.instance.isOffline;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _hasError = false;
              _errorDescription = null;
              _currentUrl = url;
            });
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _currentUrl = url;
            });
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            if (error.isForMainFrame ?? true) {
              setState(() {
                _isLoading = false;
                _hasError = true;
                _errorDescription = error.description;
              });
            }
          },
          onNavigationRequest: _handleNavigation,
        ),
      );

    _loadWithAuth();
  }

  bool _isTrustedOtyaUri(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      _trustedHosts.contains(uri.host.toLowerCase());

  NavigationDecision _handleNavigation(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;

    final path = uri.path.toLowerCase();
    final binary = path.endsWith('.apk') ||
        path.endsWith('.zip') ||
        path.endsWith('.exe') ||
        path.endsWith('.dmg') ||
        path == '/apk' ||
        path.startsWith('/apk/');

    if (_isTrustedOtyaUri(uri) && !binary) {
      return NavigationDecision.navigate;
    }

    if ({'https', 'http', 'mailto'}.contains(uri.scheme)) {
      launchUrl(uri, mode: LaunchMode.externalApplication).ignore();
    }
    return NavigationDecision.prevent;
  }

  Future<void> _loadWithAuth() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null || !_isTrustedOtyaUri(uri)) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorDescription = 'This page is not an official OTYA destination.';
      });
      return;
    }

    final token = await AuthService.instance.getValidToken();
    final workerHost =
        Uri.tryParse(Environment.workerUrl)?.host.toLowerCase() ?? '';

    if (token != null && uri.host.toLowerCase() == workerHost) {
      await _controller.loadRequest(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
    } else {
      await _controller.loadRequest(uri);
    }
  }

  String get _displayTitle {
    if (widget.title != null && widget.title!.isNotEmpty) return widget.title!;
    final uri = Uri.tryParse(_currentUrl);
    return uri?.host.isNotEmpty == true ? uri!.host : 'OTYA';
  }

  Future<void> _openInBrowser() async {
    final raw = _currentUrl.isNotEmpty ? _currentUrl : widget.url;
    final uri = Uri.tryParse(raw);
    if (uri == null || !{'https', 'http'}.contains(uri.scheme)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not verify this browser address.')),
        );
      }
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open browser.')),
      );
    }
  }

  Future<void> _retry() async {
    final online = await ConnectivityService.checkIsOnline();
    if (!mounted) return;
    if (!online) {
      setState(() => _isOffline = true);
      return;
    }
    setState(() {
      _isLoading = true;
      _hasError = false;
      _isOffline = false;
      _errorDescription = null;
    });
    await _controller.reload();
  }

  Future<bool> _handleBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final handled = await _handleBack();
        if (!handled && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () async {
              final handled = await _handleBack();
              if (!handled && context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          title: Text(
            _displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: 'Inter',
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 22),
              tooltip: 'Refresh',
              onPressed: _retry,
            ),
            IconButton(
              icon: const Icon(
                Icons.open_in_browser_rounded,
                color: AppColors.accent,
                size: 22,
              ),
              tooltip: 'Open in Browser',
              onPressed: _openInBrowser,
            ),
          ],
          bottom: _isLoading
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(3),
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                    minHeight: 3,
                  ),
                )
              : null,
        ),
        body: Column(
          children: [
            if (_isOffline)
              Material(
                color: AppColors.error.withValues(alpha: 0.12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.wifi_off_rounded,
                        color: AppColors.error,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'No internet connection',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.error,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _retry,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: _hasError || _isOffline
                  ? _buildErrorState()
                  : WebViewWidget(controller: _controller),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    final offline = _isOffline;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                offline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded,
                color: AppColors.error,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              offline ? 'No internet connection' : 'Page failed to load',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              offline
                  ? 'Connect to Wi-Fi or mobile data and try again.'
                  : (_errorDescription ??
                      'Check your connection and try again.'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontFamily: 'Inter',
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openInBrowser,
                icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                label: const Text('Open in Browser'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
