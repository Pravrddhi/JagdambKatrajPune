import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:table_calendar/table_calendar.dart';

import '../services/attendance_service.dart';
import '../config/api_endpoints.dart';
import '../models/maintenance_models.dart';
import '../services/maintenance_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../utils/qr_download_helper.dart';
import '../widgets/web_camera_qr_scanner.dart';

class AttendanceModuleScreen extends StatefulWidget {
  final bool canGenerateQr;
  final bool canDownloadAttendanceQr;
  final bool canSetAttendanceLocation;
  final bool canViewByUserAttendance;
  final bool isPathakAdmin;
  final bool scanOnly;

  const AttendanceModuleScreen({
    super.key,
    required this.canGenerateQr,
    this.canDownloadAttendanceQr = false,
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
  static const int _checkoutCooldownMinutes = 30;
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _maintenanceCheckoutBlockedMessage =
      'Maintenance request is not approved. Attendance is blocked.';
  static const String _checkoutCooldownUntilKeyBase =
      'attendance_checkout_cooldown_until';
  static const String _checkoutCooldownSourceKeyBase =
      'attendance_checkout_cooldown_source';
  static const String _checkoutCooldownServerOffsetKeyBase =
      'attendance_checkout_cooldown_server_offset_seconds';

  late final TabController _tabController;
  final MobileScannerController _scannerController = MobileScannerController(
    autoStart: false,
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
    detectionTimeoutMs: 500,
  );

  bool _isGenerating = false;
  bool _isDownloadingQr = false;
  bool _isLoadingConfiguredLocation = false;
  String? _qrPayload;
  String? _qrExpiry;
  bool _qrIsPermanent = false;
  final GlobalKey _qrPreviewKey = GlobalKey();
  double? _configuredLat;
  double? _configuredLng;
  int _configuredRadiusMeters = 100;
  String? _configuredCheckInTime; // e.g. "09:00"
  String? _configuredCheckOutTime; // e.g. "18:00"
  int _configuredAllowedBeforeMinutes = 15;
  int _configuredAllowedAfterMinutes = 15;
  double _configuredMinimumPresentHours = 4.0;
  DateTime? _configuredSeasonStartDate;
  DateTime? _configuredSeasonEndDate;

  bool _isMarking = false;
  bool _hasMarkedFromCurrentScan = false;
  String? _scanInfo;
  VoidCallback? _stopWebCamera;
  bool _isAttendanceBlocked = false;
  String? _attendanceBlockedMessage;
  bool _isCheckingAttendanceApproval = false;
  bool _hasResolvedAttendanceApprovalGate = false;
  Timer? _attendanceApprovalAutoRefreshTimer;
  DateTime? _lastSuccessfulCheckInAt;
  DateTime? _todayCheckInFromHistoryAt;
  DateTime? _todayCheckInSnapshotDay;
  DateTime? _lastTodayCheckInLookupAt;
  bool _isResolvingTodayCheckIn = false;
  DateTime? _lastSuccessfulCheckOutAt;
  DateTime? _checkoutAllowedAtFromServer;
  int _serverClockOffsetSeconds = 0;
  Timer? _checkoutCooldownTimer;
  bool _isCheckoutScannerUnlocked = false;
  String _cooldownUserScope = 'anon';

  String get _checkoutCooldownUntilKey =>
      '${_checkoutCooldownUntilKeyBase}_$_cooldownUserScope';
  String get _checkoutCooldownSourceKey =>
      '${_checkoutCooldownSourceKeyBase}_$_cooldownUserScope';
  String get _checkoutCooldownServerOffsetKey =>
      '${_checkoutCooldownServerOffsetKeyBase}_$_cooldownUserScope';

  bool _isLoadingMyAttendance = false;
  DateTime _calendarFocusDate = DateTime.now();
  DateTime _selectedDate = DateTime.now();
  final Map<DateTime, String> _attendanceByDate = <DateTime, String>{};
  final Map<DateTime, Map<String, dynamic>> _attendanceRecordByDate =
      <DateTime, Map<String, dynamic>>{};

  bool _isLoadingAttendanceByUser = false;
  DateTime _byUserFocusMonth = DateTime.now();
  List<Map<String, dynamic>> _attendanceByUser = <Map<String, dynamic>>[];
  final TextEditingController _nameSearchController = TextEditingController();
  String _nameFilter = '';
  int? _cachedCurrentUserId;
  String _cachedCurrentUserName = '';

  bool get _isSecureWebContext {
    if (!kIsWeb) return true;
    final host = Uri.base.host.toLowerCase();
    final isLocalhost = host == 'localhost' || host == '127.0.0.1';
    return Uri.base.scheme == 'https' || isLocalhost;
  }

  @override
  void initState() {
    super.initState();

    // Scan flow also needs configured check-in settings for timing validation.
    _loadConfiguredAttendanceLocation();
    _initCooldownStorageScope();
    unawaited(_ensureAttendanceApprovalGate(force: true));

    if (widget.scanOnly) {
      _tabController = TabController(length: 1, vsync: this, initialIndex: 0);
      _syncScannerLifecycle();
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
    _tabController.addListener(_handleTabControllerTick);
    _syncScannerLifecycle();

    _loadMyAttendance();
    if (widget.canViewByUserAttendance) {
      _loadAttendanceByUser();
    }
  }

  @override
  void dispose() {
    _checkoutCooldownTimer?.cancel();
    _attendanceApprovalAutoRefreshTimer?.cancel();
    if (!widget.scanOnly) {
      _tabController.removeListener(_handleTabControllerTick);
    }
    _pauseAllScanners();
    _scannerController.dispose();
    _tabController.dispose();
    _nameSearchController.dispose();
    super.dispose();
  }

  Future<void> _initCooldownStorageScope() async {
    final token = await _storage.read(key: ApiEndpoints.accessTokenKey);
    if (!mounted) return;
    _cooldownUserScope = _extractUserScopeFromToken(token) ?? 'anon';
    await _cleanupLegacyGlobalCooldownKeys();
    await _restoreCheckoutCooldown();
    // Resync scanner after cooldown state is restored to prevent
    // camera from starting if cooldown is active
    if (mounted) {
      _syncScannerLifecycle();
    }
  }

  Future<void> _cleanupLegacyGlobalCooldownKeys() async {
    // Migration cleanup: older builds used non-user-scoped keys.
    await _storage.delete(key: _checkoutCooldownUntilKeyBase);
    await _storage.delete(key: _checkoutCooldownSourceKeyBase);
    await _storage.delete(key: _checkoutCooldownServerOffsetKeyBase);
  }

  String? _extractUserScopeFromToken(String? token) {
    final raw = token?.trim();
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('.');
    if (parts.length < 2) return null;

    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;

      final candidates = <dynamic>[
        decoded['user_id'],
        decoded['userId'],
        decoded['id'],
        decoded['sub'],
      ];
      for (final value in candidates) {
        final id = value?.toString().trim();
        if (id != null && id.isNotEmpty) {
          return id;
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<int?> _resolveCurrentUserId() async {
    if (_cachedCurrentUserId != null) {
      return _cachedCurrentUserId;
    }

    final scopedUserId = int.tryParse(_cooldownUserScope);
    if (scopedUserId != null) {
      _cachedCurrentUserId = scopedUserId;
      return scopedUserId;
    }

    final token = await _storage.read(key: ApiEndpoints.accessTokenKey);
    final tokenUserId = int.tryParse(_extractUserScopeFromToken(token) ?? '');
    if (tokenUserId != null) {
      _cachedCurrentUserId = tokenUserId;
      return tokenUserId;
    }

    final rawToken = token?.trim();
    if (rawToken == null || rawToken.isEmpty) {
      return null;
    }

    try {
      final userDetails = await UserService.fetchUserDetails(rawToken);
      final userId = int.tryParse(
        userDetails['id']?.toString() ??
            userDetails['user_id']?.toString() ??
            userDetails['userId']?.toString() ??
            '',
      );
      final fullName = _extractUserFullName(userDetails);
      if (fullName.isNotEmpty) {
        _cachedCurrentUserName = fullName;
      }
      if (userId != null) {
        _cachedCurrentUserId = userId;
      }
      return userId;
    } catch (_) {
      return null;
    }
  }

  String _extractUserFullName(Map<String, dynamic> userDetails) {
    final firstName = userDetails['first_name']?.toString().trim() ?? '';
    final lastName = userDetails['last_name']?.toString().trim() ?? '';
    final fullName = '$firstName $lastName'.trim();
    if (fullName.isNotEmpty) {
      return fullName;
    }
    return userDetails['name']?.toString().trim() ?? '';
  }

  Future<String> _resolveCurrentUserName() async {
    if (_cachedCurrentUserName.trim().isNotEmpty) {
      return _cachedCurrentUserName.trim().toLowerCase();
    }

    final token = await _storage.read(key: ApiEndpoints.accessTokenKey);
    final rawToken = token?.trim();
    if (rawToken == null || rawToken.isEmpty) {
      return '';
    }

    try {
      final userDetails = await UserService.fetchUserDetails(rawToken);
      final fullName = _extractUserFullName(userDetails);
      if (fullName.isNotEmpty) {
        _cachedCurrentUserName = fullName;
      }
      return _cachedCurrentUserName.trim().toLowerCase();
    } catch (_) {
      return '';
    }
  }

  int _compareCompletionRequestRecency(
    MaintenanceCompletionRequest left,
    MaintenanceCompletionRequest right,
  ) {
    final leftUpdated = DateTime.tryParse(left.updatedAt);
    final rightUpdated = DateTime.tryParse(right.updatedAt);
    if (leftUpdated != null && rightUpdated != null) {
      final comparison = leftUpdated.compareTo(rightUpdated);
      if (comparison != 0) {
        return comparison;
      }
    } else if (leftUpdated != null) {
      return 1;
    } else if (rightUpdated != null) {
      return -1;
    }

    final leftCreated = DateTime.tryParse(left.createdAt);
    final rightCreated = DateTime.tryParse(right.createdAt);
    if (leftCreated != null && rightCreated != null) {
      final comparison = leftCreated.compareTo(rightCreated);
      if (comparison != 0) {
        return comparison;
      }
    } else if (leftCreated != null) {
      return 1;
    } else if (rightCreated != null) {
      return -1;
    }

    return left.id.compareTo(right.id);
  }

  MaintenanceCompletionRequest? _latestCompletionRequestForUser(
    Iterable<MaintenanceCompletionRequest> requests,
    int? userId,
    String normalizedCurrentUserName,
  ) {
    MaintenanceCompletionRequest? latestRequest;

    for (final request in requests) {
      final matchesById = userId != null && request.submittedBy == userId;
      final matchesByName =
          normalizedCurrentUserName.isNotEmpty &&
          request.submittedByName.trim().toLowerCase() ==
              normalizedCurrentUserName;

      if (!matchesById && !matchesByName) {
        continue;
      }

      if (latestRequest == null ||
          _compareCompletionRequestRecency(request, latestRequest) > 0) {
        latestRequest = request;
      }
    }

    return latestRequest;
  }

  Future<bool> _validateMaintenanceApprovalForCheckout() async {
    try {
      final userId = await _resolveCurrentUserId();
      final normalizedCurrentUserName = await _resolveCurrentUserName();
      if (userId == null && normalizedCurrentUserName.isEmpty) {
        if (mounted) {
          setState(() {
            _isAttendanceBlocked = true;
            _attendanceBlockedMessage = _maintenanceCheckoutBlockedMessage;
            _isCheckoutScannerUnlocked = true;
          });
        }
        return false;
      }

      // Simple rule for checkout: user's latest maintenance request must be approved.
      final completionRequests =
          await MaintenanceService.fetchCompletionRequests();
      if (completionRequests.isEmpty) {
        if (mounted) {
          setState(() {
            _isAttendanceBlocked = true;
            _attendanceBlockedMessage = _maintenanceCheckoutBlockedMessage;
            _isCheckoutScannerUnlocked = true;
          });
        }
        return false;
      }

      final latestRequest = _latestCompletionRequestForUser(
        completionRequests,
        userId,
        normalizedCurrentUserName,
      );

      if (latestRequest?.normalizedStatus == 'approved') {
        if (_isAttendanceBlocked && mounted) {
          setState(() {
            _isAttendanceBlocked = false;
            _attendanceBlockedMessage = null;
          });
        }
        return true;
      }

      if (mounted) {
        setState(() {
          _isAttendanceBlocked = true;
          _attendanceBlockedMessage = _maintenanceCheckoutBlockedMessage;
          _isCheckoutScannerUnlocked = true;
        });
      }
      return false;
    } catch (_) {
      if (mounted) {
        setState(() {
          _isAttendanceBlocked = true;
          _attendanceBlockedMessage = _maintenanceCheckoutBlockedMessage;
          _isCheckoutScannerUnlocked = true;
        });
      }
      return false;
    }
  }

  Future<void> _ensureAttendanceApprovalGate({bool force = false}) async {
    if (!mounted) return;
    if (_isCheckingAttendanceApproval) return;
    if (!force && _hasResolvedAttendanceApprovalGate) return;
    if (!_isScanTabActive) return;
    if (!_isWithinConfiguredSeason) return;
    if (!_isCheckoutApprovalContext) return;

    setState(() {
      _isCheckingAttendanceApproval = true;
    });

    await _validateMaintenanceApprovalForCheckout();

    if (!mounted) return;
    setState(() {
      _isCheckingAttendanceApproval = false;
      _hasResolvedAttendanceApprovalGate = true;
    });
  }

  void _pauseNativeScanner() {
    if (kIsWeb) return;
    unawaited(_scannerController.stop());
  }

  void _resumeNativeScanner() {
    if (kIsWeb) return;
    unawaited(_scannerController.start());
  }

  void _pauseAllScanners() {
    _pauseNativeScanner();
    _stopWebCamera?.call();
    _stopWebCamera = null;
  }

  bool get _isScanTabActive {
    if (widget.scanOnly) return true;
    return _tabController.index == 0;
  }

  bool get _shouldDisableCamera {
    if (!_isScanTabActive) return true;
    if (!_isWithinConfiguredSeason) return true;
    if (_isCheckingAttendanceApproval && _isCheckoutApprovalContext) {
      return true;
    }
    if (_isAttendanceBlocked && _isCheckoutApprovalContext) {
      return true;
    }
    if (_shouldBlockScannerForCheckoutCooldown) return true;
    if (_shouldShowCheckoutScannerUnlockCard && !_isCheckoutScannerUnlocked) {
      return true;
    }
    return false;
  }

  bool get _isCheckoutApprovalContext {
    return _isCheckoutScannerUnlocked;
  }

  bool get _hasCompletedCheckoutToday {
    final checkedOutAt = _lastSuccessfulCheckOutAt;
    if (checkedOutAt == null) return false;
    return _isSameDate(checkedOutAt, DateTime.now());
  }

  void _startAttendanceApprovalAutoRefreshIfNeeded() {
    if (_attendanceApprovalAutoRefreshTimer != null) return;
    _attendanceApprovalAutoRefreshTimer = Timer.periodic(
      const Duration(seconds: 12),
      (_) {
        if (!mounted ||
            !_isScanTabActive ||
            !_isAttendanceBlocked ||
            !_isCheckoutApprovalContext) {
          _stopAttendanceApprovalAutoRefresh();
          return;
        }
        unawaited(_ensureAttendanceApprovalGate(force: true));
      },
    );
  }

  void _stopAttendanceApprovalAutoRefresh() {
    _attendanceApprovalAutoRefreshTimer?.cancel();
    _attendanceApprovalAutoRefreshTimer = null;
  }

  void _syncScannerLifecycle() {
    if (_isScanTabActive &&
        _isAttendanceBlocked &&
        _isCheckoutApprovalContext) {
      _startAttendanceApprovalAutoRefreshIfNeeded();
    } else {
      _stopAttendanceApprovalAutoRefresh();
    }

    if (_shouldDisableCamera) {
      _pauseAllScanners();
      return;
    }

    if (!kIsWeb) {
      _resumeNativeScanner();
    }
  }

  void _handleTabControllerTick() {
    if (_isScanTabActive && _isCheckoutApprovalContext) {
      unawaited(_ensureAttendanceApprovalGate(force: _isAttendanceBlocked));
    }
    _syncScannerLifecycle();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _showScanResultPopupAndNavigateHome({
    required String title,
    required String message,
    required bool isSuccess,
  }) async {
    // Stop camera before switching tab to avoid extra detections during popup.
    _stopWebCamera?.call();

    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: isSuccess
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFFFEBEE),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
                color: isSuccess ? Colors.green : Colors.red,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.primaryMaroon,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
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
              onPressed: () => Navigator.of(dialogContext).pop(),
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

    if (!mounted) return;

    // Let the dialog route fully settle before mutating navigation state.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    // Return to Home screen after acknowledging popup.
    if (Navigator.of(context).canPop()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        } catch (e) {
          // Handle navigation errors gracefully
          debugPrint('Navigation error after attendance popup: $e');
        }
      });
      return;
    }

    // Fallback when route can't be popped.
    if (!widget.scanOnly && _tabController.length > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          if (_tabController.length > 1) {
            _tabController.animateTo(1);
          }
        } catch (e) {
          // Handle tab controller errors gracefully
          debugPrint('Tab controller error after attendance popup: $e');
        }
      });
    }
  }

