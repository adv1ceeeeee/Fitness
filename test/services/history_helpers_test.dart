import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/screens/history/history_screen.dart';

void main() {
  group('formatSessionDuration', () {
    test('returns minutes only when under 1 hour', () {
      expect(formatSessionDuration(0), '0мин');
      expect(formatSessionDuration(60), '1мин');
      expect(formatSessionDuration(45 * 60), '45мин');
      expect(formatSessionDuration(3599), '59мин');
    });

    test('returns hours and minutes when 1 hour or more', () {
      expect(formatSessionDuration(3600), '1ч 0мин');
      expect(formatSessionDuration(3660), '1ч 1мин');
      expect(formatSessionDuration(5400), '1ч 30мин');
      expect(formatSessionDuration(7200), '2ч 0мин');
      expect(formatSessionDuration(7320), '2ч 2мин');
    });

    test('handles exactly 1 hour boundary', () {
      expect(formatSessionDuration(3599), '59мин');
      expect(formatSessionDuration(3600), '1ч 0мин');
    });
  });

  group('weekdayShort', () {
    test('maps Monday=1 to Пн', () => expect(weekdayShort(1), 'Пн'));
    test('maps Tuesday=2 to Вт', () => expect(weekdayShort(2), 'Вт'));
    test('maps Wednesday=3 to Ср', () => expect(weekdayShort(3), 'Ср'));
    test('maps Thursday=4 to Чт', () => expect(weekdayShort(4), 'Чт'));
    test('maps Friday=5 to Пт', () => expect(weekdayShort(5), 'Пт'));
    test('maps Saturday=6 to Сб', () => expect(weekdayShort(6), 'Сб'));
    test('maps Sunday=7 to Вс', () => expect(weekdayShort(7), 'Вс'));
    test('out of range returns empty string', () {
      expect(weekdayShort(0), '');
      expect(weekdayShort(8), '');
    });
  });
}
