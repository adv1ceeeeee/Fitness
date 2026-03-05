import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Theme mode ───────────────────────────────────────────────────────────────

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  static const _key = 'theme_mode_dark';

  ThemeModeNotifier() : super(ThemeMode.dark) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool(_key) ?? true;
    if (mounted) state = isDark ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> setDark(bool dark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, dark);
    state = dark ? ThemeMode.dark : ThemeMode.light;
  }

  bool get isDark => state == ThemeMode.dark;
}

// ─── Units (kg / lbs) ────────────────────────────────────────────────────────

final useKgProvider = StateNotifierProvider<UseKgNotifier, bool>(
  (ref) => UseKgNotifier(),
);

class UseKgNotifier extends StateNotifier<bool> {
  static const _key = 'use_kg';

  UseKgNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) state = prefs.getBool(_key) ?? true;
  }

  Future<void> setUseKg(bool useKg) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, useKg);
    state = useKg;
  }
}

// ─── Helper ───────────────────────────────────────────────────────────────────

/// Convert kg value to display value + label depending on unit preference.
double kgToDisplay(double kg, bool useKg) =>
    useKg ? kg : double.parse((kg * 2.20462).toStringAsFixed(1));

String weightLabel(bool useKg) => useKg ? 'кг' : 'фунты';
