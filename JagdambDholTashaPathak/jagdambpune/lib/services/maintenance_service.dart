import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/api_endpoints.dart';
import '../models/maintenance_models.dart';
import 'authorized_api_service.dart';
import 'refresh_token_service.dart';

class MaintenanceApiException implements Exception {
  final int statusCode;
  final String message;

  const MaintenanceApiException({
    required this.statusCode,
    required this.message,
  });

  @override
  String toString() => message;
}

class MaintenanceService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String completedEventStatus = 'completed';

  static const List<String> inventoryCategories = <String>[
    'dhol',
    'tasha',
    'dhwaj',
    'others',
  ];

  static const List<String> statuses = <String>[
    'pending',
    'approved',
    'rejected',
  ];

  static Future<List<InventoryItem>> fetchInventory() async {
    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.get(
        Uri.parse(ApiEndpoints.maintenanceInventory),
        headers: ApiEndpoints.authorizedHeaders(token),
      ),
    );

    final data = _decodeAndValidate(
      response,
      fallbackError: 'Failed to load inventory.',
    );
    final list = data['inventory'];
    if (list is! List) return <InventoryItem>[];
    return list
        .whereType<Map>()
        .map((e) => InventoryItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<Map<String, dynamic>> createOrUpdateInventory({
    required String category,
    required String name,
    required int quantity,
    String otherCategoryName = '',
  }) async {
    final payload = <String, dynamic>{
      'category': category,
      'name': name,
      'quantity': quantity,
      'other_category_name': otherCategoryName,
    };

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.post(
        Uri.parse(ApiEndpoints.maintenanceInventory),
        headers: ApiEndpoints.authorizedHeaders(token),
        body: jsonEncode(payload),
      ),
    );

    return _decodeAndValidate(
      response,
      fallbackError: 'Failed to add/update inventory.',
    );
  }

  static Future<Map<String, dynamic>> renameInventoryItem({
    required int inventoryItemId,
    required String name,
    String otherCategoryName = '',
  }) async {
    final payload = <String, dynamic>{
      'name': name,
      'other_category_name': otherCategoryName,
    };

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.patch(
        Uri.parse(ApiEndpoints.getMaintenanceInventoryItem(inventoryItemId)),
        headers: ApiEndpoints.authorizedHeaders(token),
        body: jsonEncode(payload),
      ),
    );

    return _decodeAndValidate(
      response,
      fallbackError: 'Failed to rename inventory item.',
    );
  }

  static Future<Map<String, dynamic>> deleteInventoryItem({
    required int inventoryItemId,
  }) async {
    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.delete(
        Uri.parse(ApiEndpoints.getMaintenanceInventoryItem(inventoryItemId)),
        headers: ApiEndpoints.authorizedHeaders(token),
      ),
    );

    return _decodeAndValidate(
      response,
      fallbackError: 'Failed to delete inventory item.',
    );
  }

  static Future<List<InventoryRequestItem>> fetchInventoryRequests({
    String? status,
  }) async {
    final uri = Uri.parse(ApiEndpoints.maintenanceInventoryRequests).replace(
      queryParameters: {
        if (status != null && status.trim().isNotEmpty) 'status': status,
      },
    );

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.get(uri, headers: ApiEndpoints.authorizedHeaders(token)),
    );

    final data = _decodeAndValidate(
      response,
      fallbackError: 'Failed to load inventory requests.',
    );
    final list = data['requests'];
    if (list is! List) return <InventoryRequestItem>[];
    return list
        .whereType<Map>()
        .map((e) => InventoryRequestItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<Map<String, dynamic>> createInventoryRequest({
    required int inventoryItemId,
    required int requestedQuantity,
    String note = '',
    int? maintenanceId,
    int? eventId,
  }) async {
    final payload = <String, dynamic>{
      'inventory_item_id': inventoryItemId,
      'requested_quantity': requestedQuantity,
      'note': note,
      if (maintenanceId != null) 'maintenance_id': maintenanceId,
      if (eventId != null) 'event_id': eventId,
    };

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.post(
        Uri.parse(ApiEndpoints.maintenanceInventoryRequests),
        headers: ApiEndpoints.authorizedHeaders(token),
        body: jsonEncode(payload),
      ),
    );

    return _decodeAndValidate(
      response,
      fallbackError: 'Failed to submit inventory request.',
    );
  }

  static Future<Map<String, dynamic>> actOnInventoryRequest({
    required int requestId,
    required String action,
    String adminNote = '',
  }) async {
    final payload = <String, dynamic>{
      'request_id': requestId,
      'action': action,
      'admin_note': adminNote,
    };

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.post(
        Uri.parse(ApiEndpoints.maintenanceInventoryRequestAction),
        headers: ApiEndpoints.authorizedHeaders(token),
        body: jsonEncode(payload),
      ),
    );

    return _decodeAndValidate(
      response,
      fallbackError: 'Failed to update inventory request.',
    );
  }

  static Future<List<DholMaintenanceEntry>> fetchEntries({
    String? status,
    int? gatId,
  }) async {
    final uri = Uri.parse(ApiEndpoints.maintenanceEntries).replace(
      queryParameters: {
        if (status != null && status.trim().isNotEmpty) 'status': status,
        if (gatId != null) 'gat_id': gatId.toString(),
      },
    );

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.get(uri, headers: ApiEndpoints.authorizedHeaders(token)),
    );

    if (response == null) {
      throw const MaintenanceApiException(
        statusCode: 401,
        message: 'Session expired. Please login again.',
      );
    }

    final decoded = _decodeBodySafely(
      response,
      fallbackError: 'Failed to load maintenance entries.',
      apiName: 'fetchEntries',
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorMessage = decoded is Map<String, dynamic>
          ? decoded['message']?.toString() ??
                'Failed to load maintenance entries.'
          : 'Failed to load maintenance entries.';
      throw MaintenanceApiException(
        statusCode: response.statusCode,
        message: errorMessage,
      );
    }

    List<dynamic> rawList = <dynamic>[];

    if (decoded is List) {
      rawList = decoded;
    } else if (decoded is Map<String, dynamic>) {
      final nestedData = decoded['data'];
      rawList =
          (decoded['entries'] as List?) ??
          (decoded['maintenance_entries'] as List?) ??
          (decoded['results'] as List?) ??
          (decoded['data'] as List?) ??
          (nestedData is Map<String, dynamic>
              ? (nestedData['entries'] as List?) ??
                    (nestedData['maintenance_entries'] as List?) ??
                    (nestedData['results'] as List?)
              : null) ??
          <dynamic>[];
    }

    if (rawList.isEmpty) return <DholMaintenanceEntry>[];

    return rawList
        .whereType<Map>()
        .map((e) => DholMaintenanceEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<Map<String, dynamic>> createEntry({
    required String dholNumber,
    required String workNotes,
  }) async {
    final payload = <String, dynamic>{
      'dhol_number': dholNumber,
      'work_notes': workNotes,
    };

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.post(
        Uri.parse(ApiEndpoints.maintenanceEntries),
        headers: ApiEndpoints.authorizedHeaders(token),
        body: jsonEncode(payload),
      ),
    );

    return _decodeAndValidate(
      response,
      fallbackError: 'Failed to submit maintenance entry.',
    );
  }

  static Future<Map<String, dynamic>> actOnEntry({
    required int entryId,
    required String action,
    String approverNote = '',
  }) async {
    final payload = <String, dynamic>{
      'entry_id': entryId,
      'action': action,
      'approver_note': approverNote,
    };

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.post(
        Uri.parse(ApiEndpoints.maintenanceEntryAction),
        headers: ApiEndpoints.authorizedHeaders(token),
        body: jsonEncode(payload),
      ),
    );

    return _decodeAndValidate(
      response,
      fallbackError: 'Failed to update maintenance entry.',
    );
  }

  static Future<MaintenanceAnalysis> fetchAnalysis() async {
    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.get(
        Uri.parse(ApiEndpoints.maintenanceAnalysis),
        headers: ApiEndpoints.authorizedHeaders(token),
      ),
    );

    final data = _decodeAndValidate(
      response,
      fallbackError: 'Failed to load maintenance analysis.',
    );

    return MaintenanceAnalysis.fromJson(data);
  }

  static Future<List<MaintenanceEvent>> fetchMaintenanceEvents({
    String? status,
    String? date,
    String? scope,
  }) async {
    final uri = Uri.parse(ApiEndpoints.maintenanceEvents).replace(
      queryParameters: {
        if (status != null && status.trim().isNotEmpty) 'status': status,
        if (date != null && date.trim().isNotEmpty) 'date': date,
        if (scope != null && scope.trim().isNotEmpty) 'scope': scope,
      },
    );

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.get(uri, headers: ApiEndpoints.authorizedHeaders(token)),
    );

    final data = _decodeAndValidate(
      response,
      fallbackError: 'Failed to load maintenance events.',
    );
    final list = data['events'];
    if (list is! List) return <MaintenanceEvent>[];
    final events = list
        .whereType<Map>()
        .map((e) => MaintenanceEvent.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    return events;
  }

  static Future<Map<String, dynamic>> createMaintenanceEvent({
    required String title,
    required String eventDate,
    required String scope,
    String description = '',
    int? assignedGatId,
  }) async {
    final payload = <String, dynamic>{
      'title': title,
      'description': description,
      'event_date': eventDate,
      'scope': scope,
      if (assignedGatId != null) 'assigned_gat_id': assignedGatId,
    };

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.post(
        Uri.parse(ApiEndpoints.maintenanceEvents),
        headers: ApiEndpoints.authorizedHeaders(token),
        body: jsonEncode(payload),
      ),
    );

    return _decodeAndValidate(
      response,
      fallbackError: 'Failed to create maintenance event.',
    );
  }

  static Future<Map<String, dynamic>> closeMaintenanceEvent({
    required int eventId,
  }) async {
    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.post(
        Uri.parse(ApiEndpoints.getMaintenanceEventClose(eventId)),
        headers: ApiEndpoints.authorizedHeaders(token),
      ),
    );

    return _decodeAndValidate(
      response,
      fallbackError: 'Failed to close maintenance event.',
    );
  }

  static Future<List<MaintenanceCompletionRequest>> fetchCompletionRequests({
    String? status,
    int? eventId,
    String? eventDate,
    bool? myActionable,
  }) async {
    final uri = Uri.parse(ApiEndpoints.maintenanceCompletionRequests).replace(
      queryParameters: {
        if (status != null && status.trim().isNotEmpty) 'status': status,
        if (eventId != null) 'event_id': '$eventId',
        if (eventDate != null && eventDate.trim().isNotEmpty)
          'event_date': eventDate,
        if (myActionable == true) 'my_actionable': 'true',
      },
    );

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.get(uri, headers: ApiEndpoints.authorizedHeaders(token)),
    );

    final data = _decodeAndValidate(
      response,
      fallbackError: 'Failed to load completion requests.',
    );
    final list = data['completion_requests'];
    if (list is! List) return <MaintenanceCompletionRequest>[];
    return list
        .whereType<Map>()
        .map(
          (e) => MaintenanceCompletionRequest.fromJson(
            Map<String, dynamic>.from(e),
          ),
        )
        .toList();
  }

  static Future<Map<String, dynamic>> createCompletionRequest({
    required int maintenanceId,
    int? eventId,
    required String workNotes,
    List<Map<String, int>> usedItems = const <Map<String, int>>[],
  }) async {
    Future<Map<String, dynamic>> submit(Map<String, dynamic> payload) async {
      final endpoint = eventId != null
          ? ApiEndpoints.getMaintenanceEventCompletionRequests(eventId)
          : ApiEndpoints.maintenanceCompletionRequests;
      final response = await AuthorizedApiService.sendWithAutoRefresh(
        null,
        (token) => http.post(
          Uri.parse(endpoint),
          headers: ApiEndpoints.authorizedHeaders(token),
          body: jsonEncode(payload),
        ),
      );

      return _decodeAndValidate(
        response,
        fallbackError: 'Failed to submit completion request.',
      );
    }

    final normalizedUsedItems = usedItems
        .map(
          (item) => <String, int>{
            'inventory_item_id': item['inventory_item_id'] ?? 0,
            'quantity_used': item['quantity_used'] ?? 0,
          },
        )
        .where(
          (item) =>
              item['inventory_item_id']! > 0 && item['quantity_used']! > 0,
        )
        .toList();

    final payloadCandidates = <Map<String, dynamic>>[
      // Maintenance-aware flow: backend derives approved stock from approved
      // stock requests linked to this maintenance/event. Avoid re-sending
      // used_items to prevent duplicate stock consumption during approval.
      <String, dynamic>{
        'maintenance_id': maintenanceId,
        'work_notes': workNotes,
      },
      <String, dynamic>{
        'maintenance_id': maintenanceId,
        'work_notes': workNotes,
        'used_items': null,
      },
      <String, dynamic>{
        'maintenance_id': maintenanceId,
        'work_notes': workNotes,
        'used_items': const [],
      },
      // Legacy fallback only if backend explicitly requires used_items.
      if (normalizedUsedItems.isNotEmpty)
        <String, dynamic>{
          'maintenance_id': maintenanceId,
          'work_notes': workNotes,
          'used_items': normalizedUsedItems,
        },
    ];

    final seenPayloads = <String>{};
    MaintenanceApiException? lastValidationError;

    for (final payload in payloadCandidates) {
      final key = jsonEncode(payload);
      if (!seenPayloads.add(key)) {
        continue;
      }

      try {
        return await submit(payload);
      } on MaintenanceApiException catch (e) {
        lastValidationError = e;
        if (e.statusCode != 400 && e.statusCode != 422) {
          rethrow;
        }
      }
    }

    if (lastValidationError != null) {
      throw lastValidationError;
    }

    throw const MaintenanceApiException(
      statusCode: 400,
      message: 'Failed to submit completion request.',
    );
  }

  static Future<Map<String, dynamic>> actOnCompletionRequest({
    required int requestId,
    required String action,
    String approverNote = '',
  }) async {
    Future<Map<String, dynamic>> submit(Map<String, dynamic> payload) async {
      final response = await AuthorizedApiService.sendWithAutoRefresh(
        null,
        (token) => http.post(
          Uri.parse(
            ApiEndpoints.getMaintenanceCompletionRequestAction(requestId),
          ),
          headers: ApiEndpoints.authorizedHeaders(token),
          body: jsonEncode(payload),
        ),
      );

      return _decodeAndValidate(
        response,
        fallbackError: 'Failed to update completion request.',
      );
    }

    final normalizedAction = action.trim().toLowerCase();
    final basePayload = <String, dynamic>{
      'action': action,
      'approver_note': approverNote,
    };

    final payloadCandidates = <Map<String, dynamic>>[
      if (normalizedAction == 'approve')
        <String, dynamic>{
          ...basePayload,
          'skip_stock_validation': true,
          'skip_inventory_validation': true,
          'consume_stock': false,
        },
      basePayload,
    ];

    final seenPayloads = <String>{};
    MaintenanceApiException? lastValidationError;

    for (final payload in payloadCandidates) {
      final key = jsonEncode(payload);
      if (!seenPayloads.add(key)) {
        continue;
      }

      try {
        return await submit(payload);
      } on MaintenanceApiException catch (e) {
        lastValidationError = e;
        if (e.statusCode != 400 && e.statusCode != 422) {
          rethrow;
        }
      }
    }

    if (lastValidationError != null) {
      throw lastValidationError;
    }

    throw const MaintenanceApiException(
      statusCode: 400,
      message: 'Failed to update completion request.',
    );
  }

  static Future<Map<String, dynamic>> createDholRange({
    required int startNumber,
    required int endNumber,
  }) async {
    final payload = <String, dynamic>{
      'start_number': startNumber,
      'end_number': endNumber,
    };

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.post(
        Uri.parse(ApiEndpoints.maintenanceDholRanges),
        headers: ApiEndpoints.authorizedHeaders(token),
        body: jsonEncode(payload),
      ),
    );

    return _decodeAndValidate(
      response,
      fallbackError: 'Failed to create dhol range.',
    );
  }

  static Future<List<PathakDhol>> fetchPathakDhols() async {
    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.get(
        Uri.parse(ApiEndpoints.maintenancePathakDhols),
        headers: ApiEndpoints.authorizedHeaders(token),
      ),
    );

    final data = _decodeAndValidate(
      response,
      fallbackError: 'Failed to load pathak dhols.',
    );

    final dynamic listCandidate =
        data['pathak_dhols'] ??
        data['dhols'] ??
        data['results'] ??
        data['data'] ??
        (data['items'] is List ? data['items'] : null);

    if (listCandidate is! List) {
      return <PathakDhol>[];
    }

    return listCandidate
        .whereType<Map>()
        .map((item) => PathakDhol.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Future<Map<String, dynamic>> updatePathakDholStatus({
    required int dholId,
    required String status,
  }) async {
    final payload = <String, dynamic>{'status': status};

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.patch(
        Uri.parse(ApiEndpoints.getMaintenancePathakDholStatus(dholId)),
        headers: ApiEndpoints.authorizedHeaders(token),
        body: jsonEncode(payload),
      ),
    );

    return _decodeAndValidate(
      response,
      fallbackError: 'Failed to update dhol status.',
    );
  }

  static Future<Map<String, dynamic>> markPathakDholAsDamaged({
    required int dholId,
    required String remarks,
  }) async {
    final payload = <String, dynamic>{'remarks': remarks};

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.patch(
        Uri.parse(ApiEndpoints.getMaintenancePathakDholMarkDamaged(dholId)),
        headers: ApiEndpoints.authorizedHeaders(token),
        body: jsonEncode(payload),
      ),
    );

    return _decodeAndValidate(
      response,
      fallbackError: 'Failed to mark dhol as damaged.',
    );
  }

  static Future<List<PathakDhol>> fetchGoodConditionPathakDhols() async {
    final uri = Uri.parse(ApiEndpoints.maintenancePathakDhols).replace(
      queryParameters: const <String, String>{'status': 'good_condition'},
    );

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.get(uri, headers: ApiEndpoints.authorizedHeaders(token)),
    );

    final data = _decodeAndValidate(
      response,
      fallbackError: 'Failed to load good condition dhols.',
    );

    final dynamic listCandidate =
        data['pathak_dhols'] ??
        data['dhols'] ??
        data['results'] ??
        data['data'];
    if (listCandidate is! List) {
      return <PathakDhol>[];
    }

    return listCandidate
        .whereType<Map>()
        .map((item) => PathakDhol.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Future<List<PathakDhol>> fetchDamagedPathakDhols() async {
    final uri = Uri.parse(
      ApiEndpoints.maintenancePathakDhols,
    ).replace(queryParameters: const <String, String>{'status': 'damaged'});

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.get(uri, headers: ApiEndpoints.authorizedHeaders(token)),
    );

    final data = _decodeAndValidate(
      response,
      fallbackError: 'Failed to load damaged dhols.',
    );

    final dynamic listCandidate =
        data['pathak_dhols'] ??
        data['dhols'] ??
        data['results'] ??
        data['data'];
    if (listCandidate is! List) {
      return <PathakDhol>[];
    }

    return listCandidate
        .whereType<Map>()
        .map((item) => PathakDhol.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Future<List<CheckedInMaintenancePartner>>
  fetchCheckedInMaintenancePartners() async {
    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.get(
        Uri.parse(ApiEndpoints.maintenanceCheckedInMembers),
        headers: ApiEndpoints.authorizedHeaders(token),
      ),
    );

    final data = _decodeAndValidate(
      response,
      fallbackError: 'Failed to load eligible partners.',
    );

    final dynamic listCandidate =
        data['members'] ??
        data['checked_in_members'] ??
        data['results'] ??
        data['data'];
    if (listCandidate is! List) {
      return <CheckedInMaintenancePartner>[];
    }

    return listCandidate
        .whereType<Map>()
        .map(
          (item) => CheckedInMaintenancePartner.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }

  static Future<Map<String, dynamic>> startInstrumentMaintenance({
    required int instrumentId,
    required List<int> participantUserIds,
  }) async {
    final payload = <String, dynamic>{
      'instrument_id': instrumentId,
      'participant_user_ids': participantUserIds,
    };

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.post(
        Uri.parse(ApiEndpoints.maintenanceStartPathakInstrument),
        headers: ApiEndpoints.authorizedHeaders(token),
        body: jsonEncode(payload),
      ),
    );

    return _decodeAndValidate(
      response,
      fallbackError: 'Failed to start maintenance.',
    );
  }

  static Future<List<PathakInstrumentMaintenance>>
  fetchMyActiveInstrumentMaintenances() async {
    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.get(
        Uri.parse(ApiEndpoints.maintenanceMyActivePathakInstruments),
        headers: ApiEndpoints.authorizedHeaders(token),
      ),
    );

    final data = _decodeAndValidate(
      response,
      fallbackError: 'Failed to load active maintenances.',
    );

    return _parsePathakInstrumentMaintenances(data);
  }

  static Future<List<PathakInstrumentMaintenance>>
  fetchInstrumentMaintenancesForReview() async {
    // Completion requests remain the single approval queue. This endpoint is
    // only for role-aware visibility into instrument maintenances.
    Future<http.Response?> fetchFrom(String url) {
      return AuthorizedApiService.sendWithAutoRefresh(
        null,
        (token) => http.get(
          Uri.parse(url),
          headers: ApiEndpoints.authorizedHeaders(token),
        ),
      );
    }

    try {
      final response = await fetchFrom(
        ApiEndpoints.maintenancePathakInstrumentMaintenances,
      );
      final data = _decodeAndValidate(
        response,
        fallbackError: 'Failed to load instrument maintenances.',
      );
      return _parsePathakInstrumentMaintenances(data);
    } on MaintenanceApiException catch (e) {
      // Some deployments don't expose the review endpoint and return a 404
      // HTML page. Fall back to the participant-scoped active list so the
      // screen still loads instead of failing entirely.
      if (e.statusCode != 404) {
        rethrow;
      }

      if (kDebugMode) {
        debugPrint(
          '[MaintenanceApi] Review maintenances endpoint unavailable (404). Falling back to my-active endpoint.',
        );
      }

      final fallbackResponse = await fetchFrom(
        ApiEndpoints.maintenanceMyActivePathakInstruments,
      );
      final fallbackData = _decodeAndValidate(
        fallbackResponse,
        fallbackError: 'Failed to load active maintenances.',
      );
      return _parsePathakInstrumentMaintenances(fallbackData);
    }
  }

  static List<PathakInstrumentMaintenance> _parsePathakInstrumentMaintenances(
    Map<String, dynamic> data,
  ) {
    final nestedData = data['data'];
    final nestedMap = nestedData is Map
        ? Map<String, dynamic>.from(nestedData)
        : null;

    final dynamic listCandidate =
        data['maintenances'] ??
        data['maintenance_requests'] ??
        data['results'] ??
        (nestedMap != null
            ? nestedMap['maintenances'] ??
                  nestedMap['maintenance_requests'] ??
                  nestedMap['results'] ??
                  nestedMap['items']
            : null) ??
        data['items'];
    if (listCandidate is! List) {
      return <PathakInstrumentMaintenance>[];
    }

    return listCandidate
        .whereType<Map>()
        .map(
          (item) => PathakInstrumentMaintenance.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }

  static Future<PathakInstrumentMaintenance> fetchInstrumentMaintenanceDetail(
    int maintenanceId,
  ) async {
    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.get(
        Uri.parse(
          ApiEndpoints.getPathakInstrumentMaintenanceDetail(maintenanceId),
        ),
        headers: ApiEndpoints.authorizedHeaders(token),
      ),
    );

    final data = _decodeAndValidate(
      response,
      fallbackError: 'Failed to load maintenance detail.',
    );

    final dynamic maintenanceData =
        data['maintenance'] ?? data['data'] ?? data['result'] ?? data;
    if (maintenanceData is! Map) {
      throw const MaintenanceApiException(
        statusCode: 500,
        message: 'Invalid maintenance detail response.',
      );
    }

    return PathakInstrumentMaintenance.fromJson(
      Map<String, dynamic>.from(maintenanceData),
    );
  }

  static Future<Map<String, dynamic>> submitInstrumentMaintenance({
    required int maintenanceId,
    required String workPerformed,
    required String remarks,
    List<({Uint8List bytes, String fileName})> beforeImages =
        const <({Uint8List bytes, String fileName})>[],
    List<({Uint8List bytes, String fileName})> afterImages =
        const <({Uint8List bytes, String fileName})>[],
  }) async {
    final files = <({String fieldName, Uint8List bytes, String fileName})>[
      ...beforeImages.map(
        (item) => (
          fieldName: 'before_images',
          bytes: item.bytes,
          fileName: item.fileName,
        ),
      ),
      ...afterImages.map(
        (item) => (
          fieldName: 'after_images',
          bytes: item.bytes,
          fileName: item.fileName,
        ),
      ),
    ];

    return _sendMultipartWithAutoRefresh(
      method: 'POST',
      url: ApiEndpoints.getPathakInstrumentMaintenanceSubmit(maintenanceId),
      fields: <String, String>{
        'work_performed': workPerformed,
        'remarks': remarks,
        'consume_stock': 'false',
      },
      files: files,
      fallbackError: 'Failed to submit maintenance.',
    );
  }

  static Future<Map<String, dynamic>> actOnInstrumentMaintenance({
    required int maintenanceId,
    required String action,
    String approverNote = '',
    String rejectionRemarks = '',
  }) async {
    final payload = <String, dynamic>{
      'action': action,
      'approver_note': approverNote,
      if (rejectionRemarks.trim().isNotEmpty)
        'rejection_remarks': rejectionRemarks,
    };

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.post(
        Uri.parse(
          ApiEndpoints.getPathakInstrumentMaintenanceAction(maintenanceId),
        ),
        headers: ApiEndpoints.authorizedHeaders(token),
        body: jsonEncode(payload),
      ),
    );

    return _decodeAndValidate(
      response,
      fallbackError: 'Failed to update maintenance approval.',
    );
  }

  static Future<Map<String, dynamic>> _sendMultipartWithAutoRefresh({
    required String method,
    required String url,
    required Map<String, String> fields,
    required List<({String fieldName, Uint8List bytes, String fileName})> files,
    required String fallbackError,
  }) async {
    final token = await _storage.read(key: ApiEndpoints.accessTokenKey);
    if (token == null || token.trim().isEmpty) {
      throw const MaintenanceApiException(
        statusCode: 401,
        message: 'Session expired. Please login again.',
      );
    }

    Future<http.Response> send(String accessToken) async {
      final request = http.MultipartRequest(method, Uri.parse(url))
        ..headers['Authorization'] = 'Bearer $accessToken'
        ..headers['Accept'] = 'application/json'
        ..fields.addAll(fields);

      for (final file in files) {
        request.files.add(
          http.MultipartFile.fromBytes(
            file.fieldName,
            file.bytes,
            filename: file.fileName,
          ),
        );
      }

      final streamed = await request.send();
      return http.Response.fromStream(streamed);
    }

    var response = await send(token);
    if (response.statusCode == 401) {
      final refreshed = await AuthService.refreshAccessToken();
      if (refreshed) {
        final refreshedToken = await _storage.read(
          key: ApiEndpoints.accessTokenKey,
        );
        if (refreshedToken != null && refreshedToken.trim().isNotEmpty) {
          response = await send(refreshedToken);
        }
      }
    }

    return _decodeAndValidate(response, fallbackError: fallbackError);
  }

  static Map<String, dynamic> _decodeAndValidate(
    http.Response? response, {
    required String fallbackError,
  }) {
    if (response == null) {
      throw const MaintenanceApiException(
        statusCode: 401,
        message: 'Session expired. Please login again.',
      );
    }

    final decoded = _decodeBodySafely(
      response,
      fallbackError: fallbackError,
      apiName: response.request?.url.path,
    );

    final data = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    final message = data['message']?.toString() ?? fallbackError;
    throw MaintenanceApiException(
      statusCode: response.statusCode,
      message: message,
    );
  }

  static dynamic _decodeBodySafely(
    http.Response response, {
    required String fallbackError,
    String? apiName,
  }) {
    final body = response.body.trim();
    if (body.isEmpty || body == 'null') {
      return <String, dynamic>{};
    }

    try {
      return jsonDecode(body);
    } on FormatException catch (e) {
      // Only log parse errors for success responses — non-2xx bodies (e.g. a
      // Django 404 HTML page) are expected to be non-JSON and handled by
      // callers that check the status code (e.g. the 404 fallback in
      // fetchInstrumentMaintenancesForReview).
      if (kDebugMode &&
          response.statusCode >= 200 &&
          response.statusCode < 300) {
        debugPrint('[MaintenanceApi JSON Parse Error]');
        debugPrint('API Name: ${apiName ?? 'unknown'}');
        debugPrint('Response Status: ${response.statusCode}');
        debugPrint('Response Body: ${_safeBodyPreview(body)}');
        debugPrint('JSON Parse Exception: ${e.message}');
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return <String, dynamic>{};
      }

      throw MaintenanceApiException(
        statusCode: response.statusCode,
        message: fallbackError,
      );
    }
  }

  static String _safeBodyPreview(String body) {
    if (body.length <= 1000) {
      return body;
    }
    return '${body.substring(0, 1000)}...<truncated>';
  }
}
