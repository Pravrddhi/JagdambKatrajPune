import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/api_endpoints.dart';

class NotificationSocketService {
  NotificationSocketService({required this.onNotificationEvent});

  final VoidCallback onNotificationEvent;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;

  bool _disposed = false;
  String? _token;
  Duration _reconnectDelay = const Duration(seconds: 2);

  void connect(String accessToken) {
    final normalized = accessToken.trim();
    if (normalized.isEmpty) {
      return;
    }

    _token = normalized;
    _open();
  }

  void _open() {
    if (_disposed) {
      return;
    }
    final token = _token;
    if (token == null || token.isEmpty) {
      return;
    }

    _reconnectTimer?.cancel();
    _subscription?.cancel();

    try {
      final uri = ApiEndpoints.notificationsWebSocketUri(token);
      _channel = WebSocketChannel.connect(uri);
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
      _reconnectDelay = const Duration(seconds: 2);
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic message) {
    if (_disposed) {
      return;
    }

    if (message is String && message.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(message);
        if (decoded is Map<String, dynamic>) {
          final event = decoded['event']?.toString().trim().toLowerCase() ?? '';
          if (event.isNotEmpty &&
              event != 'notification.created' &&
              event != 'notification.read') {
            return;
          }
        }
      } catch (_) {
        // Non-JSON payloads still trigger a refresh.
      }
    }

    onNotificationEvent();
  }

  void _scheduleReconnect() {
    if (_disposed || _token == null || _token!.isEmpty) {
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, _open);

    final nextSeconds = (_reconnectDelay.inSeconds * 2).clamp(2, 30);
    _reconnectDelay = Duration(seconds: nextSeconds);
  }

  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    await _subscription?.cancel();
    _subscription = null;

    await _channel?.sink.close();
    _channel = null;
  }
}
