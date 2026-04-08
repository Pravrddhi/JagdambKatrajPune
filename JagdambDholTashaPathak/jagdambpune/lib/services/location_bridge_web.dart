// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

import 'location_types.dart';

Future<AttendanceCoordinates> fetchCurrentCoordinates() async {
  final geolocation = html.window.navigator.geolocation;
  final hostname = (html.window.location.hostname ?? '').toLowerCase();
  final isLocalhost =
      hostname == 'localhost' || hostname == '127.0.0.1' || hostname == '::1';
  final isSecureContext = html.window.isSecureContext ?? false;

  if (!isSecureContext && !isLocalhost) {
    throw Exception(
      'Location on web requires HTTPS (or localhost). Open the app on HTTPS and allow location access.',
    );
  }

  try {
    final position = await geolocation
        .getCurrentPosition(
          enableHighAccuracy: true,
          timeout: const Duration(seconds: 20),
          maximumAge: Duration.zero,
        )
        .timeout(
          const Duration(seconds: 22),
          onTimeout: () =>
              throw Exception('Location request timed out. Please try again.'),
        );

    final lat = position.coords?.latitude?.toDouble();
    final lng = position.coords?.longitude?.toDouble();
    if (lat == null || lng == null) {
      throw Exception('Unable to read location coordinates from browser.');
    }

    return AttendanceCoordinates(latitude: lat, longitude: lng);
  } catch (e) {
    final message = e.toString().toLowerCase();
    if (message.contains('permission')) {
      throw Exception(
        'Location permission denied in browser. Allow location and try again.',
      );
    }
    if (message.contains('timeout')) {
      throw Exception('Location request timed out. Please try again.');
    }
    throw Exception('Failed to get web location. Please try again.');
  }
}
