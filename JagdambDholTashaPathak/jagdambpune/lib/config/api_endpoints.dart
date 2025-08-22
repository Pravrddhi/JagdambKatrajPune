// lib/config/api_endpoints.dart

import 'dart:io';

/// Centralized class for managing API endpoints and related utilities.
class ApiEndpoints {
  // Base URL for API requests. Change this according to environment.
  // Uncomment the production URL when deploying.
  // static const String baseUrl = 'https://dev-api.jagdamb.co.in/api';
  static const String baseUrl = 'http://192.168.1.32/api';
  static const String pathak_id = "1";


  // -------------------
  // Authentication Endpoints
  // -------------------

  /// Register user without PIN
  static const String register = '$baseUrl/auth/register/';

  /// Set user PIN after registration
  static const String setPin = '$baseUrl/auth/set-pin/';

  /// Login using PIN
  static const String loginWithPin = '$baseUrl/auth/login/';

  /// Check if phone number already exists
  static const String checkPhoneNumber = '$baseUrl/auth/check-phone-number/';

  /// Check device registration
  static const String checkDeviceRegistration = '$baseUrl/auth/device-check/';

  /// Verify device and phone number association
  static const String verifyDevicePhone = '$baseUrl/auth/device/verify-phone-device/';

  // -------------------
  // Data Fetching Endpoints
  // -------------------

  /// Get list of instruments (need to append pathak id)
  static const String getInstruments = '$baseUrl/instruments';

  /// Get emergency contacts (append appropriate params if any)
  static const String getEmergencyContacts = '$baseUrl/emergency-contacts/';

  /// Update FCM token for push notifications
  static const String updateFCMToken = '$baseUrl/notifications/update-fcm-token/';

  /// Create a new event
  static const String createEvent = '$baseUrl/events/create/';

  /// Create a new notification
  static const String createNotification = '$baseUrl/notifications/create/';

  /// Fetch feature flags for the client app
  static const String featureFlags = '$baseUrl/feature-flags/';

  /// Endpoint to refresh access token using refresh token
  static const String refreshToken = '$baseUrl/auth/token/refresh/';

  // -------------------
  // Profile Endpoints
  // -------------------

  /// Get user details
  static const String getUserDetails = '$baseUrl/profile/get-user-details/';

  // -------------------
  // Miscellaneous Constants
  // -------------------

  /// Current pathak id for fetching related data
  static const String pathakId = "1";

  /// Helper method to build Uri with optional query parameters
  static Uri buildUri(String endpoint, [Map<String, dynamic>? queryParams]) {
    final uri = Uri.parse(endpoint);
    if (queryParams == null || queryParams.isEmpty) {
      return uri;
    }
    return uri.replace(queryParameters: queryParams.map(
      (key, value) => MapEntry(key, value.toString()),
    ));
  }

  /// Common headers for JSON requests without authorization
  static Map<String, String> jsonHeaders() => {
        HttpHeaders.contentTypeHeader: 'application/json',
        HttpHeaders.acceptHeader: 'application/json',
      };

  /// Headers with bearer token for authorized requests
  static Map<String, String> authorizedHeaders(String token) => {
        ...jsonHeaders(),
        HttpHeaders.authorizationHeader: 'Bearer $token',
      };
}
