import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight stale-while-revalidate cache backed by SharedPreferences.
///
/// Usage:
/// ```dart
/// final profile = await AppCache.get(
///   key: 'profile',
///   ttl: const Duration(minutes: 5),
///   fetch: () => ProfileService.getProfile(),
///   encode: (p) => jsonEncode(p?.toJson()),
///   decode: (s) => s == null ? null : Profile.fromJson(jsonDecode(s)),
/// );
/// ```
///
/// On first call:   fetches from source, stores result, returns it.
/// Within TTL:      returns cached value immediately (no network).
/// After TTL:       returns stale cached value immediately AND refetches
///                  in background to keep cache warm (stale-while-revalidate).
/// On fetch error:  returns stale cached value (graceful degradation).
class AppCache {
  AppCache._();

  static SharedPreferences? _prefs;
  static bool _forceRefresh = false;

  static Future<SharedPreferences> get _p async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Runs [work] in force-refresh mode: all [get] calls inside will skip the
  /// cache and always fetch from the real source, then update the cache.
  ///
  /// Safe to use from a single async context (Dart is single-threaded).
  static Future<T> withForceRefresh<T>(Future<T> Function() work) async {
    _forceRefresh = true;
    try {
      return await work();
    } finally {
      _forceRefresh = false;
    }
  }

  /// Get a cached value or fetch it.
  ///
  /// [key]    Unique cache key (use namespaced strings like 'profile:$userId').
  /// [ttl]    How long the cache is considered fresh.
  /// [fetch]  Async function that fetches from the real source.
  /// [encode] Converts T to a JSON string for storage (return null to skip caching).
  /// [decode] Converts stored JSON string back to T (receives null if cache miss).
  static Future<T> get<T>({
    required String key,
    required Duration ttl,
    required Future<T> Function() fetch,
    required String? Function(T value) encode,
    required T Function(String? cached) decode,
  }) async {
    final prefs = await _p;

    if (!_forceRefresh) {
      final cachedStr = prefs.getString('cache:$key');
      final cachedAtMs = prefs.getInt('cache_at:$key');
      final now = DateTime.now().millisecondsSinceEpoch;

      final isFresh = cachedAtMs != null &&
          (now - cachedAtMs) < ttl.inMilliseconds;

      if (isFresh && cachedStr != null) {
        // Cache is fresh — return immediately, no network
        return decode(cachedStr);
      }

      if (cachedStr != null && cachedAtMs != null) {
        // Stale — return cached immediately, revalidate in background
        _refetchInBackground(key: key, fetch: fetch, encode: encode, prefs: prefs);
        return decode(cachedStr);
      }
    }

    // Cache miss or force-refresh — fetch synchronously
    final value = await fetch();
    await _store(prefs, key, encode(value));
    return value;
  }

  /// Returns cached value if exists (even stale), or null on cache miss.
  /// Never triggers a network fetch.
  static Future<T?> peek<T>({
    required String key,
    required T Function(String cached) decode,
  }) async {
    final prefs = await _p;
    final cachedStr = prefs.getString('cache:$key');
    if (cachedStr == null) return null;
    return decode(cachedStr);
  }

  /// Returns true if [key] exists in cache AND was stored within [maxAge].
  /// Use this to gate phase-1 loading: if false, skip stale data and let
  /// phase-2 fill in fresh values to avoid a visible flash.
  static Future<bool> isFresh(String key, {required Duration maxAge}) async {
    final prefs = await _p;
    final cachedAtMs = prefs.getInt('cache_at:$key');
    if (cachedAtMs == null) return false;
    final age = DateTime.now().millisecondsSinceEpoch - cachedAtMs;
    return age < maxAge.inMilliseconds;
  }

  /// Invalidate a cached key (forces fresh fetch on next [get] call).
  static Future<void> invalidate(String key) async {
    final prefs = await _p;
    await prefs.remove('cache:$key');
    await prefs.remove('cache_at:$key');
  }

  /// Invalidate all keys matching a prefix (e.g. 'profile:' to clear all profiles).
  static Future<void> invalidatePrefix(String prefix) async {
    final prefs = await _p;
    final keys = prefs.getKeys()
        .where((k) => k.startsWith('cache:$prefix'))
        .toList();
    for (final k in keys) {
      await prefs.remove(k);
      await prefs.remove(k.replaceFirst('cache:', 'cache_at:'));
    }
  }

  // ─── Internals ───────────────────────────────────────────────────────────────

  static void _refetchInBackground<T>({
    required String key,
    required Future<T> Function() fetch,
    required String? Function(T) encode,
    required SharedPreferences prefs,
  }) {
    fetch().then((value) async {
      await _store(prefs, key, encode(value));
    }).catchError((e) {
      debugPrint('[AppCache] background refetch error for "$key": $e');
    });
  }

  static Future<void> _store(
      SharedPreferences prefs, String key, String? encoded) async {
    if (encoded == null) return;
    await prefs.setString('cache:$key', encoded);
    await prefs.setInt(
        'cache_at:$key', DateTime.now().millisecondsSinceEpoch);
  }
}
