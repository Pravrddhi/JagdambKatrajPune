import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';
import 'providers/feature_flags_provider.dart';
import 'providers/notification_provider.dart';
import 'screens/login_screen.dart';
import 'screens/registration_screen.dart';
import 'screens/reset_pin.dart';
import 'screens/splash_screen.dart';
import 'config/app_config.dart';
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
  String? _appVersion;
  bool _isShowingUpdateDialog = false;
  FeatureFlagsProvider? _featureFlagsProvider;

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
    _loadAppVersion();
    try {
      _featureFlagsProvider = context.read<FeatureFlagsProvider>();
      _featureFlagsProvider?.addListener(_onFeatureFlagsChanged);
    } catch (_) {
      _featureFlagsProvider = null;
    }

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
  }

  Future<void> _loadAppVersion() async {
    if (kIsWeb) return;
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      _appVersion = info.version;
      await _maybeShowUpdateDialog();
    } catch (_) {
      // If package info fails we skip forced-update check for this session.
    }
  }

  void _onFeatureFlagsChanged() {
    _maybeShowUpdateDialog();
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

  Future<void> _maybeShowUpdateDialog() async {
    if (!mounted || _isShowingUpdateDialog) {
      return;
    }

    final flags = context.read<FeatureFlagsProvider>().flags;
    if (flags == null) return;

    final dialogContext = _rootNavigatorKey.currentContext ?? context;

    if (kIsWeb) {
      final shouldShowWebUpdateNotice =
          (flags.updateMessage?.trim().isNotEmpty ?? false) ||
          flags.forceUpdateAndroid ||
          flags.forceUpdateIos ||
          (flags.minAndroidVersion?.trim().isNotEmpty ?? false) ||
          (flags.minIosVersion?.trim().isNotEmpty ?? false);

      if (!shouldShowWebUpdateNotice) return;

      _isShowingUpdateDialog = true;
      await showDialog<void>(
        context: dialogContext,
        barrierDismissible: true,
        builder: (_) => AlertDialog(
          title: const Text('Update Available'),
          content: Text(flags.updateMessage ?? 'New updates has ben there'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      _isShowingUpdateDialog = false;
      return;
    }

    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    if (!isAndroid && !isIos) return;

    final minVersion = isAndroid
        ? flags.minAndroidVersion
        : flags.minIosVersion;
    final forceFlag = isAndroid
        ? flags.forceUpdateAndroid
        : flags.forceUpdateIos;
    final storeUrl = isAndroid ? flags.androidStoreUrl : flags.iosStoreUrl;

    final requiresByVersion =
        minVersion != null &&
        _appVersion != null &&
        _compareVersions(_appVersion!, minVersion) < 0;
    final requiresUpdate = forceFlag || requiresByVersion;

    if (!requiresUpdate) return;

    _isShowingUpdateDialog = true;

    await showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (_) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          title: const Text('Update Required'),
          content: Text(
            flags.updateMessage ??
                'A new version of the app is available. Please update to continue.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (storeUrl == null || storeUrl.trim().isEmpty) return;
                final uri = Uri.tryParse(storeUrl.trim());
                if (uri == null) return;
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _featureFlagsProvider?.removeListener(_onFeatureFlagsChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<FeatureFlagsProvider>().fetchFeatureFlags(force: true);
      context.read<NotificationProvider>().fetchFromBackend(
        page: 1,
        pageSize: 20,
      );
      _maybeShowUpdateDialog();
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
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const _FlagGatedAuthRoute(),
        '/resetPin': (context) => const ResetPinScreen(),
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
