// ------------------------------------------------------------
// Ziel (Laien): Alternativer Einstiegspunkt für die Hexagon-Demo, lauffähig im iOS-Simulator.
// ------------------------------------------------------------
import 'package:flutter/material.dart';

import 'ui/hexagon_demo.dart';

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
      ),
      home: const HexagonDemoPage(),
    ),
  );
}
