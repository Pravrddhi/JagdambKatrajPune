import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/api_endpoints.dart';

class NotificationSocketService {
  NotificationSocketService({required this.onNotificationEvent});

  /// Called when a notification event is received.
  /// [notificationData] is the parsed notification object from the WebSocket
  /// message when `type == "notification.created"`.
  ///
  /// A `null` value means a full refresh is needed instead of applying an
  /// incremental update. This can be emitted in multiple situations, such as
  /// on initial connection, on reconnect, or when an incoming socket message
  /// cannot be handled as a specific notification event.
  final void Function(Map<String, dynamic>? notificationData)
  onNotificationEvent;

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
      // WebSocketChannel.connect may expose connection failures through
      // channel.ready. Handle it to avoid unhandled async exceptions.
      _channel!.ready
          .then((_) {
            if (_disposed) return;
            // Refresh once when socket is connected/reconnected to catch
            // notifications created while client was temporarily offline.
            onNotificationEvent(null);
          })
          .catchError((error) {
            _scheduleReconnect();
          });
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: (error) {
          _scheduleReconnect();
        },
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
      _reconnectDelay = const Duration(seconds: 2);
    } catch (error) {
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
          // Django Channels sends 'type' field; also check 'event' for
          // compatibility with other backend implementations.
          final event =
              (decoded['type'] ?? decoded['event'] ?? decoded['message_type'])
                  ?.toString()
                  .trim()
                  .toLowerCase() ??
              '';

          // Skip connection handshake and keepalive frames.
          if (event == 'connection.established' ||
              event == 'ping' ||
              event == 'pong' ||
              event == 'heartbeat' ||
              event == 'connected') {
            return;
          }

          if (event == 'notification.created') {
            // Prefer 'notification' key; fall back to 'data' key.
            final payload = decoded['notification'] ?? decoded['data'];
            final notifMap = payload is Map<String, dynamic> ? payload : null;
            onNotificationEvent(notifMap);
            return;
          }
        }
      } catch (_) {
        // Non-JSON payloads still trigger a full refresh.
      }
    }

    onNotificationEvent(null);
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
