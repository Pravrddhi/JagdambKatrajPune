import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../config/api_endpoints.dart';
import 'authorized_api_service.dart';
import 'location_bridge.dart';

class AttendanceApiException implements Exception {
  final int statusCode;
  final String message;
  final Map<String, dynamic> data;

  const AttendanceApiException({
    required this.statusCode,
    required this.message,
    this.data = const <String, dynamic>{},
  });

  @override
  String toString() => message;
}

class AttendanceService {
  static Future<Map<String, dynamic>> generateQr({
    required double locationLat,
    required double locationLng,
    int radiusMeters = 100,
    bool permanent = false,
  }) async {
    final payload = <String, dynamic>{
      'pathak_id': ApiEndpoints.pathakId,
      'location_lat': locationLat,
      'location_lng': locationLng,
      'radius_meters': radiusMeters,
      if (permanent) 'permanent': true,
    };

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.post(
        Uri.parse(ApiEndpoints.generateAttendanceQr),
        headers: ApiEndpoints.authorizedHeaders(token),
        body: jsonEncode(payload),
      ),
    );

    if (response == null) {
      throw Exception('Session expired. Please login again.');
    }

    final decoded = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    throw Exception(
      decoded['message']?.toString() ?? 'Failed to generate attendance QR.',
    );
  }

  static Future<Map<String, dynamic>> markAttendance({
    required String qrData,
    required double latitude,
    required double longitude,
    required String action,
  }) async {
    final payload = <String, dynamic>{
      'qr_data': qrData,
      'latitude': latitude,
      'longitude': longitude,
      'action': action,
    };

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.post(
        Uri.parse(ApiEndpoints.markAttendance),
        headers: ApiEndpoints.authorizedHeaders(token),
        body: jsonEncode(payload),
      ),
    );

    if (response == null) {
      throw Exception('Session expired. Please login again.');
    }

    final decoded = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    throw AttendanceApiException(
      statusCode: response.statusCode,
      message: decoded['message']?.toString() ?? 'Failed to mark attendance.',
      data: decoded,
    );
  }

  static Future<List<Map<String, dynamic>>> fetchMyAttendance({
    String? month,
  }) async {
    final uri = Uri.parse(ApiEndpoints.myAttendance).replace(
      queryParameters: {
        if (month != null && month.trim().isNotEmpty) 'month': month.trim(),
      },
    );

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.get(uri, headers: ApiEndpoints.authorizedHeaders(token)),
    );

    if (response == null) {
      throw Exception('Session expired. Please login again.');
    }

    final decoded = response.body.isNotEmpty
        ? jsonDecode(response.body)
        : <String, dynamic>{};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      if (decoded is Map<String, dynamic>) {
        final data = decoded['data'];
        if (data is List) {
          return data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
      return <Map<String, dynamic>>[];
    }

    if (decoded is Map<String, dynamic>) {
      throw Exception(
        decoded['message']?.toString() ?? 'Failed to load my attendance.',
      );
    }
    throw Exception('Failed to load my attendance.');
  }

  static Future<List<Map<String, dynamic>>> fetchAttendanceByUser({
    String? month,
  }) async {
    final uri = Uri.parse(ApiEndpoints.attendanceByUser).replace(
      queryParameters: {
        if (month != null && month.trim().isNotEmpty) 'month': month.trim(),
      },
    );

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.get(uri, headers: ApiEndpoints.authorizedHeaders(token)),
    );

    if (response == null) {
      throw Exception('Session expired. Please login again.');
    }

    final decoded = response.body.isNotEmpty
        ? jsonDecode(response.body)
        : <String, dynamic>{};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      if (decoded is Map<String, dynamic>) {
        final data = decoded['data'];
        if (data is List) {
          return data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
      return <Map<String, dynamic>>[];
    }

    if (decoded is Map<String, dynamic>) {
      throw Exception(
        decoded['message']?.toString() ?? 'Failed to load attendance by user.',
      );
    }
    throw Exception('Failed to load attendance by user.');
  }

  static Future<Map<String, dynamic>> fetchMyCurrentAttendanceStatus() async {
    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.get(
        Uri.parse(ApiEndpoints.myCurrentAttendanceStatus),
        headers: ApiEndpoints.authorizedHeaders(token),
      ),
    );

    if (response == null) {
      throw Exception('Session expired. Please login again.');
    }

    final decoded = response.body.isNotEmpty
        ? jsonDecode(response.body)
        : <String, dynamic>{};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is Map<String, dynamic>) {
        final data = decoded['data'];
        if (data is Map) {
          return Map<String, dynamic>.from(data);
        }
        return decoded;
      }
      return <String, dynamic>{};
    }

    if (decoded is Map<String, dynamic>) {
      throw Exception(
        decoded['message']?.toString() ??
            'Failed to load current attendance status.',
      );
    }
    throw Exception('Failed to load current attendance status.');
  }

  static Future<Map<String, dynamic>> setAttendanceLocation({
    required double latitude,
    required double longitude,
    int radiusMeters = 100,
    String? checkInTime,
    String? checkOutTime,
    int? checkoutCooldownMinutes,
    int? allowedBeforeMinutes,
    int? allowedAfterMinutes,
    double? minimumPresentHours,
    String? seasonStartDate,
    String? seasonEndDate,
  }) async {
    final payload = <String, dynamic>{
      'pathak_id': ApiEndpoints.pathakId,
      'location_lat': latitude,
      'location_lng': longitude,
      'radius_meters': radiusMeters,
      if (checkInTime != null && checkInTime.trim().isNotEmpty)
        'check_in_time': checkInTime.trim(),
      if (checkOutTime != null && checkOutTime.trim().isNotEmpty)
        'check_out_time': checkOutTime.trim(),
      if (checkoutCooldownMinutes != null)
        'checkout_cooldown_minutes': checkoutCooldownMinutes,
      if (allowedBeforeMinutes != null)
        'allowed_minutes_before_check_in': allowedBeforeMinutes,
      if (allowedAfterMinutes != null)
        'allowed_minutes_after_check_in': allowedAfterMinutes,
      if (minimumPresentHours != null)
        'minimum_present_hours': minimumPresentHours,
      if (seasonStartDate != null && seasonStartDate.trim().isNotEmpty)
        'season_start_date': seasonStartDate.trim(),
      if (seasonEndDate != null && seasonEndDate.trim().isNotEmpty)
        'season_end_date': seasonEndDate.trim(),
    };

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.post(
        Uri.parse(ApiEndpoints.setAttendanceLocation),
        headers: ApiEndpoints.authorizedHeaders(token),
        body: jsonEncode(payload),
      ),
    );

    if (response == null) {
      throw Exception('Session expired. Please login again.');
    }

    final decoded = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    throw Exception(
      decoded['message']?.toString() ?? 'Failed to set attendance location.',
    );
  }

  static Future<Map<String, dynamic>> fetchAttendanceLocation() async {
    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.get(
        Uri.parse(ApiEndpoints.getAttendanceLocation),
        headers: ApiEndpoints.authorizedHeaders(token),
      ),
    );

    if (response == null) {
      throw Exception('Session expired. Please login again.');
    }

    final decoded = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      Map<String, dynamic> asStringMap(dynamic value) {
        if (value is Map) {
          return Map<String, dynamic>.from(value);
        }
        return <String, dynamic>{};
      }

      final topLevel = asStringMap(decoded);
      final normalized = Map<String, dynamic>.from(topLevel);
      var current = topLevel;
      for (var depth = 0; depth < 3; depth += 1) {
        Map<String, dynamic>? nestedMatch;
        for (final key in <String>[
          'data',
          'settings',
          'attendance_settings',
          'attendance_location',
          'location',
        ]) {
          final nested = asStringMap(current[key]);
          if (nested.isNotEmpty) {
            nestedMatch = nested;
            break;
          }
        }
        if (nestedMatch == null) {
          break;
        }
        for (final entry in nestedMatch.entries) {
          if (entry.value != null) {
            normalized[entry.key] = entry.value;
          }
        }
        current = nestedMatch;
      }
      return normalized;
    }

    throw Exception(
      decoded['message']?.toString() ??
          'Failed to fetch configured attendance location.',
    );
  }

  static Future<AttendanceCoordinates> getCurrentPosition() {
    return fetchCurrentCoordinates();
  }

  static double distanceMeters({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _degreesToRadians(toLat - fromLat);
    final dLng = _degreesToRadians(toLng - fromLng);
    final lat1 = _degreesToRadians(fromLat);
    final lat2 = _degreesToRadians(toLat);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180.0);
  }
}
