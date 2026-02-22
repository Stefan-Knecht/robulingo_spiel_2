// ------------------------------------------------------------
// Ziel (Laien): Einstiegspunkt der Flutter-App, steckt RobuLingoApp in MaterialApp.
// Verbindung: lädt `lib/app/robulingo_app.dart`, das den gesamten Flow steuert.
// Tücken: Theme/Dialog-Hintergrund werden hier gesetzt; Host/Logic liegen in robulingo_app.dart.
// ------------------------------------------------------------
import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart'
    show FlutterError, ValueNotifier, kIsWeb;
import 'package:flutter/material.dart';

import 'package:robulingo_flutter/app/robulingo_app.dart';

final ValueNotifier<String?> _lastError = ValueNotifier<String?>(null);

void main() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _lastError.value = details.exceptionAsString();
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack));
    _lastError.value = error.toString();
    return true;
  };
  ErrorWidget.builder = (details) {
    return Material(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Error: ${details.exceptionAsString()}',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  };
  runZonedGuarded(() {
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: Colors.white,
          dialogTheme: const DialogThemeData(
            backgroundColor: Colors.white,
          ),
        ),
        builder: (context, child) {
          if (child == null) {
            return const Material(
              color: Colors.white,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'App failed to build. Check console output.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          }
          if (!kIsWeb) return child;
          final media = MediaQuery.of(context);
          const double webHeightScale = 0.96;
          return MediaQuery(
            data: media.copyWith(
              size: Size(media.size.width, media.size.height * webHeightScale),
            ),
            child: ValueListenableBuilder<String?>(
              valueListenable: _lastError,
              builder: (context, errorText, _) {
                return Stack(
                  children: [
                    child,
                    if (errorText != null)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: Material(
                          color: Colors.red.shade50,
                          elevation: 4,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'Error: $errorText',
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          );
        },
        home: const RobuLingoApp(),
      ),
    );
  }, (error, stack) {
    FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack));
    _lastError.value = error.toString();
  });
}
