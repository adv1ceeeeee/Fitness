import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';

/// Registers FCM/APNs device tokens in the `device_tokens` table.
///
/// Usage (after adding firebase_messaging):
/// ```dart
/// final token = await FirebaseMessaging.instance.getToken();
/// if (token != null) await DeviceTokenService.register(token);
/// FirebaseMessaging.instance.onTokenRefresh.listen(DeviceTokenService.register);
/// ```
class DeviceTokenService {
  static SupabaseClient get _client => Supabase.instance.client;

  static String get _platform {
    if (Platform.isIOS) return 'ios';
    return 'android';
  }

  /// Upsert the device token for the current user.
  /// Safe to call on every app start — uses ON CONFLICT DO UPDATE.
  static Future<void> register(String token) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;

    try {
      final info = await PackageInfo.fromPlatform();
      final appVersion = '${info.version}+${info.buildNumber}';
      await _client.from('device_tokens').upsert(
        {
          'user_id': userId,
          'token': token,
          'platform': _platform,
          'app_version': appVersion,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id, token',
      );
      debugPrint('[DeviceTokenService] token registered');
    } catch (e) {
      debugPrint('[DeviceTokenService] registration error: $e');
    }
  }

  /// Remove all tokens for this user on this device (call on sign-out).
  static Future<void> unregister(String token) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;
    try {
      await _client
          .from('device_tokens')
          .delete()
          .eq('user_id', userId)
          .eq('token', token);
    } catch (e) {
      debugPrint('[DeviceTokenService] unregister error: $e');
    }
  }
}
