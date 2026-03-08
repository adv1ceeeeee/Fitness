import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/services/notification_service.dart';

void main() {
  group('timezoneNameForOffset', () {
    test('returns Europe/Kaliningrad for UTC+2', () {
      expect(timezoneNameForOffset(2), 'Europe/Kaliningrad');
    });

    test('returns Europe/Moscow for UTC+3', () {
      expect(timezoneNameForOffset(3), 'Europe/Moscow');
    });

    test('returns Europe/Samara for UTC+4', () {
      expect(timezoneNameForOffset(4), 'Europe/Samara');
    });

    test('returns Asia/Yekaterinburg for UTC+5', () {
      expect(timezoneNameForOffset(5), 'Asia/Yekaterinburg');
    });

    test('returns Asia/Omsk for UTC+6', () {
      expect(timezoneNameForOffset(6), 'Asia/Omsk');
    });

    test('returns Asia/Krasnoyarsk for UTC+7', () {
      expect(timezoneNameForOffset(7), 'Asia/Krasnoyarsk');
    });

    test('returns Asia/Irkutsk for UTC+8', () {
      expect(timezoneNameForOffset(8), 'Asia/Irkutsk');
    });

    test('returns Asia/Yakutsk for UTC+9', () {
      expect(timezoneNameForOffset(9), 'Asia/Yakutsk');
    });

    test('returns Asia/Vladivostok for UTC+10', () {
      expect(timezoneNameForOffset(10), 'Asia/Vladivostok');
    });

    test('returns Asia/Sakhalin for UTC+11', () {
      expect(timezoneNameForOffset(11), 'Asia/Sakhalin');
    });

    test('returns Asia/Kamchatka for UTC+12', () {
      expect(timezoneNameForOffset(12), 'Asia/Kamchatka');
    });

    test('returns UTC for unknown offset', () {
      expect(timezoneNameForOffset(0), 'UTC');
      expect(timezoneNameForOffset(1), 'UTC');
      expect(timezoneNameForOffset(13), 'UTC');
      expect(timezoneNameForOffset(-5), 'UTC');
    });
  });
}
