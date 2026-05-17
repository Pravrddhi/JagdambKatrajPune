import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/attendance_service.dart';
import '../theme/app_colors.dart';
import '../utils/qr_download_helper.dart';

class AttendanceSettingsPanel extends StatefulWidget {
  final bool canManageSettings;
  final bool canGenerateQr;
  final bool canDownloadAttendanceQr;

  const AttendanceSettingsPanel({
    super.key,
    required this.canManageSettings,
    required this.canGenerateQr,
    this.canDownloadAttendanceQr = false,
  });

  @override
  State<AttendanceSettingsPanel> createState() =>
      _AttendanceSettingsPanelState();
}

class _AttendanceSettingsPanelState extends State<AttendanceSettingsPanel> {
  bool _isGettingLocation = false;
  bool _isSettingLocation = false;
  bool _isLoadingConfiguredLocation = false;
  bool _isSavingSettings = false;
  bool _isGenerating = false;
  bool _isDownloadingQr = false;

  double? _configuredLat;
  double? _configuredLng;
  int _configuredRadiusMeters = 100;
  String? _configuredCheckInTime;
  String? _configuredCheckOutTime;
  int _configuredAllowedBeforeMinutes = 15;
  int _configuredAllowedAfterMinutes = 15;
  double _configuredMinimumPresentHours = 4.0;
  String? _qrPayload;
  String? _qrExpiry;
  bool _qrIsPermanent = false;
  final GlobalKey _qrPreviewKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadConfiguredAttendanceLocation();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String get _minimumPresentHoursLabel {
    final hours = _configuredMinimumPresentHours;
    if (hours == hours.roundToDouble()) {
      return hours.toInt().toString();
    }
    return hours.toStringAsFixed(1);
  }

