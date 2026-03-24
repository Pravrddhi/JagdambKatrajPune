import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/feature_flags.dart';
import '../models/user.dart';
import '../config/api_endpoints.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'refresh_token_service.dart'; // Import your AuthService that handles token refresh

class ApiService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<FeatureFlags> fetchFeatureFlags() async {
    final response = await _fetchFeatureFlags();

    if (response.statusCode == 200) {
      return _parseFeatureFlagsResponse(response);
    } else {
      throw Exception(
        "Failed to load feature flags (status code ${response.statusCode})",
      );
    }
  }

  static Future<List<User>> fetchAllUsers() async {
    String? storedAccessToken = await _storage.read(
      key: ApiEndpoints.accessTokenKey,
    );

    if (storedAccessToken == null) {
      throw Exception('No access token found. Please login again.');
    }

    final uri = Uri.parse(ApiEndpoints.fetchAllUsers);

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $storedAccessToken',
      },
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);

      if (data['status'] == true && data['users'] is List) {
        final List<dynamic> usersList = data['users'];
        return usersList
            .map((userJson) => User.fromJson(userJson as Map<String, dynamic>))
            .toList();
      }

      throw Exception('Invalid response format for users');
    } else if (response.statusCode == 401) {
      final success = await _handleTokenRefresh();
      if (success) {
        return fetchAllUsers();
      }
      throw Exception('Session expired. Please login again.');
    } else {
      throw Exception(
        'Failed to load users (status code ${response.statusCode})',
      );
    }
  }

  static Future<User> fetchUserById(int userId) async {
    String? storedAccessToken = await _storage.read(
      key: ApiEndpoints.accessTokenKey,
    );

    if (storedAccessToken == null) {
      throw Exception('No access token found. Please login again.');
    }

    final uri = Uri.parse(ApiEndpoints.getUserById(userId));

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $storedAccessToken',
      },
    );

    if (response.statusCode == 200) {
      final dynamic decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        if (decoded['status'] == true &&
            decoded['user'] is Map<String, dynamic>) {
          return User.fromJson(decoded['user'] as Map<String, dynamic>);
        }
        return User.fromJson(decoded);
      }

      throw Exception('Invalid response format for user details');
    } else if (response.statusCode == 401) {
      final success = await _handleTokenRefresh();
      if (success) {
        return fetchUserById(userId);
      }
      throw Exception('Session expired. Please login again.');
    } else {
      throw Exception(
        'Failed to load user details (status code ${response.statusCode})',
      );
    }
  }

  static Future<String> activateUser(int userId) async {
    String? storedAccessToken = await _storage.read(
      key: ApiEndpoints.accessTokenKey,
    );

    if (storedAccessToken == null) {
      throw Exception('No access token found. Please login again.');
    }

    final uri = Uri.parse(ApiEndpoints.getActivateUser(userId));

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $storedAccessToken',
      },
    );

    if (response.statusCode == 200) {
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded['status'] == true) {
        return decoded['message']?.toString() ?? 'User approved';
      }
      throw Exception('Failed to approve user');
    } else if (response.statusCode == 401) {
      final success = await _handleTokenRefresh();
      if (success) {
        return activateUser(userId);
      }
      throw Exception('Session expired. Please login again.');
    } else {
      throw Exception(
        'Failed to approve user (status code ${response.statusCode})',
      );
    }
  }

  static Future<void> sendPersonalNotification({
    required int targetUser,
    required String title,
    required String message,
    String? targetUserPhone,
  }) async {
    String? storedAccessToken = await _storage.read(
      key: ApiEndpoints.accessTokenKey,
    );

    if (storedAccessToken == null) {
      throw Exception('No access token found. Please login again.');
    }

    final uri = Uri.parse(ApiEndpoints.createNotification);

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $storedAccessToken',
    };

    final payloadAttempts = <Map<String, dynamic>>[
      {
        'title': title,
        'message': message,
        'target_type': 'personal',
        'target_user': targetUser,
      },
      {
        'title': title,
        'message': message,
        'target_type': 'personal',
        'target_user_id': targetUser,
      },
    ];

    final trimmedPhone = targetUserPhone?.trim();
    if (trimmedPhone != null && trimmedPhone.isNotEmpty) {
      payloadAttempts.add({
        'title': title,
        'message': message,
        'target_type': 'personal',
        'target_user': trimmedPhone,
      });
      payloadAttempts.add({
        'title': title,
        'message': message,
        'target_type': 'personal',
        'target_phone': trimmedPhone,
      });
    }

    http.Response? response;
    for (final payload in payloadAttempts) {
      response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['status'] == true) {
          return;
        }
      }

      // Retry with the next payload shape only for validation-style failures.
      if (response.statusCode != 400 && response.statusCode != 422) {
        break;
      }
    }

    if (response == null) {
      throw Exception('Failed to send notification');
    }

    if (response.statusCode == 401) {
      final success = await _handleTokenRefresh();
      if (success) {
        return sendPersonalNotification(
          targetUser: targetUser,
          title: title,
          message: message,
          targetUserPhone: targetUserPhone,
        );
      }
      throw Exception('Session expired. Please login again.');
    }

    throw Exception(
      'Failed to send notification (status code ${response.statusCode})',
    );
  }

  static Future<void> sendBroadcastNotification({
    required String title,
    required String message,
  }) async {
    String? storedAccessToken = await _storage.read(
      key: ApiEndpoints.accessTokenKey,
    );

    if (storedAccessToken == null) {
      throw Exception('No access token found. Please login again.');
    }

    final uri = Uri.parse(ApiEndpoints.createNotification);

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $storedAccessToken',
      },
      body: jsonEncode({
        'title': title,
        'message': message,
        'target_type': 'broadcast',
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded['status'] == true) {
        return;
      }
      throw Exception('Failed to send broadcast notification');
    } else if (response.statusCode == 401) {
      final success = await _handleTokenRefresh();
      if (success) {
        return sendBroadcastNotification(title: title, message: message);
      }
      throw Exception('Session expired. Please login again.');
    } else {
      throw Exception(
        'Failed to send broadcast notification (status code ${response.statusCode})',
      );
    }
  }

  static Future<bool> _handleTokenRefresh() async {
    try {
      return await AuthService.refreshAccessToken();
    } catch (e) {
      return false;
    }
  }

  static FeatureFlags _parseFeatureFlagsResponse(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      return FeatureFlags.fromJson(data['featureFlags']);
    } catch (e) {
      throw Exception("Failed to parse feature flags response: $e");
    }
  }

  static Future<http.Response> _fetchFeatureFlags() {
    return http.get(
      Uri.parse(ApiEndpoints.featureFlags),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
