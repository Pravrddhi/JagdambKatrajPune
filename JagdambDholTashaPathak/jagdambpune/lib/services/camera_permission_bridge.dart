// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Requests camera permission on web using the browser's MediaDevices API
/// Returns true if permission is granted, false if denied
Future<bool> requestCameraPermissionWeb() async {
  try {
    // Check if the browser supports getUserMedia
    final mediaDevices = html.window.navigator.mediaDevices;
    if (mediaDevices == null) {
      throw Exception('Camera API not supported in this browser.');
    }

    // Request camera permission explicitly
    final stream = await mediaDevices
        .getUserMedia({
          'video': {'facingMode': 'user'},
          'audio': false,
        })
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw Exception(
            'Camera permission request timed out. Please try again.',
          ),
        );

    // Stop the stream immediately after getting permission
    final videoTracks = stream.getVideoTracks();
    for (final track in videoTracks) {
      track.stop();
    }

    return true;
  } catch (e) {
    final message = e.toString().toLowerCase();

    // Check for specific permission errors
    if (message.contains('notallowederror') ||
        message.contains('permission denied') ||
        message.contains('permission dismissed')) {
      return false; // User denied permission
    }

    if (message.contains('notfound') ||
        message.contains('no camera') ||
        message.contains('no device found')) {
      throw Exception('No camera device found on this system.');
    }

    if (message.contains('notreadable') || message.contains('in use')) {
      throw Exception(
        'Camera is in use by another application. Close it and try again.',
      );
    }

    if (message.contains('timeout')) {
      throw Exception('Camera permission request timed out. Please try again.');
    }

    // Generic error
    throw Exception('Unable to request camera permission. Please try again.');
  }
}

/// Checks if camera permission is already granted (non-blocking)
Future<bool> hasCameraPermissionWeb() async {
  try {
    final permissions = html.window.navigator.permissions;
    if (permissions == null) {
      return true; // Assume granted if Permissions API not available
    }

    // Try to query camera permission status
    final result = await permissions.query({'name': 'camera'});
    final state = result['state'].toString().toLowerCase();
    return state == 'granted';
  } catch (_) {
    return true; // Assume granted if check fails
  }
}
