import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/api_endpoints.dart';
import '../models/feature_flags.dart';
import 'bug_report_service.dart';

class WebApiService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }

  static Future<Map<String, dynamic>> loginWithPassword({
    required String phoneNumber,
    required String pin,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(ApiEndpoints.passwordLogin),
            headers: ApiEndpoints.jsonHeaders(),
            body: jsonEncode({
              'phone_number': phoneNumber,
              'password': pin,
              'pin': pin,
              'pathak_id': ApiEndpoints.pathakIdInt,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid login response format');
      }

      final bool isSuccessful =
          response.statusCode == 200 && decoded['status'] == true;
      if (!isSuccessful) {
        if (response.statusCode == 401) {
          throw Exception('Invalid phone number or PIN.');
        }
        if (response.statusCode == 404) {
          throw Exception('User not found.');
        }
        if (response.statusCode == 409) {
          throw Exception(
            'Multiple users found for this phone number. Please provide pathak_id.',
          );
        }
        final message =
            decoded['message']?.toString() ??
            decoded['detail']?.toString() ??
            decoded['error']?.toString();
        if (message != null && message.trim().isNotEmpty) {
          throw Exception(message.trim());
        }
        throw Exception(
          'Web PIN login failed (status code ${response.statusCode})',
        );
      }

      return decoded;
    } catch (e, st) {
      await BugReportService.reportApiFailure(
        title: 'Web password login API failure',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/login',
        endpoint: ApiEndpoints.passwordLogin,
      );
      final raw = e.toString().toLowerCase();
      if (raw.contains('socketexception') ||
          raw.contains('failed host lookup') ||
          raw.contains('timed out') ||
          raw.contains('timeout')) {
        throw Exception(ApiEndpoints.serverUnreachableMessage);
      }
      rethrow;
    }
  }

  static Future<FeatureFlags> fetchFeatureFlags() async {
    try {
      final token = await _storage.read(key: ApiEndpoints.accessTokenKey);
      final normalizedToken = token?.trim();
      final headers = (normalizedToken != null && normalizedToken.isNotEmpty)
          ? ApiEndpoints.authorizedHeaders(normalizedToken)
          : ApiEndpoints.jsonHeaders();

      final response = await http
          .get(Uri.parse(ApiEndpoints.featureFlags), headers: headers)
          .timeout(const Duration(seconds: 15));

      final decoded = jsonDecode(response.body);

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to load feature flags (status code ${response.statusCode})',
        );
      }

      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid feature flags response format');
      }

      final status = decoded['status'];
      if (status != null && !_toBool(status)) {
        throw Exception('Feature flags API returned status=false');
      }

      final payload =
          decoded['featureFlags'] ??
          decoded['feature_flags'] ??
          decoded['data'] ??
          decoded;
      if (payload is! Map<String, dynamic>) {
        throw Exception('Feature flags payload missing');
      }

      return FeatureFlags.fromJson(payload);
    } catch (e, st) {
      await BugReportService.reportApiFailure(
        title: 'Web feature flags API failure',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/feature-flags',
        endpoint: ApiEndpoints.featureFlags,
      );
      rethrow;
    }
  }
}
