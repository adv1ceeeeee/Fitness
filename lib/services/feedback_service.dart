import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/services/auth_service.dart';

/// Handles all user feedback: NPS surveys, micro-surveys, screen thumbs,
/// and free-form feedback from the Profile screen.
///
/// Shown-once flags are stored in SharedPreferences so surveys don't repeat.
class FeedbackService {
  static SupabaseClient get _client => Supabase.instance.client;

  static const _kNpsShownKey     = 'feedback_nps_shown';
  static const _kSurveyShownKey  = 'feedback_micro_survey_shown';

  // ─── NPS ──────────────────────────────────────────────────────────────────

  /// Returns true if the NPS survey should be shown:
  /// user has ≥ 3 completed sessions and has not been asked before.
  static Future<bool> shouldShowNps() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return false;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('${_kNpsShownKey}_$userId') == true) return false;

    try {
      final res = await _client
          .from('training_sessions')
          .select('id')
          .eq('user_id', userId)
          .eq('completed', true)
          .limit(3);
      return (res as List).length >= 3;
    } catch (_) {
      return false;
    }
  }

  /// Persist that NPS was shown for this user.
  static Future<void> markNpsShown() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_kNpsShownKey}_$userId', true);
  }

  // ─── Micro-survey ─────────────────────────────────────────────────────────

  /// Returns true if the "what's missing" micro-survey should be shown:
  /// user registered ≥ 7 days ago and has not been asked before.
  static Future<bool> shouldShowMicroSurvey() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return false;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('${_kSurveyShownKey}_$userId') == true) return false;

    try {
      final res = await _client
          .from('profiles')
          .select('created_at')
          .eq('id', userId)
          .maybeSingle();
      if (res == null) return false;
      final createdAt = DateTime.tryParse(res['created_at'] as String? ?? '');
      if (createdAt == null) return false;
      return DateTime.now().difference(createdAt).inDays >= 7;
    } catch (_) {
      return false;
    }
  }

  /// Persist that micro-survey was shown for this user.
  static Future<void> markMicroSurveyShown() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_kSurveyShownKey}_$userId', true);
  }

  // ─── Submit helpers ────────────────────────────────────────────────────────

  /// Submit NPS score (0–10) with optional comment.
  static Future<void> submitNps(int score, {String? comment}) async {
    await _insert(
      category: 'nps',
      rating: score,
      message: comment,
    );
  }

  /// Submit micro-survey feature request choice.
  static Future<void> submitFeatureRequest(String feature) async {
    await _insert(
      category: 'micro_survey',
      metadata: {'feature_request': feature},
    );
  }

  /// Submit screen thumbs up (+1) or down (-1).
  static Future<void> submitScreenFeedback(String screen, int vote,
      {String? comment}) async {
    await _insert(
      category: 'screen',
      rating: vote,
      message: comment,
      metadata: {'screen': screen},
    );
  }

  /// Submit free-form feedback from the Profile → Обратная связь screen.
  static Future<void> submitGeneralFeedback({
    required String category,  // 'bug' | 'feature' | 'general'
    required String message,
  }) async {
    await _insert(category: category, message: message);
  }

  // ─── Internal ─────────────────────────────────────────────────────────────

  static Future<void> _insert({
    required String category,
    int? rating,
    String? message,
    Map<String, dynamic>? metadata,
  }) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;
    try {
      await _client.from('feedback').insert({
        'user_id': userId,
        'category': category,
        if (rating != null) 'rating': rating,
        if (message != null && message.isNotEmpty) 'message': message,
        'metadata': metadata ?? {},
      });
    } catch (e) {
      debugPrint('[FeedbackService] insert error: $e');
    }
  }
}
