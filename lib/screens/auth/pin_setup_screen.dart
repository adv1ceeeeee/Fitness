import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/services/event_logger.dart';
import 'package:sportwai/services/pin_service.dart';
import 'package:sportwai/widgets/pin_pad.dart';

class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  String? _firstPin;
  String? _errorText;
  final _padKey = GlobalKey<PinPadState>();

  void _onPinComplete(String pin) {
    if (_firstPin == null) {
      // Step 1 — save first entry, ask to confirm
      setState(() {
        _firstPin = pin;
        _errorText = null;
      });
      _padKey.currentState?.reset();
    } else {
      // Step 2 — confirm
      if (pin == _firstPin) {
        _save(pin);
      } else {
        setState(() {
          _firstPin = null;
          _errorText = 'PIN-коды не совпали. Попробуйте снова.';
        });
        _padKey.currentState?.reset();
      }
    }
  }

  Future<void> _save(String pin) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) context.go('/onboarding-check');
      return;
    }
    await PinService.setupPin(pin, userId);
    EventLogger.pinSetup(enabled: true);
    if (mounted) context.go('/onboarding-check');
  }

  @override
  Widget build(BuildContext context) {
    final isConfirm = _firstPin != null;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (isConfirm) {
              // Go back to step 1
              setState(() {
                _firstPin = null;
                _errorText = null;
              });
              _padKey.currentState?.reset();
            } else {
              context.go('/onboarding-check');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 32),
              Text(
                isConfirm ? 'Подтвердите PIN' : 'Создайте PIN-код',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isConfirm
                    ? 'Введите PIN ещё раз для подтверждения'
                    : 'Придумайте 4-значный PIN для быстрого входа',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              PinPad(
                key: _padKey,
                onComplete: _onPinComplete,
                errorText: _errorText,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.go('/onboarding-check'),
                child: const Text(
                  'Пропустить',
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
