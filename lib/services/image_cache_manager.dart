import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Shared cache manager for all `CachedNetworkImage` widgets in the app.
///
/// Why a custom manager:
/// - Default manager has no size or entry limits → disk usage grows unbounded
///   as the user browses exercises (gifs are ~1 MB each).
/// - We tighten stale period so infrequently used gifs don't hold space forever.
///
/// Tuning:
///   [stalePeriod]      14 days — typical gif is revisited often if used; drop otherwise
///   [maxNrOfCacheObjects] 400  — at ~1 MB per gif ≈ 400 MB ceiling
class AppImageCacheManager {
  static const key = 'sportwaiImageCache';

  static final CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 14),
      maxNrOfCacheObjects: 400,
    ),
  );

  /// Clear the entire image disk cache. Useful for "Clear cache" settings.
  static Future<void> clearAll() => instance.emptyCache();
}
