// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

/// Opens a native browser file-input dialog, reads the selected file's bytes,
/// and returns them with the file name.  Returns null if the user cancels.
///
/// Set [useCamera] to true to open the device camera directly (adds
/// `capture="environment"` to the file input, honoured on mobile browsers).
///
/// IMPORTANT: call this synchronously within a user-gesture handler so the
/// browser allows the file dialog to open without a pop-up blocker.
Future<MapEntry<Uint8List, String>?> pickJpegFile({
  bool useCamera = false,
}) async {
  final input = html.FileUploadInputElement()
    ..accept = useCamera ? 'image/*' : 'image/jpeg,image/jpg,.jpg,.jpeg';

  if (useCamera) {
    // Tells mobile browsers to open the camera directly.
    input.setAttribute('capture', 'environment');
  }

  // Must be called synchronously within the gesture context.
  input.click();

  // Wait for the user to pick a file (or dismiss the dialog).
  await input.onChange.first;

  final files = input.files;
  if (files == null || files.isEmpty) return null;

  final file = files.first;
  final reader = html.FileReader();
  reader.readAsArrayBuffer(file);
  await reader.onLoad.first;

  final resultObj = reader.result;
  Uint8List bytes;
  if (resultObj is ByteBuffer) {
    bytes = resultObj.asUint8List();
  } else if (resultObj is List<int>) {
    bytes = Uint8List.fromList(resultObj);
  } else {
    return null;
  }

  return MapEntry(bytes, file.name);
}
