import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_endpoints.dart';
import 'bug_report_service.dart';
import 'refresh_token_service.dart';

class UserService {
  static const _storage = FlutterSecureStorage();

  /// Normalizes profile payloads coming from either flat profile APIs
  /// or login-style wrappers that contain the profile inside `data`.
  static Map<String, dynamic> normalizeUserPayload(Map<String, dynamic> raw) {
    final root = Map<String, dynamic>.from(raw);
    final nested = root['data'] is Map
        ? Map<String, dynamic>.from(root['data'] as Map)
        : <String, dynamic>{};

    final merged = <String, dynamic>{...nested, ...root};

    merged['joining_year'] ??= merged['joiningYear'] ?? merged['joined_year'];
    merged['gat_pramukh_name'] ??= merged['gatPramukhName'];

    return merged;
  }

  /// Fetch user details from API using the provided [token].
  /// If token expired, automatically refreshes then retries.
  /// Throws exceptions on failure.
  static Future<Map<String, dynamic>> fetchUserDetails(String token) async {
    try {
      final response = await _getUserDetails(token);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == true && data['data'] != null) {
          return normalizeUserPayload(Map<String, dynamic>.from(data));
        } else {
          throw Exception(data['message'] ?? 'Failed to load user details.');
        }
      } else if (response.statusCode == 401) {
        final errorData = jsonDecode(response.body);

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
    } catch (e, st) {
      await BugReportService.reportApiFailure(
        title: 'User details API failure',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/profile/get-user-details',
        endpoint: ApiEndpoints.getUserDetails,
      );
      rethrow;
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
