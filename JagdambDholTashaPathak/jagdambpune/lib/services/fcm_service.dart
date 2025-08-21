import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_endpoints.dart';

class FCMService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final storage = FlutterSecureStorage();

  /// Get current FCM token
  /// [isLogin]: if true, do not request permission (already granted)
  Future<String?> getFcmToken({bool isLogin = false}) async {
    if (!isLogin) {
      // Request permission (important for iOS)
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        if (kDebugMode) print("Notification permission not granted.");
        return null;
      }
    }

    // Get the token
    String? token = await _fcm.getToken();
    return token;
  }

  /// Listen for token refresh and send to backend
  void listenTokenRefresh() {
    _fcm.onTokenRefresh.listen((newToken) async {
      if (kDebugMode) print("FCM Token refreshed: $newToken");
      await sendTokenToServer(newToken);
    });
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
      String? accessToken = await storage.read(key: 'access_token');
      if (accessToken == null) {
        if (kDebugMode) print("Access token not found, cannot send FCM token.");
        return;
      }

      final response = await http.put(
        Uri.parse(ApiEndpoints.updateFCMToken),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'fcm_token': token}),
      );
      print(response.statusCode);
      if (response.statusCode == 200) {
        if (kDebugMode) print("Token sent to server successfully.");
      } else {
        if (kDebugMode) print("Failed to send token");
      }
    } catch (e) {
      if (kDebugMode) print("Error sending token to server: $e");
    }
  }
}
