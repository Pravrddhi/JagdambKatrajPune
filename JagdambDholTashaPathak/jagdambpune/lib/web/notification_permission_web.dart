import 'dart:html' as html;

Future<String> ensureBrowserNotificationPermission() async {
  final current = html.Notification.permission ?? 'default';
  if (current == 'default') {
    return await html.Notification.requestPermission();
  }
  return current;
}
