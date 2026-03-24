import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions are not configured for web.',
      );
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
}
