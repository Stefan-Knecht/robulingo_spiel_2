// ------------------------------------------------------------
// Ziel (Laien): Einstiegspunkt der Flutter-App, steckt RobuLingoApp in MaterialApp.
// Verbindung: lädt `lib/app/robulingo_app.dart`, das den gesamten Flow steuert.
// Tücken: Theme/Dialog-Hintergrund werden hier gesetzt; Host/Logic liegen in robulingo_app.dart.
// ------------------------------------------------------------
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
      home: const RobuLingoApp(),
    ),
  );
}
