import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static const String _webApiKey = String.fromEnvironment(
    'FIREBASE_WEB_API_KEY',
    defaultValue: 'AIzaSyDhTuSuK6hzqj0WPS88BpFjIFtcQe8Ii7o',
  );
  static const String _webAppId = String.fromEnvironment(
    'FIREBASE_WEB_APP_ID',
    defaultValue: '1:486265337828:web:09fabc9eadf4f6cdb2f9f1',
  );
  static const String _webMessagingSenderId = String.fromEnvironment(
    'FIREBASE_WEB_MESSAGING_SENDER_ID',
    defaultValue: '486265337828',
  );
  static const String _webProjectId = String.fromEnvironment(
    'FIREBASE_WEB_PROJECT_ID',
    defaultValue: 'dhol-tasha-pathak',
  );
  static const String _webAuthDomain = String.fromEnvironment(
    'FIREBASE_WEB_AUTH_DOMAIN',
    defaultValue: 'dhol-tasha-pathak.firebaseapp.com',
  );
  static const String _webStorageBucket = String.fromEnvironment(
    'FIREBASE_WEB_STORAGE_BUCKET',
    defaultValue: 'dhol-tasha-pathak.firebasestorage.app',
  );
  static const String _webMeasurementId = String.fromEnvironment(
    'FIREBASE_WEB_MEASUREMENT_ID',
    defaultValue: 'G-3CS6QBVXB7',
  );

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB9qa64T6MtrcuCth1yatHqrNeh9LXImNk',
    appId: '1:486265337828:android:21e9a451967964bfb2f9f1',
    messagingSenderId: '486265337828',
    projectId: 'dhol-tasha-pathak',
    storageBucket: 'dhol-tasha-pathak.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB5nzmSxzYMhNa-zxMrvSc6BPFFR265ErI',
    appId: '1:486265337828:ios:868f3249bee258d6b2f9f1',
    messagingSenderId: '486265337828',
    projectId: 'dhol-tasha-pathak',
    storageBucket: 'dhol-tasha-pathak.firebasestorage.app',
    iosBundleId: 'com.jagdambpune.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: _webApiKey,
    appId: _webAppId,
    messagingSenderId: _webMessagingSenderId,
    projectId: _webProjectId,
    authDomain: _webAuthDomain,
    storageBucket: _webStorageBucket,
    measurementId: _webMeasurementId,
  );
}
