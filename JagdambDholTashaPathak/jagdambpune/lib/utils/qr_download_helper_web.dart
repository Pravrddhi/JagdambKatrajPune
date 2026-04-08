// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

/// Triggers a browser file download of [pngBytes] as a PNG file named
/// [filename].  Returns true on success.
Future<bool> downloadQrBytes(Uint8List pngBytes, String filename) async {
  try {
    final blob = html.Blob([pngBytes], 'image/png');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.document.createElement('a') as html.AnchorElement
      ..href = url
      ..setAttribute('download', filename)
      ..style.display = 'none';
    html.document.body!.children.add(anchor);
    anchor.click();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    html.document.body!.children.remove(anchor);
    html.Url.revokeObjectUrl(url);
    return true;
  } catch (_) {
    return false;
  }
}
