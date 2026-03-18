import 'package:sportwai/services/local_storage.dart';

/// Manages the streak freeze mechanic.
///
/// Rules:
/// - User has at most 1 freeze at a time.
/// - A freeze is automatically refilled 7 days after it was last refilled.
/// - When getCurrentStreak detects a 1-day gap, it calls [applyIfAvailable].
/// - The used date is stored so the same gap counts correctly across app opens.
class StreakFreezeService {
  StreakFreezeService._();

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Call on every app open. Restores 1 freeze if 7+ days have passed.
  static void maybeRefill() {
    final refillDateStr = AppStorage.streakFreezeRefillDate;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (refillDateStr == null) {
      // First time — grant initial freeze and record refill date
      AppStorage.setStreakFreezeCount(1);
      AppStorage.setStreakFreezeRefillDate(_dateStr(today));
      return;
    }

    final refillDate = DateTime.parse(refillDateStr);
    if (today.difference(refillDate).inDays >= 7 &&
        AppStorage.streakFreezeCount < 1) {
      AppStorage.setStreakFreezeCount(1);
      AppStorage.setStreakFreezeRefillDate(_dateStr(today));
    }
  }

  /// Returns true if a freeze was available and applied to [skippedDate].
  /// Idempotent: calling twice for the same date doesn't consume twice.
  static bool applyIfAvailable(DateTime skippedDate) {
    final skippedStr = _dateStr(skippedDate);
    final alreadyUsed = AppStorage.streakFreezeUsedDate == skippedStr;

    if (alreadyUsed) return true; // previously applied — still counts

    if (AppStorage.streakFreezeCount > 0) {
      AppStorage.setStreakFreezeCount(AppStorage.streakFreezeCount - 1);
      AppStorage.setStreakFreezeUsedDate(skippedStr);
      return true;
    }

    return false;
  }

  /// Whether the user currently has a freeze available.
  static bool get hasFreeze => AppStorage.streakFreezeCount > 0;

  /// The date for which the freeze was last used, or null.
  static DateTime? get frozenDate {
    final s = AppStorage.streakFreezeUsedDate;
    return s != null ? DateTime.tryParse(s) : null;
  }

  /// True if the freeze is protecting the current streak right now
  /// (i.e. the frozen date was yesterday or 2 days ago).
  static bool get freezeIsActive {
    final fd = frozenDate;
    if (fd == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(fd).inDays;
    return diff <= 2;
  }
}
