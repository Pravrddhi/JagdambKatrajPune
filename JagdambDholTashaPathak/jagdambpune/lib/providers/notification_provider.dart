import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppNotification {
  final String id;
  final String title;
  final String message;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'message': message,
    'created_at': createdAt.toIso8601String(),
  };

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id:
          json['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      title: json['title']?.toString() ?? 'Notification',
      message: json['message']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class NotificationProvider with ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _storageKey = 'app_notifications';
  static const Duration _dedupeWindow = Duration(seconds: 8);

  List<AppNotification> _notifications = [];

  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _notifications.length;

  NotificationProvider() {
    _loadFromStorage();
  }

  Future<void> refreshFromStorage() async {
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

  Future<void> addNotification({
    required String title,
    required String message,
  }) async {
    final normalizedTitle = title.trim();
    final normalizedMessage = message.trim();
    final now = DateTime.now();

    final duplicateExists = _notifications.any((item) {
      final sameContent =
          item.title.trim().toLowerCase() == normalizedTitle.toLowerCase() &&
          item.message.trim().toLowerCase() == normalizedMessage.toLowerCase();
      final withinWindow = now.difference(item.createdAt) < _dedupeWindow;
      return sameContent && withinWindow;
    });

    if (duplicateExists) {
      return;
    }

    final item = AppNotification(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: normalizedTitle,
      message: normalizedMessage,
      createdAt: now,
    );

    _notifications = [item, ..._notifications];
    if (kIsWeb) {
      notifyListeners();
      await _persist();
      return;
    }

    await _persist();
    notifyListeners();
  }

  Future<void> clearNotification(String id) async {
    _notifications = _notifications.where((item) => item.id != id).toList();
    if (kIsWeb) {
      notifyListeners();
      await _persist();
      return;
    }

    await _persist();
    notifyListeners();
  }

  Future<void> clearAll() async {
    _notifications = [];
    if (kIsWeb) {
      notifyListeners();
      await _persist();
      return;
    }

    await _persist();
    notifyListeners();
  }
}
