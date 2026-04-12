import 'dart:convert';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/api_endpoints.dart';
import 'bug_report_service.dart';
import 'refresh_token_service.dart';

class FCMService {
  static const FlutterSecureStorage storage = FlutterSecureStorage();
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static bool _isRefreshListenerAttached = false;
  static const String _cachedFcmTokenKey = 'cached_fcm_token';
  static const String _webVapidKey = String.fromEnvironment(
    'FIREBASE_WEB_VAPID_KEY',
    defaultValue:
        'BHabFcp7zlBBZhkM_PiiHdGBji4v8Rpm-iG4ZLqxfHGGqCWLT2_EWv1pdpB-TqRlQ_MOE-QP0x7OOQaVGpKCZLk',
  );

  Future<String?> _waitForApnsToken() async {
    for (var attempt = 0; attempt < 8; attempt++) {
      final apnsToken = await _fcm.getAPNSToken();
      if (apnsToken != null && apnsToken.isNotEmpty) {
        print('[FCM] APNS token available on attempt=${attempt + 1}');
        return apnsToken;
      }

      print('[FCM] APNS token not ready attempt=${attempt + 1}');
      await Future.delayed(const Duration(milliseconds: 500));
    }

    print('[FCM] APNS token unavailable after retries');
    return null;
  }

  /// Ask user permission to show notifications.
  Future<bool> requestNotificationPermission() async {
    print('[FCM] requestNotificationPermission called kIsWeb=$kIsWeb');
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final isGranted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;

    print(
      '[FCM] requestNotificationPermission result: isGranted=$isGranted status=${settings.authorizationStatus}',
    );
    return isGranted;
  }

  /// Get current FCM token
  /// [isLogin]: if true, do not request permission (already granted)
  Future<String?> getFcmToken({bool isLogin = false}) async {
    print('[FCM] getFcmToken start isLogin=$isLogin isWeb=$kIsWeb');
    if (!isLogin) {
      final granted = await requestNotificationPermission();
      print('[FCM] notification permission granted=$granted');
      if (!granted) {
        print('[FCM] token fetch aborted: permission not granted');
        return null;
      }
    }

    // Get the token
    String? token;
    try {
      if (kIsWeb) {
        if (_webVapidKey.trim().isEmpty) {
          await BugReportService.reportApiFailure(
            title: 'Missing web VAPID key for FCM token',
            errorMessage:
                'FIREBASE_WEB_VAPID_KEY dart-define is empty. Web FCM token cannot be generated.',
            pageUrl: '/notifications/update-fcm-token',
            endpoint: ApiEndpoints.updateFCMToken,
          );
          return null;
        }
        for (var attempt = 0; attempt < 3; attempt++) {
          print('[FCM] web getToken attempt=${attempt + 1}');
          try {
            token = await _fcm
                .getToken(vapidKey: _webVapidKey)
                .timeout(const Duration(seconds: 10));
            print(
              '[FCM] web getToken attempt=${attempt + 1} result=${token == null || token.isEmpty ? 'empty' : 'ok'}',
            );
          } catch (e) {
            print('[FCM] web getToken attempt=${attempt + 1} exception=$e');
          }
          if (token != null && token.isNotEmpty) {
            break;
          }
          await Future.delayed(const Duration(milliseconds: 800));
        }
      } else {
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          final apnsToken = await _waitForApnsToken();
          if (apnsToken == null || apnsToken.isEmpty) {
            return null;
          }
        }

        token = await _fcm.getToken();
      }
    } catch (e) {
      final message = e.toString();
      if (message.contains('apns-token-not-set')) {
        print('[FCM] getToken skipped: APNS token not set yet');
        return null;
      }
      rethrow;
    }

