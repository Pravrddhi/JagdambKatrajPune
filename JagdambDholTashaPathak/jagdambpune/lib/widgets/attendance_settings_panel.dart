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
  DateTime? _configuredSeasonStartDate;
  DateTime? _configuredSeasonEndDate;
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

  DateTime? _parseApiDate(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  DateTime? _parseFirstApiDate(Map<String, dynamic> json, List<String> keys) {
    DateTime? search(Map<String, dynamic> source, int depth) {
      for (final key in keys) {
        final parsed = _parseApiDate(source[key]?.toString());
        if (parsed != null) return parsed;
      }
      if (depth <= 0) return null;
      for (final value in source.values) {
        if (value is Map) {
          final parsed = search(Map<String, dynamic>.from(value), depth - 1);
          if (parsed != null) return parsed;
        }
      }
      return null;
    }

    return search(json, 3);
  }

  dynamic _firstValue(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value != null) return value;
    }
    return null;
  }

  String _formatApiDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  bool _isValidApiDateFormat(String value) {
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);
  }

  String? _validateSeasonDates({
    required DateTime? seasonStart,
    required DateTime? seasonEnd,
  }) {
    if (seasonStart == null || seasonEnd == null) {
      return 'This field is required.';
    }

    final startStr = _formatApiDate(seasonStart);
    final endStr = _formatApiDate(seasonEnd);
    if (!_isValidApiDateFormat(startStr) || !_isValidApiDateFormat(endStr)) {
      return 'Date has wrong format. Use one of these formats instead: YYYY-MM-DD.';
    }

    if (seasonEnd.isBefore(seasonStart)) {
      return 'Season end date cannot be before season start date.';
    }

    return null;
  }

  String _formatDisplayDate(DateTime date) {
    const months = <String>[
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
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }

  String get _seasonDateRangeLabel {
    final start = _configuredSeasonStartDate;
    final end = _configuredSeasonEndDate;
    if (start == null || end == null) return 'Not set';
    return '${_formatDisplayDate(start)} to ${_formatDisplayDate(end)}';
  }

  bool get _isWithinConfiguredSeason {
    final start = _configuredSeasonStartDate;
    final end = _configuredSeasonEndDate;
    if (start == null || end == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !today.isBefore(start) && !today.isAfter(end);
  }

  String get _seasonUnavailableMessage {
    final start = _configuredSeasonStartDate;
    final end = _configuredSeasonEndDate;
    if (start == null || end == null) {
      return 'Attendance season dates are not configured yet.';
    }
    return 'Attendance is only allowed between ${_formatDisplayDate(start)} and ${_formatDisplayDate(end)}.';
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
      final lat = double.tryParse(
        _firstValue(response, const <String>[
              'location_lat',
              'locationLat',
              'latitude',
              'lat',
            ])?.toString() ??
            '',
      );
      final lng = double.tryParse(
        _firstValue(response, const <String>[
              'location_lng',
              'locationLng',
              'longitude',
              'lng',
            ])?.toString() ??
            '',
      );
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
      final seasonStart = _parseFirstApiDate(response, const <String>[
        'season_start_date',
        'seasonStartDate',
        'season_start',
        'season_from_date',
        'seasonFromDate',
        'from_date',
      ]);
      final seasonEnd = _parseFirstApiDate(response, const <String>[
        'season_end_date',
        'seasonEndDate',
        'season_end',
        'season_to_date',
        'seasonToDate',
        'to_date',
      ]);

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
        _configuredSeasonStartDate = seasonStart;
        _configuredSeasonEndDate = seasonEnd;
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
    final preValidationMessage = _validateSeasonDates(
      seasonStart: _configuredSeasonStartDate,
      seasonEnd: _configuredSeasonEndDate,
    );
    if (preValidationMessage != null) {
      _showSnack(preValidationMessage);
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
      final seasonStart = _configuredSeasonStartDate;
      final seasonEnd = _configuredSeasonEndDate;
      final validationMessage = _validateSeasonDates(
        seasonStart: seasonStart,
        seasonEnd: seasonEnd,
      );
      if (validationMessage != null ||
          seasonStart == null ||
          seasonEnd == null) {
        throw Exception(validationMessage ?? 'This field is required.');
      }

      final response = await AttendanceService.setAttendanceLocation(
        latitude: lat,
        longitude: lng,
        radiusMeters: _configuredRadiusMeters,
        checkInTime: _configuredCheckInTime,
        checkOutTime: _configuredCheckOutTime,
        allowedBeforeMinutes: _configuredAllowedBeforeMinutes,
        allowedAfterMinutes: _configuredAllowedAfterMinutes,
        minimumPresentHours: _configuredMinimumPresentHours,
        seasonStartDate: _formatApiDate(seasonStart),
        seasonEndDate: _formatApiDate(seasonEnd),
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
    DateTime? seasonStart = _configuredSeasonStartDate;
    DateTime? seasonEnd = _configuredSeasonEndDate;

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
                    'Season Dates',
                    style: TextStyle(
                      color: AppColors.primaryMaroon,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Attendance QR generation and scanning will work only within this date range.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryMaroon,
                          side: BorderSide(
                            color: AppColors.primaryMaroon.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: seasonStart ?? now,
                            firstDate: DateTime(now.year - 5),
                            lastDate: DateTime(now.year + 10),
                          );
                          if (picked != null) {
                            setDialogState(() {
                              seasonStart = DateTime(
                                picked.year,
                                picked.month,
                                picked.day,
                              );
                            });
                          }
                        },
                        icon: const Icon(Icons.event),
                        label: Text(
                          seasonStart == null
                              ? 'Season from'
                              : _formatDisplayDate(seasonStart!),
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryMaroon,
                          side: BorderSide(
                            color: AppColors.primaryMaroon.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: seasonEnd ?? seasonStart ?? now,
                            firstDate: DateTime(now.year - 5),
                            lastDate: DateTime(now.year + 10),
                          );
                          if (picked != null) {
                            setDialogState(() {
                              seasonEnd = DateTime(
                                picked.year,
                                picked.month,
                                picked.day,
                              );
                            });
                          }
                        },
                        icon: const Icon(Icons.event_available),
                        label: Text(
                          seasonEnd == null
                              ? 'Season to'
                              : _formatDisplayDate(seasonEnd!),
                        ),
                      ),
                    ],
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
                  final validationMessage = _validateSeasonDates(
                    seasonStart: seasonStart,
                    seasonEnd: seasonEnd,
                  );
                  if (validationMessage != null) {
                    ScaffoldMessenger.of(dialogContext)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(content: Text(validationMessage)),
                      );
                    return;
                  }

                  Navigator.pop(dialogContext, <String, dynamic>{
                    'radius': radius,
                    'allowedBefore': allowedBefore,
                    'allowedAfter': allowedAfter,
                    'minimumPresentHours': minimumPresentHours,
                    'checkInStr': checkInStr,
                    'checkOutStr': checkOutStr,
                    'seasonStart': seasonStart,
                    'seasonEnd': seasonEnd,
                  });
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (settingsResult != null) {
      final radius = settingsResult['radius'] as int;
      final allowedBefore = settingsResult['allowedBefore'] as int;
      final allowedAfter = settingsResult['allowedAfter'] as int;
      final minimumPresentHours =
          settingsResult['minimumPresentHours'] as double;
      final checkInStr = settingsResult['checkInStr'] as String?;
      final checkOutStr = settingsResult['checkOutStr'] as String?;
      final seasonStart = settingsResult['seasonStart'] as DateTime;
      final seasonEnd = settingsResult['seasonEnd'] as DateTime;

      if (mounted) {
        setState(() => _isSavingSettings = true);
      }
      try {
        var lat = _configuredLat;
        var lng = _configuredLng;
        if (lat == null || lng == null) {
          final position = await AttendanceService.getCurrentPosition();
          lat = position.latitude;
          lng = position.longitude;
        }

        final response = await AttendanceService.setAttendanceLocation(
          latitude: lat,
          longitude: lng,
          radiusMeters: radius,
          checkInTime: checkInStr,
          checkOutTime: checkOutStr,
          allowedBeforeMinutes: allowedBefore,
          allowedAfterMinutes: allowedAfter,
          minimumPresentHours: minimumPresentHours,
          seasonStartDate: _formatApiDate(seasonStart),
          seasonEndDate: _formatApiDate(seasonEnd),
        );
        if (mounted) {
          setState(() {
            _configuredLat = lat;
            _configuredLng = lng;
            _configuredRadiusMeters = radius;
            _configuredAllowedBeforeMinutes = allowedBefore;
            _configuredAllowedAfterMinutes = allowedAfter;
            _configuredMinimumPresentHours = minimumPresentHours;
            _configuredCheckInTime = checkInStr;
            _configuredCheckOutTime = checkOutStr;
            _configuredSeasonStartDate = seasonStart;
            _configuredSeasonEndDate = seasonEnd;
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
    if (!_isWithinConfiguredSeason) {
      _showSnack(_seasonUnavailableMessage);
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
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Configured location is not set yet.',
                        style: TextStyle(color: AppColors.primaryMaroon),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Season: $_seasonDateRangeLabel',
                        style: const TextStyle(color: AppColors.primaryMaroon),
                      ),
                    ],
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
                      const SizedBox(height: 4),
                      Text(
                        'Season: $_seasonDateRangeLabel',
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
              'Set check-in time, attendance window, minimum present hours, season dates, and radius.',
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
                      _configuredLng == null ||
                      !_isWithinConfiguredSeason)
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
            if (!_isWithinConfiguredSeason) ...[
              const SizedBox(height: 8),
              Text(
                _seasonUnavailableMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.primaryMaroon,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
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
