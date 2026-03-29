import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_endpoints.dart';
import '../models/feature_flags.dart';
import 'bug_report_service.dart';

class WebApiService {
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
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(ApiEndpoints.passwordLogin),
            headers: ApiEndpoints.jsonHeaders(),
            body: jsonEncode({
              'phone_number': phoneNumber,
              'password': password,
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
        throw Exception(
          'Web password login failed (status code ${response.statusCode})',
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
      rethrow;
    }
  }

  static Future<FeatureFlags> fetchFeatureFlags() async {
    try {
      final response = await http
          .get(
            Uri.parse(ApiEndpoints.featureFlags),
            headers: ApiEndpoints.jsonHeaders(),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to load feature flags (status code ${response.statusCode})',
        );
      }

      final decoded = jsonDecode(response.body);
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
