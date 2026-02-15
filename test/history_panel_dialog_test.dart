import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:robulingo_flutter/data/resume_state_service.dart';
import 'package:robulingo_flutter/data/supervisor_link_service.dart';
import 'package:robulingo_flutter/logic/history_hint_loader.dart';
import 'package:robulingo_flutter/ui/history_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('History panel dialog safety', () {
    testWidgets('renders on narrow width without RenderFlex overflow',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(318, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final flutterErrors = <FlutterErrorDetails>[];
      final oldOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        flutterErrors.add(details);
      };
      addTearDown(() => FlutterError.onError = oldOnError);

      await tester.pumpWidget(_buildHostApp(hintLoader: _FakeHintLoader()));
      await tester.tap(find.byKey(const Key('open_history')));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);

      final overflowErrors = flutterErrors
          .where((e) => e.exceptionAsString().contains('RenderFlex overflowed'))
          .toList(growable: false);
      expect(overflowErrors, isEmpty);
    });

    testWidgets(
        'closing panel during async hint load does not trigger teardown errors',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(318, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final flutterErrors = <FlutterErrorDetails>[];
      final oldOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        flutterErrors.add(details);
      };
      addTearDown(() => FlutterError.onError = oldOnError);

      await tester.pumpWidget(
        _buildHostApp(
          hintLoader: _FakeHintLoader(delay: const Duration(milliseconds: 60)),
        ),
      );
      await tester.tap(find.byKey(const Key('open_history')));
      await tester.pumpAndSettle();

      final hintIcon = find.byWidgetPredicate((widget) {
        if (widget is! Image) return false;
        final image = widget.image;
        return image is AssetImage &&
            image.assetName == 'assets/icons/Magnifying_glass.webp';
      });
      expect(hintIcon, findsOneWidget);
      await tester.ensureVisible(hintIcon);
      await tester.pumpAndSettle();
      await tester.tap(hintIcon);
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pumpAndSettle();

      bool hasPattern(String pattern) =>
          flutterErrors.any((e) => e.exceptionAsString().contains(pattern));

      expect(
        hasPattern('TextEditingController was used after being disposed'),
        isFalse,
      );
      expect(
        hasPattern("Failed assertion: line 6271 pos 12: '_dependents.isEmpty'"),
        isFalse,
      );
      expect(
        hasPattern("Looking up a deactivated widget's ancestor is unsafe"),
        isFalse,
      );
      expect(
        hasPattern('Tried to build dirty widget in the wrong build scope'),
        isFalse,
      );
    });
  });
}

Widget _buildHostApp({required HistoryHintLoader hintLoader}) {
  final mockHttp = MockClient((_) async => http.Response('{}', 200));
  final resumeService = ResumeStateService(
    workerHost: 'example.com',
    apiPrefix: '/api',
    client: mockHttp,
  );
  final supervisorService = SupervisorLinkService(
    workerHost: 'example.com',
    apiPrefix: '/api',
    client: mockHttp,
  );

  return MaterialApp(
    home: Builder(
      builder: (context) {
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('open_history'),
              onPressed: () {
                unawaited(
                  showHistoryPanel(
                    context: context,
                    userId: 'u1',
                    targetLang: 'en',
                    nativeLang: null,
                    resumeState: null,
                    resumeStateService: resumeService,
                    supervisorLinkService: supervisorService,
                    hintLoader: hintLoader,
                    onApplyUserId: (_, __) async {},
                    onRemoveUserId: () async {},
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        );
      },
    ),
  );
}

class _FakeHintLoader extends HistoryHintLoader {
  _FakeHintLoader({this.delay = Duration.zero});

  final Duration delay;

  @override
  Future<String> loadHint(String lang) async {
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    return 'Hint text';
  }
}
