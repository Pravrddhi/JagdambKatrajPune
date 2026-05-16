import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_endpoints.dart';
import '../models/item_catalog_item.dart';
import '../models/user_item.dart';
import '../services/authorized_api_service.dart';

class UserItemService {
  static dynamic _decodeBodySafely(String body) {
    if (body.trim().isEmpty || body.trimLeft().startsWith('<')) {
      return null;
    }
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    return null;
  }

  static List<dynamic>? _asList(dynamic value) {
    if (value is List) return value;
    return null;
  }

  static String? _extractError(dynamic body) {
    final map = _asMap(body);
    if (map == null) return null;
    final detail = map['detail'] ?? map['message'];
    if (detail != null && detail.toString().trim().isNotEmpty) {
      return detail.toString();
    }
    for (final entry in map.entries) {
      final value = entry.value;
      if (value is List && value.isNotEmpty) {
        return value.first.toString();
      }
    }
    return null;
  }

  /// Fetch the current user's items.
  ///
  /// All query parameters are optional:
  ///   [itemType]       – filter by item_type (e.g. 'jacket', 'instrument')
  ///   [paymentStatus]  – filter by payment_status (e.g. 'paid', 'pending')
  ///   [userId]         – filter by user id (admin use)
  static Future<List<UserItem>> fetchMyItems({
    String? itemType,
    String? paymentStatus,
    int? userId,
  }) async {
    final query = <String, dynamic>{
      if (itemType != null && itemType.isNotEmpty) 'item_type': itemType,
      if (paymentStatus != null && paymentStatus.isNotEmpty)
        'payment_status': paymentStatus,
      if (userId != null) 'user_id': userId,
    };

    final uri = ApiEndpoints.buildUri(ApiEndpoints.userItems, query);

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.get(uri, headers: ApiEndpoints.authorizedHeaders(token)),
    );

    if (response == null) {
      throw Exception('Session expired. Please login again.');
    }

    if (response.statusCode == 200) {
      final body = _decodeBodySafely(response.body);
      if (body == null) return [];
      if (body is List) {
        return UserItem.listFromJson(body);
      }
      // Some backends wrap the list in a data/results key.
      if (body is Map<String, dynamic>) {
        final inner = body['results'] ?? body['data'];
        if (inner is List) {
          return UserItem.listFromJson(inner);
        }
      }
      return [];
    }

