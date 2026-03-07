import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sportwai/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─── Pure helper functions ─────────────────────────────────────────────────

  group('kgToDisplay', () {
    test('returns same value when useKg is true', () {
      expect(kgToDisplay(80.0, true), 80.0);
      expect(kgToDisplay(0.0, true), 0.0);
    });

    test('converts kg to lbs when useKg is false', () {
      // 1 kg = 2.20462 lbs
      expect(kgToDisplay(1.0, false), 2.2); // rounded to 1 decimal
      expect(kgToDisplay(100.0, false), 220.5);
    });

    test('lbs result is rounded to 1 decimal place', () {
      final result = kgToDisplay(50.0, false);
      final parts = result.toString().split('.');
      expect(parts.length, 2);
      expect(parts[1].length, lessThanOrEqualTo(1));
    });
  });

  group('weightLabel', () {
    test('returns кг when useKg is true', () {
      expect(weightLabel(true), 'кг');
    });

    test('returns фунты when useKg is false', () {
      expect(weightLabel(false), 'фунты');
    });
  });

  group('cmToDisplay', () {
    test('returns same value when useCm is true', () {
      expect(cmToDisplay(50.0, true), 50.0);
    });

    test('converts cm to inches when useCm is false', () {
      // 1 inch = 2.54 cm → 2.54 cm = 1.0 inch
      expect(cmToDisplay(2.54, false), 1.0);
      expect(cmToDisplay(25.4, false), 10.0);
    });

    test('inch result is rounded to 1 decimal place', () {
      // 30 cm / 2.54 = 11.8110... → 11.8
      expect(cmToDisplay(30.0, false), 11.8);
    });
  });

  group('displayToCm', () {
    test('returns same value when useCm is true', () {
      expect(displayToCm(50.0, true), 50.0);
    });

    test('converts inches to cm when useCm is false', () {
      // 1 inch = 2.54 cm
      expect(displayToCm(1.0, false), 2.54);
      expect(displayToCm(10.0, false), 25.4);
    });

    test('displayToCm is approximate inverse of cmToDisplay', () {
      const originalCm = 30.0;
      final displayInches = cmToDisplay(originalCm, false);
      final backToCm = displayToCm(displayInches, false);
      // Allow small rounding error from the 1-decimal round in cmToDisplay
      expect(backToCm, closeTo(originalCm, 0.1));
    });
  });

  group('lengthLabel', () {
    test('returns см when useCm is true', () {
      expect(lengthLabel(true), 'см');
    });

    test('returns дюйм when useCm is false', () {
      expect(lengthLabel(false), 'дюйм');
    });
  });

  // ─── UseKgNotifier ─────────────────────────────────────────────────────────

  group('UseKgNotifier', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('initial state is true (kg)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(useKgProvider), isTrue);
    });

    test('setUseKg(false) switches state to lbs', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(useKgProvider.notifier).setUseKg(false);
      expect(container.read(useKgProvider), isFalse);
    });

    test('setUseKg(true) switches state back to kg', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(useKgProvider.notifier).setUseKg(false);
      await container.read(useKgProvider.notifier).setUseKg(true);
      expect(container.read(useKgProvider), isTrue);
    });

    test('persists choice to SharedPreferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(useKgProvider.notifier).setUseKg(false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('use_kg'), isFalse);
    });
  });

  // ─── UseCmNotifier ─────────────────────────────────────────────────────────

  group('UseCmNotifier', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('initial state is true (cm)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(useCmProvider), isTrue);
    });

    test('setUseCm(false) switches state to inches', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(useCmProvider.notifier).setUseCm(false);
      expect(container.read(useCmProvider), isFalse);
    });

    test('setUseCm(true) switches state back to cm', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(useCmProvider.notifier).setUseCm(false);
      await container.read(useCmProvider.notifier).setUseCm(true);
      expect(container.read(useCmProvider), isTrue);
    });

    test('persists choice to SharedPreferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(useCmProvider.notifier).setUseCm(false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('use_cm'), isFalse);
    });

    test('reads persisted value on startup', () async {
      SharedPreferences.setMockInitialValues({'use_cm': false});
      // Allow the async _load() to run
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Trigger load by reading
      await Future.delayed(Duration.zero);
      // After _load the state should be false
      expect(container.read(useCmProvider.notifier).state, isFalse);
    });
  });

  // ─── ThemeModeNotifier ────────────────────────────────────────────────────

  group('ThemeModeNotifier', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('initial state is dark', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('isDark returns true in dark mode', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(themeModeProvider.notifier).isDark, isTrue);
    });

    test('setDark(false) switches to light mode', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(themeModeProvider.notifier).setDark(false);
      expect(container.read(themeModeProvider), ThemeMode.light);
      expect(container.read(themeModeProvider.notifier).isDark, isFalse);
    });

    test('setDark(true) switches back to dark mode', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(themeModeProvider.notifier).setDark(false);
      await container.read(themeModeProvider.notifier).setDark(true);
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('persists theme choice to SharedPreferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(themeModeProvider.notifier).setDark(false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('theme_mode_dark'), isFalse);
    });
  });

  // ─── Onboarding level calculation logic ───────────────────────────────────
  // The same formula used in OnboardingScreen._finish()

  group('onboarding level calculation', () {
    String levelFromMonths(int months) {
      if (months < 6) return 'beginner';
      if (months < 24) return 'intermediate';
      return 'advanced';
    }

    int monthsBetween(DateTime start, DateTime end) =>
        (end.year - start.year) * 12 + (end.month - start.month);

    test('0 months → beginner', () {
      expect(levelFromMonths(0), 'beginner');
    });

    test('5 months → beginner', () {
      expect(levelFromMonths(5), 'beginner');
    });

    test('6 months → intermediate', () {
      expect(levelFromMonths(6), 'intermediate');
    });

    test('23 months → intermediate', () {
      expect(levelFromMonths(23), 'intermediate');
    });

    test('24 months → advanced', () {
      expect(levelFromMonths(24), 'advanced');
    });

    test('36 months → advanced', () {
      expect(levelFromMonths(36), 'advanced');
    });

    test('monthsBetween computes correct month difference', () {
      final start = DateTime(2022, 3, 1);
      final end = DateTime(2024, 3, 1);
      expect(monthsBetween(start, end), 24);
    });

    test('monthsBetween across year boundary', () {
      final start = DateTime(2023, 10, 1);
      final end = DateTime(2024, 2, 1);
      expect(monthsBetween(start, end), 4);
    });

    test('future start date gives negative months → beginner', () {
      // User accidentally picks future date — should still get beginner
      final start = DateTime(2030, 1, 1);
      final now = DateTime(2026, 1, 1);
      final months = monthsBetween(start, now);
      expect(levelFromMonths(months), 'beginner');
    });
  });
}
