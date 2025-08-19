class ApiEndpoints {
  // Base URL
  // static const String baseUrl = 'https://dev-api.jagdamb.co.in/api';
  // static const String baseUrl = 'http://192.168.1.3/api';
  static const String baseUrl = 'http://172.20.10.8/api';

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
  static const String createEvent = '$baseUrl/events/create/';
  // -------------------
  // PROFILE ENDPOINTS
  // -------------------
  static const String getUserDetails = '$baseUrl/profile/get-user-details/';

  static const String pathak_id = "1";
}
