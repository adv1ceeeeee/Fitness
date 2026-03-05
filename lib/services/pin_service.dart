import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PinService {
  static const _keyHash = 'pin_hash';
  static const _keyUserId = 'pin_user_id';
  static const _keyFails = 'pin_failed_attempts';
  static const _metaKey = 'pin_hash'; // key in Supabase user_metadata

  static const int maxAttempts = 5;

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Returns true if a PIN has been set up locally or in Supabase metadata.
  static Future<bool> hasPin() async {
    final localHash = await _secure.read(key: _keyHash);
    if (localHash != null && localHash.isNotEmpty) return true;
    return _syncFromCloud();
  }

  /// Hash the PIN and store it locally + in Supabase user metadata.
  static Future<void> setupPin(String pin, String userId) async {
    final hash = _hashPin(pin, userId);
    await _secure.write(key: _keyHash, value: hash);
    await _secure.write(key: _keyUserId, value: userId);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {_metaKey: hash}),
      );
    } catch (_) {}
    await resetFailed();
  }

  /// Verify that the entered PIN matches the stored hash.
  static Future<bool> verifyPin(String pin) async {
    String? storedHash = await _secure.read(key: _keyHash);
    String? userId = await _secure.read(key: _keyUserId);

    if (storedHash == null || userId == null) {
      await _syncFromCloud();
      storedHash = await _secure.read(key: _keyHash);
      userId = await _secure.read(key: _keyUserId);
      if (storedHash == null || userId == null) return false;
    }

    return _hashPin(pin, userId) == storedHash;
  }

  /// Remove the stored PIN locally and from Supabase metadata.
  static Future<void> clearPin() async {
    await _secure.delete(key: _keyHash);
    await _secure.delete(key: _keyUserId);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {_metaKey: null}),
      );
    } catch (_) {}
    await resetFailed();
  }

  // ── Brute-force protection ────────────────────────────────────────────────

  static Future<int> getFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyFails) ?? 0;
  }

  static Future<void> incrementFailed() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_keyFails) ?? 0;
    await prefs.setInt(_keyFails, current + 1);
  }

  static Future<void> resetFailed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFails);
  }

  // ── Internal ─────────────────────────────────────────────────────────────

  /// Pull PIN hash from Supabase user_metadata and cache it locally.
  /// Returns true if found and cached successfully.
  static Future<bool> _syncFromCloud() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return false;
      final cloudHash = user.userMetadata?[_metaKey] as String?;
      if (cloudHash == null || cloudHash.isEmpty) return false;
      await _secure.write(key: _keyHash, value: cloudHash);
      await _secure.write(key: _keyUserId, value: user.id);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// HMAC-SHA256(pin, userId) → lowercase hex string.
  static String _hashPin(String pin, String userId) {
    final key = utf8.encode(userId);
    final message = utf8.encode(pin);
    final hmac = Hmac(sha256, key);
    return hmac.convert(message).toString();
  }
}
