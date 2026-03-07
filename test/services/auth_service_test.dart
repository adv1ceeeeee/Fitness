import 'package:flutter_test/flutter_test.dart';
import 'package:sportwai/services/auth_service.dart';

void main() {
  group('AuthService.nicknameToEmail', () {
    test('appends @sportwai.app domain', () {
      expect(AuthService.nicknameToEmail('ivan'), 'ivan@sportwai.app');
    });

    test('lowercases the nickname', () {
      expect(AuthService.nicknameToEmail('IvanIvanov'), 'ivanivanov@sportwai.app');
      expect(AuthService.nicknameToEmail('ADMIN'), 'admin@sportwai.app');
    });

    test('trims whitespace', () {
      expect(AuthService.nicknameToEmail('  ivan  '), 'ivan@sportwai.app');
      expect(AuthService.nicknameToEmail('\tuser\n'), 'user@sportwai.app');
    });

    test('preserves underscores and dots', () {
      expect(AuthService.nicknameToEmail('iron_man.98'), 'iron_man.98@sportwai.app');
    });

    test('preserves digits', () {
      expect(AuthService.nicknameToEmail('user123'), 'user123@sportwai.app');
    });

    test('result is always a valid email pattern', () {
      final nicknames = ['abc', 'test_user', 'MyNick', 'n1k3'];
      for (final nick in nicknames) {
        final email = AuthService.nicknameToEmail(nick);
        expect(email.contains('@'), isTrue);
        expect(email.endsWith('@sportwai.app'), isTrue);
        expect(email.split('@').first.isNotEmpty, isTrue);
      }
    });
  });
}