    // Try to extract a human-readable message from the response body,
    // but guard against HTML / non-JSON error pages.
    final detail = _extractError(_decodeBodySafely(response.body));
    throw Exception(
      detail ?? 'Failed to load items (status ${response.statusCode})',
    );
  }

  /// Fetch pathak catalog items that can be requested/assigned.
  static Future<List<ItemCatalogItem>> fetchCatalog({
    String? itemType,
    bool showInactive = false,
  }) async {
    final query = <String, dynamic>{
      if (itemType != null && itemType.isNotEmpty) 'item_type': itemType,
      if (showInactive) 'show_inactive': 'true',
    };

    final uri = ApiEndpoints.buildUri(ApiEndpoints.itemCatalog, query);
    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.get(uri, headers: ApiEndpoints.authorizedHeaders(token)),
    );

    if (response == null) {
      throw Exception('Session expired. Please login again.');
    }

    if (response.statusCode == 200) {
      final body = _decodeBodySafely(response.body);
      if (body is List) {
        return ItemCatalogItem.listFromJson(body);
      }
      final map = _asMap(body);
      final data = map == null ? null : _asList(map['data'] ?? map['results']);
      if (data != null) {
        return ItemCatalogItem.listFromJson(data);
      }
      return <ItemCatalogItem>[];
    }

    final detail = _extractError(_decodeBodySafely(response.body));
    throw Exception(
      detail ?? 'Failed to load item catalog (status ${response.statusCode})',
    );
  }

  /// Create a new catalog item (admin only).
  static Future<ItemCatalogItem> createCatalogItem(
    Map<String, dynamic> payload,
  ) async {
    final uri = Uri.parse(ApiEndpoints.itemCatalog);

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.post(
        uri,
        headers: {
          ...ApiEndpoints.authorizedHeaders(token),
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      ),
    );

    if (response == null) {
      throw Exception('Session expired. Please login again.');
    }

    if (response.statusCode == 201 || response.statusCode == 200) {
      final decoded = _decodeBodySafely(response.body);
      final root = _asMap(decoded);
      if (root != null) {
        final data = _asMap(root['data']);
        if (data != null) {
          return ItemCatalogItem.fromJson(data);
        }
        if (root.containsKey('id')) {
          return ItemCatalogItem.fromJson(root);
        }
      }
      throw Exception('Unexpected response from server.');
    }

    final detail = _extractError(_decodeBodySafely(response.body));
    throw Exception(
      detail ?? 'Failed to create catalog item (status ${response.statusCode})',
    );
  }

  /// Create a new user item entry.
  static Future<UserItem> createItem(Map<String, dynamic> payload) async {
    final uri = Uri.parse(ApiEndpoints.userItems);

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.post(
        uri,
        headers: {
          ...ApiEndpoints.authorizedHeaders(token),
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      ),
    );

    if (response == null) {
      throw Exception('Session expired. Please login again.');
    }

    if (response.statusCode == 201 || response.statusCode == 200) {
      final decoded = _decodeBodySafely(response.body);
      final root = _asMap(decoded);
      if (root != null) {
        final data = _asMap(root['data']);
        if (data != null) {
          return UserItem.fromJson(data);
        }
        if (root.containsKey('id')) {
          return UserItem.fromJson(root);
        }
      }
      throw Exception('Unexpected response from server.');
    }

    final detail = _extractError(_decodeBodySafely(response.body));
    throw Exception(
      detail ?? 'Failed to create item (status ${response.statusCode})',
    );
  }

  /// Regular user flow: request an item from catalog.
  static Future<UserItem> requestItem({
    required int catalogItemId,
    String? size,
    String? notes,
  }) {
    return createItem({
      'catalog_item': catalogItemId,
      if (size != null && size.trim().isNotEmpty) 'size': size.trim(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
  }

  /// Fetch items pending the current user's action (pending_accept, admin_assigned, approved).
  /// The `count` field can be used as a badge number.
  static Future<List<UserItem>> fetchPendingItems() async {
    final uri = Uri.parse(ApiEndpoints.userItemsPending);
    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.get(uri, headers: ApiEndpoints.authorizedHeaders(token)),
    );

    if (response == null) {
      throw Exception('Session expired. Please login again.');
    }

    if (response.statusCode == 200) {
      final body = _decodeBodySafely(response.body);
      if (body is List) {
        return UserItem.listFromJson(body);
      }
      if (body is Map<String, dynamic>) {
        final inner = body['data'] ?? body['results'];
        if (inner is List) {
          return UserItem.listFromJson(inner);
        }
      }
      return [];
    }

    final detail = _extractError(_decodeBodySafely(response.body));
    throw Exception(
      detail ?? 'Failed to load pending items (status ${response.statusCode})',
    );
  }

  /// User confirms they received an assigned/issued/approved item.
  static Future<UserItem> confirmItemReceipt(
    int itemId, {
    String? notes,
  }) async {
    final uri = Uri.parse(ApiEndpoints.userItemConfirm(itemId));
    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.post(
        uri,
        headers: {
          ...ApiEndpoints.authorizedHeaders(token),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        }),
      ),
    );

    if (response == null) {
      throw Exception('Session expired. Please login again.');
    }

    if (response.statusCode == 200) {
      final decoded = _decodeBodySafely(response.body);
      final map = _asMap(decoded);
      final data = map == null ? null : _asMap(map['data']);
      if (data != null) {
        return UserItem.fromJson(data);
      }
      if (map != null && map.containsKey('id')) {
        return UserItem.fromJson(map);
      }
      throw Exception('Unexpected response from server.');
    }

    final detail = _extractError(_decodeBodySafely(response.body));
    throw Exception(
      detail ??
          'Failed to confirm item receipt (status ${response.statusCode})',
    );
  }

  /// Admin lifecycle action on an existing user item.
  static Future<UserItem> performAdminAction({
    required int itemId,
    required String action,
    String? statusNote,
    String? paymentAmount,
    String? paymentDate,
    String? issuedDate,
  }) async {
    final uri = Uri.parse(ApiEndpoints.userItemAction(itemId));
    final payload = <String, dynamic>{'action': action};
    if (statusNote != null && statusNote.trim().isNotEmpty) {
      payload['status_note'] = statusNote.trim();
    }
    if (paymentAmount != null && paymentAmount.trim().isNotEmpty) {
      payload['payment_amount'] = paymentAmount.trim();
    }
    if (paymentDate != null && paymentDate.trim().isNotEmpty) {
      payload['payment_date'] = paymentDate.trim();
    }
    if (issuedDate != null && issuedDate.trim().isNotEmpty) {
      payload['issued_date'] = issuedDate.trim();
    }

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http.post(
        uri,
        headers: {
          ...ApiEndpoints.authorizedHeaders(token),
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      ),
    );

    if (response == null) {
      throw Exception('Session expired. Please login again.');
    }

    if (response.statusCode == 200) {
      final decoded = _decodeBodySafely(response.body);
      final map = _asMap(decoded);
      final data = map == null ? null : _asMap(map['data']);
      if (data != null) {
        return UserItem.fromJson(data);
      }
      if (map != null && map.containsKey('id')) {
        return UserItem.fromJson(map);
      }
      throw Exception('Unexpected response from server.');
    }

    final detail = _extractError(_decodeBodySafely(response.body));
    throw Exception(
      detail ??
          'Failed to process action "$action" (status ${response.statusCode})',
    );
  }
}
