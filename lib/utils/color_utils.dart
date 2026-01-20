import 'package:flutter/material.dart';

extension ColorOpacityExtensions on Color {
  /// Returns the color with the provided opacity without relying on `.withOpacity`.
  Color withOpacityValue(double opacity) {
    final clamped = opacity.clamp(0.0, 1.0);
    return withValues(alpha: clamped);
  }
}
