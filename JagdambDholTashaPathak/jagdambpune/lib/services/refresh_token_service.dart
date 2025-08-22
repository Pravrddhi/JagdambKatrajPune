import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_endpoints.dart';

class AuthService {
  static const _storage = FlutterSecureStorage();

  /// Call Django refresh token API with the stored refresh token.
  /// On success, saves new access token to secure storage.
  static Future<bool> refreshAccessToken() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.getRefreshToken),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newAccessToken = data['access'];
        if (newAccessToken != null) {
          await _storage.write(key: 'access_token', value: newAccessToken);
          return true;
        }
        return false;
      } else {
        // Optionally parse error detail here
        return false;
      }
    } catch (e) {
      // Handle network or parsing errors
      return false;
    }
  }
}
