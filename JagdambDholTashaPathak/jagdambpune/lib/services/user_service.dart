import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_endpoints.dart';
import 'refresh_token_service.dart';

class UserInactiveException implements Exception {
  final String message;

  UserInactiveException([this.message = 'User is inactive']);

  @override
  String toString() => message;
}

class UserService {
  static const _storage = FlutterSecureStorage();

  /// Fetch user details from API using the provided [token].
  /// If token expired, automatically refreshes then retries.
  /// Throws exceptions on failure.
  static Future<Map<String, dynamic>> fetchUserDetails(String token) async {
    final response = await _getUserDetails(token);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      if (data['status'] == true && data['data'] != null) {
        return data['data'];
      } else {
        throw Exception(data['message'] ?? 'Failed to load user details.');
      }
    } else if (response.statusCode == 401) {
      final errorData = jsonDecode(response.body);

      if (errorData['code'] == 'user_inactive') {
        throw UserInactiveException(
          errorData['detail']?.toString() ?? 'User is inactive',
        );
      }

      if (errorData['code'] == 'token_not_valid' &&
          errorData['messages'] != null &&
          errorData['messages'][0]?['message']
                  .toString()
                  .toLowerCase()
                  .contains('expired') ==
              true) {
        // Token expired, try to refresh
        final refreshed = await AuthService.refreshAccessToken();
        if (refreshed) {
          final newToken = await _storage.read(key: 'access_token');
          if (newToken != null) {
            // Retry with new token
            return await fetchUserDetails(newToken);
          }
          throw Exception('Failed to retrieve refreshed token.');
        }
        throw Exception('Session expired. Please log in again.');
      }
      throw Exception('Unauthorized access.');
    } else if (response.statusCode == 403 || response.statusCode == 404) {
      throw Exception('User not found.');
    } else {
      throw Exception(
        'Failed to load user details (Code: ${response.statusCode})',
      );
    }
  }

  /// Internal helper to perform GET request with authorization header
  static Future<http.Response> _getUserDetails(String token) {
    return http.get(
      Uri.parse(ApiEndpoints.getUserDetails),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
  }
}
