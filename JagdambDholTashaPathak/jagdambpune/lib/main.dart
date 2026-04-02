import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'providers/feature_flags_provider.dart';
import 'providers/notification_provider.dart';
import 'screens/login_screen.dart';
import 'screens/registration_screen.dart';
import 'screens/reset_pin.dart';
import 'screens/splash_screen.dart';
import 'theme/app_colors.dart';
import 'web/screens/registration_web_screen.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'high_importance_channel',
  'High Importance Notifications',
  description: 'This channel is used for important notifications.',
  importance: Importance.high,
);

const FlutterSecureStorage _bgStorage = FlutterSecureStorage();
const String _notificationStorageKey = 'app_notifications';
bool _firebaseReady = false;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    return;
  }

  final notification = message.notification;
  final title =
      notification?.title ??
      message.data['notification_title']?.toString() ??
      message.data['subject']?.toString() ??
      message.data['title']?.toString() ??
      'Notification';
  final body =
      notification?.body ??
      message.data['message']?.toString() ??
      message.data['body']?.toString() ??
      message.data['notification_body']?.toString() ??
      message.data['text']?.toString() ??
      '';

  // For data-only messages (no notification block) show a local notification
  // so the user sees something even when the app is in background/killed.
  if (notification == null) {
    final bgPlugin = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await bgPlugin.initialize(
      const InitializationSettings(android: androidInit),
    );
    await bgPlugin.show(
      message.hashCode,
      title.isNotEmpty ? title : 'New Notification',
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  final raw = await _bgStorage.read(key: _notificationStorageKey);
  final List<dynamic> list = raw == null || raw.isEmpty
      ? <dynamic>[]
      : (jsonDecode(raw) as List<dynamic>);

  list.insert(0, {
    'id': DateTime.now().microsecondsSinceEpoch.toString(),
    'title': title,
    'message': body,
    'created_at': DateTime.now().toIso8601String(),
  });

  await _bgStorage.write(key: _notificationStorageKey, value: jsonEncode(list));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    _firebaseReady = true;
  } catch (e) {
    _firebaseReady = false;
  }

  if (_firebaseReady) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  if (!kIsWeb) {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await flutterLocalNotificationsPlugin.initialize(initSettings);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FeatureFlagsProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final _FeatureFlagNavigationObserver _featureFlagNavigationObserver =
      _FeatureFlagNavigationObserver(
        onNavigation: () {
          final navContext = _navigatorKey.currentContext;
          if (navContext == null) return;
          navContext.read<FeatureFlagsProvider>().fetchFeatureFlags();
        },
      );

  void _handleIncomingMessage(RemoteMessage message) {
    final notification = message.notification;
    final title =
        notification?.title ??
        message.data['notification_title']?.toString() ??
        message.data['subject']?.toString() ??
        message.data['title']?.toString() ??
        'Notification';
    final body =
        notification?.body ??
        message.data['message']?.toString() ??
        message.data['body']?.toString() ??
        message.data['notification_body']?.toString() ??
        message.data['text']?.toString() ??
        '';

    final provider = context.read<NotificationProvider>();
    provider.addNotification(title: title, message: body);

    if (title.isNotEmpty || body.isNotEmpty) {
      flutterLocalNotificationsPlugin.show(
        message.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (_firebaseReady) {
      FirebaseMessaging.onMessage.listen(_handleIncomingMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleIncomingMessage);
      FirebaseMessaging.instance.getInitialMessage().then((message) {
        if (message != null && mounted) {
          _handleIncomingMessage(message);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<FeatureFlagsProvider>().fetchFeatureFlags(force: true);
      context.read<NotificationProvider>().refreshFromStorage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      navigatorObservers: [_featureFlagNavigationObserver],
      title: 'My App',
      theme: ThemeData(
        primaryColor: AppColors.primaryMaroon,
        scaffoldBackgroundColor: AppColors.primaryMaroon,
        colorScheme: const ColorScheme.light(
          primary: AppColors.accentYellow,
          onPrimary: AppColors.primaryMaroon,
          secondary: AppColors.accentYellow,
          onSecondary: AppColors.primaryMaroon,
          surface: Colors.white,
          onSurface: AppColors.primaryMaroon,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primaryMaroon,
          foregroundColor: AppColors.textLight,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titleTextStyle: const TextStyle(
            color: AppColors.primaryMaroon,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          contentTextStyle: const TextStyle(
            color: AppColors.primaryMaroon,
            fontSize: 15,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            backgroundColor: AppColors.accentYellow,
            foregroundColor: AppColors.primaryMaroon,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.primaryMaroon),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
              color: AppColors.primaryMaroon,
              width: 1.6,
            ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.primaryMaroon),
          ),
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const _FlagGatedAuthRoute(),
        '/resetPin': (context) => const _FlagGatedAuthRoute(),
      },
    );
  }
}

class _FeatureFlagNavigationObserver extends NavigatorObserver {
  final VoidCallback onNavigation;

  _FeatureFlagNavigationObserver({required this.onNavigation});

  bool _shouldRefreshForRoute(Route<dynamic>? route) {
    if (route == null) return false;
    return route is PageRoute<dynamic>;
  }

  void _refreshOnNav(Route<dynamic>? route) {
    if (!_shouldRefreshForRoute(route)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onNavigation();
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _refreshOnNav(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _refreshOnNav(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _refreshOnNav(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _refreshOnNav(previousRoute);
  }
}

class _FlagGatedAuthRoute extends StatelessWidget {
  const _FlagGatedAuthRoute();

  @override
  Widget build(BuildContext context) {
    return Consumer<FeatureFlagsProvider>(
      builder: (_, flagsProvider, __) {
        if (flagsProvider.isLoading && flagsProvider.flags == null) {
          return const Scaffold(
            backgroundColor: AppColors.primaryMaroon,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.accentYellow),
            ),
          );
        }

        final showRegistration = flagsProvider.flags?.showRegistration ?? false;
        return showRegistration
            ? (kIsWeb
                  ? const RegistrationWebScreen()
                  : const RegistrationScreen())
            : const ResetPinScreen();
      },
    );
  }
}
