import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/feature_flags.dart';
import '../config/api_endpoints.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'refresh_token_service.dart'; // Import your AuthService that handles token refresh

class ApiService {
  static final _storage = const FlutterSecureStorage();

  static Future<FeatureFlags> fetchFeatureFlags() async {
    String? storedAccessToken = await _storage.read(key: 'access_token');

    final response = await _fetchFeatureFlagsWithToken(storedAccessToken);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return FeatureFlags.fromJson(data['featureFlags']);
    } else if (response.statusCode == 401) {
      final errorData = jsonDecode(response.body);
      if (errorData['code'] == 'token_not_valid' &&
          errorData['messages'] != null &&
          errorData['messages'][0]?['message']
                  .toString()
                  .toLowerCase()
                  .contains('expired') ==
              true) {
        // Token expired, attempt refresh
        bool refreshed = await AuthService.refreshAccessToken();
        if (refreshed) {
          // Retry with new access token
          storedAccessToken = await _storage.read(key: 'access_token');
          final retryResponse = await _fetchFeatureFlagsWithToken(
            storedAccessToken,
          );

          if (retryResponse.statusCode == 200) {
            final data = jsonDecode(retryResponse.body);
            return FeatureFlags.fromJson(data['featureFlags']);
          } else {
            throw Exception(
              "Failed to load feature flags after token refresh.",
            );
          }
        } else {
          throw Exception("Session expired. Please login again.");
        }
      } else {
        throw Exception("Authorization error: ${errorData['detail']}");
      }
    } else {
      throw Exception(
        "Failed to load feature flags (status code ${response.statusCode})",
      );
    }
  }

  static Future<http.Response> _fetchFeatureFlagsWithToken(String? token) {
    return http.get(
      Uri.parse(ApiEndpoints.featureFlags),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
  }
}