  TimeOfDay? _parseTimeOfDay(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
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
      final checkIn = response['check_in_time']?.toString();
      final checkOut = response['check_out_time']?.toString();
      final allowedBefore =
          int.tryParse(
            response['allowed_minutes_before_check_in']?.toString() ?? '',
          ) ??
          int.tryParse(response['allowed_before_minutes']?.toString() ?? '') ??
          int.tryParse(response['check_in_before_minutes']?.toString() ?? '');
      final allowedAfter =
          int.tryParse(
            response['allowed_minutes_after_check_in']?.toString() ?? '',
          ) ??
          int.tryParse(response['allowed_after_minutes']?.toString() ?? '') ??
          int.tryParse(response['check_in_after_minutes']?.toString() ?? '');
      final minimumPresentHours =
          double.tryParse(
            response['minimum_present_hours']?.toString() ?? '',
          ) ??
          double.tryParse(response['present_hours_required']?.toString() ?? '');

      if (!mounted) return;
      setState(() {
        _configuredLat = lat;
        _configuredLng = lng;
        _configuredRadiusMeters = radius;
        if (checkIn != null && checkIn.trim().isNotEmpty) {
          _configuredCheckInTime = checkIn.trim();
        }
        if (checkOut != null && checkOut.trim().isNotEmpty) {
          _configuredCheckOutTime = checkOut.trim();
        }
        if (allowedBefore != null) {
          _configuredAllowedBeforeMinutes = allowedBefore;
        }
        if (allowedAfter != null) {
          _configuredAllowedAfterMinutes = allowedAfter;
        }
        if (minimumPresentHours != null) {
          _configuredMinimumPresentHours = minimumPresentHours;
        }
      });
    } catch (_) {
      // Leave panel visible even if settings are not configured yet.
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingConfiguredLocation = false;
        });
      }
    }
  }

  Future<void> _setAttendanceLocation() async {
    if (_isSettingLocation || _isGettingLocation || !widget.canManageSettings) {
      return;
    }

    setState(() {
      _isGettingLocation = true;
    });

    double? lat;
    double? lng;
    try {
      final position = await AttendanceService.getCurrentPosition();
      lat = position.latitude;
      lng = position.longitude;
    } catch (error) {
      _showSnack(error.toString().replaceFirst('Exception: ', ''));
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
        radiusMeters: _configuredRadiusMeters,
        checkInTime: _configuredCheckInTime,
        checkOutTime: _configuredCheckOutTime,
        allowedBeforeMinutes: _configuredAllowedBeforeMinutes,
        allowedAfterMinutes: _configuredAllowedAfterMinutes,
        minimumPresentHours: _configuredMinimumPresentHours,
      );

      if (!mounted) return;
      setState(() {
        _configuredLat = lat;
        _configuredLng = lng;
        _configuredRadiusMeters =
            int.tryParse(response['radius_meters']?.toString() ?? '') ??
            _configuredRadiusMeters;
      });
      _showSnack(
        response['message']?.toString() ?? 'Attendance location updated.',
      );
    } catch (error) {
      _showSnack(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isSettingLocation = false;
        });
      }
    }
  }

  Future<void> _openAttendanceSettingsDialog() async {
    if (!widget.canManageSettings) {
      return;
    }

    final radiusCtrl = TextEditingController(
      text: _configuredRadiusMeters.toString(),
    );
    final allowedBeforeCtrl = TextEditingController(
      text: _configuredAllowedBeforeMinutes.toString(),
    );
    final allowedAfterCtrl = TextEditingController(
      text: _configuredAllowedAfterMinutes.toString(),
    );
    final minimumPresentHoursCtrl = TextEditingController(
      text: _minimumPresentHoursLabel,
    );
    TimeOfDay? checkIn = _configuredCheckInTime != null
        ? _parseTimeOfDay(_configuredCheckInTime!)
        : null;
    TimeOfDay? checkOut = _configuredCheckOutTime != null
        ? _parseTimeOfDay(_configuredCheckOutTime!)
        : null;

    final settingsResult = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text(
              'Attendance Settings',
              style: TextStyle(color: AppColors.primaryMaroon),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Check-in Time',
                    style: TextStyle(
                      color: AppColors.primaryMaroon,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryMaroon,
                      side: BorderSide(
                        color: AppColors.primaryMaroon.withValues(alpha: 0.35),
                      ),
                    ),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: dialogContext,
                        initialTime:
                            checkIn ?? const TimeOfDay(hour: 9, minute: 0),
                      );
                      if (picked != null) {
                        setDialogState(() => checkIn = picked);
                      }
                    },
                    icon: const Icon(Icons.access_time),
                    label: Text(
                      checkIn != null
                          ? checkIn!.format(dialogContext)
                          : 'Select check-in time',
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Check-out Time',
                    style: TextStyle(
                      color: AppColors.primaryMaroon,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryMaroon,
                      side: BorderSide(
                        color: AppColors.primaryMaroon.withValues(alpha: 0.35),
                      ),
                    ),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: dialogContext,
                        initialTime:
                            checkOut ?? const TimeOfDay(hour: 18, minute: 0),
                      );
                      if (picked != null) {
                        setDialogState(() => checkOut = picked);
                      }
                    },
                    icon: const Icon(Icons.access_time_filled),
                    label: Text(
                      checkOut != null
                          ? checkOut!.format(dialogContext)
                          : 'Select check-out time',
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Allowed Attendance Before Check-in (minutes)',
                    style: TextStyle(
                      color: AppColors.primaryMaroon,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Before this, attendance cannot be marked.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: allowedBeforeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'e.g. 15',
                      suffixText: 'min',
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Allowed Attendance After Check-in (minutes)',
                    style: TextStyle(
                      color: AppColors.primaryMaroon,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'After this, attendance will be marked as late.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: allowedAfterCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'e.g. 15',
                      suffixText: 'min',
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Minimum Hours For Present',
                    style: TextStyle(
                      color: AppColors.primaryMaroon,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'If user stays for less than this duration between check-in and check-out, mark absent.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: minimumPresentHoursCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'e.g. 4',
                      suffixText: 'hours',
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Attendance Radius (meters)',
                    style: TextStyle(
                      color: AppColors.primaryMaroon,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Members must be within this radius to scan QR.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: radiusCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'e.g. 100',
                      suffixText: 'm',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryMaroon,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  final radius =
                      int.tryParse(radiusCtrl.text.trim()) ??
                      _configuredRadiusMeters;
                  final allowedBefore =
                      int.tryParse(allowedBeforeCtrl.text.trim()) ??
                      _configuredAllowedBeforeMinutes;
                  final allowedAfter =
                      int.tryParse(allowedAfterCtrl.text.trim()) ??
                      _configuredAllowedAfterMinutes;
                  final minimumPresentHours =
                      double.tryParse(minimumPresentHoursCtrl.text.trim()) ??
                      _configuredMinimumPresentHours;
                  final checkInStr = checkIn != null
                      ? '${checkIn!.hour.toString().padLeft(2, '0')}:${checkIn!.minute.toString().padLeft(2, '0')}'
                      : null;
                  final checkOutStr = checkOut != null
                      ? '${checkOut!.hour.toString().padLeft(2, '0')}:${checkOut!.minute.toString().padLeft(2, '0')}'
                      : null;

                  Navigator.pop(dialogContext, <String, dynamic>{
                    'radius': radius,
                    'allowedBefore': allowedBefore,
                    'allowedAfter': allowedAfter,
                    'minimumPresentHours': minimumPresentHours,
                    'checkInStr': checkInStr,
                    'checkOutStr': checkOutStr,
                  });
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    final lat = _configuredLat;
    final lng = _configuredLng;
    if (settingsResult != null && (lat == null || lng == null)) {
      _showSnack('Set current location first before saving settings.');
    } else if (settingsResult != null && lat != null && lng != null) {
      final radius = settingsResult['radius'] as int;
      final allowedBefore = settingsResult['allowedBefore'] as int;
      final allowedAfter = settingsResult['allowedAfter'] as int;
      final minimumPresentHours =
          settingsResult['minimumPresentHours'] as double;
      final checkInStr = settingsResult['checkInStr'] as String?;
      final checkOutStr = settingsResult['checkOutStr'] as String?;

      if (mounted) {
        setState(() => _isSavingSettings = true);
      }
      try {
        final response = await AttendanceService.setAttendanceLocation(
          latitude: lat,
          longitude: lng,
          radiusMeters: radius,
          checkInTime: checkInStr,
          checkOutTime: checkOutStr,
          allowedBeforeMinutes: allowedBefore,
          allowedAfterMinutes: allowedAfter,
          minimumPresentHours: minimumPresentHours,
        );
        if (mounted) {
          setState(() {
            _configuredRadiusMeters = radius;
            _configuredAllowedBeforeMinutes = allowedBefore;
            _configuredAllowedAfterMinutes = allowedAfter;
            _configuredMinimumPresentHours = minimumPresentHours;
            _configuredCheckInTime = checkInStr;
            _configuredCheckOutTime = checkOutStr;
          });
        }
        _showSnack(response['message']?.toString() ?? 'Settings saved.');
      } catch (error) {
        _showSnack(error.toString().replaceFirst('Exception: ', ''));
      } finally {
        if (mounted) setState(() => _isSavingSettings = false);
      }
    }

    radiusCtrl.dispose();
    allowedBeforeCtrl.dispose();
    allowedAfterCtrl.dispose();
    minimumPresentHoursCtrl.dispose();
  }

  Future<void> _generateAttendanceQr() async {
    if (_isGenerating || !widget.canGenerateQr) return;

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
        permanent: widget.canManageSettings,
      );

      final payload =
          response['qr_payload']?.toString() ??
          response['qr_token']?.toString() ??
          response['token']?.toString() ??
          '';

      if (payload.isEmpty) {
        throw Exception('QR payload missing in response.');
      }

      if (!mounted) return;
      setState(() {
        _qrPayload = payload;
        _qrExpiry = response['expires_at']?.toString();
        _qrIsPermanent = response['is_permanent'] == true;
      });

      _showSnack(response['message']?.toString() ?? 'Attendance QR generated.');
    } catch (error) {
      _showSnack(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<Uint8List?> _renderQrToPng(String data, {double size = 400}) async {
    try {
      final painter = QrPainter(
        data: data,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
        dataModuleStyle: const QrDataModuleStyle(color: Color(0xFF000000)),
        eyeStyle: const QrEyeStyle(color: Color(0xFF000000)),
        gapless: false,
      );

      final byteData = await painter.toImageData(
        size,
        format: ui.ImageByteFormat.png,
      );
      if (byteData != null) return byteData.buffer.asUint8List();

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

  Future<void> _downloadQr() async {
    final payload = _qrPayload;
    if (payload == null || !widget.canDownloadAttendanceQr) return;

    setState(() => _isDownloadingQr = true);
    try {
      final bytes =
          await _captureDisplayedQrPng() ?? await _renderQrToPng(payload);
      if (bytes == null) throw Exception('Failed to render QR image.');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'jagdamb_attendance_qr_$timestamp.png';
      final ok = await downloadQrBytes(bytes, filename);
      if (ok) {
        _showSnack(kIsWeb ? 'QR downloaded.' : 'QR saved to temp folder.');
      } else {
        throw Exception('Download failed. Please try again.');
      }
    } catch (error) {
      _showSnack(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isDownloadingQr = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canManageSettings && !widget.canGenerateQr) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'You do not have access to attendance settings.',
            style: TextStyle(
              color: AppColors.primaryMaroon,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.canManageSettings
                ? 'Configure attendance location, radius, time window, minimum present hours, and generate QR from here.'
                : 'Generate attendance QR from the configured location here.',
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
                        'Location: ${_configuredLat!.toStringAsFixed(7)}, ${_configuredLng!.toStringAsFixed(7)}',
                        style: const TextStyle(
                          color: AppColors.primaryMaroon,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Radius: ${_configuredRadiusMeters}m',
                        style: const TextStyle(color: AppColors.primaryMaroon),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Check-in: ${_configuredCheckInTime ?? 'Not set'}  |  Check-out: ${_configuredCheckOutTime ?? 'Not set'}',
                        style: const TextStyle(color: AppColors.primaryMaroon),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Allowed window: $_configuredAllowedBeforeMinutes min before check-in | Late after $_configuredAllowedAfterMinutes min',
                        style: const TextStyle(color: AppColors.primaryMaroon),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Present if stayed at least: $_minimumPresentHoursLabel hour(s)',
                        style: const TextStyle(color: AppColors.primaryMaroon),
                      ),
                    ],
                  ),
          ),
          if (widget.canManageSettings) ...[
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
            OutlinedButton.icon(
              onPressed: _isSavingSettings
                  ? null
                  : _openAttendanceSettingsDialog,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryMaroon,
                side: const BorderSide(color: AppColors.primaryMaroon),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _isSavingSettings
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.settings),
              label: const Text('Attendance Settings'),
            ),
            const SizedBox(height: 4),
            const Text(
              'Set check-in time, attendance window, minimum present hours, and radius.',
              style: TextStyle(
                color: AppColors.primaryMaroon,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          if (widget.canGenerateQr) ...[
            const SizedBox(height: 16),
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
              ],
              if (widget.canDownloadAttendanceQr) ...[
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
        ],
      ),
    );
  }
}
