import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OnboardingCheckScreen extends StatefulWidget {
  const OnboardingCheckScreen({super.key});

  @override
  State<OnboardingCheckScreen> createState() => _OnboardingCheckScreenState();
}

class _OnboardingCheckScreenState extends State<OnboardingCheckScreen> {
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _hasError = false);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) context.go('/');
        return;
      }

      // Если флаг уже выставлен — онбординг уже был пройден
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool('onboarding_done') ?? false;
      if (done) {
        if (mounted) context.go('/home');
        return;
      }

      final profile = await Supabase.instance.client
          .from('profiles')
          .select('goal')
          .eq('id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;
      if (profile != null && profile['goal'] != null) {
        // Профиль уже заполнен — выставляем флаг и идём домой
        await prefs.setBool('onboarding_done', true);
        if (mounted) context.go('/home');
      } else {
        context.go('/onboarding');
      }
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Не удалось подключиться к серверу',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _check,
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
