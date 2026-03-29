import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_endpoints.dart';
import 'bug_report_service.dart';
import 'refresh_token_service.dart';

class FCMService {
  static const FlutterSecureStorage storage = FlutterSecureStorage();
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static bool _isRefreshListenerAttached = false;

  /// Ask user permission to show notifications.
  Future<bool> requestNotificationPermission() async {
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final isGranted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;

    if (!isGranted && kDebugMode) {
      print("Notification permission not granted.");
    }

    return isGranted;
  }

  /// Get current FCM token
  /// [isLogin]: if true, do not request permission (already granted)
  Future<String?> getFcmToken({bool isLogin = false}) async {
    if (!isLogin) {
      final granted = await requestNotificationPermission();
      if (!granted) {
        return null;
      }
    }

    // Get the token
    String? token = await _fcm.getToken();
    return token;
  }

  /// Listen for token refresh and send to backend
  void listenTokenRefresh() {
    if (_isRefreshListenerAttached) {
      return;
    }
    _isRefreshListenerAttached = true;

    _fcm.onTokenRefresh.listen((newToken) async {
      if (kDebugMode) print("FCM Token refreshed: $newToken");
      await sendTokenToServer(newToken);
    });
  }

  /// Ensure latest token is sent to backend (useful on app start/login resume)
  Future<void> syncCurrentTokenToServer({bool isLogin = true}) async {
    final token = await getFcmToken(isLogin: isLogin);
    if (token == null || token.isEmpty) {
      return;
    }
    await sendTokenToServer(token);
  }

  /// Subscribe to a topic
  Future<void> subscribeToTopic(String topic) async {
    await _fcm.subscribeToTopic(topic);
    if (kDebugMode) print("Subscribed to topic: $topic");
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    await _fcm.unsubscribeFromTopic(topic);
    if (kDebugMode) print("Unsubscribed from topic: $topic");
  }

  /// Send FCM token to backend
  Future<void> sendTokenToServer(String token) async {
    try {
      if (token.isEmpty) {
        if (kDebugMode) {
          print("FCM token is empty, skipping update-fcm-token call.");
        }
        return;
      }

      String? accessToken = await storage.read(
        key: ApiEndpoints.accessTokenKey,
      );
      if (accessToken == null || accessToken.isEmpty) {
        if (kDebugMode) print("Access token not found, cannot send FCM token.");
        return;
      }

      http.Response response = await _updateFcmTokenWithPatch(
        accessToken,
        token,
      );

      if (response.statusCode == 401) {
        final refreshed = await AuthService.refreshAccessToken();
        if (refreshed) {
          final newAccessToken = await storage.read(
            key: ApiEndpoints.accessTokenKey,
          );
          if (newAccessToken != null && newAccessToken.isNotEmpty) {
            response = await _updateFcmTokenWithPatch(newAccessToken, token);
          }
        }
      }

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        final bool isSuccess =
            decoded is Map<String, dynamic> &&
            (decoded['status'] == true || decoded['fcm_token'] != null);

        if (isSuccess) {
          if (kDebugMode) {
            print(
              "FCM token synced successfully: ${decoded['message'] ?? 'FCM token updated successfully.'}",
            );
          }
        } else {
          if (kDebugMode) {
            print("FCM token update response invalid: ${response.body}");
          }
        }
      } else {
        await BugReportService.reportApiFailure(
          title: 'FCM token update API failed',
          errorMessage: response.body,
          pageUrl: '/notifications/update-fcm-token',
          statusCode: response.statusCode,
          endpoint: ApiEndpoints.updateFCMToken,
        );
        if (kDebugMode) {
          print(
            "Failed to sync FCM token. Status: ${response.statusCode}, Body: ${response.body}",
          );
        }
      }
    } catch (e) {
      await BugReportService.reportApiFailure(
        title: 'FCM token update API exception',
        errorMessage: e.toString(),
        pageUrl: '/notifications/update-fcm-token',
        endpoint: ApiEndpoints.updateFCMToken,
      );
      if (kDebugMode) {
        print("Error sending FCM token to server: $e");
      }
    }
  }

  Future<http.Response> _updateFcmTokenWithPatch(
    String accessToken,
    String token,
  ) {
    return http.patch(
      Uri.parse(ApiEndpoints.updateFCMToken),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'fcm_token': token}),
    );
  }
}
