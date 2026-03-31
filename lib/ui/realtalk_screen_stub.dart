import 'package:flutter/material.dart';

class RealTalkScreen extends StatelessWidget {
  const RealTalkScreen({
    super.key,
    required this.initialUri,
    required this.onReturnToResumePanel,
  });

  final Uri initialUri;
  final Future<void> Function() onReturnToResumePanel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RealTalk')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'RealTalk in-app view is not available on this platform.\n\n$initialUri',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
