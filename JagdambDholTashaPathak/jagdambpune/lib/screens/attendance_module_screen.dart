import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:table_calendar/table_calendar.dart';

import '../services/attendance_service.dart';
import '../theme/app_colors.dart';
import '../utils/qr_download_helper.dart';
import '../widgets/web_camera_qr_scanner.dart';

class AttendanceModuleScreen extends StatefulWidget {
  final bool canGenerateQr;
  final bool canSetAttendanceLocation;
  final bool canViewByUserAttendance;
  final bool isPathakAdmin;
  final bool scanOnly;

  const AttendanceModuleScreen({
    super.key,
    required this.canGenerateQr,
    required this.canSetAttendanceLocation,
    required this.canViewByUserAttendance,
    this.isPathakAdmin = false,
    this.scanOnly = false,
  });

  @override
  State<AttendanceModuleScreen> createState() => _AttendanceModuleScreenState();
}

class _AttendanceModuleScreenState extends State<AttendanceModuleScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final MobileScannerController _scannerController = MobileScannerController(
    autoStart: !kIsWeb,
  );

  bool _isGenerating = false;
  bool _isDownloadingQr = false;
  bool _isGettingLocation = false;
  bool _isSettingLocation = false;
  bool _isLoadingConfiguredLocation = false;
  String? _qrPayload;
  String? _qrExpiry;
  bool _qrIsPermanent = false;
  final GlobalKey _qrPreviewKey = GlobalKey();
  double? _configuredLat;
  double? _configuredLng;
  int _configuredRadiusMeters = 100;

  bool _isMarking = false;
  bool _hasMarkedFromCurrentScan = false;
  String? _scanInfo;
  VoidCallback? _stopWebCamera;

  bool _isLoadingMyAttendance = false;
  DateTime _calendarFocusDate = DateTime.now();
  DateTime _selectedDate = DateTime.now();
  final Map<DateTime, String> _attendanceByDate = <DateTime, String>{};

  bool _isLoadingAttendanceByUser = false;
  DateTime _byUserFocusMonth = DateTime.now();
  List<Map<String, dynamic>> _attendanceByUser = <Map<String, dynamic>>[];
  final TextEditingController _nameSearchController = TextEditingController();
  String _nameFilter = '';

  bool get _isSecureWebContext {
    if (!kIsWeb) return true;
    final host = Uri.base.host.toLowerCase();
    final isLocalhost = host == 'localhost' || host == '127.0.0.1';
    return Uri.base.scheme == 'https' || isLocalhost;
  }

  @override
  void initState() {
    super.initState();
    if (widget.scanOnly) {
      _tabController = TabController(length: 1, vsync: this, initialIndex: 0);
      return;
    }

    final tabCount =
        1 +
        (widget.canGenerateQr ? 1 : 0) +
        (widget.canViewByUserAttendance ? 1 : 0) +
        1;
    final initialTabIndex = widget.canGenerateQr
        ? (widget.canViewByUserAttendance ? 3 : 2)
        : 0;
    _tabController = TabController(
      length: tabCount,
      vsync: this,
      initialIndex: initialTabIndex,
    );

    _loadMyAttendance();
    if (widget.canGenerateQr || widget.canSetAttendanceLocation) {
      _loadConfiguredAttendanceLocation();
    }
    if (widget.canViewByUserAttendance) {
      _loadAttendanceByUser();
    }
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _tabController.dispose();
    _nameSearchController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _generateAttendanceQr() async {
    if (_isGenerating) return;

    final targetLat = _configuredLat;
    final targetLng = _configuredLng;
    final allowedRadius = _configuredRadiusMeters;

    if (targetLat == null || targetLng == null) {
      _showSnack('Attendance location is not configured by Pathak Admin yet.');
      return;
    }

    setState(() {
      _isGenerating = true;
    });

    try {
      final current = await AttendanceService.getCurrentPosition();
      final distance = AttendanceService.distanceMeters(
        fromLat: current.latitude,
        fromLng: current.longitude,
        toLat: targetLat,
        toLng: targetLng,
      );

      if (distance > allowedRadius) {
        throw Exception(
          'You are ${distance.toStringAsFixed(1)}m away from configured location. Move within ${allowedRadius}m to generate QR.',
        );
      }

      final response = await AttendanceService.generateQr(
        locationLat: targetLat,
        locationLng: targetLng,
        radiusMeters: allowedRadius,
        permanent: widget.isPathakAdmin,
      );

      final payload =
          response['qr_payload']?.toString() ??
          response['qr_token']?.toString() ??
          response['token']?.toString() ??
          '';

      if (payload.isEmpty) {
        throw Exception('QR payload missing in response.');
      }

      setState(() {
        _qrPayload = payload;
        _qrExpiry = response['expires_at']?.toString();
        _qrIsPermanent = response['is_permanent'] == true;
      });

      _showSnack(response['message']?.toString() ?? 'Attendance QR generated.');
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _loadConfiguredAttendanceLocation() async {
    if (_isLoadingConfiguredLocation) return;

    setState(() {
      _isLoadingConfiguredLocation = true;
    });

    try {
      final response = await AttendanceService.fetchAttendanceLocation();
      final lat = double.tryParse(response['location_lat']?.toString() ?? '');
      final lng = double.tryParse(response['location_lng']?.toString() ?? '');
      final radius =
          int.tryParse(response['radius_meters']?.toString() ?? '') ?? 100;

      if (!mounted) return;
      setState(() {
        _configuredLat = lat;
        _configuredLng = lng;
        _configuredRadiusMeters = radius;
      });
    } catch (_) {
      // Do not block UI if location is not configured yet.
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingConfiguredLocation = false;
        });
      }
    }
  }

  Future<void> _setAttendanceLocation() async {
    if (_isSettingLocation || _isGettingLocation) return;

    setState(() {
      _isGettingLocation = true;
    });

    double? lat;
    double? lng;
    try {
      final position = await AttendanceService.getCurrentPosition();
      lat = position.latitude;
      lng = position.longitude;
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
      if (mounted) {
        setState(() {
          _isGettingLocation = false;
        });
      }
      return;
    }

    setState(() {
      _isGettingLocation = false;
      _isSettingLocation = true;
    });

    try {
      final response = await AttendanceService.setAttendanceLocation(
        latitude: lat,
        longitude: lng,
        radiusMeters: 100,
      );

      setState(() {
        _configuredLat = lat;
        _configuredLng = lng;
        _configuredRadiusMeters =
            int.tryParse(response['radius_meters']?.toString() ?? '') ?? 100;
      });

      _showSnack(
        response['message']?.toString() ?? 'Attendance location updated.',
      );
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isSettingLocation = false;
        });
      }
    }
  }

  Future<void> _markAttendance(String qrData) async {
    if (_isMarking || _hasMarkedFromCurrentScan) {
      return;
    }

    setState(() {
      _isMarking = true;
      _scanInfo = null;
    });

    try {
      final current = await AttendanceService.getCurrentPosition();

      final response = await AttendanceService.markAttendance(
        qrData: qrData,
        latitude: current.latitude,
        longitude: current.longitude,
      );

      final successMessage =
          response['message']?.toString() ?? 'Attendance marked successfully.';

      setState(() {
        _hasMarkedFromCurrentScan = true;
        _scanInfo = successMessage;
      });
      _loadMyAttendance();
      // Stop camera before showing dialog
      _stopWebCamera?.call();

      // Show success popup then navigate to My Calendar
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: Colors.white,
            contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE8F5E9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.green,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Attendance Marked!',
                  style: TextStyle(
                    color: AppColors.primaryMaroon,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  successMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.primaryMaroon,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryMaroon,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('OK'),
                ),
              ),
            ],
          ),
        );
      }

      if (mounted && !widget.scanOnly && _tabController.length > 1) {
        _tabController.animateTo(1);
      }
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isMarking = false;
        });
      }
    }
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  String _monthLabel(DateTime dt) {
    const monthNames = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${monthNames[dt.month - 1]} ${dt.year}';
  }

  /// Renders [data] as a QR code and returns raw PNG bytes.
  Future<Uint8List?> _renderQrToPng(String data, {double size = 400}) async {
    try {
      final painter = QrPainter(
        data: data,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
        color: const Color(0xFF000000),
        emptyColor: const Color(0xFFFFFFFF),
        gapless: false,
      );

      // Preferred path for clean export on web/mobile.
      final byteData = await painter.toImageData(
        size,
        format: ui.ImageByteFormat.png,
      );
      if (byteData != null) {
        return byteData.buffer.asUint8List();
      }

      // Fallback path when toImageData is unavailable.
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final border = size * 0.08;
      final qrSize = size - (border * 2);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size, size),
        ui.Paint()..color = const Color(0xFFFFFFFF),
      );
      canvas.save();
      canvas.translate(border, border);
      painter.paint(canvas, Size(qrSize, qrSize));
      canvas.restore();
      final picture = recorder.endRecording();
      final image = await picture.toImage(size.toInt(), size.toInt());
      final fallbackByteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      return fallbackByteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _downloadQr() async {
    final payload = _qrPayload;
    if (payload == null) return;

    setState(() => _isDownloadingQr = true);
    try {
      // Prefer exact on-screen capture so downloaded QR matches preview 1:1.
      final bytes =
          await _captureDisplayedQrPng() ?? await _renderQrToPng(payload);
      if (bytes == null) throw Exception('Failed to render QR image.');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'jagdamb_attendance_qr_$timestamp.png';
      final ok = await downloadQrBytes(bytes, filename);
      if (ok) {
        _showSnack(kIsWeb ? 'QR downloaded.' : 'QR saved to temp folder.');
      } else {
        throw Exception('Download failed — please try again.');
      }
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isDownloadingQr = false);
    }
  }

  Future<Uint8List?> _captureDisplayedQrPng() async {
    try {
      final context = _qrPreviewKey.currentContext;
      if (context == null) return null;

      final renderObject = context.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) return null;

      final image = await renderObject.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  void _changeCalendarMonth(int monthDelta) {
    final updated = DateTime(
      _calendarFocusDate.year,
      _calendarFocusDate.month + monthDelta,
      1,
    );
    setState(() {
      _calendarFocusDate = updated;
      _selectedDate = DateTime(
        updated.year,
        updated.month,
        _selectedDate.day >
                DateUtils.getDaysInMonth(updated.year, updated.month)
            ? DateUtils.getDaysInMonth(updated.year, updated.month)
            : _selectedDate.day,
      );
    });
    _loadMyAttendance();
  }

  DateTime? _extractAttendanceDate(Map<String, dynamic> row) {
    final dateStr =
        row['date']?.toString() ??
        row['attendance_date']?.toString() ??
        row['marked_date']?.toString() ??
        row['created_at']?.toString() ??
        '';
    if (dateStr.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(dateStr);
    if (parsed == null) return null;
    return _dateOnly(parsed);
  }

  String _extractAttendanceStatus(Map<String, dynamic> row) {
    final raw =
        row['status']?.toString().toLowerCase().trim() ??
        row['attendance_status']?.toString().toLowerCase().trim() ??
        'present';
    if (raw == 'present' || raw == 'p') return 'present';
    if (raw == 'absent' || raw == 'a') return 'absent';
    if (raw == 'late' || raw == 'l') return 'late';
    return raw.isEmpty ? 'present' : raw;
  }

  Future<void> _loadMyAttendance() async {
    if (_isLoadingMyAttendance) return;

    setState(() {
      _isLoadingMyAttendance = true;
    });

    try {
      final month =
          '${_calendarFocusDate.year}-${_calendarFocusDate.month.toString().padLeft(2, '0')}';
      final rows = await AttendanceService.fetchMyAttendance(month: month);
      final mapped = <DateTime, String>{};
      for (final row in rows) {
        final date = _extractAttendanceDate(row);
        if (date == null) continue;
        mapped[date] = _extractAttendanceStatus(row);
      }
      if (!mounted) return;
      setState(() {
        _attendanceByDate
          ..clear()
          ..addAll(mapped);
      });
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMyAttendance = false;
        });
      }
    }
  }

  Future<void> _loadAttendanceByUser() async {
    if (_isLoadingAttendanceByUser) return;

    setState(() {
      _isLoadingAttendanceByUser = true;
    });

    try {
      final month =
          '${_byUserFocusMonth.year}-${_byUserFocusMonth.month.toString().padLeft(2, '0')}';
      final rows = await AttendanceService.fetchAttendanceByUser(month: month);
      if (!mounted) return;
      setState(() {
        _attendanceByUser = rows;
      });
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAttendanceByUser = false;
        });
      }
    }
  }

  void _changeByUserMonth(int monthDelta) {
    setState(() {
      _byUserFocusMonth = DateTime(
        _byUserFocusMonth.year,
        _byUserFocusMonth.month + monthDelta,
        1,
      );
    });
    _loadAttendanceByUser();
  }

  Color _statusColor(String status) {
    switch (status.trim().toLowerCase()) {
      case 'present':
      case 'p':
        return Colors.green.shade700;
      case 'absent':
      case 'a':
        return Colors.red.shade700;
      case 'late':
      case 'l':
        return Colors.orange.shade700;
      default:
        return Colors.blueGrey;
    }
  }

  String _statusLabel(String status) {
    final normalized = status.trim().toLowerCase();
    switch (normalized) {
      case 'present':
      case 'p':
        return 'Present';
      case 'absent':
      case 'a':
        return 'Absent';
      case 'late':
      case 'l':
        return 'Late';
      default:
        return 'Recorded';
    }
  }

  Map<String, int> _monthStatusCounts(DateTime month) {
    var present = 0;
    var absent = 0;
    var late = 0;
    var other = 0;

    _attendanceByDate.forEach((date, status) {
      if (date.year != month.year || date.month != month.month) return;
      final normalized = status.trim().toLowerCase();
      if (normalized == 'present' || normalized == 'p') {
        present++;
      } else if (normalized == 'absent' || normalized == 'a') {
        absent++;
      } else if (normalized == 'late' || normalized == 'l') {
        late++;
      } else {
        other++;
      }
    });

    return <String, int>{
      'present': present,
      'absent': absent,
      'late': late,
      'other': other,
    };
  }

  String _selectedDateLabel(DateTime date) {
    const monthNames = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${monthNames[date.month - 1]} ${date.year}';
  }

  Widget? _attendanceDayCell(DateTime day, {required bool isSelected}) {
    final status = _attendanceByDate[_dateOnly(day)];
    if (status == null || status.trim().isEmpty) return null;

    final color = _statusColor(status);
    return Container(
      margin: const EdgeInsets.all(6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isSelected ? color : color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? color : color.withValues(alpha: 0.45),
          width: 1.2,
        ),
      ),
      child: Text(
        '${day.day}',
        style: TextStyle(
          color: isSelected ? Colors.white : AppColors.primaryMaroon,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _summaryCard({
    required String title,
    required int count,
    required Color color,
  }) {
    return Container(
      width: 110,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.primaryMaroon,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyAttendanceTab() {
    final selectedKey = _dateOnly(_selectedDate);
    final selectedStatus = _attendanceByDate[selectedKey];
    final monthCounts = _monthStatusCounts(_calendarFocusDate);
    final monthPresent = monthCounts['present'] ?? 0;
    final monthAbsent = monthCounts['absent'] ?? 0;
    final monthLate = monthCounts['late'] ?? 0;
    final monthOther = monthCounts['other'] ?? 0;
    final monthRecorded = monthPresent + monthAbsent + monthLate + monthOther;

    List<String> eventLoader(DateTime day) {
      final status = _attendanceByDate[_dateOnly(day)];
      if (status == null || status.isEmpty) {
        return <String>[];
      }
      return <String>[status];
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'My Attendance Calendar',
                  style: TextStyle(
                    color: AppColors.primaryMaroon,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _isLoadingMyAttendance ? null : _loadMyAttendance,
                icon: _isLoadingMyAttendance
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primaryMaroon.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: _isLoadingMyAttendance
                      ? null
                      : () => _changeCalendarMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      _monthLabel(_calendarFocusDate),
                      style: const TextStyle(
                        color: AppColors.primaryMaroon,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: _isLoadingMyAttendance
                      ? null
                      : () => _changeCalendarMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _summaryCard(
                title: 'Recorded',
                count: monthRecorded,
                color: AppColors.primaryMaroon,
              ),
              _summaryCard(
                title: 'Present',
                count: monthPresent,
                color: Colors.green.shade700,
              ),
              _summaryCard(
                title: 'Late',
                count: monthLate,
                color: Colors.orange.shade700,
              ),
              _summaryCard(
                title: 'Absent',
                count: monthAbsent,
                color: Colors.red.shade700,
              ),
            ],
          ),
          const SizedBox(height: 10),
          TableCalendar<String>(
            firstDay: DateTime(2020, 1, 1),
            lastDay: DateTime(2100, 12, 31),
            focusedDay: _calendarFocusDate,
            calendarFormat: CalendarFormat.month,
            availableCalendarFormats: const {CalendarFormat.month: 'Month'},
            headerVisible: false,
            selectedDayPredicate: (day) => isSameDay(day, _selectedDate),
            eventLoader: eventLoader,
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDate = selectedDay;
                _calendarFocusDate = focusedDay;
              });
            },
            onPageChanged: (focusedDay) {
              final normalized = DateTime(focusedDay.year, focusedDay.month, 1);
              setState(() {
                _calendarFocusDate = normalized;
              });
              _loadMyAttendance();
            },
            calendarStyle: const CalendarStyle(
              markerDecoration: BoxDecoration(),
              outsideDaysVisible: false,
            ),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) {
                return _attendanceDayCell(day, isSelected: false);
              },
              selectedBuilder: (context, day, focusedDay) {
                return _attendanceDayCell(day, isSelected: true) ??
                    Container(
                      margin: const EdgeInsets.all(6),
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryMaroon,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${day.day}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
              },
              markerBuilder: (context, day, events) {
                if (events.isEmpty) return const SizedBox.shrink();
                final status = events.first;
                return Positioned(
                  bottom: 4,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _statusColor(status),
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primaryMaroon.withValues(alpha: 0.2),
              ),
            ),
            child: selectedStatus == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedDateLabel(_selectedDate),
                        style: const TextStyle(
                          color: AppColors.primaryMaroon,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'No attendance record for selected date.',
                        style: TextStyle(color: AppColors.primaryMaroon),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedDateLabel(_selectedDate),
                        style: const TextStyle(
                          color: AppColors.primaryMaroon,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: _statusColor(selectedStatus),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Status: ${_statusLabel(selectedStatus)}',
                            style: TextStyle(
                              color: _statusColor(selectedStatus),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            children: [
              _legendDot('Present', Colors.green.shade700),
              _legendDot('Absent', Colors.red.shade700),
              _legendDot('Late', Colors.orange.shade700),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: AppColors.primaryMaroon)),
      ],
    );
  }

  Widget _buildAttendanceByUserTab() {
    final currentMonthKey =
        '${_byUserFocusMonth.year}-${_byUserFocusMonth.month.toString().padLeft(2, '0')}';

    final query = _nameFilter.trim().toLowerCase();
    final visibleRows = query.isEmpty
        ? _attendanceByUser
        : _attendanceByUser.where((row) {
            final name =
                (row['user_name']?.toString() ?? row['name']?.toString() ?? '')
                    .toLowerCase();
            return name.contains(query);
          }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Attendance By User',
                  style: TextStyle(
                    color: AppColors.primaryMaroon,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _isLoadingAttendanceByUser
                    ? null
                    : _loadAttendanceByUser,
                icon: _isLoadingAttendanceByUser
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _nameSearchController,
            onChanged: (value) => setState(() => _nameFilter = value),
            style: const TextStyle(color: AppColors.primaryMaroon),
            decoration: InputDecoration(
              hintText: 'Search by name',
              hintStyle: TextStyle(
                color: AppColors.primaryMaroon.withValues(alpha: 0.5),
              ),
              prefixIcon: const Icon(
                Icons.search,
                color: AppColors.primaryMaroon,
              ),
              suffixIcon: _nameFilter.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.clear,
                        color: AppColors.primaryMaroon,
                      ),
                      onPressed: () {
                        _nameSearchController.clear();
                        setState(() => _nameFilter = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppColors.primaryMaroon.withValues(alpha: 0.2),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppColors.primaryMaroon.withValues(alpha: 0.2),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primaryMaroon),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Fetching: $currentMonthKey',
              style: const TextStyle(
                color: AppColors.primaryMaroon,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primaryMaroon.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: _isLoadingAttendanceByUser
                      ? null
                      : () => _changeByUserMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      _monthLabel(_byUserFocusMonth),
                      style: const TextStyle(
                        color: AppColors.primaryMaroon,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: _isLoadingAttendanceByUser
                      ? null
                      : () => _changeByUserMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _isLoadingAttendanceByUser
              ? const Center(child: CircularProgressIndicator())
              : visibleRows.isEmpty
              ? Center(
                  child: Text(
                    _nameFilter.isNotEmpty
                        ? 'No users match "$_nameFilter"'
                        : 'No attendance data found.',
                    style: const TextStyle(color: AppColors.primaryMaroon),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemBuilder: (_, index) {
                    final row = visibleRows[index];
                    final name =
                        row['user_name']?.toString() ??
                        row['name']?.toString() ??
                        'Unknown';
                    final phone = row['phone_number']?.toString() ?? '-';
                    final presentCount =
                        row['present_count']?.toString() ??
                        row['attendance_count']?.toString() ??
                        '-';
                    final lastMarked =
                        row['last_marked_at']?.toString() ??
                        row['last_attendance_at']?.toString() ??
                        '-';

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primaryMaroon.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: AppColors.primaryMaroon,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Phone: $phone',
                            style: const TextStyle(
                              color: AppColors.primaryMaroon,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Present Count: $presentCount',
                            style: const TextStyle(
                              color: AppColors.primaryMaroon,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Last Marked: $lastMarked',
                            style: const TextStyle(
                              color: AppColors.primaryMaroon,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemCount: visibleRows.length,
                ),
        ),
      ],
    );
  }

  Widget _buildGenerateTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.canSetAttendanceLocation
                ? 'Only Pathak Admin can set the attendance location. Management can generate QR only from this configured location within 100m.'
                : 'QR can be generated only at the location configured by Pathak Admin, within 100m radius.',
            style: const TextStyle(
              color: AppColors.primaryMaroon,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primaryMaroon.withValues(alpha: 0.2),
              ),
            ),
            child: _isLoadingConfiguredLocation
                ? const SizedBox(
                    height: 32,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : (_configuredLat == null || _configuredLng == null)
                ? const Text(
                    'Configured location is not set yet.',
                    style: TextStyle(color: AppColors.primaryMaroon),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Configured Location: ${_configuredLat!.toStringAsFixed(7)}, ${_configuredLng!.toStringAsFixed(7)}',
                        style: const TextStyle(
                          color: AppColors.primaryMaroon,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Allowed Radius: ${_configuredRadiusMeters}m',
                        style: const TextStyle(color: AppColors.primaryMaroon),
                      ),
                    ],
                  ),
          ),
          if (widget.canSetAttendanceLocation) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: (_isSettingLocation || _isGettingLocation)
                  ? null
                  : _setAttendanceLocation,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryMaroon,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: (_isSettingLocation || _isGettingLocation)
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.location_on),
              label: Text(
                _configuredLat == null || _configuredLng == null
                    ? ((_isSettingLocation || _isGettingLocation)
                          ? 'Setting Location...'
                          : 'Set Current Location')
                    : ((_isSettingLocation || _isGettingLocation)
                          ? 'Updating Location...'
                          : 'Update With Current Location'),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This uses your current GPS location and sets 100m allowed radius.',
              style: TextStyle(
                color: AppColors.primaryMaroon,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed:
                (_isGenerating ||
                    _configuredLat == null ||
                    _configuredLng == null)
                ? null
                : _generateAttendanceQr,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryMaroon,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: _isGenerating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.qr_code),
            label: Text(_isGenerating ? 'Generating...' : 'Generate QR'),
          ),
          if (_qrPayload != null) ...[
            const SizedBox(height: 18),
            Center(
              child: RepaintBoundary(
                key: _qrPreviewKey,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primaryMaroon.withValues(alpha: 0.25),
                    ),
                  ),
                  child: QrImageView(
                    data: _qrPayload!,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            ),
            // Show expiry only for non-permanent QRs
            if (!_qrIsPermanent &&
                _qrExpiry != null &&
                _qrExpiry!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Expires at: $_qrExpiry',
                  style: const TextStyle(
                    color: AppColors.primaryMaroon,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            if (_qrIsPermanent) ...[
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'This QR does not expire.',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isDownloadingQr ? null : _downloadQr,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryMaroon,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _isDownloadingQr
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Icon(Icons.download),
                  label: Text(
                    _isDownloadingQr ? 'Downloading...' : 'Download QR (PNG)',
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildScanTab() {
    final isSecureWeb = _isSecureWebContext;

    // Scanner widget: custom web-native scanner on web, MobileScanner on native.
    Widget scannerWidget;
    if (kIsWeb && !isSecureWeb) {
      scannerWidget = Container(
        color: Colors.black,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(20),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock, color: Colors.white70, size: 48),
            SizedBox(height: 12),
            Text(
              'Secure Connection Required',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Camera requires HTTPS or localhost.\nOpen this app on a secure URL.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                height: 1.4,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    } else if (kIsWeb) {
      // Web: use browser-native camera + jsQR (no mobile_scanner platform channel).
      scannerWidget = WebCameraQrScannerWidget(
        onQrDetected: (raw) => _markAttendance(raw.trim()),
        onReady: (stop) => _stopWebCamera = stop,
      );
    } else {
      // Native (Android / iOS): use mobile_scanner.
      scannerWidget = MobileScanner(
        controller: _scannerController,
        onDetect: (capture) {
          final barcodes = capture.barcodes;
          if (barcodes.isEmpty) return;
          final raw = barcodes.first.rawValue;
          if (raw == null || raw.trim().isEmpty) return;
          _markAttendance(raw.trim());
        },
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            _hasMarkedFromCurrentScan
                ? 'Attendance marked. Scan next QR when needed.'
                : 'Scan the attendance QR while you are within the allowed location radius.',
            style: const TextStyle(
              color: AppColors.primaryMaroon,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ),
        if (_scanInfo != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _scanInfo!,
                style: const TextStyle(
                  color: AppColors.primaryMaroon,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  Positioned.fill(child: scannerWidget),
                  if (_isMarking)
                    Container(
                      color: Colors.black.withValues(alpha: 0.4),
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _hasMarkedFromCurrentScan = false;
                  _scanInfo = null;
                });
              },
              icon: const Icon(Icons.restart_alt),
              label: const Text('Scan Again'),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.scanOnly) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Scan Attendance'),
          backgroundColor: AppColors.primaryMaroon,
          foregroundColor: Colors.white,
        ),
        body: _buildScanTab(),
      );
    }

    final tabs = <Tab>[
      const Tab(text: 'Scan & Mark'),
      const Tab(text: 'My Calendar'),
      if (widget.canViewByUserAttendance) const Tab(text: 'By User'),
      if (widget.canGenerateQr) const Tab(text: 'Generate QR'),
    ];

    final views = <Widget>[
      _buildScanTab(),
      _buildMyAttendanceTab(),
      if (widget.canViewByUserAttendance) _buildAttendanceByUserTab(),
      if (widget.canGenerateQr) _buildGenerateTab(),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Attendance Module'),
        backgroundColor: AppColors.primaryMaroon,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          tabs: tabs,
          indicatorColor: AppColors.accentYellow,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.8),
        ),
      ),
      body: TabBarView(controller: _tabController, children: views),
    );
  }
}
