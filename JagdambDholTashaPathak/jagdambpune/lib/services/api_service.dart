import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/feature_flags.dart';
import '../models/user.dart';
import '../config/api_endpoints.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'bug_report_service.dart';
import 'refresh_token_service.dart'; // Import your AuthService that handles token refresh

class ApiService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<FeatureFlags> fetchFeatureFlags() async {
    try {
      final response = await _fetchFeatureFlags();

      if (response.statusCode == 200) {
        return _parseFeatureFlagsResponse(response);
      } else {
        throw Exception(
          "Failed to load feature flags (status code ${response.statusCode})",
        );
      }
    } catch (e, st) {
      await BugReportService.reportApiFailure(
        title: 'Feature flags API failure',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/feature-flags',
        endpoint: ApiEndpoints.featureFlags,
      );
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchGats() async {
    try {
      String? storedAccessToken = await _storage.read(
        key: ApiEndpoints.accessTokenKey,
      );

      if (storedAccessToken == null) {
        throw Exception('No access token found. Please login again.');
      }

      final uri = Uri.parse(ApiEndpoints.getGats);

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $storedAccessToken',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['success'] == true && data['gat_names'] is List) {
          return List<Map<String, dynamic>>.from(data['gat_names']);
        }
        throw Exception('Invalid response format for gats');
      } else if (response.statusCode == 401) {
        final success = await _handleTokenRefresh();
        if (success) {
          return fetchGats();
        }
        throw Exception('Session expired. Please login again.');
      } else {
        throw Exception(
          'Failed to load gats (status code ${response.statusCode})',
        );
      }
    } catch (e, st) {
      await BugReportService.reportApiFailure(
        title: 'Gats API failure',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/gats',
        endpoint: ApiEndpoints.getGats,
      );
      rethrow;
    }
  }

  static Future<List<User>> fetchAllUsers() async {
    try {
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
              .map(
                (userJson) => User.fromJson(userJson as Map<String, dynamic>),
              )
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
    } catch (e, st) {
      await BugReportService.reportApiFailure(
        title: 'All users API failure',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/users',
        endpoint: ApiEndpoints.fetchAllUsers,
      );
      rethrow;
    }
  }

  static Future<User> fetchUserById(int userId) async {
    try {
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
    } catch (e, st) {
      await BugReportService.reportApiFailure(
        title: 'User by id API failure',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/user/$userId',
        endpoint: ApiEndpoints.getUserById(userId),
      );
      rethrow;
    }
  }

  static Future<String> activateUser(int userId) async {
    try {
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
    } catch (e, st) {
      await BugReportService.reportApiFailure(
        title: 'Activate user API failure',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/users/activate/$userId',
        endpoint: ApiEndpoints.getActivateUser(userId),
      );
      rethrow;
    }
  }

  static Future<void> sendBroadcastNotification({
    required String title,
    required String message,
  }) async {
    return _createNotification(title: title, message: message);
  }

  static Future<void> _createNotification({
    required String title,
    required String message,
  }) async {
    try {
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
        body: jsonEncode({'title': title, 'message': message}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['status'] == true) {
          return;
        }
        throw Exception('Failed to send notification');
      } else if (response.statusCode == 401) {
        final success = await _handleTokenRefresh();
        if (success) {
          return _createNotification(title: title, message: message);
        }
        throw Exception('Session expired. Please login again.');
      } else {
        throw Exception(
          'Failed to send notification (status code ${response.statusCode})',
        );
      }
    } catch (e, st) {
      await BugReportService.reportApiFailure(
        title: 'Create notification API failure',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/notifications/create',
        endpoint: ApiEndpoints.createNotification,
      );
      rethrow;
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
