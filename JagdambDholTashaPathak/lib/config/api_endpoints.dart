class ApiEndpoints {
  // Base URL
  static const String baseUrl = 'http://192.168.1.9/api';

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
  static const String getRefreshToken = '$baseUrl/auth/token/refresh/';
  // -------------------
  // PROFILE ENDPOINTS
  // -------------------
  static const String getUserDetails = '$baseUrl/profile/get-user-details/';
}
