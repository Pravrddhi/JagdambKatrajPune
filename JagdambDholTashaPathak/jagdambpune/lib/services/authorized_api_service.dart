import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/api_endpoints.dart';
import 'refresh_token_service.dart';

class AuthorizedApiService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// Executes an authorized API request and retries once after refreshing
  /// the access token when the first response is 401.
  static Future<http.Response?> sendWithAutoRefresh(
    String? initialAccessToken,
    dynamic request,
  ) async {
    final providedToken = initialAccessToken?.trim();
    final token = (providedToken != null && providedToken.isNotEmpty)
        ? providedToken
        : await _storage.read(key: ApiEndpoints.accessTokenKey);

    if (token == null || token.trim().isEmpty) {
      return null;
    }

    var response = await request(token) as http.Response;
    if (response.statusCode != 401) {
      return response;
    }

    final refreshed = await AuthService.refreshAccessToken();
    if (!refreshed) {
      return response;
    }

    final refreshedToken = await _storage.read(
      key: ApiEndpoints.accessTokenKey,
    );
    if (refreshedToken == null || refreshedToken.trim().isEmpty) {
      return response;
    }

    return await request(refreshedToken) as http.Response;
  }
}
