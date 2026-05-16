import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/api_endpoints.dart';
import '../services/authorized_api_service.dart';

class AppNotification {
  final String id;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;
  final String? type;
  final String? readAt;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.isRead,
    this.type,
    this.readAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'message': message,
    'created_at': createdAt.toIso8601String(),
    'is_read': isRead,
    'type': type,
    'read_at': readAt,
  };

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id:
          json['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      title: json['title']?.toString() ?? 'Notification',
      message: json['message']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      isRead: json['is_read'] == true,
      type: json['type']?.toString(),
      readAt: json['read_at']?.toString(),
    );
  }
}

class NotificationProvider with ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _storageKey = 'app_notifications';
  static const _readNotificationIdsKey = 'read_notification_ids';
  static const _lastRefreshTimeKey = 'notification_cache_last_refresh';
  static const Duration _cacheRefreshWindow = Duration(days: 8);

  List<AppNotification> _notifications = [];
  Set<String> _readNotificationIds = <String>{};
  DateTime? _lastRefreshTime;
  int _serverUnreadCount = 0;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _serverUnreadCount;

  NotificationProvider() {
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadReadNotificationIds();
    await _checkAndRefreshCacheIfNeeded();
    await _loadFromStorage();
  }

  Future<void> refreshFromStorage() async {
    await _loadReadNotificationIds();
    await _checkAndRefreshCacheIfNeeded();
    await _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw == null || raw.isEmpty) {
        _notifications = [];
      } else {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _notifications = decoded
              .whereType<Map>()
              .map(
                (item) =>
                    AppNotification.fromJson(Map<String, dynamic>.from(item)),
              )
              .where(
                (item) =>
                    !item.isRead && !_readNotificationIds.contains(item.id),
              )
              .toList();
        } else {
          _notifications = [];
        }
      }
    } catch (_) {
      _notifications = [];
    }

    notifyListeners();
  }

  Future<void> _persist() async {
    final raw = jsonEncode(
      _notifications.map((item) => item.toJson()).toList(),
    );
    if (kIsWeb) {
      try {
        await _storage.write(key: _storageKey, value: raw);
      } catch (_) {
        // Best effort persistence for web.
      }
      return;
    }
    await _storage.write(key: _storageKey, value: raw);
  }

  Future<void> _loadReadNotificationIds() async {
    try {
      final raw = await _storage.read(key: _readNotificationIdsKey);
      if (raw == null || raw.isEmpty) {
        _readNotificationIds = <String>{};
      } else {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _readNotificationIds = Set<String>.from(
            decoded.map((e) => e.toString()),
          );
        } else {
          _readNotificationIds = <String>{};
        }
      }
    } catch (_) {
      _readNotificationIds = <String>{};
    }
  }

  Future<void> _persistReadNotificationIds() async {
    final raw = jsonEncode(_readNotificationIds.toList());
    if (kIsWeb) {
      try {
        await _storage.write(key: _readNotificationIdsKey, value: raw);
      } catch (_) {
        // Best effort persistence for web.
      }
      return;
    }
    await _storage.write(key: _readNotificationIdsKey, value: raw);
  }

  Future<void> _checkAndRefreshCacheIfNeeded() async {
    try {
      final raw = await _storage.read(key: _lastRefreshTimeKey);
      if (raw == null || raw.isEmpty) {
        final now = DateTime.now();
        _lastRefreshTime = now;
        await _storage.write(
          key: _lastRefreshTimeKey,
          value: now.toIso8601String(),
        );
        return;
      }

      _lastRefreshTime = DateTime.tryParse(raw);
      if (_lastRefreshTime == null) {
        final now = DateTime.now();
        _lastRefreshTime = now;
        await _storage.write(
          key: _lastRefreshTimeKey,
          value: now.toIso8601String(),
        );
        return;
      }

      final lastRefreshTime = _lastRefreshTime;
      if (lastRefreshTime != null &&
          DateTime.now().difference(lastRefreshTime) >= _cacheRefreshWindow) {
        _readNotificationIds.clear();
        await _storage.delete(key: _readNotificationIdsKey);
        final now = DateTime.now();
        _lastRefreshTime = now;
        await _storage.write(
          key: _lastRefreshTimeKey,
          value: now.toIso8601String(),
        );
      }
    } catch (_) {
      // Ignore refresh-check failures.
    }
  }

  /// Prepends a notification received live from the WebSocket without a
  /// round-trip to the REST API.
  Future<void> prependNotification(Map<String, dynamic> json) async {
    final item = AppNotification.fromJson(json);
    // Avoid duplicates when the same event fires more than once.
    if (_notifications.any((n) => n.id == item.id)) return;
    _notifications = [item, ..._notifications];
    if (!item.isRead) _serverUnreadCount += 1;
    await _persist();
    notifyListeners();
  }

  Future<void> addNotification({
    required String title,
    required String message,
  }) async {
    final item = AppNotification(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title.trim(),
      message: message.trim(),
      createdAt: DateTime.now(),
      isRead: false,
    );

    _notifications = [item, ..._notifications];
    _serverUnreadCount += 1;
    await _persist();
    notifyListeners();
  }

  Future<bool> fetchFromBackend({int page = 1, int pageSize = 20}) async {
    try {
      await _loadReadNotificationIds();
      await _checkAndRefreshCacheIfNeeded();

      final uri = ApiEndpoints.buildUri(ApiEndpoints.listNotifications, {
        'page': page,
        'page_size': pageSize,
      });

      final response = await AuthorizedApiService.sendWithAutoRefresh(
        null,
        (token) => http
            .get(uri, headers: ApiEndpoints.authorizedHeaders(token))
            .timeout(const Duration(seconds: 12)),
      );

      if (response == null) {
        return false;
      }

      if (response.statusCode != 200) {
        return false;
      }

      final decoded = jsonDecode(response.body);

      // Support both a plain array response and a {"data": [...]} envelope.
      final List<dynamic> data;
      if (decoded is List) {
        data = decoded;
      } else if (decoded is Map<String, dynamic>) {
        final inner = decoded['data'];
        if (inner is! List) {
          _notifications = [];
          _serverUnreadCount = 0;
          await _persist();
          notifyListeners();
          return true;
        }
        data = inner;
      } else {
        return false;
      }

      _notifications = data
          .whereType<Map>()
          .map(
            (item) => AppNotification.fromJson(Map<String, dynamic>.from(item)),
          )
          .where(
            (item) => !item.isRead && !_readNotificationIds.contains(item.id),
          )
          .toList();

      // Derive count from the filtered list so locally-cleared notifications
      // are never counted even if the server hasn't processed mark-as-read yet.
      _serverUnreadCount = _notifications.where((n) => !n.isRead).length;

      await _persist();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _markAsReadOnServer(String notificationId) async {
    final id = int.tryParse(notificationId);
    if (id == null) {
      return false;
    }

    final response = await AuthorizedApiService.sendWithAutoRefresh(
      null,
      (token) => http
          .post(
            Uri.parse(ApiEndpoints.markNotificationRead(id)),
            headers: ApiEndpoints.authorizedHeaders(token),
            body: '{}',
          )
          .timeout(const Duration(seconds: 8)),
    );

    if (response == null) {
      return false;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return false;
    }

    return true;
  }

  Future<void> clearNotification(String id) async {
    _readNotificationIds.add(id);
    await _persistReadNotificationIds();

    _notifications = _notifications.where((item) => item.id != id).toList();
    if (_serverUnreadCount > 0) {
      _serverUnreadCount -= 1;
    }

    await _persist();
    notifyListeners();

    _markAsReadOnServer(id).ignore();
  }

  Future<void> clearAll() async {
    final ids = _notifications.map((item) => item.id).toList(growable: false);
    _readNotificationIds.addAll(ids);
    await _persistReadNotificationIds();

    _notifications = [];
    _serverUnreadCount = 0;

    await _persist();
    notifyListeners();

    for (final id in ids) {
      _markAsReadOnServer(id).ignore();
    }
  }

  Future<bool> markAsRead(String notificationId) async {
    _readNotificationIds.add(notificationId);
    await _persistReadNotificationIds();

    _notifications = _notifications
        .where((item) => item.id != notificationId)
        .toList();
    if (_serverUnreadCount > 0) {
      _serverUnreadCount -= 1;
    }

    await _persist();
    notifyListeners();

    _markAsReadOnServer(notificationId).ignore();
    return true;
  }

  List<AppNotification> getUnreadNotifications() {
    return _notifications.where((item) => !item.isRead).toList();
  }

  Future<void> syncWithBackend() async {
    await fetchFromBackend();
  }
}
