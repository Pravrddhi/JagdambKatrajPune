import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_endpoints.dart';
import '../models/maintenance_models.dart';
import 'authorized_api_service.dart';

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
    int? eventId,
  }) async {
    final payload = <String, dynamic>{
      'inventory_item_id': inventoryItemId,
      'requested_quantity': requestedQuantity,
      'note': note,
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

    final decoded = response.body.isNotEmpty
        ? jsonDecode(response.body)
        : <String, dynamic>{};

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
    required int eventId,
    required String workNotes,
    List<Map<String, int>> usedItems = const <Map<String, int>>[],
  }) async {
    Future<Map<String, dynamic>> submit(Map<String, dynamic> payload) async {
      final response = await AuthorizedApiService.sendWithAutoRefresh(
        null,
        (token) => http.post(
          Uri.parse(
            ApiEndpoints.getMaintenanceEventCompletionRequests(eventId),
          ),
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

    final payloadCandidates = <Map<String, dynamic>>[];

    if (normalizedUsedItems.isEmpty) {
      payloadCandidates.addAll(<Map<String, dynamic>>[
        <String, dynamic>{'work_notes': workNotes, 'used_items': const []},
        <String, dynamic>{'work_notes': workNotes, 'used_items': null},
        <String, dynamic>{'work_notes': workNotes},
      ]);
    } else {
      payloadCandidates.add(<String, dynamic>{
        'work_notes': workNotes,
        'used_items': normalizedUsedItems,
      });
    }

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
    final payload = <String, dynamic>{
      'action': action,
      'approver_note': approverNote,
    };

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

    final decoded = response.body.isNotEmpty
        ? jsonDecode(response.body)
        : <String, dynamic>{};

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
}
