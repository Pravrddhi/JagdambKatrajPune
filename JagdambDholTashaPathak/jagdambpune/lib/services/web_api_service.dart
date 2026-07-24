import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/api_endpoints.dart';
import '../models/feature_flags.dart';
import 'bug_report_service.dart';

class WebLoginException implements Exception {
  final int statusCode;
  final String message;
  final int? userId;
  final String? clientType;
  final bool clientTypeMissing;

  const WebLoginException({
    required this.statusCode,
    required this.message,
    this.userId,
    this.clientType,
    this.clientTypeMissing = false,
  });

  @override
  String toString() => message;
}

class WebApiService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static void _logApiResponse(String apiName, String responseBody) {
    debugPrint('API $apiName RESPONSE $responseBody');
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value != null) {
      return int.tryParse(value.toString());
    }
    return null;
  }

  static int? _extractUserId(Map<String, dynamic> payload) {
    final topLevelUserId = _asInt(payload['user_id']);
    if (topLevelUserId != null) return topLevelUserId;

    final topLevelId = _asInt(payload['id']);
    if (topLevelId != null) return topLevelId;

    final topLevelUser = payload['user'];
    if (topLevelUser is Map<String, dynamic>) {
      final topLevelUserNestedId = _asInt(topLevelUser['user_id']);
      if (topLevelUserNestedId != null) return topLevelUserNestedId;
      final topLevelUserId2 = _asInt(topLevelUser['id']);
      if (topLevelUserId2 != null) return topLevelUserId2;
    }

    final data = payload['data'];
    if (data is Map<String, dynamic>) {
      final nestedUserId = _asInt(data['user_id']);
      if (nestedUserId != null) return nestedUserId;

      final nestedId = _asInt(data['id']);
      if (nestedId != null) return nestedId;

      final nestedUser = data['user'];
      if (nestedUser is Map<String, dynamic>) {
        final nestedUserId2 = _asInt(nestedUser['user_id']);
        if (nestedUserId2 != null) return nestedUserId2;
        final nestedId2 = _asInt(nestedUser['id']);
        if (nestedId2 != null) return nestedId2;
      }
    }

    if (data is Map) {
      final nestedUserId = _asInt(data['user_id']);
      if (nestedUserId != null) return nestedUserId;

      final nestedId = _asInt(data['id']);
      if (nestedId != null) return nestedId;
    }
    return null;
  }

  static String? _extractClientType(Map<String, dynamic> payload) {
    final topLevel = payload['client_type']?.toString().trim();
    if (topLevel != null && topLevel.isNotEmpty) {
      return topLevel;
    }

    final topLevelAlt = payload['clientType']?.toString().trim();
    if (topLevelAlt != null && topLevelAlt.isNotEmpty) {
      return topLevelAlt;
    }

    final topLevelUser = payload['user'];
    if (topLevelUser is Map<String, dynamic>) {
      final userClientType = topLevelUser['client_type']?.toString().trim();
      if (userClientType != null && userClientType.isNotEmpty) {
        return userClientType;
      }
    }

    final data = payload['data'];
    if (data is Map<String, dynamic>) {
      final nested = data['client_type']?.toString().trim();
      if (nested != null && nested.isNotEmpty) {
        return nested;
      }

      final nestedAlt = data['clientType']?.toString().trim();
      if (nestedAlt != null && nestedAlt.isNotEmpty) {
        return nestedAlt;
      }

      final nestedUser = data['user'];
      if (nestedUser is Map<String, dynamic>) {
        final userClientType = nestedUser['client_type']?.toString().trim();
        if (userClientType != null && userClientType.isNotEmpty) {
          return userClientType;
        }
      }
    }
    return null;
  }

  static bool _clientTypeLooksMissing(
    Map<String, dynamic> payload,
    String msg,
  ) {
    final normalized = msg.toLowerCase();

    // Explicit device-linked errors should never be treated as missing client_type.
    if (normalized.contains('linked to a device') ||
        normalized.contains('login using device') ||
        normalized.contains('registered on mobile') ||
        normalized.contains('device login')) {
      return false;
    }

    final ct = _extractClientType(payload)?.trim().toLowerCase();
    if (ct == null || ct.isEmpty || ct == 'null') {
      return true;
    }

    return normalized.contains('client_type') &&
        (normalized.contains('null') ||
            normalized.contains('missing') ||
            normalized.contains('not set') ||
            normalized.contains('empty'));
  }

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
              'pathak_id': ApiEndpoints.pathakIdInt,
            }),
          )
          .timeout(const Duration(seconds: 15));

      _logApiResponse('password-login', response.body);

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid login response format');
      }

      final bool isSuccessful =
          response.statusCode == 200 && decoded['status'] == true;
      if (!isSuccessful) {
        final message =
            decoded['message']?.toString() ??
            decoded['detail']?.toString() ??
            decoded['error']?.toString() ??
            'Login failed.';
        final userId = _extractUserId(decoded);
        final clientType = _extractClientType(decoded);
        final clientTypeMissing = _clientTypeLooksMissing(decoded, message);

        if (response.statusCode == 403) {
          throw WebLoginException(
            statusCode: 403,
            message: message.trim().isNotEmpty
                ? message.trim()
                : 'You are registered on mobile. You cannot login using web.',
            userId: userId,
            clientType: clientType,
            clientTypeMissing: clientTypeMissing,
          );
        }
        if (response.statusCode == 401) {
          throw const WebLoginException(
            statusCode: 401,
            message: 'Invalid phone number or password.',
          );
        }
        if (response.statusCode == 404) {
          throw const WebLoginException(
            statusCode: 404,
            message: 'User not found.',
          );
        }
        if (response.statusCode == 409) {
          throw const WebLoginException(
            statusCode: 409,
            message:
                'Multiple users found for this phone number. Please provide pathak_id.',
          );
        }
        throw WebLoginException(
          statusCode: response.statusCode,
          message: message.trim().isNotEmpty
              ? message.trim()
              : 'Web password login failed (status code ${response.statusCode})',
          userId: userId,
          clientType: clientType,
          clientTypeMissing: clientTypeMissing,
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

  static Future<void> updateClientTypeToWeb({
    String? fcmToken,
    String? accessToken,
  }) async {
    final normalizedToken = accessToken?.trim();
    final normalizedFcmToken = fcmToken?.trim() ?? '';

    final basePayload = <String, dynamic>{
      'client_type': 'web',
      if (normalizedFcmToken.isNotEmpty) 'fcm_token': normalizedFcmToken,
    };

    try {
      await _submitClientTypeUpdate(
        payload: basePayload,
        expectedClientType: 'web',
        accessToken: normalizedToken,
      );
      return;
    } on WebLoginException catch (e) {
      final retryPayload = <String, dynamic>{
        'cleint_type': 'web',
        if (normalizedFcmToken.isNotEmpty) 'fcm_token': normalizedFcmToken,
      };

      final shouldRetryWithTypo =
          e.statusCode == 400 ||
          e.message.toLowerCase().contains('client_type');
      if (!shouldRetryWithTypo) {
        rethrow;
      }

      await _submitClientTypeUpdate(
        payload: retryPayload,
        expectedClientType: 'web',
        accessToken: normalizedToken,
      );
    }
  }

  static Future<void> updateClientTypeToDevice({
    String? fcmToken,
    String? accessToken,
    String? deviceId,
  }) async {
    final normalizedToken = accessToken?.trim();
    final normalizedFcmToken = fcmToken?.trim() ?? '';
    final normalizedDeviceId = deviceId?.trim() ?? '';

    if (normalizedDeviceId.isEmpty ||
        normalizedDeviceId == 'unknown' ||
        normalizedDeviceId == 'unsupported_platform') {
      throw Exception('Device ID is required for device client_type update.');
    }

    final payload = <String, dynamic>{
      'client_type': 'device',
      'device_id': normalizedDeviceId,
      if (normalizedFcmToken.isNotEmpty) 'fcm_token': normalizedFcmToken,
    };

    try {
      await _submitClientTypeUpdate(
        payload: payload,
        expectedClientType: 'device',
        accessToken: normalizedToken,
      );
      return;
    } on WebLoginException catch (e) {
      final retryPayload = <String, dynamic>{
        'cleint_type': 'device',
        'device_id': normalizedDeviceId,
        if (normalizedFcmToken.isNotEmpty) 'fcm_token': normalizedFcmToken,
      };

      final shouldRetryWithTypo =
          e.statusCode == 400 ||
          e.message.toLowerCase().contains('client_type');
      if (!shouldRetryWithTypo) {
        rethrow;
      }

      await _submitClientTypeUpdate(
        payload: retryPayload,
        expectedClientType: 'device',
        accessToken: normalizedToken,
      );
    }
  }

  static Future<void> _submitClientTypeUpdate({
    required Map<String, dynamic> payload,
    required String expectedClientType,
    String? accessToken,
  }) async {
    final normalizedToken = accessToken?.trim();
    final headers = (normalizedToken != null && normalizedToken.isNotEmpty)
        ? ApiEndpoints.authorizedHeaders(normalizedToken)
        : ApiEndpoints.jsonHeaders();

    final response = await http
        .post(
          Uri.parse(ApiEndpoints.updateClientType),
          headers: headers,
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 15));

    _logApiResponse('update-client-type-request', jsonEncode(payload));
    _logApiResponse('update-client-type', response.body);

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }

    final is2xx = response.statusCode >= 200 && response.statusCode < 300;
    if (is2xx) {
      if (decoded is Map<String, dynamic>) {
        final statusValue = decoded['status'];
        if (statusValue == false || statusValue?.toString() == 'false') {
          final message =
              decoded['message']?.toString() ??
              decoded['detail']?.toString() ??
              decoded['error']?.toString() ??
              'Failed to update client type.';
          throw WebLoginException(
            statusCode: response.statusCode,
            message: message.trim().isNotEmpty
                ? message.trim()
                : 'Failed to update client type.',
            clientType: expectedClientType,
            clientTypeMissing: false,
          );
        }
      }
      return;
    }

    final message = decoded is Map<String, dynamic>
        ? decoded['message']?.toString() ??
              decoded['detail']?.toString() ??
              decoded['error']?.toString() ??
              'Failed to update client type.'
        : 'Failed to update client type.';

    throw WebLoginException(
      statusCode: response.statusCode,
      message: message.trim().isNotEmpty
          ? message.trim()
          : 'Failed to update client type.',
      clientType: expectedClientType,
      clientTypeMissing: false,
    );
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

      _logApiResponse('feature-flags', response.body);

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
