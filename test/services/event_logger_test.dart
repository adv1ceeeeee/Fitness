import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/services/event_logger.dart';

// Note: EventLogger depends on AuthService.currentUser and Supabase client,
// which require full initialization unavailable in unit tests.
// We test only the observable surface that doesn't touch Supabase.

void main() {
  group('EventLogger', () {
    test('queueLength starts at zero', () {
      expect(EventLogger.queueLength, 0);
    });

    test('queueLength is a non-negative integer', () {
      expect(EventLogger.queueLength, isA<int>());
      expect(EventLogger.queueLength, greaterThanOrEqualTo(0));
    });
  });
}
