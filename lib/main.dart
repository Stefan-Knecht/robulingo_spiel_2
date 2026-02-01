// ------------------------------------------------------------
// Ziel (Laien): Einstiegspunkt der Flutter-App, steckt RobuLingoApp in MaterialApp.
// Verbindung: lädt `lib/app/robulingo_app.dart`, das den gesamten Flow steuert.
// Tücken: Theme/Dialog-Hintergrund werden hier gesetzt; Host/Logic liegen in robulingo_app.dart.
// ------------------------------------------------------------
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:robulingo_flutter/app/robulingo_app.dart';

void main() {
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
        if (child == null || !kIsWeb) {
          return child ?? const SizedBox.shrink();
        }
        final media = MediaQuery.of(context);
        const double webHeightScale = 0.96;
        return MediaQuery(
          data: media.copyWith(
            size: Size(media.size.width, media.size.height * webHeightScale),
          ),
          child: child,
        );
      },
      home: const RobuLingoApp(),
    ),
  );
}