  DateTime? _todayAtConfiguredTime(String? hhmm) {
    final time = hhmm == null ? null : _parseTimeOfDay(hhmm);
    if (time == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, time.hour, time.minute);
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatTimeLabel(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  DateTime? _parseServerDateTime(dynamic raw) {
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    return parsed.isUtc ? parsed.toLocal() : parsed;
  }

  int _resolveServerOffsetSeconds(DateTime? serverNow) {
    if (serverNow == null) {
      return _serverClockOffsetSeconds;
    }
    return serverNow.difference(DateTime.now()).inSeconds;
  }

  DateTime? get _checkoutAllowedAt {
    final serverAllowedAt = _checkoutAllowedAtFromServer;
    if (serverAllowedAt != null) {
      return serverAllowedAt;
    }
    final checkInAt = _lastSuccessfulCheckInAt;
    if (checkInAt == null) return null;
    return checkInAt.add(const Duration(minutes: _checkoutCooldownMinutes));
  }

  DateTime get _effectiveNowForCooldown {
    return DateTime.now().add(Duration(seconds: _serverClockOffsetSeconds));
  }

  Duration? get _checkoutCooldownRemaining {
    final allowedAt = _checkoutAllowedAt;
    if (allowedAt == null) return null;
    final remaining = allowedAt.difference(_effectiveNowForCooldown);
    if (remaining.isNegative) return Duration.zero;
    return remaining;
  }

  bool get _isCheckoutCooldownActive {
    final remaining = _checkoutCooldownRemaining;
    return remaining != null && remaining > Duration.zero;
  }

  bool get _shouldBlockScannerForCheckoutCooldown {
    final checkInAt = _lastSuccessfulCheckInAt;
    if (checkInAt == null) return false;
    if (!_isSameDate(checkInAt, DateTime.now())) return false;
    return _isCheckoutCooldownActive;
  }

  bool get _shouldShowCheckoutScannerUnlockCard {
    final checkInAt = _lastSuccessfulCheckInAt;
    if (checkInAt == null) return false;
    if (!_isSameDate(checkInAt, DateTime.now())) return false;
    return !_isCheckoutCooldownActive;
  }

  String get _checkoutCooldownRemainingLabel {
    final remaining = _checkoutCooldownRemaining ?? Duration.zero;
    final totalSeconds = remaining.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes <= 0) {
      return '$seconds sec';
    }
    return '$minutes min ${seconds.toString().padLeft(2, '0')} sec';
  }

  double get _checkoutCooldownProgress {
    final remaining = _checkoutCooldownRemaining ?? Duration.zero;
    const totalSeconds = _checkoutCooldownMinutes * 60;
    final remainingSeconds = remaining.inSeconds.clamp(0, totalSeconds);
    return 1 - (remainingSeconds / totalSeconds);
  }

  Future<void> _persistCheckoutCooldown({
    required DateTime checkInAt,
    required DateTime allowedAt,
    required String source,
    required int serverClockOffsetSeconds,
  }) async {
    await _storage.write(
      key: _checkoutCooldownUntilKey,
      value: allowedAt.toIso8601String(),
    );
    await _storage.write(key: _checkoutCooldownSourceKey, value: source);
    await _storage.write(
      key: _checkoutCooldownServerOffsetKey,
      value: serverClockOffsetSeconds.toString(),
    );

    _lastSuccessfulCheckInAt = checkInAt;
    _checkoutAllowedAtFromServer = allowedAt;
    _serverClockOffsetSeconds = serverClockOffsetSeconds;
  }

  Future<void> _clearCheckoutCooldown() async {
    _checkoutCooldownTimer?.cancel();
    _checkoutCooldownTimer = null;
    _lastSuccessfulCheckInAt = null;
    _checkoutAllowedAtFromServer = null;
    _serverClockOffsetSeconds = 0;
    _isCheckoutScannerUnlocked = false;
    await _storage.delete(key: _checkoutCooldownUntilKey);
    await _storage.delete(key: _checkoutCooldownSourceKey);
    await _storage.delete(key: _checkoutCooldownServerOffsetKey);
  }

  Future<void> _restoreCheckoutCooldown() async {
    final stored = await _storage.read(key: _checkoutCooldownUntilKey);
    final source = await _storage.read(key: _checkoutCooldownSourceKey);
    final storedOffset = await _storage.read(
      key: _checkoutCooldownServerOffsetKey,
    );
    if (!mounted || stored == null || stored.trim().isEmpty) return;

    // Ignore cooldown values from older builds that were not explicitly check-in based.
    final normalizedSource = source?.trim().toLowerCase() ?? '';
    if (normalizedSource != 'check_in' && normalizedSource != 'server') {
      await _storage.delete(key: _checkoutCooldownUntilKey);
      await _storage.delete(key: _checkoutCooldownSourceKey);
      await _storage.delete(key: _checkoutCooldownServerOffsetKey);
      return;
    }

    final allowedAt = DateTime.tryParse(stored.trim());
    if (allowedAt == null) {
      await _storage.delete(key: _checkoutCooldownUntilKey);
      await _storage.delete(key: _checkoutCooldownSourceKey);
      await _storage.delete(key: _checkoutCooldownServerOffsetKey);
      return;
    }

    final restoredOffset = int.tryParse(storedOffset?.trim() ?? '') ?? 0;
    _serverClockOffsetSeconds = restoredOffset;

    final checkInAt = allowedAt.subtract(
      const Duration(minutes: _checkoutCooldownMinutes),
    );

    if (allowedAt.isBefore(_effectiveNowForCooldown)) {
      // Cooldown already expired. Clean up storage but if it's still the same
      // calendar day keep the check-in marker so the next scan sends check_out.
      await _storage.delete(key: _checkoutCooldownUntilKey);
      await _storage.delete(key: _checkoutCooldownSourceKey);
      await _storage.delete(key: _checkoutCooldownServerOffsetKey);
      _checkoutAllowedAtFromServer = null;
      if (_isSameDate(checkInAt, DateTime.now()) && mounted) {
        setState(() {
          _lastSuccessfulCheckInAt = checkInAt;
        });
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _lastSuccessfulCheckInAt = checkInAt;
      _checkoutAllowedAtFromServer = allowedAt;
    });
    _startCheckoutCooldownTicker();
  }

  void _startCheckoutCooldownTicker() {
    _checkoutCooldownTimer?.cancel();
    if (!_isCheckoutCooldownActive) return;
    _checkoutCooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!_isCheckoutCooldownActive) {
        _checkoutCooldownTimer?.cancel();
        _checkoutCooldownTimer = null;
        // Cooldown timer expired: clear storage but keep _lastSuccessfulCheckInAt
        // so the next scan correctly sends check_out instead of check_in.
        _storage.delete(key: _checkoutCooldownUntilKey);
        _storage.delete(key: _checkoutCooldownSourceKey);
        _storage.delete(key: _checkoutCooldownServerOffsetKey);
        _checkoutAllowedAtFromServer = null;
        if (mounted) {
          setState(() {});
        }
        return;
      }
      setState(() {});
    });
  }

  Future<void> _showCheckoutCooldownPopup() async {
    final allowedAt = _checkoutAllowedAt;
    if (!mounted || allowedAt == null || !_isCheckoutCooldownActive) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        title: const Text(
          'Checkout Available Later',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.primaryMaroon,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.primaryMaroon.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.hourglass_top_rounded,
                color: AppColors.primaryMaroon,
                size: 34,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primaryMaroon.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text(
                    'Time Remaining',
                    style: TextStyle(
                      color: AppColors.primaryMaroon,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _checkoutCooldownRemainingLabel,
                    style: const TextStyle(
                      color: AppColors.primaryMaroon,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: _checkoutCooldownProgress,
                      minHeight: 8,
                      backgroundColor: AppColors.primaryMaroon.withValues(
                        alpha: 0.12,
                      ),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primaryMaroon,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Checkout can be marked after ${_formatTimeLabel(allowedAt)}.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.primaryMaroon,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryMaroon,
                foregroundColor: Colors.white,
              ),
              child: const Text('OK'),
            ),
          ),
        ],
      ),
    );
  }

  String _formatHoursLabel(double hours) {
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

  Future<void> _generateAttendanceQr() async {
    if (_isGenerating) return;

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
        permanent: widget.canSetAttendanceLocation,
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
        if (seasonStart != null && seasonEnd != null) {
          _calendarFocusDate = _clampMonthToSeason(_calendarFocusDate);
          _selectedDate = _clampDateToSeason(_selectedDate);
          _byUserFocusMonth = _clampMonthToSeason(_byUserFocusMonth);
        }
      });
      _syncScannerLifecycle();
      if (seasonStart != null && seasonEnd != null) {
        _loadMyAttendance();
        if (widget.canViewByUserAttendance) {
          _loadAttendanceByUser();
        }
      }
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

  Future<void> _markAttendance(String qrData) async {
    if (_isMarking || _hasMarkedFromCurrentScan) {
      return;
    }
    if (!_isWithinConfiguredSeason) {
      _pauseAllScanners();
      _showSnack(_seasonUnavailableMessage);
      return;
    }

    final now = DateTime.now();
    final checkInToday = _todayAtConfiguredTime(_configuredCheckInTime);
    final checkOutToday = _todayAtConfiguredTime(_configuredCheckOutTime);
    var hadMissedCheckoutFromPreviousDay = false;

    // Keep local state scoped to the current day only.
    // This avoids forcing checkout because of yesterday's check-in state.
    if (_lastSuccessfulCheckInAt != null &&
        !_isSameDate(_lastSuccessfulCheckInAt!, now)) {
      hadMissedCheckoutFromPreviousDay = true;
      await _clearCheckoutCooldown();
    }

    final lastCheckInAt = _lastSuccessfulCheckInAt;
    final hasActiveCheckIn = lastCheckInAt != null;
    final checkoutModeRequestedByUser = _isCheckoutScannerUnlocked;
    final checkoutAllowedAt = _checkoutAllowedAt;
    if (checkoutAllowedAt != null && !checkoutModeRequestedByUser) {
      if (_isCheckoutCooldownActive) {
        await _showCheckoutCooldownPopup();
        return;
      }
    }

    if (_isLoadingConfiguredLocation) {
      await _showScanResultPopupAndNavigateHome(
        title: 'Attendance Not Marked',
        message: 'Loading attendance settings. Please try again shortly.',
        isSuccess: false,
      );
      return;
    }
    var isLateWindow = false;
    if (checkInToday != null) {
      final allowedBefore = _configuredAllowedBeforeMinutes;
      final allowedAfter = _configuredAllowedAfterMinutes;
      final windowStart = checkInToday.subtract(
        Duration(minutes: allowedBefore),
      );
      final lateAfter = checkInToday.add(Duration(minutes: allowedAfter));

      if (now.isBefore(windowStart)) {
        await _showScanResultPopupAndNavigateHome(
          title: 'Attendance Not Allowed Yet',
          message:
              'Attendance can be marked from ${_formatTimeLabel(windowStart)}. '
              'Early check-in is not allowed.',
          isSuccess: false,
        );
        return;
      }

      if (now.isAfter(lateAfter)) {
        isLateWindow = true;
      }
    }

    if (checkOutToday != null && now.isAfter(checkOutToday)) {
      await _showScanResultPopupAndNavigateHome(
        title: 'Attendance Window Closed',
        message: hasActiveCheckIn
            ? 'Checkout is allowed only until ${_formatTimeLabel(checkOutToday)}.'
            : 'Check-in is allowed only until ${_formatTimeLabel(checkOutToday)}.',
        isSuccess: false,
      );
      return;
    }

    setState(() {
      _isMarking = true;
      _scanInfo = null;
    });

    try {
      final current = await AttendanceService.getCurrentPosition();
      final checkoutModeRequestedByUser = _isCheckoutScannerUnlocked;
      var requestedAction = (checkoutModeRequestedByUser || hasActiveCheckIn)
          ? 'check_out'
          : 'check_in';

      if (requestedAction == 'check_out' &&
          hasActiveCheckIn &&
          !checkoutModeRequestedByUser) {
        try {
          final resolvedCheckIn = await _resolveTodayCheckInFromHistory();
          if (resolvedCheckIn == null) {
            requestedAction = 'check_in';
          } else {
            _lastSuccessfulCheckInAt = resolvedCheckIn;
          }
        } catch (_) {
          // Fall back to current local state if history cannot be loaded.
        }
      }

      if (requestedAction == 'check_out') {
        final isMaintenanceApproved =
            await _validateMaintenanceApprovalForCheckout();
        if (!isMaintenanceApproved) {
          return;
        }
      }

      Map<String, dynamic> response;
      try {
        response = await AttendanceService.markAttendance(
          qrData: qrData,
          latitude: current.latitude,
          longitude: current.longitude,
          action: requestedAction,
        );
      } catch (e) {
        final errorText = e.toString().replaceFirst('Exception: ', '');
        final normalized = errorText.toLowerCase();
        final apiError = e is AttendanceApiException ? e : null;
        final errorPayload = apiError?.data ?? const <String, dynamic>{};
        final serverAllowedAt = _parseServerDateTime(
          errorPayload['checkout_allowed_at'],
        );
        final serverNow = _parseServerDateTime(errorPayload['server_now']);
        final looksLikeAlreadyMarkedToday =
            normalized.contains('attendance already marked for today') ||
            normalized.contains('already marked for today');
        final looksLikeNoCheckIn =
            normalized.contains('check in not found') ||
            normalized.contains('check-in not found') ||
            normalized.contains('check_in not found') ||
            normalized.contains('no active check') ||
            normalized.contains('no check-in') ||
            normalized.contains('no check in');

        if (requestedAction == 'check_in' && looksLikeAlreadyMarkedToday) {
          // Backend already has today's check-in. Move UI into checkout flow.
          DateTime inferredCheckInAt;
          DateTime effectiveAllowedAt;
          var source = 'check_in';

          if (serverAllowedAt != null) {
            effectiveAllowedAt = serverAllowedAt;
            inferredCheckInAt = serverAllowedAt.subtract(
              const Duration(minutes: _checkoutCooldownMinutes),
            );
            source = 'server';
          } else {
            DateTime? checkInAt;
            try {
              checkInAt = await _resolveTodayCheckInFromHistory();
            } catch (_) {
              // Non-fatal: fallback below.
            }

            final nowTime = DateTime.now();
            final configuredCheckInToday = _todayAtConfiguredTime(
              _configuredCheckInTime,
            );
            final configuredFallback =
                configuredCheckInToday != null &&
                    nowTime.isAfter(configuredCheckInToday)
                ? configuredCheckInToday
                : null;
            inferredCheckInAt = checkInAt ?? configuredFallback ?? nowTime;
            effectiveAllowedAt = inferredCheckInAt.add(
              const Duration(minutes: _checkoutCooldownMinutes),
            );
          }

          _lastSuccessfulCheckInAt = inferredCheckInAt;
          _checkoutAllowedAtFromServer = effectiveAllowedAt;
          _serverClockOffsetSeconds = _resolveServerOffsetSeconds(serverNow);
          _isCheckoutScannerUnlocked = !_isCheckoutCooldownActive;
          _hasMarkedFromCurrentScan = false;
          _scanInfo =
              'Check-in already marked for today. Proceeding with checkout.';

          if (_isCheckoutCooldownActive) {
            await _persistCheckoutCooldown(
              checkInAt: inferredCheckInAt,
              allowedAt: effectiveAllowedAt,
              source: source,
              serverClockOffsetSeconds: _serverClockOffsetSeconds,
            );
            _startCheckoutCooldownTicker();
          }

          if (mounted) {
            setState(() {});
          }

          // Cooldown has passed. Complete checkout in the same scan attempt.
          final isMaintenanceApproved =
              await _validateMaintenanceApprovalForCheckout();
          if (!isMaintenanceApproved) {
            return;
          }

          requestedAction = 'check_out';
          response = await AttendanceService.markAttendance(
            qrData: qrData,
            latitude: current.latitude,
            longitude: current.longitude,
            action: requestedAction,
          );
        }

        if (requestedAction == 'check_out' && looksLikeNoCheckIn) {
          // Reconcile against today's history first and retry checkout once.
          // This avoids requiring a second scan when backend state is briefly stale.
          DateTime? resolvedCheckIn;
          try {
            resolvedCheckIn = await _resolveTodayCheckInFromHistory();
          } catch (_) {
            // Non-fatal: fallback path below will handle the outcome.
          }

          if (resolvedCheckIn != null) {
            _lastSuccessfulCheckInAt = resolvedCheckIn;
            response = await AttendanceService.markAttendance(
              qrData: qrData,
              latitude: current.latitude,
              longitude: current.longitude,
              action: 'check_out',
            );
          } else if (!checkoutModeRequestedByUser) {
            // Backend has no check-in record; our local state was stale.
            // Only retry as check_in if we're actually inside the valid check-in window.
            final checkInNow = _todayAtConfiguredTime(_configuredCheckInTime);
            final windowStart = checkInNow?.subtract(
              Duration(minutes: _configuredAllowedBeforeMinutes),
            );
            final insideCheckInWindow =
                windowStart == null || !DateTime.now().isBefore(windowStart);
            if (!insideCheckInWindow) {
              // Too early (or too late) to check in — clear stale state, show original error.
              await _clearCheckoutCooldown();
              rethrow;
            }
            await _clearCheckoutCooldown();
            requestedAction = 'check_in';
            response = await AttendanceService.markAttendance(
              qrData: qrData,
              latitude: current.latitude,
              longitude: current.longitude,
              action: requestedAction,
            );
          } else {
            // User explicitly requested checkout, but no check-in exists for today.
            await _clearCheckoutCooldown();
            rethrow;
          }
        } else if (requestedAction == 'check_out' &&
            (normalized.contains('30 minutes') || serverAllowedAt != null)) {
          // Backend enforced the 30-min cooldown.
          // Re-sync cooldown from backend authoritative timestamps when provided.
          final nowTime = DateTime.now();
          final effectiveAllowedAt =
              serverAllowedAt ??
              nowTime.add(
                const Duration(minutes: _checkoutCooldownMinutes - 1),
              );
          final effectiveCheckInAt = effectiveAllowedAt.subtract(
            const Duration(minutes: _checkoutCooldownMinutes),
          );

          _lastSuccessfulCheckInAt = effectiveCheckInAt;
          _checkoutAllowedAtFromServer = effectiveAllowedAt;
          _serverClockOffsetSeconds = _resolveServerOffsetSeconds(serverNow);
          _isCheckoutScannerUnlocked = false;
          _hasMarkedFromCurrentScan = false;
          _scanInfo =
              'Checkout is allowed only after 30 minutes from check-in.';

          await _persistCheckoutCooldown(
            checkInAt: effectiveCheckInAt,
            allowedAt: effectiveAllowedAt,
            source: serverAllowedAt != null ? 'server' : 'check_in',
            serverClockOffsetSeconds: _serverClockOffsetSeconds,
          );
          _startCheckoutCooldownTicker();
          if (mounted) {
            setState(() {});
          }
          return;
        } else {
          rethrow;
        }
      }

      final baseMessage =
          response['message']?.toString() ?? 'Attendance marked successfully.';
      final actionText =
          (response['attendance_action'] ??
                  response['attendance_type'] ??
                  response['action'])
              ?.toString()
              .toLowerCase() ??
          '';
      final resolvedActionText = actionText.trim().isEmpty
          ? requestedAction
          : actionText;
      final isCheckInAction =
          resolvedActionText.contains('checkin') ||
          resolvedActionText.contains('check_in') ||
          resolvedActionText == 'in';
      final isCheckoutAction =
          resolvedActionText.contains('checkout') ||
          resolvedActionText.contains('check_out') ||
          resolvedActionText == 'out';
      final statusText =
          (response['attendance_status'] ?? response['status'])
              ?.toString()
              .toLowerCase()
              .trim() ??
          '';
      final workedHours = double.tryParse(
        response['worked_hours']?.toString() ?? '',
      );

      String popupTitle;
      String successMessage;
      if (isCheckoutAction) {
        popupTitle = 'Checkout Marked!';
        _lastSuccessfulCheckOutAt = DateTime.now();
        final finalStatusLine = switch (statusText) {
          'present' || 'p' => '\nFinal status: Present.',
          'late' || 'l' => '\nFinal status: Late.',
          'absent' || 'a' => '\nFinal status: Absent.',
          _ => '',
        };
        final workedHoursLine = workedHours != null
            ? '\nWorked hours: ${_formatHoursLabel(workedHours)}.'
            : '';
        successMessage = '$baseMessage$workedHoursLine$finalStatusLine';
      } else if (isCheckInAction) {
        final isLateStatus =
            statusText == 'late' || statusText == 'l' || isLateWindow;
        final responseAllowedAt = _parseServerDateTime(
          response['checkout_allowed_at'],
        );
        final responseServerNow = _parseServerDateTime(response['server_now']);
        final checkInRecordedAt =
            responseAllowedAt?.subtract(
              const Duration(minutes: _checkoutCooldownMinutes),
            ) ??
            DateTime.now();
        final checkoutAllowedAt =
            responseAllowedAt ??
            checkInRecordedAt.add(
              const Duration(minutes: _checkoutCooldownMinutes),
            );
        popupTitle = isLateStatus
            ? 'Late Check-in Marked!'
            : 'Check-in Marked!';
        final statusLine = isLateStatus
            ? '\nStatus: Late check-in.'
            : '\nStatus: Present.';
        final checkoutLine =
            '\nCheckout can be marked after ${_formatTimeLabel(checkoutAllowedAt)} '
            '($_checkoutCooldownMinutes min cooldown).';
        final missedCheckoutNote = hadMissedCheckoutFromPreviousDay
            ? '\nNote: Previous day checkout was missed. Backend should mark that day as absent.'
            : '';
        successMessage =
            '$baseMessage$statusLine$checkoutLine$missedCheckoutNote';
        _todayCheckInSnapshotDay = _dateOnly(checkInRecordedAt);
        _todayCheckInFromHistoryAt = checkInRecordedAt;
        _serverClockOffsetSeconds = _resolveServerOffsetSeconds(
          responseServerNow,
        );
        await _persistCheckoutCooldown(
          checkInAt: checkInRecordedAt,
          allowedAt: checkoutAllowedAt,
          source: responseAllowedAt != null ? 'server' : 'check_in',
          serverClockOffsetSeconds: _serverClockOffsetSeconds,
        );
        _isCheckoutScannerUnlocked = false;
        _startCheckoutCooldownTicker();
      } else {
        popupTitle = 'Attendance Marked!';
        successMessage = baseMessage;
      }

      if (isCheckoutAction) {
        await _clearCheckoutCooldown();
      }

      setState(() {
        _hasMarkedFromCurrentScan = true;
        _scanInfo = successMessage;
      });
      _loadMyAttendance();
      await _showScanResultPopupAndNavigateHome(
        title: popupTitle,
        message: successMessage,
        isSuccess: true,
      );
    } catch (e) {
      await _showScanResultPopupAndNavigateHome(
        title: 'Attendance Failed',
        message: e.toString().replaceFirst('Exception: ', ''),
        isSuccess: false,
      );
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

  bool get _hasConfiguredSeason =>
      _configuredSeasonStartDate != null && _configuredSeasonEndDate != null;

  DateTime _clampDateToSeason(DateTime date) {
    final start = _configuredSeasonStartDate;
    final end = _configuredSeasonEndDate;
    final normalized = _dateOnly(date);
    if (start == null || end == null) return normalized;
    if (normalized.isBefore(start)) return start;
    if (normalized.isAfter(end)) return end;
    return normalized;
  }

  DateTime _clampMonthToSeason(DateTime month) {
    final start = _configuredSeasonStartDate;
    final end = _configuredSeasonEndDate;
    final normalized = DateTime(month.year, month.month, 1);
    if (start == null || end == null) return normalized;
    final seasonStartMonth = DateTime(start.year, start.month, 1);
    final seasonEndMonth = DateTime(end.year, end.month, 1);
    if (normalized.isBefore(seasonStartMonth)) return seasonStartMonth;
    if (normalized.isAfter(seasonEndMonth)) return seasonEndMonth;
    return normalized;
  }

  bool _isDateInConfiguredSeason(DateTime date) {
    final start = _configuredSeasonStartDate;
    final end = _configuredSeasonEndDate;
    if (start == null || end == null) return false;
    final normalized = _dateOnly(date);
    return !normalized.isBefore(start) && !normalized.isAfter(end);
  }

  bool _canMoveMonth(DateTime currentMonth, int monthDelta) {
    if (!_hasConfiguredSeason) return false;
    final target = DateTime(
      currentMonth.year,
      currentMonth.month + monthDelta,
      1,
    );
    return _clampMonthToSeason(target) == target;
  }

  /// Renders [data] as a QR code and returns raw PNG bytes.
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
    if (!_canMoveMonth(_calendarFocusDate, monthDelta)) return;
    final updated = _clampMonthToSeason(
      DateTime(
        _calendarFocusDate.year,
        _calendarFocusDate.month + monthDelta,
        1,
      ),
    );
    final maxSelectedDay = DateUtils.getDaysInMonth(
      updated.year,
      updated.month,
    );
    final selected = _clampDateToSeason(
      DateTime(
        updated.year,
        updated.month,
        _selectedDate.day > maxSelectedDay ? maxSelectedDay : _selectedDate.day,
      ),
    );
    setState(() {
      _calendarFocusDate = updated;
      _selectedDate = selected;
    });
    _loadMyAttendance();
  }

  DateTime? _extractAttendanceDate(Map<String, dynamic> row) {
    final dateStr =
        _firstValueFromAttendanceRow(row, const <String>[
          'date',
          'attendance_date',
          'attendance_day',
          'marked_date',
          'day',
          'created_at',
        ])?.toString() ??
        '';
    if (dateStr.trim().isEmpty) return null;
    final parsed = _parseFlexibleDateTime(dateStr);
    if (parsed == null) return null;
    return _dateOnly(parsed);
  }

  String _extractAttendanceStatus(Map<String, dynamic> row) {
    final raw =
        _firstValueFromAttendanceRow(row, const <String>[
          'status',
          'attendance_status',
          'state',
        ])?.toString().toLowerCase().trim() ??
        'present';
    if (raw == 'present' || raw == 'p') return 'present';
    if (raw == 'absent' || raw == 'a') return 'absent';
    if (raw == 'late' || raw == 'l') return 'late';
    return raw.isEmpty ? 'present' : raw;
  }

  DateTime? _parseCheckInDateTimeFromRow(Map<String, dynamic> row) {
    final now = DateTime.now();
    final date = _extractAttendanceDate(row) ?? _dateOnly(now);

    DateTime? parseDateTimeCandidate(dynamic raw) {
      final text = raw?.toString().trim() ?? '';
      if (text.isEmpty) return null;
      final dt = _parseFlexibleDateTime(text);
      if (dt != null) return dt;
      final tod = _parseTimeOfDay(text);
      if (tod == null) return null;
      return DateTime(date.year, date.month, date.day, tod.hour, tod.minute);
    }

    final candidates = <dynamic>[];
    for (final key in const <String>[
      'check_in_at',
      'checkin_at',
      'in_time',
      'check_in_time',
      'checkin_time',
      'check_in',
      'clock_in',
      'login_time',
      'created_at',
    ]) {
      candidates.add(_firstValueFromAttendanceRow(row, <String>[key]));
    }

    for (final raw in candidates) {
      final parsed = parseDateTimeCandidate(raw);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  DateTime? _parseCheckOutDateTimeFromRow(Map<String, dynamic> row) {
    final now = DateTime.now();
    final date = _extractAttendanceDate(row) ?? _dateOnly(now);

    DateTime? parseDateTimeCandidate(dynamic raw) {
      final text = raw?.toString().trim() ?? '';
      if (text.isEmpty) return null;
      final dt = _parseFlexibleDateTime(text);
      if (dt != null) return dt;
      final tod = _parseTimeOfDay(text);
      if (tod == null) return null;
      return DateTime(date.year, date.month, date.day, tod.hour, tod.minute);
    }

    final candidates = <dynamic>[];
    for (final key in const <String>[
      'check_out_at',
      'checkout_at',
      'out_time',
      'check_out_time',
      'checkout_time',
      'check_out',
      'clock_out',
      'logout_time',
      'updated_at',
    ]) {
      candidates.add(_firstValueFromAttendanceRow(row, <String>[key]));
    }

    for (final raw in candidates) {
      final parsed = parseDateTimeCandidate(raw);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  double? _parseWorkedHoursFromRow(Map<String, dynamic> row) {
    final candidates = <dynamic>[];
    for (final key in const <String>[
      'worked_hours',
      'work_hours',
      'present_hours',
      'total_hours',
      'duration_hours',
      'hours',
    ]) {
      candidates.add(_firstValueFromAttendanceRow(row, <String>[key]));
    }
    for (final raw in candidates) {
      final parsed = double.tryParse(raw?.toString() ?? '');
      if (parsed != null && parsed >= 0) {
        return parsed;
      }
    }
    return null;
  }

  DateTime _rowRecencyTime(Map<String, dynamic> row) {
    final candidates = <DateTime?>[
      _parseCheckOutDateTimeFromRow(row),
      _parseCheckInDateTimeFromRow(row),
      _parseServerDateTime(row['updated_at']),
      _parseServerDateTime(row['created_at']),
      _extractAttendanceDate(row),
    ];
    for (final dt in candidates) {
      if (dt != null) return dt;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  dynamic _firstValueFromAttendanceRow(
    Map<String, dynamic> row,
    List<String> keys,
  ) {
    for (final key in keys) {
      final direct = row[key];
      if (direct != null && direct.toString().trim().isNotEmpty) {
        return direct;
      }
    }

    for (final containerKey in const <String>[
      'data',
      'attendance',
      'record',
      'details',
    ]) {
      final nestedRaw = row[containerKey];
      if (nestedRaw is Map) {
        final nested = Map<String, dynamic>.from(nestedRaw);
        for (final key in keys) {
          final value = nested[key];
          if (value != null && value.toString().trim().isNotEmpty) {
            return value;
          }
        }
      }
    }

    return null;
  }

  DateTime? _parseFlexibleDateTime(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final direct = DateTime.tryParse(trimmed);
    if (direct != null) {
      return direct;
    }

    final normalized = trimmed.replaceAll('/', '-');
    final dateOnlyMatch = RegExp(
      r'^(\d{1,2})-(\d{1,2})-(\d{4})$',
    ).firstMatch(normalized);
    if (dateOnlyMatch != null) {
      final day = int.tryParse(dateOnlyMatch.group(1) ?? '');
      final month = int.tryParse(dateOnlyMatch.group(2) ?? '');
      final year = int.tryParse(dateOnlyMatch.group(3) ?? '');
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    final dateTimeMatch = RegExp(
      r'^(\d{1,2})-(\d{1,2})-(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?$',
    ).firstMatch(normalized);
    if (dateTimeMatch != null) {
      final day = int.tryParse(dateTimeMatch.group(1) ?? '');
      final month = int.tryParse(dateTimeMatch.group(2) ?? '');
      final year = int.tryParse(dateTimeMatch.group(3) ?? '');
      final hour = int.tryParse(dateTimeMatch.group(4) ?? '');
      final minute = int.tryParse(dateTimeMatch.group(5) ?? '');
      final second = int.tryParse(dateTimeMatch.group(6) ?? '0') ?? 0;
      if (day != null &&
          month != null &&
          year != null &&
          hour != null &&
          minute != null) {
        return DateTime(year, month, day, hour, minute, second);
      }
    }

    return null;
  }

  String _formatDurationLabel(Duration duration) {
    final totalMinutes = duration.inMinutes;
    if (totalMinutes <= 0) {
      return '0m';
    }
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours <= 0) {
      return '${minutes}m';
    }
    if (minutes == 0) {
      return '${hours}h';
    }
    return '${hours}h ${minutes}m';
  }

  Duration? _resolveDurationForDate(
    Map<String, dynamic> row,
    DateTime selectedDate,
  ) {
    final workedHours = _parseWorkedHoursFromRow(row);
    if (workedHours != null) {
      return Duration(minutes: (workedHours * 60).round());
    }

    final checkInAt = _parseCheckInDateTimeFromRow(row);
    if (checkInAt == null) return null;

    final checkOutAt = _parseCheckOutDateTimeFromRow(row);
    if (checkOutAt != null && !checkOutAt.isBefore(checkInAt)) {
      return checkOutAt.difference(checkInAt);
    }

    if (_isSameDate(selectedDate, DateTime.now())) {
      final now = DateTime.now();
      if (now.isAfter(checkInAt)) {
        return now.difference(checkInAt);
      }
    }

    return null;
  }

  Future<DateTime?> _resolveTodayCheckInFromHistory() async {
    final now = DateTime.now();
    final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final rows = await AttendanceService.fetchMyAttendance(month: month);

    DateTime? best;
    for (final row in rows) {
      final date = _extractAttendanceDate(row);
      if (date == null || !_isSameDate(date, now)) {
        continue;
      }
      final parsed = _parseCheckInDateTimeFromRow(row);
      if (parsed == null) continue;
      if (best == null || parsed.isAfter(best)) {
        best = parsed;
      }
    }
    return best;
  }

  Future<void> _loadMyAttendance() async {
    if (_isLoadingMyAttendance) return;

    setState(() {
      _calendarFocusDate = _clampMonthToSeason(_calendarFocusDate);
      _selectedDate = _clampDateToSeason(_selectedDate);
      _isLoadingMyAttendance = true;
    });

    try {
      final month =
          '${_calendarFocusDate.year}-${_calendarFocusDate.month.toString().padLeft(2, '0')}';
      final rows = await AttendanceService.fetchMyAttendance(month: month);
      final mapped = <DateTime, String>{};
      final detailed = <DateTime, Map<String, dynamic>>{};
      for (final row in rows) {
        final date = _extractAttendanceDate(row);
        if (date == null) continue;
        mapped[date] = _extractAttendanceStatus(row);

        final normalizedRow = Map<String, dynamic>.from(row);
        final existing = detailed[date];
        if (existing == null ||
            _rowRecencyTime(normalizedRow).isAfter(_rowRecencyTime(existing))) {
          detailed[date] = normalizedRow;
        }
      }
      if (!mounted) return;
      setState(() {
        _attendanceByDate
          ..clear()
          ..addAll(mapped);
        _attendanceRecordByDate
          ..clear()
          ..addAll(detailed);
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

  Future<void> _ensureTodayCheckInSnapshot({bool force = false}) async {
    if (!mounted || !_isScanTabActive) return;
    if (_isResolvingTodayCheckIn) return;

    final now = DateTime.now();
    final today = _dateOnly(now);
    if (!force &&
        _todayCheckInSnapshotDay != null &&
        _isSameDate(_todayCheckInSnapshotDay!, today) &&
        _todayCheckInFromHistoryAt != null) {
      return;
    }

    if (!force && _lastTodayCheckInLookupAt != null) {
      if (now.difference(_lastTodayCheckInLookupAt!) <
          const Duration(seconds: 12)) {
        return;
      }
    }

    _isResolvingTodayCheckIn = true;
    _lastTodayCheckInLookupAt = now;
    try {
      final resolved = await _resolveTodayCheckInFromHistory();
      if (!mounted) return;
      setState(() {
        _todayCheckInSnapshotDay = today;
        _todayCheckInFromHistoryAt = resolved;
        if (resolved != null) {
          final local = _lastSuccessfulCheckInAt;
          if (local == null || !_isSameDate(local, resolved)) {
            _lastSuccessfulCheckInAt = resolved;
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _todayCheckInSnapshotDay = today;
      });
    } finally {
      _isResolvingTodayCheckIn = false;
    }
  }

  Future<void> _loadAttendanceByUser() async {
    if (_isLoadingAttendanceByUser) return;

    setState(() {
      _byUserFocusMonth = _clampMonthToSeason(_byUserFocusMonth);
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
    if (!_canMoveMonth(_byUserFocusMonth, monthDelta)) return;
    setState(() {
      _byUserFocusMonth = _clampMonthToSeason(
        DateTime(
          _byUserFocusMonth.year,
          _byUserFocusMonth.month + monthDelta,
          1,
        ),
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

  String? _statusForDate(DateTime day) {
    final key = _dateOnly(day);
    final fromMap = _attendanceByDate[key];
    if (fromMap != null && fromMap.trim().isNotEmpty) {
      return fromMap;
    }

    final record = _attendanceRecordByDate[key];
    if (record == null) {
      return null;
    }

    final raw =
        record['status']?.toString().trim() ??
        record['attendance_status']?.toString().trim() ??
        '';
    if (raw.isEmpty) {
      return null;
    }
    return _extractAttendanceStatus(record);
  }

  Map<String, int> _monthStatusCounts(DateTime month) {
    var present = 0;
    var absent = 0;
    var late = 0;
    var other = 0;

    _attendanceByDate.forEach((date, status) {
      if (date.year != month.year || date.month != month.month) return;
      if (!_isDateInConfiguredSeason(date)) return;
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

  String _attendanceHoverDetails(DateTime day) {
    final normalizedDay = _dateOnly(day);
    final label = _selectedDateLabel(normalizedDay);
    final status = _attendanceByDate[normalizedDay];
    if (status == null || status.trim().isEmpty) {
      return '$label\nNo attendance record';
    }
    return '$label\nStatus: ${_statusLabel(status)}';
  }

  Widget _tooltipDayCell(DateTime day, Widget child) {
    return Tooltip(
      message: _attendanceHoverDetails(day),
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 3),
      preferBelow: false,
      child: child,
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
    if (_isLoadingConfiguredLocation) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_hasConfiguredSeason) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(child: _buildSeasonUnavailableCard()),
      );
    }

    final selectedKey = _dateOnly(_selectedDate);
    final selectedStatus = _statusForDate(selectedKey);
    final selectedRecord = _attendanceRecordByDate[selectedKey];
    final selectedCheckInAt = selectedRecord == null
        ? null
        : _parseCheckInDateTimeFromRow(selectedRecord);
    final selectedCheckOutAt = selectedRecord == null
        ? null
        : _parseCheckOutDateTimeFromRow(selectedRecord);
    final selectedDuration = selectedRecord == null
        ? null
        : _resolveDurationForDate(selectedRecord, _selectedDate);
    final monthCounts = _monthStatusCounts(_calendarFocusDate);
    final monthPresent = monthCounts['present'] ?? 0;
    final monthAbsent = monthCounts['absent'] ?? 0;
    final monthLate = monthCounts['late'] ?? 0;
    final monthOther = monthCounts['other'] ?? 0;
    final monthRecorded = monthPresent + monthAbsent + monthLate + monthOther;

    List<String> eventLoader(DateTime day) {
      if (!_isDateInConfiguredSeason(day)) return <String>[];
      final status = _statusForDate(day);
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
                  onPressed:
                      (_isLoadingMyAttendance ||
                          !_canMoveMonth(_calendarFocusDate, -1))
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
                  onPressed:
                      (_isLoadingMyAttendance ||
                          !_canMoveMonth(_calendarFocusDate, 1))
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
            firstDay: _configuredSeasonStartDate!,
            lastDay: _configuredSeasonEndDate!,
            focusedDay: _clampDateToSeason(_calendarFocusDate),
            calendarFormat: CalendarFormat.month,
            availableCalendarFormats: const {CalendarFormat.month: 'Month'},
            headerVisible: false,
            enabledDayPredicate: _isDateInConfiguredSeason,
            selectedDayPredicate: (day) =>
                _isDateInConfiguredSeason(day) && isSameDay(day, _selectedDate),
            eventLoader: eventLoader,
            onDaySelected: (selectedDay, focusedDay) {
              if (!_isDateInConfiguredSeason(selectedDay)) return;
              setState(() {
                _selectedDate = _dateOnly(selectedDay);
                _calendarFocusDate = _clampMonthToSeason(focusedDay);
              });
              unawaited(_loadMyAttendance());
            },
            onPageChanged: (focusedDay) {
              final normalized = _clampMonthToSeason(
                DateTime(focusedDay.year, focusedDay.month, 1),
              );
              setState(() {
                _calendarFocusDate = normalized;
                _selectedDate = _clampDateToSeason(_selectedDate);
              });
              _loadMyAttendance();
            },
            calendarStyle: const CalendarStyle(
              markerDecoration: BoxDecoration(),
              outsideDaysVisible: false,
            ),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) {
                final cell =
                    _attendanceDayCell(day, isSelected: false) ??
                    Container(
                      margin: const EdgeInsets.all(6),
                      alignment: Alignment.center,
                      child: Text(
                        '${day.day}',
                        style: const TextStyle(
                          color: AppColors.primaryMaroon,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                return _tooltipDayCell(day, cell);
              },
              selectedBuilder: (context, day, focusedDay) {
                final cell =
                    _attendanceDayCell(day, isSelected: true) ??
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
                return _tooltipDayCell(day, cell);
              },
              todayBuilder: (context, day, focusedDay) {
                final isSelected = isSameDay(day, _selectedDate);
                final cell =
                    _attendanceDayCell(day, isSelected: isSelected) ??
                    Container(
                      margin: const EdgeInsets.all(6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primaryMaroon
                            : AppColors.primaryMaroon.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primaryMaroon,
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : AppColors.primaryMaroon,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                return _tooltipDayCell(day, cell);
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
            child: (selectedStatus == null && selectedRecord == null)
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
                      if (selectedStatus != null)
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
                      if (selectedCheckInAt != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Check-in Time: ${_formatTimeLabel(selectedCheckInAt)}',
                          style: const TextStyle(
                            color: AppColors.primaryMaroon,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (selectedCheckOutAt != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Check-out Time: ${_formatTimeLabel(selectedCheckOutAt)}',
                          style: const TextStyle(
                            color: AppColors.primaryMaroon,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (selectedDuration != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          selectedCheckOutAt == null
                              ? 'Time Spent Since Check-in: ${_formatDurationLabel(selectedDuration)}'
                              : 'Time Present: ${_formatDurationLabel(selectedDuration)}',
                          style: const TextStyle(
                            color: AppColors.primaryMaroon,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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
    if (_isLoadingConfiguredLocation) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_hasConfiguredSeason) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(child: _buildSeasonUnavailableCard()),
      );
    }

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
                  onPressed:
                      (_isLoadingAttendanceByUser ||
                          !_canMoveMonth(_byUserFocusMonth, -1))
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
                  onPressed:
                      (_isLoadingAttendanceByUser ||
                          !_canMoveMonth(_byUserFocusMonth, 1))
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
          const Text(
            'QR can be generated only at the location configured by Pathak Admin, within the allowed radius.',
            style: TextStyle(
              color: AppColors.primaryMaroon,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          // --- Configured location info card ---
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
                      const SizedBox(height: 4),
                      Text(
                        'Season: $_seasonDateRangeLabel',
                        style: const TextStyle(color: AppColors.primaryMaroon),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          if (!_isLoadingConfiguredLocation && !_isWithinConfiguredSeason) ...[
            _buildSeasonUnavailableCard(),
            const SizedBox(height: 12),
          ],
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
      ),
    );
  }

  Widget _buildBlockerCard({
    required String title,
    required String message,
    IconData icon = Icons.event_busy_rounded,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primaryMaroon.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AppColors.primaryMaroon.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primaryMaroon, size: 32),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.primaryMaroon,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              color: AppColors.primaryMaroon,
              fontSize: 13,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSeasonUnavailableCard() {
    return _buildBlockerCard(
      title: 'Attendance Season Closed',
      message: _seasonUnavailableMessage,
      icon: Icons.event_busy_rounded,
    );
  }

  Widget _buildScanTab() {
    final isSecureWeb = _isSecureWebContext;

    if (_isLoadingConfiguredLocation) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isCheckingAttendanceApproval && _isCheckoutApprovalContext) {
      _pauseAllScanners();
      return const Center(child: CircularProgressIndicator());
    }

    if (!_isWithinConfiguredSeason) {
      _pauseAllScanners();
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(child: _buildSeasonUnavailableCard()),
      );
    }

    unawaited(_ensureTodayCheckInSnapshot());

    if (_isAttendanceBlocked &&
        _isCheckoutApprovalContext &&
        !_shouldBlockScannerForCheckoutCooldown) {
      _pauseAllScanners();
      final message =
          _attendanceBlockedMessage ?? _maintenanceCheckoutBlockedMessage;
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildBlockerCard(
                title: 'Check Out Not Allowed Till You Do Maintenance',
                message: message,
                icon: Icons.block_rounded,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isCheckingAttendanceApproval
                      ? null
                      : () {
                          unawaited(_ensureAttendanceApprovalGate(force: true));
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryMaroon,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: _isCheckingAttendanceApproval
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
                      : const Icon(Icons.refresh_rounded),
                  label: Text(
                    _isCheckingAttendanceApproval
                        ? 'Checking...'
                        : 'Check Again',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_hasCompletedCheckoutToday && _isCheckoutScannerUnlocked) {
      _pauseAllScanners();
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: _buildBlockerCard(
            title: 'You Have Already Marked Checkout',
            message:
                'Checkout is already completed for today. Please scan again on the next attendance day.',
            icon: Icons.verified_rounded,
          ),
        ),
      );
    }

    if (_shouldBlockScannerForCheckoutCooldown) {
      _pauseAllScanners();
      final allowedAt = _checkoutAllowedAt;
      final unlockMessage = allowedAt == null
          ? 'Checkout is not available yet.'
          : 'Checkout can be marked after ${_formatTimeLabel(allowedAt)}.';

      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primaryMaroon.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: AppColors.primaryMaroon.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.hourglass_top_rounded,
                    color: AppColors.primaryMaroon,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Checkout Not Allowed Yet',
                  style: TextStyle(
                    color: AppColors.primaryMaroon,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryMaroon.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Time Remaining',
                        style: TextStyle(
                          color: AppColors.primaryMaroon,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _checkoutCooldownRemainingLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.primaryMaroon,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: _checkoutCooldownProgress,
                          minHeight: 8,
                          backgroundColor: AppColors.primaryMaroon.withValues(
                            alpha: 0.12,
                          ),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.primaryMaroon,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  unlockMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.primaryMaroon,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'You can open checkout scanner after cooldown ends.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_shouldShowCheckoutScannerUnlockCard && !_isCheckoutScannerUnlocked) {
      _pauseAllScanners();
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primaryMaroon.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: AppColors.primaryMaroon.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: AppColors.primaryMaroon,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Checkout Ready',
                  style: TextStyle(
                    color: AppColors.primaryMaroon,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Cooldown finished. Tap the button below to open scanner and mark checkout.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.primaryMaroon,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final isApproved =
                          await _validateMaintenanceApprovalForCheckout();
                      if (!mounted || !isApproved) {
                        return;
                      }
                      setState(() {
                        _isCheckoutScannerUnlocked = true;
                        // Allow first scan attempt in checkout mode.
                        _hasMarkedFromCurrentScan = false;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryMaroon,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('Open Scanner For Checkout'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Scanner widget: custom web-native scanner on web, MobileScanner on native.
    Widget scannerWidget;
    final showScannerBracketOverlay = !(kIsWeb && !isSecureWeb);
    if (kIsWeb && !isSecureWeb) {
      _pauseAllScanners();
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
      _resumeNativeScanner();
      scannerWidget = MobileScanner(
        controller: _scannerController,
        onDetect: (capture) {
          final raw = capture.barcodes
              .map((barcode) => barcode.rawValue?.trim() ?? '')
              .firstWhere((value) => value.isNotEmpty, orElse: () => '');
          if (raw.isEmpty) return;
          _markAttendance(raw);
        },
      );
    }

    final todayCheckInAt =
        (_lastSuccessfulCheckInAt != null &&
            _isSameDate(_lastSuccessfulCheckInAt!, DateTime.now()))
        ? _lastSuccessfulCheckInAt
        : _todayCheckInFromHistoryAt;

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
        if (todayCheckInAt != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primaryMaroon.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.primaryMaroon.withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                'Check-in done on ${_selectedDateLabel(todayCheckInAt)} at ${_formatTimeLabel(todayCheckInAt)}',
                style: const TextStyle(
                  color: AppColors.primaryMaroon,
                  fontWeight: FontWeight.w600,
                ),
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
                  if (showScannerBracketOverlay)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: _buildScannerBracketOverlay(),
                      ),
                    ),
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

  Widget _buildScannerBracketOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        final frameSize = (shortestSide * 0.62).clamp(160.0, 300.0);

        return Center(
          child: SizedBox(
            width: frameSize,
            height: frameSize,
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  child: _buildScannerBracketCorner(top: true, left: true),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: _buildScannerBracketCorner(top: true, left: false),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  child: _buildScannerBracketCorner(top: false, left: true),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: _buildScannerBracketCorner(top: false, left: false),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildScannerBracketCorner({required bool top, required bool left}) {
    const bracketLength = 34.0;
    const strokeWidth = 4.0;

    return Container(
      width: bracketLength,
      height: bracketLength,
      decoration: BoxDecoration(
        border: Border(
          top: top
              ? const BorderSide(color: Colors.white, width: strokeWidth)
              : BorderSide.none,
          bottom: !top
              ? const BorderSide(color: Colors.white, width: strokeWidth)
              : BorderSide.none,
          left: left
              ? const BorderSide(color: Colors.white, width: strokeWidth)
              : BorderSide.none,
          right: !left
              ? const BorderSide(color: Colors.white, width: strokeWidth)
              : BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncScannerLifecycle();

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
      _isScanTabActive ? _buildScanTab() : const SizedBox.shrink(),
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
