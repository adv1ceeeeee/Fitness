import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sportwai/models/workout.dart';

class CacheService {
  static Future<File> _file(String name) async {
    final dir = await getApplicationCacheDirectory();
    return File('${dir.path}/$name.json');
  }

  // ─── Workouts ──────────────────────────────────────────────────────────────

  static Future<void> saveWorkouts(List<Workout> workouts) async {
    try {
      final file = await _file('workouts');
      final data = workouts.map((w) => w.toJson()).toList();
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('CacheService.saveWorkouts error: $e');
    }
  }

  static Future<List<Workout>> loadWorkouts() async {
    try {
      final file = await _file('workouts');
      if (!await file.exists()) return [];
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      return raw
          .map((e) => Workout.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('CacheService.loadWorkouts error: $e');
      return [];
    }
  }

  // ─── Today's workout ───────────────────────────────────────────────────────

  static Future<void> saveTodayWorkout(Map<String, dynamic>? data) async {
    try {
      final file = await _file('today_workout');
      if (data == null) {
        if (await file.exists()) await file.delete();
        return;
      }
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('CacheService.saveTodayWorkout error: $e');
    }
  }

  static Future<Map<String, dynamic>?> loadTodayWorkout() async {
    try {
      final file = await _file('today_workout');
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('CacheService.loadTodayWorkout error: $e');
      return null;
    }
  }
}
