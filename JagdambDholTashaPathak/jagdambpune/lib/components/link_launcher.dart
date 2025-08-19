import 'package:url_launcher/url_launcher.dart';

class LinkLauncher {
  /// Opens any given link in the default app or browser
  static Future<void> openLink(String link) async {
    final Uri uri = Uri.parse(link);

    if (await canLaunchUrl(uri)) {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication, // Forces opening in app/browser
      );
    } else {
      throw 'Could not launch $link';
    }
  }
}
