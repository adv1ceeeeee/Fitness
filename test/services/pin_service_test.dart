import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/services/pin_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('PinService — brute-force protection', () {
    test('maxAttempts constant is 5', () {
      expect(PinService.maxAttempts, 5);
    });

    test('getFailedAttempts returns 0 initially', () async {
      expect(await PinService.getFailedAttempts(), 0);
    });

    test('incrementFailed increases count by 1 each call', () async {
      await PinService.incrementFailed();
      expect(await PinService.getFailedAttempts(), 1);

      await PinService.incrementFailed();
      expect(await PinService.getFailedAttempts(), 2);
    });

    test('resetFailed sets count back to 0', () async {
      await PinService.incrementFailed();
      await PinService.incrementFailed();
      await PinService.resetFailed();

      expect(await PinService.getFailedAttempts(), 0);
    });

    test('getFailedAttempts returns 0 after reset even if incremented before',
        () async {
      for (var i = 0; i < PinService.maxAttempts; i++) {
        await PinService.incrementFailed();
      }
      await PinService.resetFailed();

      expect(await PinService.getFailedAttempts(), 0);
    });

    test('count reaches maxAttempts after that many increments', () async {
      for (var i = 0; i < PinService.maxAttempts; i++) {
        await PinService.incrementFailed();
      }

      expect(await PinService.getFailedAttempts(), PinService.maxAttempts);
    });

    test('count can exceed maxAttempts if not reset', () async {
      for (var i = 0; i < PinService.maxAttempts + 2; i++) {
        await PinService.incrementFailed();
      }

      expect(
        await PinService.getFailedAttempts(),
        greaterThan(PinService.maxAttempts),
      );
    });

    test('resetFailed is idempotent — calling twice is safe', () async {
      await PinService.resetFailed();
      await PinService.resetFailed();

      expect(await PinService.getFailedAttempts(), 0);
    });

    test('isLockedOut returns false initially', () async {
      expect(await PinService.isLockedOut(), false);
    });

    test('isLockedOut returns true after maxAttempts increments', () async {
      for (var i = 0; i < PinService.maxAttempts; i++) {
        await PinService.incrementFailed();
      }
      expect(await PinService.isLockedOut(), true);
    });

    test('isLockedOut returns false after resetFailed', () async {
      for (var i = 0; i < PinService.maxAttempts; i++) {
        await PinService.incrementFailed();
      }
      await PinService.resetFailed();
      expect(await PinService.isLockedOut(), false);
    });
  });
}
