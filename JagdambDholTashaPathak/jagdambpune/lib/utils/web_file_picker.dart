// Conditional export: on web uses dart:html directly to avoid the
// image_picker plugin channel which can fail in Flutter web environments.
export 'web_file_picker_stub.dart'
    if (dart.library.html) 'web_file_picker_web.dart';
