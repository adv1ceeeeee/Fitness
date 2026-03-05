import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/services/auth_service.dart';
import 'package:sportwai/services/pin_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<String?> _emailFromNickname(String nickname) async {
    final res = await Supabase.instance.client
        .rpc('get_email_by_nickname', params: {'p_nickname': nickname});
    if (res == null) return null;
    if (res is String && res.isNotEmpty) return res;
    return null;
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      try {
        final login = _loginController.text.trim();
        String email = login;
        if (!login.contains('@')) {
          final lookup = await _emailFromNickname(login);
          if (lookup == null) {
            throw Exception('Ник не найден');
          }
          email = lookup;
        }
        await AuthService.signIn(
          email,
          _passwordController.text,
        );
        if (mounted) context.go('/onboarding-check');
      } catch (e) {
        final msg = e.toString();
        String userMsg;
        if (msg.contains('Email not confirmed') || msg.contains('not confirmed')) {
          userMsg = 'Email не подтверждён. Проверьте почту и спам.';
        } else if (msg.contains('Ник не найден')) {
          userMsg = 'Ник не найден. Попробуйте email или зарегистрируйтесь.';
        } else {
          userMsg = 'Неверный логин или пароль. Попробуйте снова.';
        }
        setState(() => _errorMessage = userMsg);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(context.rPad),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                const Text(
                  'Вход',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 32),
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _loginController,
                  keyboardType: TextInputType.text,
                  decoration: const InputDecoration(
                    labelText: 'Email или ник',
                    hintText: 'example@mail.com или ironman_98',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Введите email или ник';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Пароль',
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Введите пароль';
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Войти'),
                  ),
                ),
                FutureBuilder<bool>(
                  future: PinService.hasPin(),
                  builder: (context, snap) {
                    if (snap.data != true) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextButton(
                        onPressed: () => context.push('/pin-login'),
                        child: const Text(
                          'Войти по PIN-коду',
                          style: TextStyle(color: AppColors.accent),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Нет аккаунта?',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    ),
                    TextButton(
                      onPressed: () => context.pushReplacement('/register'),
                      child: const Text(
                        'Создать',
                        style: TextStyle(color: AppColors.accent, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
