import 'dart:typed_data';

// Non-web stub — never called at runtime (callers guard with kIsWeb).
Future<MapEntry<Uint8List, String>?> pickJpegFile({
  bool useCamera = false,
}) async => null;

Future<List<MapEntry<Uint8List, String>>> pickJpegFiles({
  bool useCamera = false,
}) async => <MapEntry<Uint8List, String>>[];
