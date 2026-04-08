// Conditional export: use real web impl on web, stub elsewhere.
export 'web_camera_qr_scanner_stub.dart'
    if (dart.library.html) 'web_camera_qr_scanner_impl.dart';
