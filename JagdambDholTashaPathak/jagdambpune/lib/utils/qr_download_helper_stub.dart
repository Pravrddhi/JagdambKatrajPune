import 'dart:io';
import 'dart:typed_data';

/// Saves [pngBytes] to the system temp directory as [filename].
/// Returns the file path on success, or null on failure.
Future<bool> downloadQrBytes(Uint8List pngBytes, String filename) async {
  try {
    final file = File('${Directory.systemTemp.path}/$filename');
    await file.writeAsBytes(pngBytes);
    return true;
  } catch (_) {
    return false;
  }
}
