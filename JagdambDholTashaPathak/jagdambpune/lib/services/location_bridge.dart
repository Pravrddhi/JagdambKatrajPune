import 'location_bridge_io.dart'
    if (dart.library.html) 'location_bridge_web.dart'
    as impl;
import 'location_types.dart';

export 'location_types.dart';

Future<AttendanceCoordinates> fetchCurrentCoordinates() {
  return impl.fetchCurrentCoordinates();
}
