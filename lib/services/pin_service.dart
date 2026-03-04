import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PinService {
  static const _keyHash = 'pin_hash';
  static const _keyUserId = 'pin_user_id';
  static const _keyFails = 'pin_failed_attempts';

  static const int maxAttempts = 5;

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Returns true if a PIN has been set up on this device.
  static Future<bool> hasPin() async {
    final h = await _secure.read(key: _keyHash);
    return h != null && h.isNotEmpty;
  }

  /// Hash the PIN and store it along with the userId.
  static Future<void> setupPin(String pin, String userId) async {
    final hash = _hashPin(pin, userId);
    await _secure.write(key: _keyHash, value: hash);
    await _secure.write(key: _keyUserId, value: userId);
    await resetFailed();
  }

  /// Verify that the entered PIN matches the stored hash.
  static Future<bool> verifyPin(String pin) async {
    final storedHash = await _secure.read(key: _keyHash);
    final userId = await _secure.read(key: _keyUserId);
    if (storedHash == null || userId == null) return false;
    return _hashPin(pin, userId) == storedHash;
  }

  /// Remove the stored PIN (e.g. after too many failures or explicit reset).
  static Future<void> clearPin() async {
    await _secure.delete(key: _keyHash);
    await _secure.delete(key: _keyUserId);
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

  /// HMAC-SHA256(pin, userId) → lowercase hex string.
  static String _hashPin(String pin, String userId) {
    final key = utf8.encode(userId);
    final message = utf8.encode(pin);
    final hmac = Hmac(sha256, key);
    return hmac.convert(message).toString();
  }
}
