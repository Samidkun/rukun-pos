import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukun_mobile/core/theme/app_colors.dart';
import 'package:rukun_mobile/core/theme/app_theme.dart';

void main() {
  group('AppColors Tests', () {
    test('Anti-UI-Slop color tokens must match DESIGN.md specifications', () {
      // Must not be pitch black (#000000)
      expect(AppColors.bgPrimary, isNot(equals(Colors.black)));
      expect(AppColors.bgPrimary, equals(const Color(0xFF16181C)));

      // Accent tokens
      expect(AppColors.accentPrimary, equals(const Color(0xFFC7F53B)));
      expect(AppColors.accentSuccess, equals(const Color(0xFF4EE5B6)));
      expect(AppColors.accentWarning, equals(const Color(0xFFF5A623)));
      expect(AppColors.accentDanger, equals(const Color(0xFFFF4D4D)));

      // Hairline border
      expect(AppColors.borderHairline, equals(const Color(0xFF2A2E35)));
    });
  });

  group('AppTheme Tests', () {
    test('darkTheme properly assigns dark brightness and semantic colors', () {
      final theme = AppTheme.darkTheme;

      expect(theme.brightness, equals(Brightness.dark));
      expect(theme.scaffoldBackgroundColor, equals(AppColors.bgPrimary));
      expect(theme.colorScheme.primary, equals(AppColors.accentPrimary));
      expect(theme.colorScheme.surface, equals(AppColors.surfacePrimary));
      expect(theme.cardTheme.color, equals(AppColors.surfacePrimary));
      expect(theme.dividerTheme.color, equals(AppColors.borderHairline));
    });
  });
}
