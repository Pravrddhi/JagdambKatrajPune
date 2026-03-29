// lib/config/api_endpoints.dart

import 'package:flutter/foundation.dart';

/// Centralized class for managing API endpoints and related utilities.
class ApiEndpoints {
  // Base URL for API requests. Change this according to environment.
  // Uncomment the production URL when deploying.
  // static const String baseUrl = 'https://myriam-confirmatory-darlena.ngrok-free.dev/api';
  static const String baseUrl = 'https://api.jagdamb.co.in/api';
  static const String pathakId = "1";

  // -------------------
  // Storage Keys
  // -------------------
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String pinKey = 'pin';
  static const String isGatPramukhKey = 'is_gat_pramukh';
  static const String gatPramukhNameKey = 'gat_pramukh_name';

  // -------------------
  // Authentication Endpoints
  // -------------------

  /// Register user without PIN
  static final String register = '$baseUrl/auth/register/';

  /// Set user PIN after registration
  static final String setPin = '$baseUrl/auth/set-pin/';

  /// Login using PIN
  static final String loginWithPin = '$baseUrl/auth/login/';

  /// Login using phone number and password (web)
  static final String passwordLogin = '$baseUrl/auth/password-login/';

  /// Check if phone number already exists
  static final String checkPhoneNumber = '$baseUrl/auth/check-phone-number/';

  /// Check device registration
  static final String checkDeviceRegistration = '$baseUrl/auth/device-check/';

  /// Verify device and phone number association
  static final String verifyDevicePhone =
      '$baseUrl/auth/device/verify-phone-device/';

  /// Refresh access token
  static final String getRefreshToken = '$baseUrl/auth/token/refresh/';

  // -------------------
  // Data Fetching Endpoints
  // -------------------

  /// Get list of instruments (need to append pathak id)
  static final String getInstruments = '$baseUrl/instruments';

  /// Get emergency contacts (append appropriate params if any)
  static final String getEmergencyContacts = '$baseUrl/emergency-contacts/';

  /// Update FCM token for push notifications
  static final String updateFCMToken =
      '$baseUrl/notifications/update-fcm-token/';

  /// Create a new event
  static final String createEvent = '$baseUrl/events/create/';

  /// Create a new notification
  static final String createNotification = '$baseUrl/notifications/create/';

  /// Submit a new bug report
  static final String createBugReport =
      '$baseUrl/notifications/bug-report/create/';

  /// Fetch feature flags for the client app
  static final String featureFlags = '$baseUrl/feature-flags/';

  /// Get all gats
  static final String getGats = '$baseUrl/gats';

  /// Get users (admin only)
  static final String fetchAllUsers = '$baseUrl/users/';

  /// Base endpoint for a specific user by id (api/user/<int:id>/)
  static final String userByIdBase = '$baseUrl/user';

  /// Base endpoint to activate a user (api/notifications/activate-user/<int:user_id>/)
  static final String activateUserBase = '$baseUrl/notifications/activate-user';

  /// Endpoint to refresh access token using refresh token
  static final String refreshToken = '$baseUrl/auth/token/refresh/';

  // -------------------
  // Profile Endpoints
  // -------------------

  /// Get user details
  static final String getUserDetails = '$baseUrl/profile/get-user-details/';

  // -------------------
  // Miscellaneous Constants
  // -------------------

  /// Generic message shown for API failures.
  static const String genericApiFailureMessage =
      'Something went wrong. Bug has reported to admins';

  /// Helper method to build Uri with optional query parameters
  static Uri buildUri(String endpoint, [Map<String, dynamic>? queryParams]) {
    final uri = Uri.parse(endpoint);
    if (queryParams == null || queryParams.isEmpty) {
      return uri;
    }
    return uri.replace(
      queryParameters: queryParams.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    );
  }

  /// Common headers for JSON requests without authorization
  static Map<String, String> jsonHeaders() => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  /// Headers with bearer token for authorized requests
  static Map<String, String> authorizedHeaders(String token) => {
    ...jsonHeaders(),
    'Authorization': 'Bearer $token',
  };

  /// Build endpoint for specific user details using id
  static String getUserById(int id) => '$userByIdBase/$id/';

  /// Build endpoint to activate user by id
  static String getActivateUser(int id) => '$activateUserBase/$id/';
}
