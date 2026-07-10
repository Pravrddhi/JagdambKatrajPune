import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_endpoints.dart';
import 'bug_report_service.dart';
import 'session_service.dart';

class AuthService {
  static const _storage = FlutterSecureStorage();

  /// Call Django refresh token API with the stored refresh token.
  /// On success, saves new access token to secure storage.
  static Future<bool> refreshAccessToken() async {
    final refreshToken = await _storage.read(key: ApiEndpoints.refreshTokenKey);

    if (refreshToken == null || refreshToken.isEmpty) {
      await SessionService.logoutDueToSessionExpiry();
      return false;
    }

    try {
      final uri = Uri.parse(ApiEndpoints.getRefreshToken);
      final requestBody = jsonEncode({'refresh': refreshToken});

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: requestBody,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newAccessToken = data['access'];
        if (newAccessToken != null && newAccessToken is String) {
          await _storage.write(
            key: ApiEndpoints.accessTokenKey,
            value: newAccessToken,
          );
          return true;
        }
        return false;
      } else {
        await BugReportService.reportApiFailure(
          title: 'Refresh token API failure',
          errorMessage: response.body,
          pageUrl: '/auth/token/refresh',
          statusCode: response.statusCode,
          endpoint: ApiEndpoints.getRefreshToken,
        );
        // Log specific error codes for debugging
        if (response.statusCode == 401) {
          // Refresh token is invalid/expired
          await _storage.delete(key: ApiEndpoints.refreshTokenKey);
          await _storage.delete(key: ApiEndpoints.accessTokenKey);
          await SessionService.logoutDueToSessionExpiry();
        }
        return false;
      }
    } catch (e) {
      await BugReportService.reportApiFailure(
        title: 'Refresh token exception',
        errorMessage: e.toString(),
        pageUrl: '/auth/token/refresh',
        endpoint: ApiEndpoints.getRefreshToken,
      );
      return false;
    }
  }
}