    if (token != null && token.isNotEmpty) {
      await storage.write(key: _cachedFcmTokenKey, value: token);
      print('[FCM] token fetched length=${token.length}');
    } else {
      print('[FCM] token fetch returned null/empty');
    }
    return token;
  }

  /// Listen for token refresh and send to backend
  void listenTokenRefresh() {
    if (_isRefreshListenerAttached) {
      return;
    }
    _isRefreshListenerAttached = true;

    _fcm.onTokenRefresh.listen((newToken) async {
      if (newToken.isNotEmpty) {
        await storage.write(key: _cachedFcmTokenKey, value: newToken);
      }
      await sendTokenToServer(newToken);
    });
  }

  /// Ensure latest token is sent to backend (useful on app start/login resume)
  Future<bool> syncCurrentTokenToServer({bool isLogin = true}) async {
    print(
      '[FCM] syncCurrentTokenToServer start isLogin=$isLogin kIsWeb=$kIsWeb',
    );
    String? token;
    try {
      token = await getFcmToken(isLogin: isLogin);
    } catch (e) {
      print('[FCM] syncCurrentTokenToServer token fetch exception=$e');
    }
    print(
      '[FCM] getFcmToken result: ${token == null ? 'null' : 'token length=${token.length}'}',
    );
    if (token != null && token.isNotEmpty) {
      print('[FCM] sync using fresh token length=${token.length}');
      await sendTokenToServer(token);
      return true;
    }

    final cachedToken = await storage.read(key: _cachedFcmTokenKey);
    print(
      '[FCM] cached token: ${cachedToken == null ? 'null' : 'length=${cachedToken.length}'}',
    );
    if (cachedToken != null && cachedToken.isNotEmpty) {
      print('[FCM] sync using cached token length=${cachedToken.length}');
      await sendTokenToServer(cachedToken);
      return true;
    } else {
      print('[FCM] sync skipped: no fresh or cached token');
    }

    return false;
  }

  /// Subscribe to a topic
  Future<void> subscribeToTopic(String topic) async {
    await _fcm.subscribeToTopic(topic);
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    await _fcm.unsubscribeFromTopic(topic);
  }

  /// Send FCM token to backend
  Future<void> sendTokenToServer(String token) async {
    try {
      print('[FCM] sendTokenToServer called tokenLength=${token.length}');
      if (token.isEmpty) {
        print('[FCM] sendTokenToServer skipped: empty token');
        return;
      }

      String? accessToken = await storage.read(
        key: ApiEndpoints.accessTokenKey,
      );
      print(
        '[FCM] retrieved accessToken from storage: ${accessToken == null ? 'null' : 'length=${accessToken.length}'}',
      );
      if (accessToken == null || accessToken.isEmpty) {
        print('[FCM] sendTokenToServer skipped: missing access token');
        return;
      }

      print(
        '[FCM] calling ${ApiEndpoints.updateFCMToken} with token length=${token.length}',
      );

      http.Response response = await _updateFcmToken(accessToken, token);
      print(
        '[FCM] update-fcm-token response received: statusCode=${response.statusCode}',
      );
      debugPrint(
        '[FCM] update-fcm-token response: ${response.statusCode} ${response.body}',
      );

      if (response.statusCode == 401) {
        print('[FCM] Token expired (401), attempting refresh...');
        final refreshed = await AuthService.refreshAccessToken();
        if (refreshed) {
          final newAccessToken = await storage.read(
            key: ApiEndpoints.accessTokenKey,
          );
          if (newAccessToken != null && newAccessToken.isNotEmpty) {
            response = await _updateFcmToken(newAccessToken, token);
            print(
              '[FCM] update-fcm-token retry response: ${response.statusCode}',
            );
            debugPrint(
              '[FCM] update-fcm-token retry response: ${response.statusCode} ${response.body}',
            );
          }
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        print('[FCM] API returned error: ${response.statusCode}');
        await BugReportService.reportApiFailure(
          title: 'FCM token update API failed',
          errorMessage: response.body,
          pageUrl: '/notifications/update-fcm-token',
          statusCode: response.statusCode,
          endpoint: ApiEndpoints.updateFCMToken,
        );
      } else {
        print('[FCM] Token successfully sent to backend');
      }
    } catch (e) {
      print('[FCM] update-fcm-token exception caught: $e');
      debugPrint('[FCM] update-fcm-token exception: $e');
      await BugReportService.reportApiFailure(
        title: 'FCM token update API exception',
        errorMessage: e.toString(),
        pageUrl: '/notifications/update-fcm-token',
        endpoint: ApiEndpoints.updateFCMToken,
      );
    }
  }

  Future<http.Response> _updateFcmToken(
    String accessToken,
    String token,
  ) async {
    final response = await http.patch(
      Uri.parse(ApiEndpoints.updateFCMToken),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'fcm_token': token}),
    );

    return response;
  }
}
