import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/config/app_config.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru_RU', null);

  // Lock to portrait — all layouts are designed for vertical
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  
  runApp(
    const ProviderScope(
      child: SportifyApp(),
    ),
  );
}

class SportifyApp extends StatelessWidget {
  const SportifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Sportify',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: AppRouter.router,
      // Clamp system text-scale so large-accessibility settings don't break layouts
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final clampedScale = mq.textScaler.scale(1.0).clamp(0.85, 1.15);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(clampedScale)),
          child: child!,
        );
      },
    );
  }
}
