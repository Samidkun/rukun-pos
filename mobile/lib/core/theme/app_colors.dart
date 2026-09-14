import 'package:flutter/material.dart';

/// Semantic color tokens based on mobile/DESIGN.md
abstract final class AppColors {
  // Master Canvas & Surfaces
  static const Color bgPrimary = Color(0xFF16181C);
  static const Color surfacePrimary = Color(0xFF1E2228);
  static const Color surfaceElevated = Color(0xFF252A32);

  // Hairline Borders
  static const Color borderHairline = Color(0xFF2A2E35);
  static const Color borderFocus = Color(0xFF3F4550);

  // Accents & Actions
  static const Color accentPrimary = Color(0xFFC7F53B); // Electric Lime
  static const Color accentSuccess = Color(0xFF4EE5B6); // Serene Mint
  static const Color accentWarning = Color(0xFFF5A623); // Warm Amber
  static const Color accentDanger = Color(0xFFFF4D4D);  // Crimson Alert

  // Typography
  static const Color textPrimary = Color(0xFFF4F5F6);
  static const Color textSecondary = Color(0xFF9DA5B4);
  static const Color textMuted = Color(0xFF5A6270);
}
