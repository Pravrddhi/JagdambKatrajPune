import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_endpoints.dart';

class NewRegistrationPayload {
  const NewRegistrationPayload({
    required this.fullName,
    required this.gender,
    required this.whatsappNumber,
    required this.dateOfBirth,
    required this.instrument,
    required this.fullAddress,
    required this.season,
  });

  final String fullName;
  final String gender;
  final String whatsappNumber;
  final DateTime dateOfBirth;
  final String instrument;
  final String fullAddress;
  final String season;

  Map<String, dynamic> toJson() {
    return {
      'full_name': fullName,
      'gender': gender,
      'whatsapp_mobile_number': whatsappNumber,
      'date_of_birth': dateOfBirth.toIso8601String().split('T').first,
      'instrument': instrument,
      'full_address': fullAddress,
      'season': season,
      'pathak_id': ApiEndpoints.pathakIdInt,
    };
  }
}

class NewRegistrationResult {
  const NewRegistrationResult({
    required this.success,
    required this.message,
    this.registrationId,
    this.fieldErrors = const <String, String>{},
  });

  final bool success;
  final String message;
  final int? registrationId;
  final Map<String, String> fieldErrors;
}

class NewRegistrationService {
  static final RegExp _seasonShortPattern = RegExp(r'^(\d{4})-(\d{2})$');

  static String? validateSeasonFormat(String season) {
    final normalized = season.trim();
    final shortMatch = _seasonShortPattern.firstMatch(normalized);
    if (shortMatch == null) {
      return 'Season must be in YYYY-YY format (example: 2026-27).';
    }

    final startYear = int.tryParse(shortMatch.group(1) ?? '');
    final endShortYear = int.tryParse(shortMatch.group(2) ?? '');
    if (startYear == null || endShortYear == null) {
      return 'Season must be in YYYY-YY format (example: 2026-27).';
    }

    final expectedEndShortYear = (startYear + 1) % 100;
    if (endShortYear != expectedEndShortYear) {
      return 'Season end year must be next year (example: 2026-27).';
    }

    return null;
  }

  static Map<String, dynamic> _decodeMap(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return const <String, dynamic>{};
    }
    final decoded = jsonDecode(trimmed);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return const <String, dynamic>{};
  }

  static String _extractMessage(Map<String, dynamic> body, String fallback) {
    final dynamic message = body['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message.trim();
    }
    return fallback;
  }

  static Map<String, String> _extractFieldErrors(Map<String, dynamic> body) {
    final dynamic rawErrors = body['errors'];
    if (rawErrors is! Map) {
      return const <String, String>{};
    }

    final result = <String, String>{};
    rawErrors.forEach((key, value) {
      final field = key.toString();
      if (value is List) {
        final messages = value
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .join(' ');
        if (messages.isNotEmpty) {
          result[field] = messages;
        }
      } else {
        final message = value.toString().trim();
        if (message.isNotEmpty) {
          result[field] = message;
        }
      }
    });

    return result;
  }

  static Future<NewRegistrationResult> submit(
    NewRegistrationPayload payload,
  ) async {
    final seasonError = validateSeasonFormat(payload.season);
    if (seasonError != null) {
      return NewRegistrationResult(
        success: false,
        message: 'Validation failed.',
        fieldErrors: <String, String>{'season': seasonError},
      );
    }

    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.newComerRegistration),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(payload.toJson()),
      );

      final decodedBody = _decodeMap(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return NewRegistrationResult(
          success: true,
          message: _extractMessage(
            decodedBody,
            'Registration submitted successfully.',
          ),
          registrationId: decodedBody['registration_id'] is int
              ? decodedBody['registration_id'] as int
              : int.tryParse(decodedBody['registration_id']?.toString() ?? ''),
        );
      }

      final fieldErrors = _extractFieldErrors(decodedBody);
      if (response.statusCode == 400) {
        return NewRegistrationResult(
          success: false,
          message: _extractMessage(decodedBody, 'Validation failed.'),
          fieldErrors: fieldErrors,
        );
      }

      final rawBody = response.body.trim();
      if (rawBody.isNotEmpty && decodedBody.isEmpty) {
        return NewRegistrationResult(success: false, message: rawBody);
      }

      return NewRegistrationResult(
        success: false,
        message: _extractMessage(
          decodedBody,
          response.statusCode >= 500
              ? 'Internal server error.'
              : 'Unable to submit registration (status ${response.statusCode}).',
        ),
        fieldErrors: fieldErrors,
      );
    } catch (_) {
      return const NewRegistrationResult(
        success: false,
        message: 'Could not connect to server. Please try again later.',
      );
    }
  }
}
