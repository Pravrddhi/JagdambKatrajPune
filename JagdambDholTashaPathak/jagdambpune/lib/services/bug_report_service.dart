import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/api_endpoints.dart';

class BugReportService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<void> reportApiFailure({
    required String title,
    required String errorMessage,
    String? stackTrace,
    String? pageUrl,
    int? statusCode,
    String? endpoint,
  }) async {
    try {
      // Web flow should not post bug reports to protected endpoint.
      if (kIsWeb) {
        return;
      }

      final token = await _storage.read(key: ApiEndpoints.accessTokenKey);

      // Avoid unauthenticated requests to protected bug-report API.
      if (token == null || token.isEmpty) {
        return;
      }

      final headers = <String, String>{'Content-Type': 'application/json'};
      headers['Authorization'] = 'Bearer $token';

      final payload = {
        'title': title,
        'error_message': statusCode == null
            ? errorMessage
            : '$errorMessage (status: $statusCode)',
        'stack_trace': stackTrace ?? '',
        'page_url': pageUrl ?? '',
        'device_info': {
          'platform': _platformName(),
          'endpoint': endpoint ?? '',
        },
      };

      await http.post(
        Uri.parse(ApiEndpoints.createBugReport),
        headers: headers,
        body: jsonEncode(payload),
      );
    } catch (_) {
      // Intentionally silent: bug reporting must never interrupt the app flow.
    }
  }

  static String _platformName() {
    if (kIsWeb) {
      return 'web';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }
}
