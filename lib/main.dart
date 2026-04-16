import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportwai/config/app_config.dart';
import 'package:sportwai/config/theme.dart';
import 'package:sportwai/firebase_options.dart';
import 'package:sportwai/providers/settings_provider.dart';
import 'package:sportwai/router.dart';
import 'package:sportwai/services/auth_service.dart';
import 'package:sportwai/services/device_token_service.dart';
import 'package:sportwai/services/event_logger.dart';
import 'package:sportwai/services/local_storage.dart';
import 'package:sportwai/services/notification_service.dart';
import 'package:sportwai/services/offline_queue_service.dart';
import 'package:sportwai/services/streak_freeze_service.dart';
import 'package:sportwai/services/gamification_service.dart';

bool get _isMobilePlatform =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Initialises Firebase and wires up FCM token registration.
/// Skipped on non-mobile platforms (Windows, etc.) so tests keep passing.
Future<void> _initFcm() async {
  if (!_isMobilePlatform) return;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Foreground message handler (optional — shows local notif if needed)
    FirebaseMessaging.onMessage.listen((_) {});

    // Register / refresh token whenever auth state changes
    Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      if (data.session == null) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await DeviceTokenService.register(token);
    });

    FirebaseMessaging.instance.onTokenRefresh.listen(
      DeviceTokenService.register,
    );
  } catch (e) {
    // Firebase not configured yet — app works fine with local notifications
    if (kDebugMode) debugPrint('[FCM] init skipped: $e');
  }
}

void _setupErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (AppConfig.sentryDsn.isNotEmpty) {
      Sentry.captureException(
        details.exception,
        stackTrace: details.stack,
      );
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    if (kDebugMode) debugPrint('[Uncaught] $error\n$stack');
    if (AppConfig.sentryDsn.isNotEmpty) {
      Sentry.captureException(error, stackTrace: stack);
    }
    return true;
  };
}

Future<void> _initWindowForDesktop() async {
  if (defaultTargetPlatform != TargetPlatform.windows) return;
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(500, 850),
      minimumSize: Size(500, 850),
      maximumSize: Size(500, 850),
      center: true,
      title: 'Sportify',
      backgroundColor: Colors.transparent,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initWindowForDesktop();
  _setupErrorHandlers();
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

  await AppStorage.init();
  StreakFreezeService.maybeRefill();
  await NotificationService.initialize();
  await _initFcm();
  NotificationService.scheduleChurnNotification();
  OfflineQueueService.init();

  // Warm caches on cold start when the user is already authenticated.
  // Fire-and-forget — errors fall back to normal on-demand fetches.
  if (Supabase.instance.client.auth.currentSession != null) {
    AuthService.prefetchOnLogin();
  }

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

void main() async {
  if (AppConfig.sentryDsn.isEmpty) {
    await _bootstrap();
    return;
  }
  await SentryFlutter.init(
    (options) {
      options.dsn = AppConfig.sentryDsn;
      options.tracesSampleRate = 0.2;
    },
    appRunner: _bootstrap,
  );
}

class SportifyApp extends ConsumerStatefulWidget {
  const SportifyApp({super.key});

  @override
  ConsumerState<SportifyApp> createState() => _SportifyAppState();
}

class _SportifyAppState extends ConsumerState<SportifyApp> {
  late final AppLifecycleListener _lifecycleListener;
  DateTime? _foregroundStart;

  @override
  void initState() {
    super.initState();
    _foregroundStart = DateTime.now();
    // Check season decay once on app start
    GamificationService.checkSeasonDecay();
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        _foregroundStart = DateTime.now();
        EventLogger.resetSession();
        EventLogger.appOpened(source: 'resume');
        NotificationService.refreshWeeklySummary();
        NotificationService.scheduleChurnNotification();
      },
      onPause: () {
        _flushForegroundTime();
        EventLogger.flushOnExit();
      },
      onDetach: () {
        _flushForegroundTime();
        EventLogger.flushOnExit();
      },
    );
  }

  void _flushForegroundTime() {
    final start = _foregroundStart;
    if (start == null) return;
    final seconds = DateTime.now().difference(start).inSeconds;
    _foregroundStart = null;
    if (seconds > 0) {
      GamificationService.addActiveTime(seconds);
    }
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Sportify',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
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
