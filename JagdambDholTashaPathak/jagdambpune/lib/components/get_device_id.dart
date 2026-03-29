import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

Future<String> getDeviceId() async {
  if (kIsWeb) {
    return "web_default_device_id";
  }

  const AndroidId androidIdPlugin = AndroidId();
  final deviceInfo = DeviceInfoPlugin();

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      String? androidId = await androidIdPlugin.getId();
      return androidId ?? "unknown";
    case TargetPlatform.iOS:
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? "unknown";
    default:
      return "unsupported_platform";
  }
}
