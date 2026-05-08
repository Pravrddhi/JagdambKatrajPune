import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../widgets/set_pin_dialog.dart';
import '../theme/app_colors.dart';
import '../config/app_config.dart';
import '../components/app_drawer.dart';
import '../components/upcoming_events.dart';
import '../components/mirvnuk_dialog.dart';
import '../components/notification_dialog.dart';
import '../services/user_service.dart';
import '../components/emergency_contact_dialog.dart';
import '../providers/notification_provider.dart';
import '../config/api_endpoints.dart';
import '../services/fcm_service.dart';
import '../services/notification_socket_service.dart';
import '../services/maintenance_service.dart';
import '../models/maintenance_models.dart';
import '../services/api_service.dart';
import '../components/maintenance_completion_dialog.dart';
import 'attendance_module_screen.dart';
import 'dhol_maintenance_screen.dart';
import 'admin_operations_screen.dart';

const storage = FlutterSecureStorage();

class HomeScreen extends StatefulWidget {
  final String authToken;
  final String phoneNumber;
  final bool isRegistration;
  final bool? hasFcmToken;
  final Map<String, dynamic>? initialPermissions;
  final bool? initialVadak;

  const HomeScreen({
    super.key,
    required this.authToken,
    required this.phoneNumber,
    required this.isRegistration,
    this.hasFcmToken,
    this.initialPermissions,
    this.initialVadak,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  static const String _showEmergencyAfterFirstLoginKey =
      'show_emergency_after_first_login';

  Map<String, dynamic>? _userDetails; // User profile data
  bool _isLoading = false; // Loading indicator
  String? _errorMessage; // Error messages
  String accessToken = ''; // Current access token
  List<Map<String, dynamic>> _events = []; // User's upcoming events
  List<MaintenanceEvent> _maintenanceDays = <MaintenanceEvent>[];
  final Map<int, String> _completionStatusByEvent = <int, String>{};
  bool _isSubmittingHomeCompletion = false;

  bool _isFabOpen = false;
  late final AnimationController _fabAnimationController;
  late final Animation<double> _fabAnimation;

  final List<String> _motivationalSayings = const [
    'Practice with discipline today, perform with confidence tomorrow.',
    'Team rhythm is stronger than individual speed.',
    'Small daily effort builds unstoppable performance.',
    'Consistency beats intensity when repeated every day.',
    'Respect the beat, trust the team, enjoy the journey.',
  ];
  late final PageController _sayingsPageController;
  Timer? _sayingsTimer;
  Timer? _pushSetupRetryTimer;
  int _currentSayingIndex = 0;
  NotificationSocketService? _notificationSocketService;
  final FCMService _fcmService = FCMService();
  int _pushSetupRetryCount = 0;

  static const int _maxPushSetupRetries = 3;
  @override
  void initState() {
    super.initState();

    // Initialize FAB menu animations
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fabAnimation = CurvedAnimation(
      parent: _fabAnimationController,
      curve: Curves.easeInOut,
    );

    _sayingsPageController = PageController();
    _startSayingsAutoScroll();

    // Start user initialization workflow
    _initializeUser();
  }

  void _startSayingsAutoScroll() {
    _sayingsTimer?.cancel();
    _sayingsTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !_sayingsPageController.hasClients) {
        return;
      }

      final next = (_currentSayingIndex + 1) % _motivationalSayings.length;
      _sayingsPageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOut,
      );
      _currentSayingIndex = next;
    });
  }

  Future<void> _syncNotificationsFromBackend() async {
    if (!mounted) return;
    final provider = context.read<NotificationProvider>();
    await provider.fetchFromBackend(page: 1, pageSize: 20);
  }

  Future<void> _loadMaintenanceDays() async {
    try {
      final events = await MaintenanceService.fetchMaintenanceEvents();
      if (!mounted) return;

      final current = events.where((event) => event.shouldShowOnHome).toList();

      current.sort((a, b) {
        final da = DateTime.tryParse(a.eventDate);
        final db = DateTime.tryParse(b.eventDate);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });

      setState(() {
        _maintenanceDays = current;
      });
      await _loadMaintenanceCompletionStatuses();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _maintenanceDays = <MaintenanceEvent>[];
        _completionStatusByEvent.clear();
      });
    }
  }

  Future<void> _loadMaintenanceCompletionStatuses() async {
    if (_maintenanceDays.isEmpty) {
      if (!mounted) return;
      setState(() {
        _completionStatusByEvent.clear();
      });
      return;
    }

    try {
      final requests = await MaintenanceService.fetchCompletionRequests();
      final userScopedRequests = _filterCompletionRequestsForCurrentUser(
        requests,
      );
      final eventIds = _maintenanceDays.map((event) => event.id).toSet();

      final grouped = <int, Set<String>>{};
      for (final request in userScopedRequests) {
        if (!eventIds.contains(request.event)) continue;
        final status = request.status.trim().toLowerCase();
        if (status.isEmpty) continue;
        grouped.putIfAbsent(request.event, () => <String>{}).add(status);
      }

      final resolved = <int, String>{};
      for (final event in _maintenanceDays) {
        final statuses = grouped[event.id] ?? <String>{};
        if (statuses.contains('pending')) {
          resolved[event.id] = 'pending';
          continue;
        }
        if (statuses.contains('approved')) {
          resolved[event.id] = 'approved';
          continue;
        }
        if (statuses.contains('rejected')) {
          resolved[event.id] = 'rejected';
        }
      }

      if (!mounted) return;
      setState(() {
        _completionStatusByEvent
          ..clear()
          ..addAll(resolved);
      });
    } catch (_) {
      // Keep previous status snapshot when refresh fails.
    }
  }

  Future<void> _ensureMobilePushSetup() async {
    if (kIsWeb) return;

    // Request notification permission on Android 13+ after login
    await _requestNotificationPermission();

    // Keep token refresh listener active and sync the current token once
    // we have an authenticated user session.
    _fcmService.listenTokenRefresh();
    final hasToken = await _fcmService.syncCurrentTokenToServer(isLogin: false);

    if (defaultTargetPlatform == TargetPlatform.iOS && !hasToken) {
      _pushSetupRetryCount = 0;
      _scheduleIosPushRetry();
    }
  }

  void _scheduleIosPushRetry() {
    if (!mounted || _pushSetupRetryCount >= _maxPushSetupRetries) {
      return;
    }

    _pushSetupRetryTimer?.cancel();
    _pushSetupRetryTimer = Timer(const Duration(seconds: 4), () async {
      if (!mounted) return;

      _pushSetupRetryCount += 1;
      final hasToken = await _fcmService.syncCurrentTokenToServer(
        isLogin: true,
      );

      if (hasToken) {
        _pushSetupRetryTimer?.cancel();
        return;
      }

      if (mounted && _pushSetupRetryCount < _maxPushSetupRetries) {
        _scheduleIosPushRetry();
      }
    });
  }

  Future<void> _requestNotificationPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    final status = await Permission.notification.request();
    if (status.isDenied) {
      debugPrint('[Notification] Permission denied');
    } else if (status.isPermanentlyDenied) {
      debugPrint('[Notification] Permission permanently denied');
    } else if (status.isGranted) {
      debugPrint('[Notification] Permission granted');
    }
  }

  void _connectNotificationSocket(String token) {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      return;
    }

    _notificationSocketService?.dispose().ignore();
    _notificationSocketService = NotificationSocketService(
      onNotificationEvent: () {
        if (!mounted) return;
        context
            .read<NotificationProvider>()
            .fetchFromBackend(page: 1, pageSize: 20)
            .ignore();
      },
    );
    _notificationSocketService?.connect(normalized);
  }

  /// Initialize user info depending on registration status
  Future<void> _initializeUser() async {
    if (widget.isRegistration) {
      Future.delayed(const Duration(seconds: 2), () async {
        final registrationAccessToken = widget.authToken.trim();
        if (registrationAccessToken.isNotEmpty) {
          await storage.write(
            key: _showEmergencyAfterFirstLoginKey,
            value: 'false',
          );

          if (!mounted) return;
          await EmergencyContactDialog.show(
            context,
            registrationAccessToken,
            userFirstName: null,
            userLastName: null,
            userPhone: widget.phoneNumber,
          );
        }

        if (!mounted) return;
        accessToken = await showSetPinDialog(
          context,
          widget.phoneNumber,
          isResetFlow: false,
        );

        if (!mounted) return;

        if (accessToken.isNotEmpty) {
          final effectiveHomeToken = accessToken.trim().isNotEmpty
              ? accessToken.trim()
              : registrationAccessToken;
          accessToken = effectiveHomeToken;

          await storage.write(
            key: ApiEndpoints.accessTokenKey,
            value: effectiveHomeToken,
          );

          await storage.write(
            key: _showEmergencyAfterFirstLoginKey,
            value: 'false',
          );

          final loaded = await _loadUserDetails(effectiveHomeToken);
          if (!mounted || !loaded) return;
          await _ensureMobilePushSetup();
          await _syncNotificationsFromBackend();
          _connectNotificationSocket(effectiveHomeToken);
        } else {
          // PIN dialog was dismissed without a token — fall back to login.
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/login', (route) => false);
        }
      });
    } else {
      String? token = await storage.read(key: 'access_token');
      if (token != null && token.isNotEmpty) {
        accessToken = token;
        final loaded = await _loadUserDetails(accessToken);
        if (!mounted || !loaded) return;
        await _ensureMobilePushSetup();
        await _syncNotificationsFromBackend();
        _connectNotificationSocket(accessToken);
        await _showEmergencyDialogOnFirstLoginIfNeeded(accessToken);
      } else {
        final loaded = await _loadUserDetails(widget.authToken);
        if (!mounted || !loaded) return;
        await _ensureMobilePushSetup();
        await _syncNotificationsFromBackend();
        _connectNotificationSocket(widget.authToken);
        await _showEmergencyDialogOnFirstLoginIfNeeded(widget.authToken);
      }
    }
  }

  Future<void> _showEmergencyDialogOnFirstLoginIfNeeded(String token) async {
    final rawFlag = await storage.read(key: _showEmergencyAfterFirstLoginKey);
    final shouldShow = rawFlag == 'true' || rawFlag == '1';
    final emergencyName =
        _userDetails?['emergency_contact_name']?.toString().trim() ?? '';
    final emergencyPhone =
        _userDetails?['emergency_contact_phone']?.toString().trim() ?? '';
    final hasEmergencyDetails =
        emergencyName.isNotEmpty && emergencyPhone.isNotEmpty;

    // If details already exist, never keep asking on login.
    if (hasEmergencyDetails) {
      await storage.write(
        key: _showEmergencyAfterFirstLoginKey,
        value: 'false',
      );
      return;
    }

    if (!shouldShow || !mounted) {
      return;
    }

    // Avoid waiting on frame rendering here because web can dispose the
    // EngineFlutterView during teardown/navigation.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final fallbackToken = await storage.read(key: ApiEndpoints.accessTokenKey);
    final effectiveToken = token.isNotEmpty ? token : (fallbackToken ?? '');
    if (effectiveToken.isEmpty) {
      return;
    }

    if (!mounted) return;

    // Clear first to avoid repeated popups if dialog flow is interrupted.
    await storage.write(key: _showEmergencyAfterFirstLoginKey, value: 'false');
    if (!mounted) return;
    await EmergencyContactDialog.show(
      context,
      effectiveToken,
      userFirstName: _userDetails?['first_name']?.toString(),
      userLastName: _userDetails?['last_name']?.toString(),
      userPhone: widget.phoneNumber,
    );
  }

  /// Wrapper to handle loading/error state while fetching user details
  Future<bool> _loadUserDetails(String token, {bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _errorMessage = null;
      });
    }

    try {
      final userData = UserService.normalizeUserPayload(
        await UserService.fetchUserDetails(token),
      );
      final storedIsGatPramukhRaw = await storage.read(
        key: ApiEndpoints.isGatPramukhKey,
      );
      final storedGatPramukhName = await storage.read(
        key: ApiEndpoints.gatPramukhNameKey,
      );
      final storedGatId = await storage.read(key: ApiEndpoints.gatIdKey);
      final storedGatName = await storage.read(key: ApiEndpoints.gatNameKey);
      final storedJoiningYear = await storage.read(key: 'joining_year');

      final mergedUserData = Map<String, dynamic>.from(userData);

      if (mergedUserData['is_gat_pramukh'] == null &&
          storedIsGatPramukhRaw != null) {
        mergedUserData['is_gat_pramukh'] =
            storedIsGatPramukhRaw.toLowerCase() == 'true' ||
            storedIsGatPramukhRaw == '1';
      }
      if ((mergedUserData['gat_pramukh_name'] == null ||
              mergedUserData['gat_pramukh_name'].toString().trim().isEmpty) &&
          storedGatPramukhName != null &&
          storedGatPramukhName.trim().isNotEmpty) {
        mergedUserData['gat_pramukh_name'] = storedGatPramukhName.trim();
      }
      if ((mergedUserData['gat_id'] == null ||
              mergedUserData['gat_id'].toString().trim().isEmpty) &&
          storedGatId != null &&
          storedGatId.trim().isNotEmpty) {
        mergedUserData['gat_id'] = storedGatId.trim();
      }
      if ((mergedUserData['gat_name'] == null ||
              mergedUserData['gat_name'].toString().trim().isEmpty) &&
          storedGatName != null &&
          storedGatName.trim().isNotEmpty) {
        mergedUserData['gat_name'] = storedGatName.trim();
      }
      // Normalize joined year key from possible backend variants.
      mergedUserData['joining_year'] ??=
          mergedUserData['joiningYear'] ?? mergedUserData['joined_year'];
      final initialPermissions = widget.initialPermissions;
      if (mergedUserData['permissions'] == null && initialPermissions != null) {
        mergedUserData['permissions'] = Map<String, dynamic>.from(
          initialPermissions,
        );
      }
      if ((mergedUserData['joining_year'] == null ||
              mergedUserData['joining_year'].toString().trim().isEmpty) &&
          storedJoiningYear != null &&
          storedJoiningYear.trim().isNotEmpty) {
        mergedUserData['joining_year'] = storedJoiningYear.trim();
      }
      // Always OR with initialVadak: if login said vadak=true, keep it true
      // even if the profile API returns vadak=false or omits it.
      if (widget.initialVadak == true) {
        mergedUserData['vadak'] = true;
      } else {
        mergedUserData['vadak'] ??= widget.initialVadak;
      }

      if (!mounted) return false;

      final rawApprovalStatus = mergedUserData['approval_status'];
      final approvalStatus = rawApprovalStatus is int
          ? rawApprovalStatus
          : int.tryParse(rawApprovalStatus?.toString() ?? '');
      if (approvalStatus == 0) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Pending Approval !'),
            content: const Text('Please wait till admin approves the account'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );

        if (!mounted) return false;
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
        return false;
      }

      if (approvalStatus == 3) {
        final rejectionComment =
            mergedUserData['approval_comment']?.toString().trim() ?? '';
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Rejected !'),
            content: Text(
              rejectionComment.isNotEmpty
                  ? 'your account has been rejected with below comment\n\n$rejectionComment'
                  : 'your account has been rejected with below comment',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );

        if (!mounted) return false;
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
        return false;
      }

      setState(() {
        _userDetails = mergedUserData;

        if (mergedUserData['events'] != null &&
            mergedUserData['events'].isNotEmpty) {
          final list = List<Map<String, dynamic>>.from(
            mergedUserData['events'],
          );
          list.sort((a, b) {
            DateTime? parse(Map<String, dynamic> e) {
              final date = e['date']?.toString().trim() ?? '';
              final time = e['time_from']?.toString().trim() ?? '00:00';
              if (date.isEmpty) return null;
              return DateTime.tryParse('$date $time');
            }

            final da = parse(a);
            final db = parse(b);
            if (da == null && db == null) return 0;
            if (da == null) return 1;
            if (db == null) return -1;
            return db.compareTo(da); // latest first
          });
          _events = list;
        } else {
          _events = [];
        }
      });

      await _loadMaintenanceDays();

      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _errorMessage = ApiEndpoints.genericApiFailureMessage;
        _userDetails = null;
        _events = [];
        _maintenanceDays = <MaintenanceEvent>[];
      });
      return false;
    } finally {
      if (mounted && showLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshEventsSection() async {
    final storedToken = await storage.read(key: ApiEndpoints.accessTokenKey);
    final effectiveToken = (storedToken != null && storedToken.isNotEmpty)
        ? storedToken
        : accessToken.trim().isNotEmpty
        ? accessToken
        : widget.authToken;

    if (effectiveToken.trim().isEmpty) {
      return;
    }

    await _loadUserDetails(effectiveToken, showLoading: false);
    await _loadMaintenanceDays();
  }

  Future<void> _openMaintenanceCompletionFromHome(
    MaintenanceEvent event,
  ) async {
    if (!mounted) return;
    DateTime? submitLoaderStart;

    if (event.isClosedForUserAction) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'This maintenance day is closed. Completion can only be handled automatically for the current day.',
            ),
          ),
        );
      return;
    }

    try {
      final dayScopedRequests =
          await MaintenanceService.fetchCompletionRequests(eventId: event.id);
      final userScopedDayRequests = _filterCompletionRequestsForCurrentUser(
        dayScopedRequests,
      );

      final hasPendingOrApprovedCompletion = userScopedDayRequests.any((
        request,
      ) {
        final status = request.status.toLowerCase();
        return status == 'pending' || status == 'approved';
      });

      if (hasPendingOrApprovedCompletion) {
        final hasPending = userScopedDayRequests.any(
          (request) => request.status.toLowerCase() == 'pending',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                hasPending
                    ? 'Completion already submitted and pending approval for this day.'
                    : 'Completion already approved for this day.',
              ),
            ),
          );
        return;
      }

      final requests = await MaintenanceService.fetchInventoryRequests();
      final eventScopedRequests = requests.where((request) {
        if (request.maintenanceEventId != null) {
          return request.maintenanceEventId == event.id;
        }

        final linkedEventDay = request.linkedEventDay;
        final eventDay = event.parsedEventDate;
        if (linkedEventDay != null && eventDay != null) {
          return linkedEventDay == eventDay;
        }

        return false;
      }).toList();

      final userScopedStockRequests = eventScopedRequests
          .where(_isInventoryRequestOwnedByCurrentUser)
          .toList();

      final hasPendingStockRequest = userScopedStockRequests.any(
        _isPendingInventoryRequest,
      );
      if (hasPendingStockRequest) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Pending Stock Request'),
              content: const Text(
                'You have pending stock approval request(s). Submit maintenance completion only after stock approval.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
        return;
      }

      final approvedRequests = userScopedStockRequests
          .where((req) => req.normalizedStatus == 'approved')
          .toList();

      final usedItems = buildCompletionUsedItems(approvedRequests);

      if (!mounted) return;
      final submission = await showMaintenanceCompletionDialog(
        context: context,
        eventTitle: event.title,
        usedItems: usedItems,
      );

      if (submission == null) {
        return;
      }

      submitLoaderStart = DateTime.now();
      if (mounted) {
        setState(() {
          _isSubmittingHomeCompletion = true;
        });
      }

      final response = await MaintenanceService.createCompletionRequest(
        eventId: event.id,
        workNotes: submission.workNotes,
        usedItems: submission.usedItems,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              response['message']?.toString() ??
                  'Completion request submitted successfully.',
            ),
          ),
        );

      await _refreshEventsSection();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (submitLoaderStart != null) {
        final elapsedMs = DateTime.now()
            .difference(submitLoaderStart)
            .inMilliseconds;
        if (elapsedMs < 450) {
          await Future<void>.delayed(Duration(milliseconds: 450 - elapsedMs));
        }
      }
      if (mounted && _isSubmittingHomeCompletion) {
        setState(() {
          _isSubmittingHomeCompletion = false;
        });
      }
    }
  }

  Widget _buildMaintenanceDaysPanel({required bool isCompact}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.accentYellow.withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.event_note,
                color: AppColors.primaryMaroon,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Maintenance Days',
                  style: TextStyle(
                    color: AppColors.primaryMaroon,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              TextButton(
                onPressed: _refreshEventsSection,
                child: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_maintenanceDays.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'No maintenance day found.',
                style: TextStyle(color: AppColors.primaryMaroon),
              ),
            )
          else
            ..._maintenanceDays
                .take(isCompact ? 2 : 3)
                .map(
                  (item) => Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.title,
                                style: const TextStyle(
                                  color: AppColors.primaryMaroon,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Builder(
                              builder: (context) {
                                final completionStatus =
                                    _completionStatusByEvent[item.id]
                                        ?.trim()
                                        .toLowerCase();
                                if (completionStatus == null ||
                                    completionStatus.isEmpty) {
                                  return const SizedBox.shrink();
                                }

                                final isPending = completionStatus == 'pending';
                                final isApproved =
                                    completionStatus == 'approved';
                                final badgeLabel = isPending
                                    ? 'Pending'
                                    : isApproved
                                    ? 'Approved'
                                    : completionStatus == 'rejected'
                                    ? 'Rejected'
                                    : completionStatus[0].toUpperCase() +
                                          completionStatus.substring(1);
                                final badgeIcon = isApproved
                                    ? Icons.check_circle_outline
                                    : isPending
                                    ? Icons.hourglass_top
                                    : Icons.cancel_outlined;

                                final backgroundColor = isApproved
                                    ? Colors.green.withValues(alpha: 0.14)
                                    : isPending
                                    ? Colors.orange.withValues(alpha: 0.16)
                                    : Colors.red.withValues(alpha: 0.12);
                                final foregroundColor = isApproved
                                    ? Colors.green.shade700
                                    : isPending
                                    ? Colors.orange.shade800
                                    : Colors.red.shade700;

                                return Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: backgroundColor,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        badgeIcon,
                                        size: 11,
                                        color: foregroundColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        badgeLabel,
                                        style: TextStyle(
                                          color: foregroundColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Date: ${item.eventDate}',
                          style: const TextStyle(
                            color: AppColors.primaryMaroon,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Builder(
                            builder: (context) {
                              final completionStatus =
                                  _completionStatusByEvent[item.id]
                                      ?.trim()
                                      .toLowerCase();

                              if (completionStatus == 'pending') {
                                return OutlinedButton.icon(
                                  onPressed: null,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.orange,
                                  ),
                                  icon: const Icon(Icons.hourglass_top),
                                  label: const Text('Pending'),
                                );
                              }

                              if (completionStatus == 'approved') {
                                return OutlinedButton.icon(
                                  onPressed: null,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.green,
                                  ),
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text('Approved'),
                                );
                              }

                              return OutlinedButton.icon(
                                onPressed: () =>
                                    _openMaintenanceCompletionFromHome(item),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primaryMaroon,
                                ),
                                icon: const Icon(
                                  Icons.assignment_turned_in_outlined,
                                ),
                                label: const Text('Submit'),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Visible for today only. It closes automatically after the day ends.',
                          style: TextStyle(
                            color: AppColors.primaryMaroon.withValues(
                              alpha: 0.78,
                            ),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value == 1;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  Map<String, dynamic> get _permissions {
    final details = _userDetails;
    if (details == null) return <String, dynamic>{};

    final topLevel = details['permissions'];
    if (topLevel is Map<String, dynamic>) return topLevel;
    if (topLevel is Map) return Map<String, dynamic>.from(topLevel);

    final nested = details['data'];
    if (nested is Map<String, dynamic>) {
      final nestedPermissions = nested['permissions'];
      if (nestedPermissions is Map<String, dynamic>) return nestedPermissions;
      if (nestedPermissions is Map) {
        return Map<String, dynamic>.from(nestedPermissions);
      }
    }
    if (nested is Map) {
      final nestedPermissions = nested['permissions'];
      if (nestedPermissions is Map<String, dynamic>) return nestedPermissions;
      if (nestedPermissions is Map) {
        return Map<String, dynamic>.from(nestedPermissions);
      }
    }

    return <String, dynamic>{};
  }

  bool _permissionBool(String key, {bool fallback = false}) {
    final permissions = _permissions;
    if (permissions.containsKey(key)) {
      return _parseBool(permissions[key]);
    }
    return fallback;
  }

  bool _permissionIsGatOnly(String key) {
    final permissions = _permissions;
    if (!permissions.containsKey(key)) return false;
    final normalized = permissions[key]?.toString().trim().toLowerCase();
    return normalized == 'gat_only';
  }

  bool get _isPathakAdminOnly {
    return _permissionBool(
      'user_approval',
      fallback: _permissionBool(
        'attendance_settings',
        fallback: _permissionBool(
          'document_approval',
          fallback: _permissionBool(
            'manage_terms',
            fallback: _permissionBool('add_asign_gat'),
          ),
        ),
      ),
    );
  }

  bool get _isPathakAdmin {
    return _isPathakAdminOnly ||
        _permissionBool('update_maintance_stock') ||
        _permissionBool('maintance_stock_approval') ||
        _permissionBool('maintance_create_event') ||
        _permissionBool('maintance_analysis') ||
        _permissionBool('maintance_analysis_by_user') ||
        _canApproveMaintenanceCompletions;
  }

  bool get _isGatPramukh {
    final userDetails = _userDetails;
    if (userDetails == null) {
      return false;
    }

    final nested = userDetails['data'];
    return _parseBool(userDetails['is_gat_pramukh']) ||
        _parseBool(userDetails['isGatPramukh']) ||
        (nested is Map<String, dynamic> &&
            (_parseBool(nested['is_gat_pramukh']) ||
                _parseBool(nested['isGatPramukh']))) ||
        (nested is Map &&
            (_parseBool(nested['is_gat_pramukh']) ||
                _parseBool(nested['isGatPramukh'])));
  }

  int? get _currentUserGatId {
    final userDetails = _userDetails;
    final nested = userDetails?['data'];
    return int.tryParse(
      userDetails?['gat_id']?.toString() ??
          userDetails?['gatId']?.toString() ??
          (nested is Map<String, dynamic>
              ? nested['gat_id']?.toString()
              : null) ??
          (nested is Map<String, dynamic>
              ? nested['gatId']?.toString()
              : null) ??
          (nested is Map ? nested['gat_id']?.toString() : null) ??
          (nested is Map ? nested['gatId']?.toString() : null) ??
          '',
    );
  }

  int? get _currentUserId {
    final details = _userDetails;
    return int.tryParse(
      details?['id']?.toString() ??
          details?['user_id']?.toString() ??
          details?['userId']?.toString() ??
          '',
    );
  }

  String get _currentUserName {
    final details = _userDetails;
    if (details == null) return '';

    final nested = details['data'];
    final firstName =
        details['first_name']?.toString() ??
        (nested is Map<String, dynamic>
            ? nested['first_name']?.toString()
            : null) ??
        (nested is Map ? nested['first_name']?.toString() : null) ??
        '';
    final lastName =
        details['last_name']?.toString() ??
        (nested is Map<String, dynamic>
            ? nested['last_name']?.toString()
            : null) ??
        (nested is Map ? nested['last_name']?.toString() : null) ??
        '';
    final fullName = '$firstName $lastName'.trim();
    if (fullName.isNotEmpty) return fullName;

    return details['name']?.toString().trim() ??
        (nested is Map<String, dynamic>
            ? nested['name']?.toString().trim()
            : null) ??
        (nested is Map ? nested['name']?.toString().trim() : null) ??
        '';
  }

  bool _isCompletionRequestOwnedByCurrentUser(
    MaintenanceCompletionRequest request,
  ) {
    final currentUserId = _currentUserId;
    if (currentUserId != null && request.submittedBy == currentUserId) {
      return true;
    }

    final normalizedCurrentUserName = _currentUserName.trim().toLowerCase();
    final normalizedSubmittedByName = request.submittedByName
        .trim()
        .toLowerCase();
    if (normalizedCurrentUserName.isEmpty ||
        normalizedSubmittedByName.isEmpty) {
      return false;
    }

    return normalizedCurrentUserName == normalizedSubmittedByName;
  }

  List<MaintenanceCompletionRequest> _filterCompletionRequestsForCurrentUser(
    Iterable<MaintenanceCompletionRequest> requests,
  ) {
    return requests.where(_isCompletionRequestOwnedByCurrentUser).toList();
  }

  bool _isInventoryRequestOwnedByCurrentUser(InventoryRequestItem request) {
    final currentUserId = _currentUserId;
    if (currentUserId != null && request.requestedBy == currentUserId) {
      return true;
    }

    final normalizedCurrentUserName = _currentUserName.trim().toLowerCase();
    final normalizedRequestedByName = request.requestedByName
        .trim()
        .toLowerCase();
    if (normalizedCurrentUserName.isEmpty ||
        normalizedRequestedByName.isEmpty) {
      return false;
    }

    return normalizedCurrentUserName == normalizedRequestedByName;
  }

  bool _isPendingInventoryRequest(InventoryRequestItem request) {
    final normalizedStatus = request.normalizedStatus.trim().toLowerCase();
    if (normalizedStatus == 'pending' ||
        normalizedStatus.startsWith('pending') ||
        normalizedStatus.contains('pending')) {
      return true;
    }

    final rawStatus = request.status.trim().toLowerCase();
    return rawStatus == 'pending' ||
        rawStatus.startsWith('pending') ||
        rawStatus.contains('pending');
  }

  String? get _currentGatName {
    final details = _userDetails;
    if (details == null) return null;

    final nested = details['data'];
    final candidates = <dynamic>[
      details['gat_name'],
      details['gatName'],
      details['gat'],
      if (nested is Map<String, dynamic>) ...[
        nested['gat_name'],
        nested['gatName'],
        nested['gat'],
      ],
      if (nested is Map) ...[
        nested['gat_name'],
        nested['gatName'],
        nested['gat'],
      ],
    ];

    for (final candidate in candidates) {
      final value = candidate?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  String get _gatPramukhBannerText {
    final gatName = _currentGatName;
    if (gatName != null && gatName.isNotEmpty) {
      return 'You are gat pramukh of $gatName';
    }
    return 'You are gat pramukh';
  }

  bool get _canOpenMirvnukForm {
    if (_isPathakAdmin || _isGatPramukh) {
      return true;
    }
    return _permissionBool('send_notification');
  }

  bool get _canSendNotification {
    return _permissionBool(
      'send_notification',
      fallback: _isPathakAdmin || _isGatPramukh,
    );
  }

  bool get _canGenerateAttendanceQr {
    return _permissionBool(
      'generate_attendance_qr',
      fallback: _permissionBool(
        'attendance_settings',
        fallback: _isPathakAdmin,
      ),
    );
  }

  bool get _canSetAttendanceLocation {
    return _permissionBool('attendance_settings', fallback: _isPathakAdminOnly);
  }

  bool get _canViewAttendanceByUser {
    return _isPathakAdmin || _isGatPramukh;
  }

  bool get _canViewDocumentApprovals {
    return _permissionBool('document_approval', fallback: _isPathakAdmin);
  }

  bool get _canAccessAttendance {
    return _userDetails != null;
  }

  bool get _canAccessMaintenance {
    return _userDetails != null;
  }

  bool get _canManageMaintenanceInventory {
    return _permissionBool('update_maintance_stock');
  }

  bool get _canCreateMaintenanceEvents {
    return _permissionBool('maintance_create_event');
  }

  bool get _canApproveMaintenanceCompletions {
    return _permissionBool('maintenance_approval', fallback: _isGatPramukh) ||
        _permissionIsGatOnly('maintenance_approval');
  }

  bool get _canApproveMaintenanceEntries {
    return _permissionBool('maintance_stock_approval');
  }

  bool get _canViewMaintenanceAnalysis {
    return _permissionBool('maintance_analysis') ||
        _permissionBool('maintance_analysis_by_user');
  }

  bool get _isAdminFabUser {
    return _permissionBool('attendance_settings') ||
        _permissionBool('user_approval') ||
        _permissionBool('update_maintance_stock') ||
        _permissionBool('maintance_stock_approval') ||
        _permissionBool('maintance_create_event') ||
        _permissionBool('maintance_analysis') ||
        _permissionBool('maintance_analysis_by_user') ||
        _canApproveMaintenanceEntries ||
        _canApproveMaintenanceCompletions ||
        _permissionBool('document_approval') ||
        _permissionBool('manage_terms') ||
        _isPathakAdmin;
  }

  bool get _showMaintenanceFabAction {
    return !_isAdminFabUser && _canAccessMaintenance;
  }

  bool get _showAttendanceFabAction {
    return !_isAdminFabUser && _canAccessAttendance;
  }

  bool get _showMirvnukFabAction {
    return _canOpenMirvnukForm;
  }

  bool get _showSendNoticeFabAction {
    return _canSendNotification;
  }

  bool get _showCreateMaintenanceDayFabAction {
    return _isAdminFabUser && _canAccessMaintenance;
  }

  bool get _hasFabActions {
    return _showMirvnukFabAction ||
        _showSendNoticeFabAction ||
        _showCreateMaintenanceDayFabAction ||
        _showAttendanceFabAction ||
        _showMaintenanceFabAction;
  }

  bool get _isNormalAttendanceOnlyUser {
    return _showAttendanceFabAction &&
        !_canOpenMirvnukForm &&
        !_canSendNotification &&
        !_canGenerateAttendanceQr &&
        !_canSetAttendanceLocation &&
        !_canViewAttendanceByUser;
  }

  void _handleLogout() {
    Navigator.of(context).pushReplacementNamed('/login');
  }

  void _toggleFabMenu() {
    setState(() {
      _isFabOpen = !_isFabOpen;
      if (_isFabOpen) {
        _fabAnimationController.forward();
      } else {
        _fabAnimationController.reverse();
      }
    });
  }

  Future<void> _openAdminOperationsFromFab({required int initialTabIndex}) {
    final showStatusFilters = _isPathakAdmin || !_isGatPramukh;

    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminOperationsScreen(
          initialTabIndex: initialTabIndex,
          canGenerateAttendanceQr: _canGenerateAttendanceQr,
          canSetAttendanceLocation: _canSetAttendanceLocation,
          canViewAttendanceByUser: _canViewAttendanceByUser,
          isPathakAdmin: _isPathakAdmin,
          canViewDocumentApprovals: _canViewDocumentApprovals,
          canManageMaintenanceInventory: _canManageMaintenanceInventory,
          canApproveMaintenanceEntries: _canApproveMaintenanceEntries,
          canCreateMaintenanceEvents: _canCreateMaintenanceEvents,
          canApproveMaintenanceCompletions: _canApproveMaintenanceCompletions,
          canViewMaintenanceAnalysis: _canViewMaintenanceAnalysis,
          isPathakAdminApprover:
              _isPathakAdminOnly || _permissionBool('maintenance_approval'),
          approverGatId: _currentUserGatId,
          currentUserId: _currentUserId,
          currentUserName:
              '${_userDetails?['first_name'] ?? ''} ${_userDetails?['last_name'] ?? ''}'
                  .trim(),
          userInstrument: _userDetails?['instrument']?.toString(),
          canManageTerms: _permissionBool(
            'manage_terms',
            fallback: _isPathakAdminOnly,
          ),
          showUsersStatusFilters: showStatusFilters,
          canUpdateUserGroup: _permissionBool(
            'user_approval',
            fallback: _isPathakAdminOnly,
          ),
          isGatPramukh: _isGatPramukh,
          gatPramukhName:
              _userDetails?['gat_pramukh_name']?.toString() ??
              _userDetails?['gatPramukhName']?.toString(),
        ),
      ),
    );
  }

  Future<void> _openNotificationDetails(AppNotification item) async {
    if (!mounted) return;

    final provider = context.read<NotificationProvider>();
    final createdAt = item.createdAt;
    final createdAtText =
        '${createdAt.day.toString().padLeft(2, '0')}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.year} '
        '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(item.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.message,
                style: const TextStyle(color: AppColors.primaryMaroon),
              ),
              const SizedBox(height: 10),
              Text(
                'Received: $createdAtText',
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () async {
                await provider.markAsRead(item.id);
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
              },
              style: ElevatedButton.styleFrom(
                foregroundColor: AppColors.primaryMaroon,
              ),
              child: const Text('Mark as read'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNotificationsPanel() {
    return Consumer<NotificationProvider>(
      builder: (_, notificationProvider, __) {
        final notifications = notificationProvider.notifications;
        final unreadCount = notificationProvider.unreadCount;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.accentYellow.withValues(alpha: 0.6),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.notifications_active,
                    color: AppColors.primaryMaroon,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Recent Notifications',
                      style: TextStyle(
                        color: AppColors.primaryMaroon,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (unreadCount > 0)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade700,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : unreadCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (notifications.isNotEmpty)
                    TextButton(
                      onPressed: notificationProvider.clearAll,
                      child: const Text('Clear all'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: notifications.isEmpty
                    ? const Center(
                        child: Text(
                          'No notifications yet',
                          style: TextStyle(color: AppColors.primaryMaroon),
                        ),
                      )
                    : ListView.separated(
                        itemCount: notifications.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, index) {
                          final item = notifications[index];
                          return InkWell(
                            onTap: () => _openNotificationDetails(item),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: AppColors.primaryMaroon,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      InkWell(
                                        onTap: () => notificationProvider
                                            .clearNotification(item.id),
                                        borderRadius: BorderRadius.circular(12),
                                        child: const Padding(
                                          padding: EdgeInsets.all(2),
                                          child: Icon(
                                            Icons.close,
                                            size: 16,
                                            color: AppColors.primaryMaroon,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.message,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.primaryMaroon,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMotivationalSayingsPanel({required bool isCompact}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        isCompact ? 12 : 14,
        isCompact ? 12 : 14,
        isCompact ? 12 : 14,
        isCompact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white,
            AppColors.accentYellow.withValues(alpha: 0.15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.accentYellow.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                color: AppColors.primaryMaroon,
                size: isCompact ? 16 : 18,
              ),
              SizedBox(width: isCompact ? 6 : 8),
              Text(
                'Motivation Corner',
                style: TextStyle(
                  color: AppColors.primaryMaroon,
                  fontWeight: FontWeight.w700,
                  fontSize: isCompact ? 13 : 14,
                ),
              ),
            ],
          ),
          SizedBox(height: isCompact ? 8 : 10),
          Expanded(
            child: PageView.builder(
              controller: _sayingsPageController,
              scrollDirection: Axis.vertical,
              itemCount: _motivationalSayings.length,
              onPageChanged: (index) => _currentSayingIndex = index,
              itemBuilder: (_, index) {
                return Center(
                  child: Text(
                    _motivationalSayings[index],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.primaryMaroon,
                      fontSize: isCompact ? 16 : 18,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabeledFabAction({
    required String label,
    required IconData icon,
    required String heroTag,
    required bool isCompact,
    required Future<void> Function() onPressed,
  }) {
    return FadeTransition(
      opacity: _fabAnimation,
      child: ScaleTransition(
        scale: _fabAnimation,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 10 : 12,
                vertical: isCompact ? 6 : 7,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.accentYellow.withValues(alpha: 0.8),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: AppColors.primaryMaroon,
                  fontWeight: FontWeight.w700,
                  fontSize: isCompact ? 11 : 12,
                ),
              ),
            ),
            SizedBox(width: isCompact ? 6 : 8),
            FloatingActionButton(
              heroTag: heroTag,
              mini: true,
              backgroundColor: AppColors.accentYellow,
              onPressed: () {
                onPressed();
              },
              child: Icon(icon, color: AppColors.primaryMaroon),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _notificationSocketService?.dispose().ignore();
    _fabAnimationController.dispose();
    _sayingsTimer?.cancel();
    _pushSetupRetryTimer?.cancel();
    _sayingsPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 390 || size.height < 760;
    final hasScheduledMaintenanceDays = _maintenanceDays.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          AppConfig.appDisplayName,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        elevation: 0,
        backgroundColor: AppColors.primaryMaroon,
        actions: const [],
      ),
      drawer: AppDrawer(
        firstName: _userDetails?['first_name'],
        phoneNumber: _userDetails?['phone_number'],
        userDetails: _userDetails,
        onLogout: _handleLogout,
      ),
      body: Stack(
        children: [
          Positioned(
            top: isCompact ? -90 : -80,
            right: isCompact ? -50 : -30,
            child: Container(
              width: isCompact ? 180 : 220,
              height: isCompact ? 180 : 220,
              decoration: BoxDecoration(
                color: AppColors.accentYellow.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: isCompact ? -120 : -100,
            left: isCompact ? -100 : -60,
            child: Container(
              width: isCompact ? 210 : 260,
              height: isCompact ? 210 : 260,
              decoration: BoxDecoration(
                color: AppColors.primaryMaroon.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(isCompact ? 12 : 16),
            child: _errorMessage != null
                ? Center(
                    child: Text(
                      _errorMessage ?? '',
                      style: const TextStyle(color: AppColors.accentYellow),
                    ),
                  )
                : _userDetails != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            SizedBox(height: isCompact ? 6 : 8),
                            if (_isGatPramukh)
                              Padding(
                                padding: EdgeInsets.only(
                                  bottom: isCompact ? 8 : 10,
                                ),
                                child: Align(
                                  alignment: Alignment.center,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          AppColors.accentYellow.withValues(
                                            alpha: 0.3,
                                          ),
                                          Colors.white,
                                        ],
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: AppColors.accentYellow
                                            .withValues(alpha: 0.85),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.workspace_premium_outlined,
                                          size: 14,
                                          color: AppColors.primaryMaroon,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _gatPramukhBannerText,
                                          style: const TextStyle(
                                            color: AppColors.primaryMaroon,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            Expanded(
                              flex: isCompact ? 4 : 3,
                              child: _buildNotificationsPanel(),
                            ),
                            if (hasScheduledMaintenanceDays) ...[
                              SizedBox(height: isCompact ? 10 : 12),
                              _buildMaintenanceDaysPanel(isCompact: isCompact),
                            ],
                            SizedBox(height: isCompact ? 10 : 12),
                            Expanded(
                              flex: isCompact ? 5 : 6,
                              child: _events.isNotEmpty
                                  ? SingleChildScrollView(
                                      child: UpcomingEvents(
                                        events: _events,
                                        isPathakAdmin: _isPathakAdmin,
                                        onRefresh: _refreshEventsSection,
                                      ),
                                    )
                                  : _buildMotivationalSayingsPanel(
                                      isCompact: isCompact,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.accentYellow,
                    ),
                  )
                : Container(),
          ),
          if (_isSubmittingHomeCompletion)
            Positioned.fill(
              child: AbsorbPointer(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.22),
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(
                    color: AppColors.accentYellow,
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _hasFabActions
          ? (_isNormalAttendanceOnlyUser && !_canAccessMaintenance
                ? FloatingActionButton(
                    heroTag: 'attendance_scan_direct',
                    backgroundColor: AppColors.accentYellow,
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AttendanceModuleScreen(
                            canGenerateQr: _canGenerateAttendanceQr,
                            canSetAttendanceLocation: _canSetAttendanceLocation,
                            canViewByUserAttendance: _canViewAttendanceByUser,
                            scanOnly: true,
                          ),
                        ),
                      );
                    },
                    child: const Icon(
                      Icons.qr_code_scanner,
                      color: AppColors.primaryMaroon,
                    ),
                  )
                : SizedBox(
                    width: isCompact ? 220 : 240,
                    height: isCompact ? 330 : 360,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        if (_showMaintenanceFabAction)
                          Positioned(
                            bottom: isCompact ? 262 : 286,
                            right: 0,
                            child: IgnorePointer(
                              ignoring: !_isFabOpen,
                              child: _buildLabeledFabAction(
                                label: 'Dhol Maintenance',
                                icon: Icons.build,
                                heroTag: 'dhol_maintenance_module',
                                isCompact: isCompact,
                                onPressed: () async {
                                  _toggleFabMenu();
                                  if (_isAdminFabUser) {
                                    await _openAdminOperationsFromFab(
                                      initialTabIndex: 3,
                                    );
                                    return;
                                  }
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => DholMaintenanceScreen(
                                        // Home maintenance shortcut is always user-mode.
                                        // Admin actions are available in Admin Operations.
                                        canManageInventory: false,
                                        canApproveEntries: false,
                                        canCreateMaintenanceEvents: false,
                                        canApproveCompletionRequests: false,
                                        isPathakAdminApprover: false,
                                        approverGatId: _currentUserGatId,
                                        currentUserId: _currentUserId,
                                        currentUserName:
                                            '${_userDetails?['first_name'] ?? ''} ${_userDetails?['last_name'] ?? ''}'
                                                .trim(),
                                        userInstrument:
                                            _userDetails?['instrument']
                                                ?.toString(),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        if (_showAttendanceFabAction)
                          Positioned(
                            bottom: isCompact ? 196 : 222,
                            right: 0,
                            child: IgnorePointer(
                              ignoring: !_isFabOpen,
                              child: _buildLabeledFabAction(
                                label: 'Attendance',
                                icon: Icons.qr_code_scanner,
                                heroTag: 'attendance_module',
                                isCompact: isCompact,
                                onPressed: () async {
                                  _toggleFabMenu();
                                  if (_isAdminFabUser) {
                                    await _openAdminOperationsFromFab(
                                      initialTabIndex: 0,
                                    );
                                    return;
                                  }
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => AttendanceModuleScreen(
                                        canGenerateQr: _canGenerateAttendanceQr,
                                        canSetAttendanceLocation:
                                            _canSetAttendanceLocation,
                                        canViewByUserAttendance:
                                            _canViewAttendanceByUser,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        if (_showMirvnukFabAction)
                          Positioned(
                            bottom: isCompact ? 130 : 148,
                            right: 0,
                            child: IgnorePointer(
                              ignoring: !_isFabOpen,
                              child: _buildLabeledFabAction(
                                label: 'Add Mirvnuk',
                                icon: Icons.event,
                                heroTag: 'add_mirvnuk',
                                isCompact: isCompact,
                                onPressed: () async {
                                  _toggleFabMenu();
                                  await MirvnukForm.open(context);
                                  String? token = await storage.read(
                                    key: 'access_token',
                                  );
                                  if (token != null && token.isNotEmpty) {
                                    _loadUserDetails(token);
                                  }
                                },
                              ),
                            ),
                          ),
                        if (_showCreateMaintenanceDayFabAction)
                          Positioned(
                            bottom: isCompact ? 196 : 222,
                            right: 0,
                            child: IgnorePointer(
                              ignoring: !_isFabOpen,
                              child: _buildLabeledFabAction(
                                label: 'Create Maintenance Day',
                                icon: Icons.event_available,
                                heroTag: 'create_maintenance_day_home',
                                isCompact: isCompact,
                                onPressed: () async {
                                  _toggleFabMenu();
                                  if (_isAdminFabUser) {
                                    await _openAdminOperationsFromFab(
                                      initialTabIndex: 3,
                                    );
                                    await _refreshEventsSection();
                                    return;
                                  }
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => DholMaintenanceScreen(
                                        // Home maintenance shortcut is always user-mode.
                                        // Admin actions are available in Admin Operations.
                                        canManageInventory: false,
                                        canApproveEntries: false,
                                        canCreateMaintenanceEvents: false,
                                        canApproveCompletionRequests: false,
                                        isPathakAdminApprover: false,
                                        approverGatId: _currentUserGatId,
                                        currentUserId: _currentUserId,
                                        currentUserName:
                                            '${_userDetails?['first_name'] ?? ''} ${_userDetails?['last_name'] ?? ''}'
                                                .trim(),
                                        userInstrument:
                                            _userDetails?['instrument']
                                                ?.toString(),
                                        openCreateMaintenanceDayOnStart: false,
                                      ),
                                    ),
                                  );
                                  await _refreshEventsSection();
                                },
                              ),
                            ),
                          ),
                        if (_showSendNoticeFabAction)
                          Positioned(
                            bottom: isCompact ? 64 : 74,
                            right: 0,
                            child: IgnorePointer(
                              ignoring: !_isFabOpen,
                              child: _buildLabeledFabAction(
                                label: 'Send Notice',
                                icon: Icons.notifications,
                                heroTag: 'add_notification',
                                isCompact: isCompact,
                                onPressed: () async {
                                  _toggleFabMenu();
                                  int? targetGatId = _isGatPramukh
                                      ? _currentUserGatId
                                      : null;
                                  String? targetGatName = _isGatPramukh
                                      ? _currentGatName
                                      : null;

                                  // Gat pramukh must always send to their gat.
                                  // If the gat info is not yet in user details
                                  // (e.g. after a previous session), fetch it.
                                  if (_isGatPramukh && targetGatId == null) {
                                    try {
                                      final gatData =
                                          await ApiService.fetchMyGat();
                                      final id = int.tryParse(
                                        gatData['id']?.toString() ??
                                            gatData['gat_id']?.toString() ??
                                            '',
                                      );
                                      final name =
                                          gatData['name']?.toString() ??
                                          gatData['gat_name']?.toString();
                                      if (id != null) {
                                        targetGatId = id;
                                        targetGatName = name;
                                        // Cache so subsequent opens work too.
                                        if (mounted) {
                                          setState(() {
                                            _userDetails?['gat_id'] = id
                                                .toString();
                                            if (name != null) {
                                              _userDetails?['gat_name'] = name;
                                            }
                                          });
                                        }
                                      }
                                    } catch (_) {
                                      // ignore — will show the error below
                                    }
                                    if (targetGatId == null && mounted) {
                                      // ignore: use_build_context_synchronously
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Could not load your gat info. Please try again.',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                  }

                                  if (!mounted) return;
                                  // ignore: use_build_context_synchronously
                                  await NotificationForm.open(
                                    context,
                                    targetGatId: targetGatId,
                                    targetGatName: targetGatName,
                                  );
                                },
                              ),
                            ),
                          ),
                        FloatingActionButton(
                          heroTag: 'main',
                          backgroundColor: AppColors.accentYellow,
                          onPressed: _toggleFabMenu,
                          child: AnimatedRotation(
                            turns: _isFabOpen ? 0.125 : 0,
                            duration: const Duration(milliseconds: 250),
                            child: const Icon(Icons.add),
                          ),
                        ),
                      ],
                    ),
                  ))
          : null,
    );
  }
}
