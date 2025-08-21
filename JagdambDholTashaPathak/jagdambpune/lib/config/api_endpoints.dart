class ApiEndpoints {
  // Base URL
  // static const String baseUrl = 'https://dev-api.jagdamb.co.in/api';
  // static const String baseUrl = 'http://192.168.1.3/api';
  static const String baseUrl = 'http://192.168.1.3/api';

  // -------------------
  // AUTH ENDPOINTS
  // -------------------
  static const String register =
      '$baseUrl/auth/register/'; // Step 1: Register user (without PIN)
  static const String setPin =
      '$baseUrl/auth/set-pin/'; // Step 2: Set PIN after registration
  static const String loginWithPin = '$baseUrl/auth/login/';
  static const String checkPhoneNumber = '$baseUrl/auth/check-phone-number/';
  static const String checkDeviceRegistration = '$baseUrl/auth/device-check/';
  static const String verifyDevicePhone =
      '$baseUrl/auth/device/verify-phone-device/';
  static const String getInstruments = '$baseUrl/instruments';
  static const String getEmergencyContacts = '$baseUrl/emergency-contacts/';
  static const String updateFCMToken = '$baseUrl/notifications/update-fcm-token/';
  static const String createEvent = '$baseUrl/events/create/';
  static const String createNotification = '$baseUrl/notifications/create/';
  static const String subscribeToTopic = '$baseUrl/notifications/subscribe/';
  static const String listNotifications = '$baseUrl/notifications/list/';
  // -------------------
  // PROFILE ENDPOINTS
  // -------------------
  static const String getUserDetails = '$baseUrl/profile/get-user-details/';

  static const String pathak_id = "1";
}
// lib/config/api_endpoints.dart


// import 'dart:io';

// /// Build-time environment (set with --dart-define)
// /// Examples:
// ///  --dart-define=FLAVOR=prod
// ///  --dart-define=API_BASE_URL=https://api.yourdomain.com/api
// const String _flavor = String.fromEnvironment('FLAVOR', defaultValue: 'dev');
// const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');

// /// Sensible defaults per flavor (used only if API_BASE_URL is not provided)
// const Map<String, String> _defaultBaseByFlavor = {
//   'dev':    'http://10.0.2.2:8000/api',   // Android emulator loopback to host
//   'staging':'https://staging-api.yourdomain.com/api',
//   'prod':   'https://api.yourdomain.com/api',
// };

// /// Final base URL selected at runtime (compile time constants above)
// String get _baseUrl => _envBaseUrl.isNotEmpty
//     ? _envBaseUrl
//     : (_defaultBaseByFlavor[_flavor] ?? _defaultBaseByFlavor['dev']!);

// /// Timeouts (tune per your infra)
// class ApiTimeouts {
//   static const connect = Duration(seconds: 10);
//   static const receive = Duration(seconds: 30);
// }

// /// Common route segments
// class _Routes {
//   // Auth
//   static const register = '/auth/register/';
//   static const setPin = '/auth/set-pin/';
//   static const loginWithPin = '/auth/login/';
//   static const checkPhoneNumber = '/auth/check-phone-number/';
//   static const deviceCheck = '/auth/device-check/';
//   static const verifyDevicePhone = '/auth/device/verify-phone-device/';

//   // Master data
//   static const instruments = '/instruments';

//   // Profile
//   static const getUserDetails = '/profile/get-user-details/';

//   // Emergency
//   static const emergencyContacts = '/emergency-contacts/';

//   // Events
//   static const createEvent = '/events/create/';

//   // Notifications
//   static const createNotification = '/notifications/create/';
//   static const subscribeToTopic = '/notifications/subscribe/';
//   static const listNotifications = '/notifications/list/';
// }

// /// Centralized API endpoints + helpers
// class ApiEndpoints {
//   ApiEndpoints._();

//   /// Base URL selected for this build
//   static String get baseUrl => _baseUrl;

//   // -------------------
//   // AUTH ENDPOINTS
//   // -------------------
//   static String get register => '$baseUrl${_Routes.register}';
//   static String get setPin => '$baseUrl${_Routes.setPin}';
//   static String get loginWithPin => '$baseUrl${_Routes.loginWithPin}';
//   static String get checkPhoneNumber => '$baseUrl${_Routes.checkPhoneNumber}';
//   static String get checkDeviceRegistration => '$baseUrl${_Routes.deviceCheck}';
//   static String get verifyDevicePhone => '$baseUrl${_Routes.verifyDevicePhone}';

//   // -------------------
//   // MASTER / PROFILE
//   // -------------------
//   static String get getInstruments => '$baseUrl${_Routes.instruments}';
//   static String get getEmergencyContacts => '$baseUrl${_Routes.emergencyContacts}';
//   static String get getUserDetails => '$baseUrl${_Routes.getUserDetails}';

//   // -------------------
//   // EVENTS
//   // -------------------
//   static String get createEvent => '$baseUrl${_Routes.createEvent}';

//   // -------------------
//   // NOTIFICATIONS
//   // -------------------
//   static String get createNotification => '$baseUrl${_Routes.createNotification}';
//   static String get subscribeToTopic => '$baseUrl${_Routes.subscribeToTopic}';
//   static String get listNotifications => '$baseUrl${_Routes.listNotifications}';

//   /// Build an absolute [Uri] safely.
//   /// Example: `ApiEndpoints.uri(ApiEndpoints.createEvent)`
//   static Uri uri(String endpoint, {Map<String, dynamic>? query}) {
//     final base = Uri.parse(endpoint);
//     return base.replace(queryParameters: query?.map(
//       (k, v) => MapEntry(k, v?.toString()),
//     ));
//   }

//   /// JSON headers without auth
//   static Map<String, String> jsonHeaders() => {
//         HttpHeaders.contentTypeHeader: 'application/json',
//         HttpHeaders.acceptHeader: 'application/json',
//       };

//   /// JSON headers with Bearer token
//   static Map<String, String> authHeaders(String token) => {
//         ...jsonHeaders(),
//         HttpHeaders.authorizationHeader: 'Bearer $token',
//       };
// }

