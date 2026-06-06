// lib/config/api_endpoints.dart

import 'package:flutter/foundation.dart';

import 'app_config.dart';

/// Centralized class for managing API endpoints and related utilities.
class ApiEndpoints {
  // Base URL for API requests.
  // Override with: --dart-define=API_BASE_URL=https://your-domain/api
  // This allows separate dev/prod builds without code edits.
  static const String _defaultBaseUrl = AppConfig.defaultApiBaseUrl;
  static const String baseUrlFromDefine = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultBaseUrl,
  );
  static String get baseUrl {
    final normalized = baseUrlFromDefine.trim();
    if (normalized.isEmpty) {
      return _defaultBaseUrl;
    }
    final trimmed = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;

    final parsed = Uri.tryParse(trimmed);
    final isAbsoluteHttpUrl =
        parsed != null &&
        (parsed.scheme == 'http' || parsed.scheme == 'https') &&
        parsed.host.isNotEmpty;

    // Ignore invalid/relative values (e.g. '/api') and use configured default.
    if (!isAbsoluteHttpUrl) {
      return _defaultBaseUrl.endsWith('/')
          ? _defaultBaseUrl.substring(0, _defaultBaseUrl.length - 1)
          : _defaultBaseUrl;
    }

    // Guard against absolute but wrong root path such as 'https://host/api'.
    // Project APIs are expected under '/dholtashapathak/api'.
    final path = parsed.path.endsWith('/')
        ? parsed.path.substring(0, parsed.path.length - 1)
        : parsed.path;
    if (path == '/api') {
      return _defaultBaseUrl.endsWith('/')
          ? _defaultBaseUrl.substring(0, _defaultBaseUrl.length - 1)
          : _defaultBaseUrl;
    }

    return trimmed;
  }

  /// API root without trailing /api, used for non-REST endpoints.
  static String get apiRootUrl {
    final base = baseUrl;
    if (base.endsWith('/api')) {
      return base.substring(0, base.length - 4);
    }
    return base;
  }

  /// Build websocket URI for live notifications.
  static Uri notificationsWebSocketUri(String accessToken) {
    final rootUri = Uri.parse(apiRootUrl);
    final pageIsSecureWebContext = kIsWeb && Uri.base.scheme == 'https';
    final secure = rootUri.scheme == 'https' || pageIsSecureWebContext;
    final wsScheme = secure ? 'wss' : 'ws';
    final rootPath = rootUri.path.endsWith('/')
        ? rootUri.path.substring(0, rootUri.path.length - 1)
        : rootUri.path;
    final wsPath = (rootPath.isEmpty || rootPath == '/')
        ? '/ws/notifications/'
        : '$rootPath/ws/notifications/';

    return Uri(
      scheme: wsScheme,
      host: rootUri.host,
      port: rootUri.hasPort ? rootUri.port : null,
      path: wsPath,
      queryParameters: {'token': accessToken},
    );
  }

  static const String pathakId = AppConfig.pathakId;
  static int get pathakIdInt => int.tryParse(pathakId) ?? 1;

  // -------------------
  // Storage Keys
  // -------------------
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String pinKey = 'pin';
  static const String isGatPramukhKey = 'is_gat_pramukh';
  static const String gatPramukhNameKey = 'gat_pramukh_name';
  static const String gatIdKey = 'gat_id';
  static const String gatNameKey = 'gat_name';

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

  /// Check if Aadhaar number already exists within a pathak
  static final String checkAdhaarNumber = '$baseUrl/auth/check-adhaar-number/';

  /// Public web endpoint for new player registration form (Season 2026-27+).
  static final String newComerRegistration = '$baseUrl/new_registration/';

  /// Check device registration
  static final String checkDeviceRegistration = '$baseUrl/auth/device-check/';

  /// Verify device and phone number association
  static final String verifyDevicePhone =
      '$baseUrl/auth/device/verify-phone-device/';

  /// Terms and conditions list (pathak scoped)
  static final String termsAndConditions = '$baseUrl/terms-and-conditions/';

  /// Pathak-admin endpoint for terms and conditions
  static final String termsAndConditionsManage =
      '$baseUrl/terms-and-conditions/manage/';

  /// Reset PIN with phone number + Aadhaar last 4 digits
  static final String resetPin = '$baseUrl/auth/reset-pin/';

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

  /// List active ID card template images
  static final String idTemplateImages = '$baseUrl/id-template-images/';

  /// List / create user items (jacket, instrument, uniform, shela, id_card, other)
  static final String userItems = '$baseUrl/user-items/';

  /// User's action inbox — items requiring their attention (pending_accept, admin_assigned, approved)
  static final String userItemsPending = '$baseUrl/user-items/pending/';

  /// List / create item catalog entries
  static final String itemCatalog = '$baseUrl/item-catalog/';

  /// Detail / partial-update / delete a specific user item
  static String userItemDetail(int itemId) => '$baseUrl/user-items/$itemId/';

  /// Perform lifecycle action on a user item
  static String userItemAction(int itemId) =>
      '$baseUrl/user-items/$itemId/action/';

  /// Confirm item receipt for current user
  static String userItemConfirm(int itemId) =>
      '$baseUrl/user-items/$itemId/confirm/';

  /// Detail / partial-update / delete a specific catalog item
  static String itemCatalogDetail(int catalogId) =>
      '$baseUrl/item-catalog/$catalogId/';

  /// Create a new event
  static final String createEvent = '$baseUrl/events/create/';

  /// Update status of a Mirvnuk event (0=not started, 1=started, 3=canceled, 4=completed)
  static final String updateMirvnukStatus = '$baseUrl/mirvnuk-status/';

  /// Generate attendance QR at a specific location (pathak_admin)
  static final String generateAttendanceQr = '$baseUrl/attendance/qr/generate/';

  /// Mark attendance by scanning QR (all users)
  static final String markAttendance = '$baseUrl/attendance/mark/';

  /// Set attendance QR generation location (pathak_admin only)
  static final String setAttendanceLocation =
      '$baseUrl/attendance/location/set/';

  /// Get configured attendance QR generation location
  static final String getAttendanceLocation = '$baseUrl/attendance/location/';

  /// Update attendance settings: in_time, out_time, full_day_threshold_minutes, radius_meters (pathak_admin only)
  static final String updateAttendanceSettings =
      '$baseUrl/attendance/location/set/';

  /// List my attendance entries (calendar view)
  static final String myAttendance = '$baseUrl/attendance/my/';

  /// List attendance grouped by user (pathak_admin and gat_pramukh)
  static final String attendanceByUser = '$baseUrl/attendance/by-user/';

  /// Create a new notification
  static final String createNotification = '$baseUrl/notifications/create/';

  /// Fetch user's notification list
  static final String listNotifications = '$baseUrl/notifications/list/';

  /// Mark a notification as read
  static final String markNotificationReadBase = '$baseUrl/notifications';

  /// Build endpoint to mark a notification as read
  static String markNotificationRead(int id) =>
      '$markNotificationReadBase/$id/read/';

  /// Submit a new bug report
  static final String createBugReport =
      '$baseUrl/notifications/bug-report/create/';

  /// Fetch feature flags for the client app
  static final String featureFlags =
      '$baseUrl/feature-flags/?pathak_id=$pathakId';

  /// Get all gats
  static final String getGats = '$baseUrl/gats';

  /// Create a gat (pathak_admin only)
  static final String createGat = '$baseUrl/gats/';

  /// Upload user document (multipart/form-data)
  static final String uploadDocument = '$baseUrl/documents/';

  /// Review uploaded user document (pathak_admin only)
  static final String reviewPathakDocumentBase = '$baseUrl/documents/pathak';

  /// List uploaded documents for the logged-in pathak_admin's pathak
  static final String listPathakDocuments = '$baseUrl/documents/pathak/';

  /// Get only logged-in user's gat details and members
  static final String myGatWithMembers = '$baseUrl/gats/my-gat/';

  /// Get all gats with optional members payload (admin)
  static final String listGatsWithMembers = '$baseUrl/gats/list-with-members/';

  /// Auto assign members to gats for a year (pathak_admin only)
  static final String autoAssignMembersToGats =
      '$baseUrl/gats/auto-assign-members/';

  /// Get users (admin only)
  static final String fetchAllUsers = '$baseUrl/users/';

  /// Fetch all assignable groups for pathak admin
  static final String fetchGroups = '$baseUrl/groups/';

  /// Base endpoint for a specific user by id (api/user/<int:id>/)
  static final String userByIdBase = '$baseUrl/user';

  /// Base endpoint to activate a user (api/notifications/activate-user/<int:user_id>/)
  static final String activateUserBase = '$baseUrl/notifications/activate-user';

  /// Base endpoint to approve/reject a user (PATCH /api/users/{user_id}/approval/)
  static final String userApprovalBase = '$baseUrl/users';

  /// Approve/reject endpoint for self/admin updates (PATCH /api/users/approval/)
  static final String userApproval = '$baseUrl/users/approval/';

  /// Endpoint to refresh access token using refresh token
  static final String refreshToken = '$baseUrl/auth/token/refresh/';

  // -------------------
  // Profile Endpoints
  // -------------------

  /// Get user details
  static final String getUserDetails = '$baseUrl/profile/get-user-details/';

  /// Update currently authenticated user profile (PATCH /api/user/update/)
  static final String updateCurrentUser = '$baseUrl/user/update/';

  // -------------------
  // Dhol Maintenance Endpoints
  // -------------------

  /// List inventory and add/update inventory items
  static final String maintenanceInventory = '$baseUrl/maintenance/inventory/';

  /// Update/delete specific inventory item
  static String getMaintenanceInventoryItem(int id) =>
      '$baseUrl/maintenance/inventory/$id/';

  /// List and create inventory requests
  static final String maintenanceInventoryRequests =
      '$baseUrl/maintenance/inventory/requests/';

  /// Approve/reject inventory request
  static final String maintenanceInventoryRequestAction =
      '$baseUrl/maintenance/inventory/requests/action/';

  /// List and create dhol maintenance entries
  static final String maintenanceEntries = '$baseUrl/maintenance/entries/';

  /// Approve/reject dhol maintenance entry
  static final String maintenanceEntryAction =
      '$baseUrl/maintenance/entries/action/';

  /// Maintenance stock analysis dashboard
  static final String maintenanceAnalysis = '$baseUrl/maintenance/analysis/';

  /// Maintenance events list/create
  static final String maintenanceEvents = '$baseUrl/maintenance/events/';

  /// Maintenance event details by id
  static String getMaintenanceEventDetail(int eventId) =>
      '$baseUrl/maintenance/events/$eventId/';

  /// Submit completion request for a maintenance event
  static String getMaintenanceEventCompletionRequests(int eventId) =>
      '$baseUrl/maintenance/events/$eventId/completion-requests/';

  /// List completion requests
  static final String maintenanceCompletionRequests =
      '$baseUrl/maintenance/completion-requests/';

  /// Approve/reject completion request by id
  static String getMaintenanceCompletionRequestAction(int requestId) =>
      '$baseUrl/maintenance/completion-requests/$requestId/action/';

  /// Maintenance audit logs
  static final String maintenanceAuditLogs = '$baseUrl/maintenance/audit-logs/';

  // -------------------
  // Miscellaneous Constants
  // -------------------

  /// Generic message shown for API failures.
  static const String genericApiFailureMessage =
      'Something went wrong. Please try again. If the issue continues, contact support.';

  /// Message shown when backend server cannot be reached.
  static const String serverUnreachableMessage =
      'Unable to reach server. Please check your internet connection and try again.';

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

  /// Build endpoint to update user profile by id (PATCH /api/user/<id>/update/)
  static String getUserUpdateById(int id) => '$userByIdBase/$id/update/';

  /// Build endpoint to update user profile by identifier
  /// (PATCH /api/user/<identifier>/update/)
  static String getUserUpdateByIdentifier(String identifier) =>
      '$userByIdBase/${Uri.encodeComponent(identifier)}/update/';

  /// Build endpoint to activate user by id
  static String getActivateUser(int id) => '$activateUserBase/$id/';

  /// Build endpoint to approve/reject user by id
  static String getUserApproval(int id) => '$userApprovalBase/$id/approval/';

  /// Build endpoint to soft-delete user by id
  static String getUserSoftDelete(int id) =>
      '$userApprovalBase/$id/soft-delete/';

  /// Build endpoint to restore soft-deleted user by id
  static String getUserRestore(int id) => '$userApprovalBase/$id/restore/';

  /// Build endpoint to update user group by id
  static String getUserGroupUpdate(int id) => '$userApprovalBase/$id/group/';

  /// Build endpoint to review a document by id
  static String reviewPathakDocument(int id) =>
      '$reviewPathakDocumentBase/$id/review/';
}
