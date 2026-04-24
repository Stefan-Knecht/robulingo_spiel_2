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
            namingCorrectDetected: false,
            namingOutcome: null,
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
            startNamingLabel: 'Start naming',
            retryMicLabel: 'Retry mic',
            settingsLabel: 'Settings',
            withoutMicLabel: 'Without mic',
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

  testWidgets('naming view shows a single circular target image',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NamingView(
            leftImageBytes: Uint8List.fromList(const [0, 1, 2, 3]),
            rightImageBytes: Uint8List.fromList(const [4, 5, 6, 7]),
            targetOnLeft: true,
            imageHeight: 180,
            namingCorrectDetected: false,
            namingOutcome: null,
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
            startNamingLabel: 'Start naming',
            retryMicLabel: 'Retry mic',
            settingsLabel: 'Settings',
            withoutMicLabel: 'Without mic',
            onStartNaming: () {},
            onOpenSettings: () {},
            onContinueWithoutMic: (_) {},
            onSkip: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(ClipOval), findsOneWidget);
  });

  testWidgets('naming view turns the frame green on early correct detection',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NamingView(
            leftImageBytes: Uint8List.fromList(const [0, 1, 2, 3]),
            rightImageBytes: Uint8List.fromList(const [4, 5, 6, 7]),
            targetOnLeft: true,
            imageHeight: 180,
            namingCorrectDetected: true,
            namingOutcome: null,
            micPrimed: true,
            micDenied: false,
            micPermanentlyDenied: false,
            speechPermanentlyDenied: false,
            namingHold: false,
            showHourglass: false,
            namingInProgress: true,
            namingStartPending: false,
            showTinySpinner: false,
            liveTranscript: '',
            startNamingLabel: 'Start naming',
            retryMicLabel: 'Retry mic',
            settingsLabel: 'Settings',
            withoutMicLabel: 'Without mic',
            onStartNaming: () {},
            onOpenSettings: () {},
            onContinueWithoutMic: (_) {},
            onSkip: (_) {},
          ),
        ),
      ),
    );

    final animated =
        tester.widget<AnimatedContainer>(find.byType(AnimatedContainer).first);
    final decoration = animated.decoration! as BoxDecoration;
    final border = decoration.border! as Border;

    expect(border.top.color, Colors.green);
    expect(find.byType(CircleAvatar), findsNothing);
  });

  test(
      'session menu info combines naming status and mic details only in naming',
      () {
    expect(
      buildSessionInfoText(
        isNaming: true,
        namingStatus: 'Mic permission blocked',
        micStatusDetails: 'Speech recognition: not granted',
      ),
      'Mic permission blocked\n\nSpeech recognition: not granted',
    );
    expect(
      buildSessionInfoText(
        isNaming: false,
        namingStatus: 'Mic permission blocked',
        micStatusDetails: 'Speech recognition: not granted',
      ),
      isEmpty,
    );
  });
}
