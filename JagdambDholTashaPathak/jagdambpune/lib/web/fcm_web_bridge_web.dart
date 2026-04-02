import 'dart:html' as html;
import 'dart:convert';

/// Initialize the web FCM bridge to listen for messages from service worker
void initializeWebFcmBridge(
  Future<void> Function(String title, String body) onMessage,
) {
  // Listen for messages from service worker
  html.window.addEventListener('message', (event) {
    if (event is html.MessageEvent) {
      final data = event.data;
      if (data is String) {
        try {
          final decoded = jsonDecode(data);
          if (decoded['type'] == 'fcm_background_message') {
            final title = decoded['title'] ?? 'Notification';
            final body = decoded['body'] ?? '';
            onMessage(title, body);
          }
        } catch (_) {
          // Ignore JSON parse errors
        }
      }
    }
  });

  // Also listen via service worker controller
  final controller = html.window.navigator.serviceWorker?.controller;
  if (controller != null) {
    html.window.navigator.serviceWorker?.onMessage.listen((event) {
      final data = event.data;
      if (data is String) {
        try {
          final decoded = jsonDecode(data);
          if (decoded['type'] == 'fcm_background_message') {
            final title = decoded['title'] ?? 'Notification';
            final body = decoded['body'] ?? '';
            onMessage(title, body);
          }
        } catch (_) {
          // Ignore JSON parse errors
        }
      }
    });
  }
}
