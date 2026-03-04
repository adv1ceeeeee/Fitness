import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/services/pin_service.dart';
import 'package:sportwai/widgets/pin_pad.dart';

class PinLoginScreen extends StatefulWidget {
  const PinLoginScreen({super.key});

  @override
  State<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends State<PinLoginScreen> {
  String? _errorText;
  bool _blocked = false;
  final _padKey = GlobalKey<PinPadState>();

  String get _nickname {
    final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
    return meta?['nickname'] as String? ?? '';
  }

  Future<void> _onPinComplete(String pin) async {
    final attempts = await PinService.getFailedAttempts();
    if (attempts >= PinService.maxAttempts) {
      setState(() => _blocked = true);
      return;
    }

    final correct = await PinService.verifyPin(pin);
    if (!correct) {
      await PinService.incrementFailed();
      final newAttempts = await PinService.getFailedAttempts();
      final remaining = PinService.maxAttempts - newAttempts;
      if (mounted) {
        setState(() {
          _errorText = remaining > 0
              ? 'Неверный PIN. Осталось попыток: $remaining'
              : 'Превышено число попыток.';
          _blocked = remaining <= 0;
        });
        _padKey.currentState?.reset();
      }
      return;
    }

    // PIN correct
    await PinService.resetFailed();

    // Check if Supabase session is still alive
    final session = Supabase.instance.client.auth.currentSession;
    if (!mounted) return;

    if (session != null) {
      context.go('/onboarding-check');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сессия истекла. Войдите с паролем.'),
        ),
      );
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 48),
              // Avatar placeholder
              CircleAvatar(
                radius: 36,
                backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                child: const Icon(
                  Icons.person_rounded,
                  size: 40,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 16),
              if (_nickname.isNotEmpty)
                Text(
                  'Привет, $_nickname!',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              const SizedBox(height: 4),
              const Text(
                'Введите PIN-код для входа',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 40),
              if (_blocked)
                const Column(
                  children: [
                    Icon(Icons.lock_outline,
                        size: 48, color: AppColors.error),
                    SizedBox(height: 12),
                    Text(
                      'PIN заблокирован.\nВойдите с паролем.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.error,
                        fontSize: 16,
                      ),
                    ),
                  ],
                )
              else
                PinPad(
                  key: _padKey,
                  onComplete: _onPinComplete,
                  errorText: _errorText,
                ),
              const Spacer(),
              TextButton(
                onPressed: () => context.go('/login'),
                child: const Text(
                  'Войти с паролем',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
