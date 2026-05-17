import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';

/// Captures and upserts a per-device profile (platform / OS / model / app
/// version / locale) into `user_devices`. Called fire-and-forget from
/// `main.dart` on app start, immediately after the auth state is known.
///
/// Errors are swallowed — this is observability data; it must never block
/// the app or surface a user-facing failure. The DB upsert uses the
/// (user_id, device_id) primary key so re-runs just refresh last_seen_at +
/// any drifted fields.
class DeviceProfileService {
  DeviceProfileService._();

  static SupabaseClient get _client => Supabase.instance.client;

  /// Idempotent upsert of the current device profile for the logged-in user.
  /// No-op when not authenticated, or on platforms we can't fingerprint
  /// safely (web returns a less-stable id; we still record it).
  static Future<void> upsertOnAppStart() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;
    try {
      final payload = await _collect();
      if (payload == null) return;
      await _client.from('user_devices').upsert(
        {
          'user_id': userId,
          ...payload,
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,device_id',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[DeviceProfileService] upsert error: $e');
    }
  }

  /// Returns a flat map ready for upsert, or null if we can't even guess
  /// a stable device id on this platform.
  static Future<Map<String, dynamic>?> _collect() async {
    final info = DeviceInfoPlugin();
    final pkg = await PackageInfo.fromPlatform();
    final appVersion = '${pkg.version}+${pkg.buildNumber}';
    final locale = PlatformDispatcher.instance.locale.toLanguageTag();

    String? deviceId;
    String platform;
    String? osVersion;
    String? deviceModel;
    String? manufacturer;

    if (kIsWeb) {
      final web = await info.webBrowserInfo;
      platform = 'web';
      deviceId = '${web.browserName.name}:${web.platform ?? "unknown"}';
      osVersion = web.appVersion;
      deviceModel = web.browserName.name;
      manufacturer = web.vendor;
    } else if (Platform.isAndroid) {
      final a = await info.androidInfo;
      platform = 'android';
      deviceId = a.id; // ANDROID_ID — per-app per-device
      osVersion = a.version.release;
      deviceModel = a.model;
      manufacturer = a.manufacturer;
    } else if (Platform.isIOS) {
      final i = await info.iosInfo;
      platform = 'ios';
      deviceId = i.identifierForVendor;
      osVersion = i.systemVersion;
      deviceModel = i.utsname.machine;
      manufacturer = 'Apple';
    } else if (Platform.isWindows) {
      final w = await info.windowsInfo;
      platform = 'windows';
      deviceId = w.deviceId;
      osVersion = '${w.majorVersion}.${w.minorVersion}.${w.buildNumber}';
      deviceModel = w.productName;
      manufacturer = 'Microsoft';
    } else if (Platform.isMacOS) {
      final m = await info.macOsInfo;
      platform = 'macos';
      deviceId = m.systemGUID;
      osVersion = m.osRelease;
      deviceModel = m.model;
      manufacturer = 'Apple';
    } else if (Platform.isLinux) {
      final l = await info.linuxInfo;
      platform = 'linux';
      deviceId = l.machineId;
      osVersion = l.versionId ?? l.version;
      deviceModel = l.prettyName;
      manufacturer = l.id;
    } else {
      return null;
    }

    if (deviceId == null || deviceId.isEmpty) return null;
    return {
      'device_id': deviceId,
      'platform': platform,
      if (osVersion != null && osVersion.isNotEmpty) 'os_version': osVersion,
      if (deviceModel.isNotEmpty) 'device_model': deviceModel,
      if (manufacturer != null && manufacturer.isNotEmpty)
        'manufacturer': manufacturer,
      'app_version': appVersion,
      'locale': locale,
    };
  }
}
