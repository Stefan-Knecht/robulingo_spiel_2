import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robulingo_flutter/ui/session/session_widgets.dart';

void main() {
  testWidgets('naming view hides mic actions during lead-in', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NamingView(
            leftImageBytes: Uint8List.fromList(const [0, 1, 2, 3]),
            rightImageBytes: Uint8List.fromList(const [4, 5, 6, 7]),
            targetOnLeft: true,
            imageHeight: 180,
            namingOutcome: null,
            namingStatus: '',
            micPrimed: true,
            micDenied: false,
            micPermanentlyDenied: false,
            speechPermanentlyDenied: false,
            namingHold: false,
            showHourglass: false,
            namingInProgress: false,
            namingStartPending: true,
            showTinySpinner: false,
            liveTranscript: '',
            onStartNaming: () {},
            onOpenSettings: () {},
            onContinueWithoutMic: (_) {},
            onSkip: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Retry mic'), findsNothing);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Without mic'), findsNothing);
  });
}
