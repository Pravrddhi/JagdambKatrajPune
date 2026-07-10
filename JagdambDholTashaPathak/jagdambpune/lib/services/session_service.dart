import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/api_endpoints.dart';

class SessionService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static bool _isLoggingOut = false;

  static Future<void> logoutDueToSessionExpiry() async {
    if (_isLoggingOut) return;
    _isLoggingOut = true;

    try {
      await _storage.delete(key: ApiEndpoints.accessTokenKey);
      await _storage.delete(key: ApiEndpoints.refreshTokenKey);

      final navigator = navigatorKey.currentState;
      if (navigator != null) {
        navigator.pushNamedAndRemoveUntil('/login', (route) => false);
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final fallbackNavigator = navigatorKey.currentState;
        if (fallbackNavigator == null) return;
        fallbackNavigator.pushNamedAndRemoveUntil('/login', (route) => false);
      });
    } finally {
      _isLoggingOut = false;
    }
  }
}
