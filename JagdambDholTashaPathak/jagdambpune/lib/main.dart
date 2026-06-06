import 'dart:convert';
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:new_version_plus/new_version_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';
import 'providers/feature_flags_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/request_counts_provider.dart';
import 'screens/login_screen.dart';
import 'screens/registration_screen.dart';
import 'screens/reset_pin.dart';
import 'screens/splash_screen.dart';
import 'config/app_config.dart';
import 'theme/app_colors.dart';
import 'web/screens/registration_web_screen.dart';
import 'web/screens/new_registration_web_screen.dart';

// Web-only FCM bridge (conditional compilation for web platform)
import 'web/fcm_web_bridge_stub.dart'
    if (dart.library.html) 'web/fcm_web_bridge_web.dart';

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
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

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
  if (kIsWeb) {
    usePathUrlStrategy();
  }
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    _firebaseReady = true;
  } catch (e) {
    _firebaseReady = false;
  }

  if (_firebaseReady && !kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  if (!kIsWeb) {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
    );
    await flutterLocalNotificationsPlugin.initialize(initSettings);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FeatureFlagsProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => RequestCountsProvider()),
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
  static const Duration _updateCheckCooldown = Duration(minutes: 5);
  static const Duration _updateCheckTimeout = Duration(seconds: 10);

  String? _appVersion;
  String? _packageName;
  bool _isShowingUpdateDialog = false;
  bool _isUpdateCheckInProgress = false;
  DateTime? _lastUpdateCheckAt;

  bool get _isAndroidRuntime =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool _isNewRegistrationRouteName(String? rawRouteName) {
    if (rawRouteName == null || rawRouteName.trim().isEmpty) {
      return false;
    }

    final routeName = rawRouteName.trim();
    final normalized = routeName.split('#').first;

    final parsed = Uri.tryParse(normalized);
    final path = (parsed?.path ?? normalized).trim();
    final noTrailingSlash = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;

    return noTrailingSlash == '/new_registration' ||
        noTrailingSlash.contains('/new_registration');
  }

  MaterialPageRoute<void> _newRegistrationRoute() {
    return MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/new_registration'),
      builder: (_) => const NewRegistrationWebScreen(),
    );
  }

  String _resolveInitialRoute() {
    if (!kIsWeb) {
      return '/';
    }

    final path = Uri.base.path.trim();
    if (_isNewRegistrationRouteName(path)) {
      return '/new_registration';
    }
    return '/';
  }

  Future<void> _handleIncomingMessage(RemoteMessage message) async {
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
    if (kIsWeb) {
      await provider.addNotification(title: title, message: body);
    } else {
      provider.addNotification(title: title, message: body);
    }

    if (!kIsWeb && (title.isNotEmpty || body.isNotEmpty)) {
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
    if (_isAndroidRuntime) {
      unawaited(_loadAppVersion());
    }

    // Setup Firebase message listeners for mobile
    if (_firebaseReady && !kIsWeb) {
      FirebaseMessaging.onMessage.listen((message) {
        _handleIncomingMessage(message);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _handleIncomingMessage(message);
      });
      FirebaseMessaging.instance.getInitialMessage().then((message) {
        if (message != null && mounted) {
          _handleIncomingMessage(message);
        }
      });
    }

    // Setup web FCM bridge to listen for messages from service worker
    if (_firebaseReady && kIsWeb) {
      FirebaseMessaging.onMessage.listen((message) {
        _handleIncomingMessage(message);
      });

      initializeWebFcmBridge((title, body) async {
        if (mounted) {
          final provider = context.read<NotificationProvider>();
          await provider.addNotification(title: title, message: body);
        }
      });
    }
  }

  Future<void> _loadAppVersion() async {
    if (!_isAndroidRuntime) return;
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      _appVersion = info.version;
      _packageName = info.packageName;
      await _maybeShowPlayStoreForceUpdateDialog(force: true);
    } catch (_) {
      // If package info fails we skip forced-update check for this session.
    }
  }

  Future<BuildContext?> _resolveDialogContext() async {
    if (!mounted) return null;

    final direct = _rootNavigatorKey.currentContext;
    if (direct != null) {
      return direct;
    }

    // During app startup navigator context may not be ready yet.
    for (var i = 0; i < 3; i++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return null;
      final next = _rootNavigatorKey.currentContext;
      if (next != null) {
        return next;
      }
    }

    return mounted ? context : null;
  }

  Future<void> _openPlayStoreLink({
    required String packageName,
    required String appStoreLink,
  }) async {
    final raw = appStoreLink.trim();
    final fallbackWeb = Uri.parse(
      'https://play.google.com/store/apps/details?id=$packageName',
    );
    final fallbackMarket = Uri.parse('market://details?id=$packageName');

    Future<bool> tryLaunch(Uri uri) async {
      try {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }

    if (raw.isNotEmpty) {
      final primary = Uri.tryParse(raw);
      if (primary != null && await tryLaunch(primary)) {
        return;
      }
    }

    if (await tryLaunch(fallbackMarket)) {
      return;
    }
    await tryLaunch(fallbackWeb);
  }

  Future<void> _maybeShowPlayStoreForceUpdateDialog({
    bool force = false,
  }) async {
    if (!_isAndroidRuntime || !mounted || _isShowingUpdateDialog) {
      return;
    }
    if (_isUpdateCheckInProgress) {
      return;
    }

    final now = DateTime.now();
    if (!force && _lastUpdateCheckAt != null) {
      final elapsed = now.difference(_lastUpdateCheckAt!);
      if (elapsed < _updateCheckCooldown) {
        return;
      }
    }

    _lastUpdateCheckAt = now;
    _isUpdateCheckInProgress = true;

    final packageName = _packageName;
    final appVersion = _appVersion;
    if (packageName == null ||
        packageName.trim().isEmpty ||
        appVersion == null) {
      return;
    }

    try {
      final newVersion = NewVersionPlus(androidId: packageName.trim());
      final status = await newVersion.getVersionStatus().timeout(
        _updateCheckTimeout,
      );
      if (status == null) return;

      final storeVersion = status.storeVersion.trim();
      if (storeVersion.isEmpty) return;

      final shouldForceUpdate =
          _compareVersions(appVersion, storeVersion) < 0 || status.canUpdate;
      if (!shouldForceUpdate) return;

      final dialogContext = await _resolveDialogContext();
      if (dialogContext == null || !mounted) return;

      _isShowingUpdateDialog = true;

      await showDialog<void>(
        context: dialogContext,
        barrierDismissible: false,
        builder: (_) => WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            title: const Text('Update Required'),
            content: Text(
              'A newer version ($storeVersion) is available on Play Store. '
              'Please update to continue using the app.',
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await _openPlayStoreLink(
                    packageName: packageName.trim(),
                    appStoreLink: status.appStoreLink,
                  );
                },
                child: const Text('Update'),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      // Ignore Play Store lookup failures for this check cycle.
    } finally {
      _isUpdateCheckInProgress = false;
      _isShowingUpdateDialog = false;
    }
  }

  int _compareVersions(String current, String required) {
    final currentParts = current
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final requiredParts = required
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();

    final maxLen = currentParts.length > requiredParts.length
        ? currentParts.length
        : requiredParts.length;

    for (var i = 0; i < maxLen; i++) {
      final a = i < currentParts.length ? currentParts[i] : 0;
      final b = i < requiredParts.length ? requiredParts[i] : 0;
      if (a < b) return -1;
      if (a > b) return 1;
    }
    return 0;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isAndroidRuntime) return;
    if (state == AppLifecycleState.resumed) {
      context.read<FeatureFlagsProvider>().fetchFeatureFlags(force: true);
      context.read<NotificationProvider>().fetchFromBackend(
        page: 1,
        pageSize: 20,
      );
      unawaited(_maybeShowPlayStoreForceUpdateDialog());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _rootNavigatorKey,
      title: AppConfig.appTitle,
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
      initialRoute: _resolveInitialRoute(),
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const _FlagGatedAuthRoute(),
        '/new_registration': (context) => const NewRegistrationWebScreen(),
        '/new_registration/': (context) => const NewRegistrationWebScreen(),
        '/resetPin': (context) => const ResetPinScreen(),
      },
      onGenerateRoute: (settings) {
        if (_isNewRegistrationRouteName(settings.name)) {
          return _newRegistrationRoute();
        }
        return null;
      },
      onUnknownRoute: (settings) {
        if (_isNewRegistrationRouteName(settings.name)) {
          return _newRegistrationRoute();
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const SplashScreen(),
        );
      },
    );
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
