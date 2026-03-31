import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class RealTalkScreen extends StatefulWidget {
  const RealTalkScreen({
    super.key,
    required this.initialUri,
    required this.onReturnToResumePanel,
  });

  final Uri initialUri;
  final Future<void> Function() onReturnToResumePanel;

  @override
  State<RealTalkScreen> createState() => _RealTalkScreenState();
}

class _RealTalkScreenState extends State<RealTalkScreen> {
  late final WebViewController _controller;
  late final Uri _returnUri;
  int _loadingProgress = 0;
  bool _exitingToResume = false;

  @override
  void initState() {
    super.initState();
    _returnUri = _resolveReturnUri(widget.initialUri);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF8F3EA))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) return;
            setState(() {
              _loadingProgress = progress.clamp(0, 100);
            });
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _loadingProgress = 0;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() {
              _loadingProgress = 100;
            });
          },
          onNavigationRequest: (request) {
            if (_shouldReturnToResume(request.url)) {
              unawaited(_handleReturnToResume());
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(widget.initialUri);
  }

  Uri _resolveReturnUri(Uri initialUri) {
    final rawReturnTo = initialUri.queryParameters['return_to'];
    if (rawReturnTo != null && rawReturnTo.trim().isNotEmpty) {
      try {
        return Uri.parse(rawReturnTo);
      } catch (_) {
        // Fall through to the default DailyWords landing page.
      }
    }
    return Uri.parse('https://www.dailywords-project.org/');
  }

  bool _shouldReturnToResume(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl);
      return uri.scheme.startsWith('http') &&
          uri.host.toLowerCase() == _returnUri.host.toLowerCase() &&
          uri.path == _returnUri.path;
    } catch (_) {
      return false;
    }
  }

  Future<void> _handleReturnToResume() async {
    if (_exitingToResume) return;
    setState(() {
      _exitingToResume = true;
    });
    try {
      await widget.onReturnToResumePanel();
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() {
          _exitingToResume = false;
        });
      }
    }
  }

  Future<bool> _handleBackPressed() async {
    if (_exitingToResume) {
      return false;
    }
    final canGoBack = await _controller.canGoBack();
    if (canGoBack) {
      await _controller.goBack();
      return false;
    }
    await _handleReturnToResume();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final showLoader = _exitingToResume || _loadingProgress < 100;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_handleBackPressed());
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('RealTalk'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _exitingToResume ? null : () => unawaited(_handleReturnToResume()),
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (showLoader)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: LinearProgressIndicator(
                  minHeight: 3,
                  value: _exitingToResume
                      ? null
                      : (_loadingProgress <= 0 || _loadingProgress >= 100)
                          ? null
                          : _loadingProgress / 100,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
