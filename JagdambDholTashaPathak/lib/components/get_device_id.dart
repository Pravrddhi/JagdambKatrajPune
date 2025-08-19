import 'dart:io';
import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';

Future<String> getDeviceId() async {
    final AndroidId androidIdPlugin = AndroidId();
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      String? androidId = await androidIdPlugin.getId();
      return androidId ?? "unknown";
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? "unknown";
    } else {
      return "unsupported_platform";
    }
  }