import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/feature_flags.dart';
import '../models/user.dart';
import '../config/api_endpoints.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'bug_report_service.dart';
import 'refresh_token_service.dart'; // Import your AuthService that handles token refresh
import 'authorized_api_service.dart';

class ApiService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const Set<String> _allowedDocumentTypes = {
    'adhaar_card',
    'pan_card',
    'personal_photo',
    'agreement_document',
  };
  static final Map<String, Future<void>> _inFlightNotificationRequests =
      <String, Future<void>>{};
  static String? _lastNotificationFingerprint;
  static DateTime? _lastNotificationAt;
  static const Duration _notificationDedupeWindow = Duration(seconds: 10);

  static bool _isJpegBytes(Uint8List bytes) {
    // JPEG files begin with FF D8 FF.
    return bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;
  }

  static Future<FeatureFlags> fetchFeatureFlags() async {
    try {
      final response = await _fetchFeatureFlags();

      if (response.statusCode == 200) {
        return _parseFeatureFlagsResponse(response);
      } else {
        throw Exception(
          "Failed to load feature flags (status code ${response.statusCode})",
        );
      }
    } catch (e, st) {
      await BugReportService.reportApiFailure(
        title: 'Feature flags API failure',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/feature-flags',
        endpoint: ApiEndpoints.featureFlags,
      );
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchGats() async {
    try {
      String? storedAccessToken = await _storage.read(
        key: ApiEndpoints.accessTokenKey,
      );

      if (storedAccessToken == null) {
        throw Exception('No access token found. Please login again.');
      }

      final uri = Uri.parse(ApiEndpoints.getGats);

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $storedAccessToken',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['success'] == true && data['gat_names'] is List) {
          return List<Map<String, dynamic>>.from(data['gat_names']);
        }
        throw Exception('Invalid response format for gats');
      } else if (response.statusCode == 401) {
        final success = await _handleTokenRefresh();
        if (success) {
          return fetchGats();
        }
        throw Exception('Session expired. Please login again.');
      } else {
        throw Exception(
          'Failed to load gats (status code ${response.statusCode})',
        );
      }
    } catch (e, st) {
      await BugReportService.reportApiFailure(
        title: 'Gats API failure',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/gats',
        endpoint: ApiEndpoints.getGats,
      );
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> fetchMyGat({
    bool includeMembers = false,
    int? membersLimit,
  }) async {
    try {
      if (membersLimit != null && membersLimit <= 0) {
        throw Exception('members_limit must be greater than 0');
      }

      final uri = ApiEndpoints.buildUri(ApiEndpoints.myGatWithMembers, {
        'include_members': includeMembers,
        if (membersLimit != null) 'members_limit': membersLimit,
      });

      final response = await AuthorizedApiService.sendWithAutoRefresh(
        null,
        (token) =>
            http.get(uri, headers: ApiEndpoints.authorizedHeaders(token)),
      );

      if (response == null) {
        throw Exception('Session expired. Please login again.');
      }

      final decoded = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : <String, dynamic>{};

      if (response.statusCode == 200) {
        if (decoded is Map<String, dynamic>) {
          final data = decoded['data'];
          if (data is Map<String, dynamic>) {
            return data;
          }
        }
        throw Exception('Invalid response format for my gat.');
      }

      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail']?.toString();
        if (detail != null && detail.isNotEmpty) {
          throw Exception(detail);
        }
        final message = decoded['message']?.toString();
        if (message != null && message.isNotEmpty) {
          throw Exception(message);
        }
      }

      throw Exception(
        'Failed to load my gat (status code ${response.statusCode})',
      );
    } catch (e, st) {
      await BugReportService.reportApiFailure(
        title: 'My gat API failure',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/gats/my-gat',
        endpoint: ApiEndpoints.myGatWithMembers,
      );
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> createGat({
    required String name,
    int? gatPramukhId,
  }) async {
    try {
      final trimmedName = name.trim();
      if (trimmedName.isEmpty) {
        throw Exception('Gat name is required.');
      }

      final payload = <String, dynamic>{
        'name': trimmedName,
        if (gatPramukhId != null) 'gat_pramukh_id': gatPramukhId,
      };

      final response = await AuthorizedApiService.sendWithAutoRefresh(
        null,
        (token) => http.post(
          Uri.parse(ApiEndpoints.createGat),
          headers: ApiEndpoints.authorizedHeaders(token),
          body: jsonEncode(payload),
        ),
      );

      if (response == null) {
        throw Exception('Session expired. Please login again.');
      }

      final decoded = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : <String, dynamic>{};

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        return <String, dynamic>{
          'success': true,
          'message': 'Gat created successfully.',
        };
      }

      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail']?.toString();
        if (detail != null && detail.isNotEmpty) {
          throw Exception(detail);
        }

        final message = decoded['message']?.toString();
        if (message != null && message.isNotEmpty) {
          throw Exception(message);
        }
      }

      throw Exception(
        'Failed to create gat (status code ${response.statusCode})',
      );
    } catch (e, st) {
      await BugReportService.reportApiFailure(
        title: 'Create gat API failure',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/gats/',
        endpoint: ApiEndpoints.createGat,
      );
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchGatsWithMembers({
    bool includeMembers = false,
    int? membersLimit,
  }) async {
    try {
      if (membersLimit != null && membersLimit <= 0) {
        throw Exception('members_limit must be greater than 0');
      }

      final uri = ApiEndpoints.buildUri(ApiEndpoints.listGatsWithMembers, {
        'include_members': includeMembers,
        if (membersLimit != null) 'members_limit': membersLimit,
      });

      final response = await AuthorizedApiService.sendWithAutoRefresh(
        null,
        (token) =>
            http.get(uri, headers: ApiEndpoints.authorizedHeaders(token)),
      );

      if (response == null) {
        throw Exception('Session expired. Please login again.');
      }

      final decoded = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : <String, dynamic>{};

      if (response.statusCode == 200) {
        if (decoded is Map<String, dynamic>) {
          final data = decoded['data'];
          if (data is List) {
            return data
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
          if (data is Map<String, dynamic> && data['gats'] is List) {
            return (data['gats'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
          if (decoded['gats'] is List) {
            return (decoded['gats'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        }
        throw Exception('Invalid response format for gats with members.');
      }

      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail']?.toString();
        if (detail != null && detail.isNotEmpty) {
          throw Exception(detail);
        }
        final message = decoded['message']?.toString();
        if (message != null && message.isNotEmpty) {
          throw Exception(message);
        }
      }

      throw Exception(
        'Failed to load gats with members (status code ${response.statusCode})',
      );
    } catch (e, st) {
      await BugReportService.reportApiFailure(
        title: 'Gats with members API failure',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/gats/list-with-members',
        endpoint: ApiEndpoints.listGatsWithMembers,
      );
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> autoAssignMembersToGats({
    required int year,
    bool reassign = false,
    bool dryRun = false,
    int? seed,
  }) async {
    try {
      final payload = <String, dynamic>{
        'year': year,
        'reassign': reassign,
        'dry_run': dryRun,
      };
      if (seed != null) {
        payload['seed'] = seed;
      }

      final response = await AuthorizedApiService.sendWithAutoRefresh(
        null,
        (token) => http.post(
          Uri.parse(ApiEndpoints.autoAssignMembersToGats),
          headers: ApiEndpoints.authorizedHeaders(token),
          body: jsonEncode(payload),
        ),
      );

      if (response == null) {
        throw Exception('Session expired. Please login again.');
      }

      final decoded = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : <String, dynamic>{};

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        throw Exception('Invalid response format');
      }

      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail']?.toString();
        if (detail != null && detail.isNotEmpty) {
          throw Exception(detail);
        }

        final message = decoded['message']?.toString();
        if (message != null && message.isNotEmpty) {
          throw Exception(message);
        }
      }

      throw Exception(
        'Failed to auto-assign members (status code ${response.statusCode})',
      );
    } catch (e, st) {
      await BugReportService.reportApiFailure(
        title: 'Auto assign members API failure',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/gats/auto-assign-members',
        endpoint: ApiEndpoints.autoAssignMembersToGats,
      );
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> uploadDocument({
    required String documentType,
    required Uint8List fileBytes,
    required String fileName,
  }) async {
    try {
      final normalizedType = documentType.trim();
      final normalizedFileName = fileName.trim();
      final lowerFileName = normalizedFileName.toLowerCase();

      debugPrint(
        '[uploadDocument] START — type=$normalizedType file=$normalizedFileName size=${fileBytes.length}B',
      );

      if (!_allowedDocumentTypes.contains(normalizedType)) {
        debugPrint(
          '[uploadDocument] ERROR — invalid document type: $normalizedType',
        );
        throw Exception('Invalid document type.');
      }
      if (!(lowerFileName.endsWith('.jpg') ||
          lowerFileName.endsWith('.jpeg'))) {
        debugPrint(
          '[uploadDocument] ERROR — disallowed file extension: $normalizedFileName',
        );
        throw Exception('Only .jpg and .jpeg files are allowed.');
      }
      if (!_isJpegBytes(fileBytes)) {
        debugPrint('[uploadDocument] ERROR — file bytes are not JPEG');
        throw Exception(
          'Selected image is not a valid JPEG. Please capture/select a JPG/JPEG image.',
        );
      }

      final token = await _storage.read(key: ApiEndpoints.accessTokenKey);
      if (token == null || token.trim().isEmpty) {
        debugPrint('[uploadDocument] ERROR — no access token in storage');
        throw Exception('Session expired. Please login again.');
      }
      debugPrint('[uploadDocument] token present (${token.length} chars)');

      Future<http.Response> sendRequest(String accessToken) async {
        final url = ApiEndpoints.uploadDocument;
        debugPrint('[uploadDocument] POST $url');
        final request = http.MultipartRequest('POST', Uri.parse(url))
          ..headers['Authorization'] = 'Bearer $accessToken'
          ..fields['document_type'] = normalizedType
          ..files.add(
            http.MultipartFile.fromBytes(
              'document_file',
              fileBytes,
              filename: normalizedFileName,
              contentType: MediaType('image', 'jpeg'),
            ),
          );

        final streamed = await request.send().timeout(
          const Duration(seconds: 90),
        );
        return http.Response.fromStream(streamed);
      }

      var response = await sendRequest(token);
      debugPrint('[uploadDocument] response status=${response.statusCode}');
      debugPrint('[uploadDocument] response body=${response.body}');

      if (response.statusCode == 401) {
        debugPrint('[uploadDocument] 401 — attempting token refresh');
        final refreshed = await AuthService.refreshAccessToken();
        if (refreshed) {
          final refreshedToken = await _storage.read(
            key: ApiEndpoints.accessTokenKey,
          );
          if (refreshedToken != null && refreshedToken.trim().isNotEmpty) {
            debugPrint('[uploadDocument] retrying with refreshed token');
            response = await sendRequest(refreshedToken);
            debugPrint('[uploadDocument] retry status=${response.statusCode}');
            debugPrint('[uploadDocument] retry body=${response.body}');
          }
        } else {
          debugPrint('[uploadDocument] token refresh failed');
        }
      }

      Map<String, dynamic> decoded;
      if (response.body.isNotEmpty) {
        try {
          final raw = jsonDecode(response.body);
          decoded = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
        } catch (jsonError) {
          debugPrint('[uploadDocument] JSON parse error: $jsonError');
          debugPrint('[uploadDocument] raw body was: ${response.body}');
          throw Exception(
            'Server returned an unexpected response (status ${response.statusCode}). '
            'Raw: ${response.body.length > 300 ? response.body.substring(0, 300) : response.body}',
          );
        }
      } else {
        decoded = <String, dynamic>{};
      }

      debugPrint('[uploadDocument] decoded=$decoded');

      if (response.statusCode == 201) {
        debugPrint('[uploadDocument] SUCCESS');
        return decoded;
      }

      if (decoded['detail'] != null) {
        throw Exception(decoded['detail'].toString());
      }

      final documentTypeErrors = decoded['document_type'];
      if (documentTypeErrors is List && documentTypeErrors.isNotEmpty) {
        throw Exception(documentTypeErrors.first.toString());
      }

      final fileErrors = decoded['document_file'];
      if (fileErrors is List && fileErrors.isNotEmpty) {
        throw Exception(fileErrors.first.toString());
      }

      final message = decoded['message']?.toString();
      if (message != null && message.isNotEmpty) {
        throw Exception(message);
      }

      throw Exception(
        'Failed to upload document (status code ${response.statusCode})',
      );
    } on TimeoutException catch (e, st) {
      debugPrint('[uploadDocument] TIMEOUT: $e');
      await BugReportService.reportApiFailure(
        title: 'Upload document API timeout',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/documents',
        endpoint: ApiEndpoints.uploadDocument,
      );
      throw Exception(
        'Upload timed out. Please try again with a smaller JPG image.',
      );
    } catch (e, st) {
      debugPrint('[uploadDocument] EXCEPTION: $e');
      debugPrint('[uploadDocument] STACKTRACE: $st');
      await BugReportService.reportApiFailure(
        title: 'Upload document API failure',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/documents',
        endpoint: ApiEndpoints.uploadDocument,
      );
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> fetchPathakDocuments({
    String? status,
    String? documentType,
    int? uploadedById,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      if (page <= 0) {
        throw Exception('Page must be greater than 0.');
      }
      if (pageSize <= 0) {
        throw Exception('Page size must be greater than 0.');
      }

      final normalizedStatus = status?.trim().toLowerCase();
      final normalizedDocumentType = documentType?.trim();

      if (normalizedStatus != null &&
          normalizedStatus.isNotEmpty &&
          !{'pending', 'approved', 'rejected'}.contains(normalizedStatus)) {
        throw Exception('Invalid document status filter.');
      }

      if (normalizedDocumentType != null &&
          normalizedDocumentType.isNotEmpty &&
          !_allowedDocumentTypes.contains(normalizedDocumentType)) {
        throw Exception('Invalid document type filter.');
      }

      if (uploadedById != null && uploadedById <= 0) {
        throw Exception('uploaded_by_id must be greater than 0.');
      }

      final uri = ApiEndpoints.buildUri(ApiEndpoints.listPathakDocuments, {
        if (normalizedStatus != null && normalizedStatus.isNotEmpty)
          'status': normalizedStatus,
        if (normalizedDocumentType != null && normalizedDocumentType.isNotEmpty)
          'document_type': normalizedDocumentType,
        if (uploadedById != null) 'uploaded_by_id': uploadedById,
        'page': page,
        'page_size': pageSize,
      });

      final response = await AuthorizedApiService.sendWithAutoRefresh(
        null,
        (token) =>
            http.get(uri, headers: ApiEndpoints.authorizedHeaders(token)),
      );

      if (response == null) {
        throw Exception('Session expired. Please login again.');
      }

      final decoded = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : <String, dynamic>{};

      if (response.statusCode == 200) {
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        throw Exception('Invalid response format from document list API.');
      }

      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail']?.toString();
        if (detail != null && detail.isNotEmpty) {
          throw Exception(detail);
        }

        final message = decoded['message']?.toString();
        if (message != null && message.isNotEmpty) {
          throw Exception(message);
        }
      }

      throw Exception(
        'Failed to load documents (status code ${response.statusCode})',
      );
    } catch (e, st) {
      await BugReportService.reportApiFailure(
        title: 'Pathak documents API failure',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/documents/pathak',
        endpoint: ApiEndpoints.listPathakDocuments,
      );
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> reviewDocument({
    required int documentId,
    required String status,
    String? reason,
  }) async {
    try {
      if (documentId <= 0) {
        throw Exception('Invalid document id.');
      }

      final normalizedStatus = status.trim().toLowerCase();
      final normalizedReason = reason?.trim();

      if (normalizedStatus != 'approved' && normalizedStatus != 'rejected') {
        throw Exception('Status must be either approved or rejected.');
      }

      if (normalizedStatus == 'rejected' &&
          (normalizedReason == null || normalizedReason.isEmpty)) {
        throw Exception(
          'Rejection reason is required when status is rejected.',
        );
      }

      final uri = Uri.parse(ApiEndpoints.reviewPathakDocument(documentId));
      final body = <String, dynamic>{
        'status': normalizedStatus,
        if (normalizedStatus == 'rejected') 'reason': normalizedReason,
      };

      final response = await AuthorizedApiService.sendWithAutoRefresh(
        null,
        (token) => http.patch(
          uri,
          headers: ApiEndpoints.authorizedHeaders(token),
          body: jsonEncode(body),
        ),
      );

      if (response == null) {
        throw Exception('Session expired. Please login again.');
      }

      final decoded = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : <String, dynamic>{};

      if (response.statusCode == 200) {
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        throw Exception('Invalid response format from review API.');
      }

      if (decoded is Map<String, dynamic>) {
        final reasonErrors = decoded['reason'];
        if (reasonErrors is List && reasonErrors.isNotEmpty) {
          throw Exception(reasonErrors.first.toString());
        }

        final detail = decoded['detail']?.toString();
        if (detail != null && detail.isNotEmpty) {
          throw Exception(detail);
        }

        final message = decoded['message']?.toString();
        if (message != null && message.isNotEmpty) {
          throw Exception(message);
        }
      }

      throw Exception(
        'Failed to review document (status code ${response.statusCode})',
      );
    } catch (e, st) {
      await BugReportService.reportApiFailure(
        title: 'Review document API failure',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/documents/pathak/$documentId/review',
        endpoint: ApiEndpoints.reviewPathakDocument(documentId),
      );
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchMyDocuments() async {
    try {
      final uri = Uri.parse(ApiEndpoints.uploadDocument);

      final response = await AuthorizedApiService.sendWithAutoRefresh(
        null,
        (token) =>
            http.get(uri, headers: ApiEndpoints.authorizedHeaders(token)),
      );

      if (response == null) {
        throw Exception('Session expired. Please login again.');
      }

      final decoded = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : <String, dynamic>{};

      if (response.statusCode == 200) {
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }
        if (decoded is Map<String, dynamic>) {
          final data = decoded['data'] ?? decoded['results'];
          if (data is List) {
            return data
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
          }
          return [];
        }
        throw Exception('Invalid response format from my documents API.');
      }

      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail']?.toString();
        if (detail != null && detail.isNotEmpty) {
          throw Exception(detail);
        }
      }

      throw Exception(
        'Failed to load your documents (status code ${response.statusCode})',
      );
    } catch (e, st) {
      await BugReportService.reportApiFailure(
        title: 'My documents API failure',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/documents',
        endpoint: ApiEndpoints.uploadDocument,
      );
      rethrow;
    }
  }

  static Future<List<User>> fetchAllUsers() async {
    try {
      String? storedAccessToken = await _storage.read(
        key: ApiEndpoints.accessTokenKey,
      );

      if (storedAccessToken == null) {
        throw Exception('No access token found. Please login again.');
      }

      final uri = Uri.parse(ApiEndpoints.fetchAllUsers);

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $storedAccessToken',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);

        if (data['status'] == true && data['users'] is List) {
          final List<dynamic> usersList = data['users'];
          return usersList
              .map(
                (userJson) => User.fromJson(userJson as Map<String, dynamic>),
              )
              .toList();
        }

        throw Exception('Invalid response format for users');
      } else if (response.statusCode == 401) {
        final success = await _handleTokenRefresh();
        if (success) {
          return fetchAllUsers();
        }
        throw Exception('Session expired. Please login again.');
      } else {
        throw Exception(
          'Failed to load users (status code ${response.statusCode})',
        );
      }
    } catch (e, st) {
      await BugReportService.reportApiFailure(
        title: 'All users API failure',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/users',
        endpoint: ApiEndpoints.fetchAllUsers,
      );
      rethrow;
    }
  }

  static Future<User> fetchUserById(int userId) async {
    try {
      String? storedAccessToken = await _storage.read(
        key: ApiEndpoints.accessTokenKey,
      );

      if (storedAccessToken == null) {
        throw Exception('No access token found. Please login again.');
      }

      final uri = Uri.parse(ApiEndpoints.getUserById(userId));

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $storedAccessToken',
        },
      );

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);

        if (decoded is Map<String, dynamic>) {
          if (decoded['status'] == true &&
              decoded['user'] is Map<String, dynamic>) {
            return User.fromJson(decoded['user'] as Map<String, dynamic>);
          }
          return User.fromJson(decoded);
        }

        throw Exception('Invalid response format for user details');
      } else if (response.statusCode == 401) {
        final success = await _handleTokenRefresh();
        if (success) {
          return fetchUserById(userId);
        }
        throw Exception('Session expired. Please login again.');
      } else {
        throw Exception(
          'Failed to load user details (status code ${response.statusCode})',
        );
      }
    } catch (e, st) {
      await BugReportService.reportApiFailure(
        title: 'User by id API failure',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/user/$userId',
        endpoint: ApiEndpoints.getUserById(userId),
      );
      rethrow;
    }
  }

  static Future<String> updateUserApproval({
    required int userId,
    required int decision,
    String? comment,
  }) async {
    try {
      String? storedAccessToken = await _storage.read(
        key: ApiEndpoints.accessTokenKey,
      );

      if (storedAccessToken == null) {
        throw Exception('No access token found. Please login again.');
      }

      final uri = Uri.parse(ApiEndpoints.getUserApproval(userId));

      final payload = <String, dynamic>{'decision': decision};
      if (comment != null && comment.trim().isNotEmpty) {
        payload['comment'] = comment.trim();
      }

      final response = await http.patch(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $storedAccessToken',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['status'] == true) {
          return decoded['message']?.toString() ?? 'User approval updated';
        }
        throw Exception('Failed to update user approval');
      } else if (response.statusCode == 400 ||
          response.statusCode == 403 ||
          response.statusCode == 404) {
        final dynamic decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final message = decoded['message']?.toString();
          if (message != null && message.isNotEmpty) {
            throw Exception(message);
          }
          final commentErrors = decoded['comment'];
          if (commentErrors is List && commentErrors.isNotEmpty) {
            throw Exception(commentErrors.first.toString());
          }
        }
        throw Exception(
          'Failed to update user approval (status code ${response.statusCode})',
        );
      } else if (response.statusCode == 401) {
        final success = await _handleTokenRefresh();
        if (success) {
          return updateUserApproval(
            userId: userId,
            decision: decision,
            comment: comment,
          );
        }
        throw Exception('Session expired. Please login again.');
      } else {
        throw Exception(
          'Failed to update user approval (status code ${response.statusCode})',
        );
      }
    } catch (e, st) {
      await BugReportService.reportApiFailure(
        title: 'User approval API failure',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/users/$userId/approval',
        endpoint: ApiEndpoints.getUserApproval(userId),
      );
      rethrow;
    }
  }

  static Future<void> sendBroadcastNotification({
    required String title,
    required String message,
    String? type,
    String? targetType,
    int? targetRole,
    int? targetUser,
    int? targetGat,
  }) async {
    final normalizedTitle = title.trim();
    final normalizedMessage = message.trim();
    final normalizedType = type?.trim();
    var normalizedTargetType = targetType?.trim();
    // Backend contract: gat-targeted notifications use target_type='user'
    // with target_gat=<id>.
    if (targetGat != null &&
        (normalizedTargetType == null ||
            normalizedTargetType.isEmpty ||
            normalizedTargetType == 'gat')) {
      normalizedTargetType = 'user';
    }
    final fingerprint =
        '${normalizedTitle.toLowerCase()}::${normalizedMessage.toLowerCase()}::${normalizedType ?? ''}::${normalizedTargetType ?? ''}::${targetRole ?? ''}::${targetUser ?? ''}::${targetGat ?? ''}';

    final existingRequest = _inFlightNotificationRequests[fingerprint];
    if (existingRequest != null) {
      return existingRequest;
    }

    final now = DateTime.now();
    final isRecentDuplicate =
        _lastNotificationFingerprint == fingerprint &&
        _lastNotificationAt != null &&
        now.difference(_lastNotificationAt!) < _notificationDedupeWindow;
    if (isRecentDuplicate) {
      return;
    }

    final request = _createNotification(
      title: normalizedTitle,
      message: normalizedMessage,
      type: normalizedType,
      targetType: normalizedTargetType,
      targetRole: targetRole,
      targetUser: targetUser,
      targetGat: targetGat,
    );
    _inFlightNotificationRequests[fingerprint] = request;

    try {
      await request;
      _lastNotificationFingerprint = fingerprint;
      _lastNotificationAt = DateTime.now();
    } finally {
      _inFlightNotificationRequests.remove(fingerprint);
    }
  }

  static Future<void> _createNotification({
    required String title,
    required String message,
    String? type,
    String? targetType,
    int? targetRole,
    int? targetUser,
    int? targetGat,
  }) async {
    try {
      final uri = Uri.parse(ApiEndpoints.createNotification);
      String extractErrorMessage(Map<String, dynamic> decoded) {
        final detail = decoded['detail']?.toString();
        if (detail != null && detail.isNotEmpty) {
          return detail;
        }

        final message = decoded['message']?.toString();
        if (message != null && message.isNotEmpty) {
          return message;
        }

        for (final entry in decoded.entries) {
          final value = entry.value;
          if (value is List && value.isNotEmpty) {
            return '${entry.key}: ${value.first}';
          }
          if (value is String && value.trim().isNotEmpty) {
            return '${entry.key}: $value';
          }
        }
        return 'Bad request';
      }

      Future<http.Response?> sendPayload(Map<String, dynamic> payload) async {
        debugPrint('[createNotification] POST $uri payload=$payload');
        return AuthorizedApiService.sendWithAutoRefresh(
          null,
          (token) => http.post(
            uri,
            headers: ApiEndpoints.authorizedHeaders(token),
            body: jsonEncode(payload),
          ),
        );
      }

      Map<String, dynamic> buildPayload({String? overrideTargetType}) {
        final payload = <String, dynamic>{'title': title, 'message': message};
        if (type != null && type.isNotEmpty) {
          payload['type'] = type;
        }
        final effectiveTargetType = overrideTargetType ?? targetType;
        if (effectiveTargetType != null && effectiveTargetType.isNotEmpty) {
          payload['target_type'] = effectiveTargetType;
        }
        if (targetRole != null) {
          payload['target_role'] = targetRole;
        }
        if (targetUser != null) {
          payload['target_user'] = targetUser;
        }
        if (targetGat != null) {
          payload['target_gat'] = targetGat;
        }
        return payload;
      }

      final payloadAttempts = <Map<String, dynamic>>[buildPayload()];

      String? lastError;

      for (final payload in payloadAttempts) {
        final response = await sendPayload(payload);

        if (response == null) {
          throw Exception('Session expired. Please login again.');
        }

        debugPrint(
          '[createNotification] status=${response.statusCode}, body=${response.body}',
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          if (response.body.trim().isEmpty) {
            return;
          }

          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            final status = decoded['status'];
            if (status == null || status == true || status == 'success') {
              return;
            }
            final err = extractErrorMessage(decoded);
            throw Exception(err);
          }
          return;
        }

        if (response.statusCode == 401) {
          throw Exception('Session expired. Please login again.');
        }

        if (response.statusCode == 400) {
          try {
            final decoded = jsonDecode(response.body);
            if (decoded is Map<String, dynamic>) {
              lastError = extractErrorMessage(decoded);
            }
          } catch (_) {
            lastError = 'Bad request';
          }
          // Try next payload variant if available.
          continue;
        }

        throw Exception(
          'Failed to send notification (status code ${response.statusCode})',
        );
      }

      throw Exception(lastError ?? 'Failed to send notification (Bad Request)');
    } catch (e, st) {
      await BugReportService.reportApiFailure(
        title: 'Create notification API failure',
        errorMessage: e.toString(),
        stackTrace: st.toString(),
        pageUrl: '/notifications/create',
        endpoint: ApiEndpoints.createNotification,
      );
      rethrow;
    }
  }

  static Future<bool> _handleTokenRefresh() async {
    try {
      return await AuthService.refreshAccessToken();
    } catch (e) {
      return false;
    }
  }

  static FeatureFlags _parseFeatureFlagsResponse(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid feature flags response format');
      }

      final dynamic payload =
          decoded['featureFlags'] ??
          decoded['feature_flags'] ??
          decoded['data'] ??
          decoded;

      if (payload is! Map<String, dynamic>) {
        throw Exception('Feature flags payload is not an object');
      }

      return FeatureFlags.fromJson(payload);
    } catch (e) {
      throw Exception("Failed to parse feature flags response: $e");
    }
  }

  static Future<http.Response> _fetchFeatureFlags() {
    return _storage.read(key: ApiEndpoints.accessTokenKey).then((token) {
      final normalizedToken = token?.trim();
      final headers = (normalizedToken != null && normalizedToken.isNotEmpty)
          ? ApiEndpoints.authorizedHeaders(normalizedToken)
          : ApiEndpoints.jsonHeaders();

      return http.get(Uri.parse(ApiEndpoints.featureFlags), headers: headers);
    });
  }
}
