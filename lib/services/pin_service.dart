import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PinService {
  static const _keyHash = 'pin_hash';
  static const _keyUserId = 'pin_user_id';
  static const _keyFails = 'pin_failed_attempts';
  static const _keyLockoutUntil = 'pin_lockout_until';

  static const int maxAttempts = 5;
  static const int lockoutMinutes = 15;

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Returns true if a PIN has been set up locally.
  static Future<bool> hasPin() async {
    final localHash = await _secure.read(key: _keyHash);
    return localHash != null && localHash.isNotEmpty;
  }

  /// Hash the PIN and store it locally.
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

  /// Remove the stored PIN locally.
  static Future<void> clearPin() async {
    await _secure.delete(key: _keyHash);
    await _secure.delete(key: _keyUserId);
    await resetFailed();
  }

  // ── Brute-force protection ────────────────────────────────────────────────

  static Future<int> getFailedAttempts() async {
    final val = await _secure.read(key: _keyFails);
    return int.tryParse(val ?? '0') ?? 0;
  }

  static Future<void> incrementFailed() async {
    final current = await getFailedAttempts();
    final next = current + 1;
    await _secure.write(key: _keyFails, value: '$next');
    if (next >= maxAttempts) {
      final until = DateTime.now()
          .add(const Duration(minutes: lockoutMinutes))
          .millisecondsSinceEpoch;
      await _secure.write(key: _keyLockoutUntil, value: '$until');
    }
  }

  static Future<void> resetFailed() async {
    await _secure.delete(key: _keyFails);
    await _secure.delete(key: _keyLockoutUntil);
  }

  /// Returns true if the PIN is currently locked out.
  static Future<bool> isLockedOut() async {
    final val = await _secure.read(key: _keyLockoutUntil);
    if (val == null) return false;
    final until = int.tryParse(val);
    if (until == null) return false;
    if (DateTime.now().millisecondsSinceEpoch < until) return true;
    await resetFailed();
    return false;
  }

  /// Returns remaining lockout minutes (0 if not locked).
  static Future<int> getLockoutRemainingMinutes() async {
    final val = await _secure.read(key: _keyLockoutUntil);
    if (val == null) return 0;
    final until = int.tryParse(val);
    if (until == null) return 0;
    final remaining = until - DateTime.now().millisecondsSinceEpoch;
    if (remaining <= 0) return 0;
    return (remaining / 60000).ceil();
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
