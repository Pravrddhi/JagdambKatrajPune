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
import '../navigation/app_route_observer.dart';
import '../services/fcm_service.dart';
import '../services/notification_socket_service.dart';
import '../services/maintenance_service.dart';
import '../services/attendance_service.dart';
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

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver, RouteAware {
  static const String _showEmergencyAfterFirstLoginKey =
      'show_emergency_after_first_login';

  Map<String, dynamic>? _userDetails; // User profile data
  bool _isLoading = false; // Loading indicator
  String? _errorMessage; // Error messages
  String accessToken = ''; // Current access token
  List<Map<String, dynamic>> _events = []; // User's upcoming events
  List<MaintenanceEvent> _maintenanceDays = <MaintenanceEvent>[];
  final Map<int, String> _completionStatusByEvent = <int, String>{};
  List<PathakInstrumentMaintenance> _activeInstrumentMaintenances =
      <PathakInstrumentMaintenance>[];
  bool _isLoadingActiveInstrumentMaintenances = false;
  String? _activeInstrumentMaintenanceErrorMessage;
  bool _isStartMaintenanceEligible = false;
  bool _isEvaluatingStartMaintenanceEligibility = false;
  bool _hasPendingStartMaintenanceEligibilityRefresh = false;
  String? _startMaintenanceIneligibilityReason;
  bool _isSubmittingHomeCompletion = false;

  bool _isFabOpen = false;
  late final AnimationController _fabAnimationController;
  late final Animation<double> _fabAnimation;

  List<Map<String, dynamic>> _homeScreenSlides = <Map<String, dynamic>>[];
  late final PageController _homePhotosPageController;
  Timer? _homePhotosTimer;
  Timer? _maintenanceDaysRefreshTimer;
  bool _isLoadingHomePhotos = false;
  Timer? _pushSetupRetryTimer;
  int _currentHomePhotoIndex = 0;
  NotificationSocketService? _notificationSocketService;
  final FCMService _fcmService = FCMService();
  int _pushSetupRetryCount = 0;
  ModalRoute<dynamic>? _subscribedRoute;

  // Backward-compatibility shims for hot-reload sessions that may still
  // reference older motivation field names.
  // ignore: unused_element
  PageController get _sayingsPageController => _homePhotosPageController;
  // ignore: unused_element
  Timer? get _sayingsTimer => _homePhotosTimer;
  // ignore: unused_element
  int get _currentSayingIndex => _currentHomePhotoIndex;
  // ignore: unused_element
  set _currentSayingIndex(int value) {
    _currentHomePhotoIndex = value;
  }

  // ignore: unused_element
  void _startSayingsAutoScroll() => _startHomePhotosAutoScroll();
  // ignore: unused_element
  Widget _buildMotivationalSayingsPanel({required bool isCompact}) =>
      _buildHomePhotosPanel(isCompact: isCompact);

  static const int _maxPushSetupRetries = 3;
  static const Duration _maintenanceDaysRefreshInterval = Duration(seconds: 30);
  bool _isRefreshingMaintenanceDays = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize FAB menu animations
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fabAnimation = CurvedAnimation(
      parent: _fabAnimationController,
      curve: Curves.easeInOut,
    );

    _homePhotosPageController = PageController();
    _startHomePhotosAutoScroll();
    _startMaintenanceDaysAutoRefresh();

    // Start user initialization workflow
    _initializeUser();
  }

  void _startMaintenanceDaysAutoRefresh() {
    _maintenanceDaysRefreshTimer?.cancel();
    _maintenanceDaysRefreshTimer = Timer.periodic(
      _maintenanceDaysRefreshInterval,
      (_) {
        unawaited(_refreshMaintenanceDaysSilently());
      },
    );
  }

  Future<void> _refreshMaintenanceDaysSilently() async {
    if (!mounted || _isRefreshingMaintenanceDays) return;

    final storedToken = await storage.read(key: ApiEndpoints.accessTokenKey);
    final effectiveToken = (storedToken != null && storedToken.isNotEmpty)
        ? storedToken
        : accessToken.trim().isNotEmpty
        ? accessToken
        : widget.authToken;

    if (effectiveToken.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _maintenanceDays = <MaintenanceEvent>[];
          _completionStatusByEvent.clear();
          _activeInstrumentMaintenances = <PathakInstrumentMaintenance>[];
          _activeInstrumentMaintenanceErrorMessage = null;
        });
      }
      return;
    }

    _isRefreshingMaintenanceDays = true;
    try {
      await Future.wait<void>([
        _loadMaintenanceDays(),
        _loadActiveInstrumentMaintenances(),
      ]);
    } finally {
      _isRefreshingMaintenanceDays = false;
    }
  }

  void _startHomePhotosAutoScroll() {
    _homePhotosTimer?.cancel();
    _homePhotosTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_homePhotosPageController.hasClients) {
        return;
      }
      if (_homeScreenSlides.length <= 1) {
        return;
      }

      final next = (_currentHomePhotoIndex + 1) % _homeScreenSlides.length;
      try {
        _homePhotosPageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOut,
        );
        _currentHomePhotoIndex = next;
      } catch (_) {
        // If controller/view gets disposed during teardown on web, stop timer.
        _homePhotosTimer?.cancel();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    if (state == AppLifecycleState.resumed) {
      _startHomePhotosAutoScroll();
      _startMaintenanceDaysAutoRefresh();
      unawaited(_loadHomeScreenPhotos());
      unawaited(_refreshMaintenanceDaysSilently());
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _homePhotosTimer?.cancel();
      _maintenanceDaysRefreshTimer?.cancel();
    }
  }

  Future<void> _syncNotificationsFromBackend() async {
    if (!mounted) return;
    final provider = context.read<NotificationProvider>();
    await provider.fetchFromBackend(page: 1, pageSize: 20);
  }

  void _refreshPhotosOnHomeVisit() {
    if (!mounted) return;
    unawaited(_loadHomeScreenPhotos());
    unawaited(_refreshMaintenanceDaysSilently());
    unawaited(_refreshStartMaintenanceEligibility(forceBackendRefresh: true));
  }

  @override
  void didPush() {
    _refreshPhotosOnHomeVisit();
  }

  @override
  void didPopNext() {
    _refreshPhotosOnHomeVisit();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == null || identical(route, _subscribedRoute)) {
      return;
    }

    if (_subscribedRoute != null) {
      appRouteObserver.unsubscribe(this);
    }
    appRouteObserver.subscribe(this, route);
    _subscribedRoute = route;
  }

  String _resolvePhotoUrl(String? rawUrl) {
    final value = rawUrl?.trim() ?? '';
    if (value.isEmpty) {
      return '';
    }

    Uri configuredRoot() {
      final root = Uri.parse(ApiEndpoints.apiRootUrl);
      final host = root.host.trim().toLowerCase();
      final isLocal =
          host == 'localhost' || host == '127.0.0.1' || host == '::1';
      final hasNonStandardPort =
          root.hasPort && root.port != 80 && root.port != 443;

      if (root.scheme == 'http' && !isLocal && !hasNonStandardPort) {
        return root.replace(scheme: 'https');
      }
      return root;
    }

    String fromConfiguredRoot({required String path, String? query}) {
      final root = configuredRoot();
      final normalizedPath = path.startsWith('/') ? path : '/$path';
      final resolved = root.resolve(normalizedPath);
      if (query == null || query.isEmpty) {
        return resolved.toString();
      }
      return resolved.replace(query: query).toString();
    }

    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme) {
      return value;
    }

    if (value.startsWith('/media/')) {
      return fromConfiguredRoot(path: value);
    }

    final base = configuredRoot();
    return base.resolve(value).toString();
  }

  List<Map<String, dynamic>> _extractHomeSlides(Map<String, dynamic> payload) {
    final carousel = payload['carousel'];
    if (carousel is Map<String, dynamic>) {
      final slides = carousel['slides'];
      if (slides is List) {
        return slides
            .whereType<Map>()
            .map((e) {
              final normalized = Map<String, dynamic>.from(e);
              normalized['image_url'] = _resolvePhotoUrl(
                normalized['image_url']?.toString(),
              );
              return normalized;
            })
            .where((slide) {
              final imageUrl = slide['image_url']?.toString().trim() ?? '';
              return imageUrl.isNotEmpty;
            })
            .toList();
      }
    }

    final photos = payload['photos'];
    if (photos is List) {
      return photos
          .whereType<Map>()
          .map((e) {
            final normalized = Map<String, dynamic>.from(e);
            normalized['image_url'] = _resolvePhotoUrl(
              normalized['image_url']?.toString(),
            );
            return normalized;
          })
          .where((photo) {
            final imageUrl = photo['image_url']?.toString().trim() ?? '';
            return imageUrl.isNotEmpty;
          })
          .toList();
    }

    return <Map<String, dynamic>>[];
  }

  Future<void> _loadHomeScreenPhotos() async {
    if (_isLoadingHomePhotos) return;
    if (mounted) {
      setState(() {
        _isLoadingHomePhotos = true;
      });
    }

    try {
      final response = await ApiService.fetchHomeScreenPhotos();
      final slides = _extractHomeSlides(response);
      if (!mounted) return;
      setState(() {
        _homeScreenSlides = slides;
        if (_currentHomePhotoIndex >= _homeScreenSlides.length) {
          _currentHomePhotoIndex = 0;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _homeScreenSlides = <Map<String, dynamic>>[];
        _currentHomePhotoIndex = 0;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingHomePhotos = false;
        });
      }
    }
  }

  Future<void> _loadMaintenanceDays() async {
    try {
      final events = await MaintenanceService.fetchMaintenanceEvents();
      if (!mounted) return;

      final latestEventId = latestActiveMaintenanceEventId(events);
      final current = events
          .where((event) => latestEventId != null && event.id == latestEventId)
          .toList();

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
      unawaited(_refreshStartMaintenanceEligibility());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _maintenanceDays = <MaintenanceEvent>[];
        _completionStatusByEvent.clear();
      });
      unawaited(_refreshStartMaintenanceEligibility());
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

  Future<void> _loadActiveInstrumentMaintenances() async {
    if (mounted) {
      setState(() {
        _isLoadingActiveInstrumentMaintenances = true;
        _activeInstrumentMaintenanceErrorMessage = null;
      });
    }

    try {
      final items =
          await MaintenanceService.fetchMyActiveInstrumentMaintenances();
      if (!mounted) return;
      setState(() {
        _activeInstrumentMaintenances = items;
      });
      unawaited(_refreshStartMaintenanceEligibility());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _activeInstrumentMaintenances = <PathakInstrumentMaintenance>[];
        _activeInstrumentMaintenanceErrorMessage = e.toString();
      });
      unawaited(_refreshStartMaintenanceEligibility());
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingActiveInstrumentMaintenances = false;
        });
      }
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
      onNotificationEvent: (notificationData) {
        if (!mounted) return;
        if (notificationData != null) {
          // Live event: prepend directly — no REST call needed.
          context
              .read<NotificationProvider>()
              .prependNotification(notificationData)
              .ignore();
        } else {
          // Reconnect: fetch to catch any missed notifications.
          context
              .read<NotificationProvider>()
              .fetchFromBackend(page: 1, pageSize: 20)
              .ignore();
        }
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
      await _loadActiveInstrumentMaintenances();
      await _loadHomeScreenPhotos();

      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _errorMessage = ApiEndpoints.genericApiFailureMessage;
        _userDetails = null;
        _events = [];
        _maintenanceDays = <MaintenanceEvent>[];
        _activeInstrumentMaintenances = <PathakInstrumentMaintenance>[];
        _activeInstrumentMaintenanceErrorMessage = null;
        _homeScreenSlides = <Map<String, dynamic>>[];
        _currentHomePhotoIndex = 0;
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
    await _loadActiveInstrumentMaintenances();
  }

  Future<void> _openMaintenanceCompletionFromHome(
    MaintenanceEvent event,
  ) async {
    if (!mounted) return;
    DateTime? submitLoaderStart;

    if (!isLatestActiveMaintenanceEvent(event, _maintenanceDays)) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Message'),
          content: const Text(
            'This maintenance day is closed. It stays open until a newer maintenance day is created.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
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
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Message'),
            content: Text(
              hasPending
                  ? 'Completion already submitted and pending approval for this day.'
                  : 'Completion already approved for this day.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
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
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Success'),
          content: Text(
            response['message']?.toString() ??
                'Completion request submitted successfully.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      await _refreshEventsSection();
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Error'),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
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
                              final userMaintenanceStatusItem =
                                  _currentUserLatestMaintenanceStatusItem;

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

                              if (completionStatus == 'rejected') {
                                return OutlinedButton.icon(
                                  onPressed: () =>
                                      _openMaintenanceCompletionFromHome(item),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red.shade700,
                                  ),
                                  icon: const Icon(Icons.replay_outlined),
                                  label: const Text('Submit Maintenance'),
                                );
                              }

                              if (userMaintenanceStatusItem != null) {
                                final status =
                                    userMaintenanceStatusItem.normalizedStatus;
                                if (status == 'under_maintenance' ||
                                    status == 'in_progress' ||
                                    status == 'active' ||
                                    status == 'started') {
                                  return OutlinedButton.icon(
                                    onPressed: () =>
                                        _openSubmitInstrumentMaintenanceDialogFromHome(
                                          userMaintenanceStatusItem,
                                        ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.primaryMaroon,
                                    ),
                                    icon: const Icon(
                                      Icons.assignment_turned_in_outlined,
                                    ),
                                    label: const Text('Submit Maintenance'),
                                  );
                                }

                                if (status == 'pending_approval' ||
                                    status == 'pending' ||
                                    status == 'submitted') {
                                  return OutlinedButton.icon(
                                    onPressed: null,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.orange,
                                    ),
                                    icon: const Icon(Icons.hourglass_top),
                                    label: const Text('Pending Approval'),
                                  );
                                }

                                if (status == 'approved') {
                                  return OutlinedButton.icon(
                                    onPressed: null,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.green,
                                    ),
                                    icon: const Icon(
                                      Icons.check_circle_outline,
                                    ),
                                    label: const Text('Approved'),
                                  );
                                }

                                if (status == 'rejected') {
                                  return OutlinedButton.icon(
                                    onPressed: null,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red.shade700,
                                    ),
                                    icon: const Icon(Icons.cancel_outlined),
                                    label: const Text('Rejected'),
                                  );
                                }
                              }

                              return OutlinedButton.icon(
                                onPressed: _canStartMaintenanceFromHome
                                    ? _openStartMaintenanceDialogFromHome
                                    : null,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primaryMaroon,
                                ),
                                icon: const Icon(Icons.play_circle_outline),
                                label: const Text('Start Maintenance'),
                              );
                            },
                          ),
                        ),
                        if (_startMaintenanceIneligibilityReason != null &&
                            !_canStartMaintenanceFromHome) ...[
                          const SizedBox(height: 6),
                          Text(
                            _startMaintenanceIneligibilityReason!,
                            style: TextStyle(
                              color: AppColors.primaryMaroon.withValues(
                                alpha: 0.74,
                              ),
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (_isEvaluatingStartMaintenanceEligibility) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primaryMaroon,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Revalidating eligibility...',
                                style: TextStyle(
                                  color: AppColors.primaryMaroon.withValues(
                                    alpha: 0.74,
                                  ),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          'Visible until a newer maintenance day is created.',
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

  // ignore: unused_element
  Widget _buildActiveMaintenancePanel({required bool isCompact}) {
    final item = _priorityActiveInstrumentMaintenance;

    if (item == null) {
      if (_isLoadingActiveInstrumentMaintenances) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.accentYellow.withValues(alpha: 0.6),
            ),
          ),
          child: const Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Checking active maintenance assignments...',
                  style: TextStyle(color: AppColors.primaryMaroon),
                ),
              ),
            ],
          ),
        );
      }

      if (_activeInstrumentMaintenanceErrorMessage != null) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withValues(alpha: 0.22)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Active maintenance unavailable',
                style: TextStyle(
                  color: AppColors.primaryMaroon,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _activeInstrumentMaintenanceErrorMessage!,
                style: const TextStyle(color: AppColors.primaryMaroon),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: _loadActiveInstrumentMaintenances,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ),
            ],
          ),
        );
      }

      return const SizedBox.shrink();
    }

    final isParticipant = _isInstrumentMaintenanceParticipant(item);
    final canSubmit = _canSubmitInstrumentMaintenanceItem(item);
    final userLatestMaintenanceStatus = _currentUserLatestMaintenanceStatusItem;
    final normalizedUserStatus =
        userLatestMaintenanceStatus?.normalizedStatus ?? '';
    final isUserPendingApproval =
        normalizedUserStatus == 'pending_approval' ||
        normalizedUserStatus == 'pending' ||
        normalizedUserStatus == 'submitted';
    final isUserApproved = normalizedUserStatus == 'approved';
    final isUserRejected = normalizedUserStatus == 'rejected';
    final isUserUnderMaintenance =
        normalizedUserStatus == 'under_maintenance' ||
        normalizedUserStatus == 'in_progress' ||
        normalizedUserStatus == 'active' ||
        normalizedUserStatus == 'started';
    final hasPendingApprovalStatusForCard =
        isUserPendingApproval ||
        item.normalizedStatus == 'pending_approval' ||
        item.normalizedStatus == 'pending' ||
        item.normalizedStatus == 'submitted';

    String primaryActionLabel;
    IconData primaryActionIcon;
    bool primaryActionEnabled;
    late Future<void> Function() primaryAction;

    if (isUserPendingApproval) {
      primaryActionLabel = 'Pending Approval';
      primaryActionIcon = Icons.hourglass_top;
      primaryActionEnabled = false;
      primaryAction = () async {};
    } else if (isUserApproved) {
      primaryActionLabel = 'Approved';
      primaryActionIcon = Icons.check_circle_outline;
      primaryActionEnabled = false;
      primaryAction = () async {};
    } else if (isUserRejected) {
      primaryActionLabel = 'Rejected';
      primaryActionIcon = Icons.cancel_outlined;
      primaryActionEnabled = false;
      primaryAction = () async {};
    } else if (isUserUnderMaintenance && userLatestMaintenanceStatus != null) {
      primaryActionLabel = 'Submit Maintenance';
      primaryActionIcon = Icons.assignment_turned_in_outlined;
      primaryActionEnabled = true;
      primaryAction = () async {
        await _openMaintenanceScreenFromHome(
          maintenanceId: userLatestMaintenanceStatus.id,
          openSubmitOnStart: true,
        );
      };
    } else {
      primaryActionLabel = 'Start Maintenance';
      primaryActionIcon = Icons.play_circle_outline;
      primaryActionEnabled = _canStartMaintenanceFromHome;
      primaryAction = () async {
        await _openStartMaintenanceDialogFromHome();
      };
    }

    final isHighlighted = item.normalizedStatus == 'under_maintenance';
    final participantsText = item.participants
        .map((participant) => participant.fullName.trim())
        .where((name) => name.isNotEmpty)
        .join(', ');
    final extraCount = _activeInstrumentMaintenances.length - 1;

    return InkWell(
      onTap: () => _openMaintenanceScreenFromHome(
        maintenanceId: item.id,
        openSubmitOnStart: false,
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isHighlighted
                ? <Color>[const Color(0xFFFFF5D6), const Color(0xFFFFE4C4)]
                : <Color>[
                    Colors.white,
                    AppColors.accentYellow.withValues(alpha: 0.14),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isHighlighted
                ? const Color(0xFFC96B1A)
                : AppColors.accentYellow.withValues(alpha: 0.72),
            width: isHighlighted ? 1.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryMaroon.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isHighlighted ? Icons.priority_high : Icons.build_circle,
                    color: AppColors.primaryMaroon,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              isParticipant
                                  ? 'Active Maintenance Assigned To You'
                                  : 'Active Maintenance',
                              style: const TextStyle(
                                color: AppColors.primaryMaroon,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          if (extraCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryMaroon,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '+$extraCount more',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap to open maintenance details directly from Home.',
                        style: TextStyle(
                          color: AppColors.primaryMaroon.withValues(
                            alpha: 0.82,
                          ),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildMaintenanceInfoChip(
                  label: 'Dhol Number',
                  value: item.dholNumber.isEmpty
                      ? '-'
                      : 'Dhol #${item.dholNumber}',
                ),
                _buildMaintenanceInfoChip(
                  label: 'Status',
                  value: _instrumentMaintenanceStatusLabel(item.status),
                ),
                _buildMaintenanceInfoChip(
                  label: 'Started Time',
                  value: _formatMaintenanceStartedAt(item.startedAt),
                ),
                _buildMaintenanceInfoChip(
                  label: 'Event',
                  value: item.maintenanceEventTitle.trim().isEmpty
                      ? '-'
                      : item.maintenanceEventTitle,
                ),
                _buildMaintenanceInfoChip(
                  label: 'Event Date',
                  value: item.maintenanceEventDate.trim().isEmpty
                      ? '-'
                      : item.maintenanceEventDate,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Participants',
                    style: TextStyle(
                      color: AppColors.primaryMaroon,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    participantsText.isEmpty ? '-' : participantsText,
                    style: const TextStyle(color: AppColors.primaryMaroon),
                  ),
                ],
              ),
            ),
            if (isParticipant) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryMaroon,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  canSubmit
                      ? 'Your maintenance is still in progress. Submit it directly from this card.'
                      : 'You are a participant on this maintenance. Approval details are available from this card.',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildMaintenanceActionButton(
                  label: primaryActionLabel,
                  icon: primaryActionIcon,
                  isCompact: isCompact,
                  isEnabled: primaryActionEnabled,
                  onPressed: primaryAction,
                ),
                _buildMaintenanceActionButton(
                  label: 'View Maintenance Details',
                  icon: Icons.visibility_outlined,
                  isCompact: isCompact,
                  isEnabled: true,
                  onPressed: () =>
                      _openMaintenanceScreenFromHome(maintenanceId: item.id),
                ),
                _buildMaintenanceActionButton(
                  label: primaryActionLabel,
                  icon: primaryActionIcon,
                  isCompact: isCompact,
                  isEmphasized: true,
                  isEnabled: primaryActionEnabled,
                  onPressed: primaryAction,
                ),
                _buildMaintenanceActionButton(
                  label: 'View Approval Status',
                  icon: hasPendingApprovalStatusForCard
                      ? Icons.rule_folder_outlined
                      : Icons.fact_check_outlined,
                  isCompact: isCompact,
                  isEnabled: true,
                  onPressed: () =>
                      _openMaintenanceScreenFromHome(maintenanceId: item.id),
                ),
              ],
            ),
            if (_isEvaluatingStartMaintenanceEligibility) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primaryMaroon,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Revalidating eligibility...',
                    style: TextStyle(
                      color: AppColors.primaryMaroon.withValues(alpha: 0.74),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMaintenanceInfoChip({
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.primaryMaroon.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.primaryMaroon,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaintenanceActionButton({
    required String label,
    required IconData icon,
    required bool isCompact,
    required Future<void> Function() onPressed,
    required bool isEnabled,
    bool isEmphasized = false,
  }) {
    return ElevatedButton.icon(
      onPressed: isEnabled ? () => onPressed() : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: isEmphasized ? AppColors.primaryMaroon : Colors.white,
        foregroundColor: isEmphasized ? Colors.white : AppColors.primaryMaroon,
        disabledBackgroundColor: Colors.white,
        disabledForegroundColor: AppColors.primaryMaroon.withValues(
          alpha: 0.45,
        ),
        elevation: 0,
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 10 : 12,
          vertical: 10,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isEmphasized
                ? AppColors.primaryMaroon
                : AppColors.accentYellow.withValues(alpha: 0.7),
          ),
        ),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, textAlign: TextAlign.center),
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

  bool _isUpcomingMirvnuk(Map<String, dynamic> event) {
    final status = event['status'] is int
        ? event['status'] as int
        : int.tryParse(event['status']?.toString() ?? '0') ?? 0;

    // Canceled and completed events are not upcoming.
    if (status == 3 || status == 4) {
      return false;
    }

    final date = event['date']?.toString().trim() ?? '';
    if (date.isEmpty) {
      return true;
    }

    final eventDate = DateTime.tryParse(date);
    if (eventDate == null) {
      return true;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final normalizedEventDate = DateTime(
      eventDate.year,
      eventDate.month,
      eventDate.day,
    );

    return !normalizedEventDate.isBefore(today);
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

  bool get _canDownloadAttendanceQr {
    return _permissionBool(
      'download_attendance_qr',
      fallback: _canGenerateAttendanceQr,
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

  bool get _canManageHomeScreenPhotos {
    return _permissionBool('homescreenphotomanage');
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
        _canManageHomeScreenPhotos ||
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

  bool get _canReviewInstrumentMaintenances {
    return _canApproveMaintenanceCompletions ||
        _canApproveMaintenanceEntries ||
        _canManageMaintenanceInventory ||
        _isPathakAdminOnly;
  }

  String get _homeCurrentUserName {
    return '${_userDetails?['first_name'] ?? ''} ${_userDetails?['last_name'] ?? ''}'
        .trim();
  }

  bool _isInstrumentMaintenanceParticipant(PathakInstrumentMaintenance item) {
    final currentUserId = _currentUserId;
    if (currentUserId != null &&
        item.participants.any(
          (participant) => participant.userId == currentUserId,
        )) {
      return true;
    }

    final normalizedCurrentName = _currentUserName.trim().toLowerCase();
    if (normalizedCurrentName.isEmpty) {
      return false;
    }

    return item.participants.any(
      (participant) =>
          participant.fullName.trim().toLowerCase() == normalizedCurrentName,
    );
  }

  bool _canSubmitInstrumentMaintenanceItem(PathakInstrumentMaintenance item) {
    final normalizedStatus = item.normalizedStatus;
    return _isInstrumentMaintenanceParticipant(item) &&
        normalizedStatus != 'pending_approval' &&
        normalizedStatus != 'pending' &&
        normalizedStatus != 'submitted' &&
        normalizedStatus != 'approved' &&
        normalizedStatus != 'rejected';
  }

  bool get _hasBlockingActiveMaintenanceAssignment {
    return _activeInstrumentMaintenances.any((item) {
      if (!_isInstrumentMaintenanceParticipant(item)) {
        return false;
      }

      final normalizedStatus = item.normalizedStatus;
      return normalizedStatus == 'under_maintenance' ||
          normalizedStatus == 'pending_approval';
    });
  }

  bool _coerceBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }

  Future<(bool, bool)> _currentAttendanceState() async {
    final status = await AttendanceService.fetchMyCurrentAttendanceStatus();
    final isCheckedIn = _coerceBool(status['is_checked_in']);
    final isCheckedOut = _coerceBool(status['is_checked_out']);
    return (isCheckedIn, isCheckedOut);
  }

  bool get _canStartMaintenanceFromHome {
    return _isStartMaintenanceEligible;
  }

  Future<void> _refreshStartMaintenanceEligibility({
    bool forceBackendRefresh = false,
  }) async {
    final hasActiveMaintenanceDay = _maintenanceDays.isNotEmpty;
    final hasBlockingAssignment = _hasBlockingActiveMaintenanceAssignment;

    var eligibleByDefaults = hasActiveMaintenanceDay && !hasBlockingAssignment;
    String? reason;

    if (!hasActiveMaintenanceDay) {
      reason = 'Maintenance day is not active.';
    } else if (hasBlockingAssignment) {
      reason = 'You already have an active maintenance assigned.';
    }

    if (mounted) {
      setState(() {
        _isStartMaintenanceEligible = eligibleByDefaults;
        _startMaintenanceIneligibilityReason = reason;
      });
    }

    if (!mounted) {
      return;
    }

    if (_isEvaluatingStartMaintenanceEligibility) {
      if (forceBackendRefresh) {
        _hasPendingStartMaintenanceEligibilityRefresh = true;
      }
      return;
    }

    _isEvaluatingStartMaintenanceEligibility = true;
    try {
      final damagedFuture = MaintenanceService.fetchDamagedPathakDhols();
      final currentAttendanceStateFuture = _currentAttendanceState();
      final results = await Future.wait<dynamic>([
        damagedFuture,
        currentAttendanceStateFuture,
      ]);

      final damagedDhols = results[0] as List<PathakDhol>;
      final currentAttendanceState = results[1] as (bool, bool);
      final isCurrentUserCheckedIn = currentAttendanceState.$1;
      final isCurrentUserCheckedOut = currentAttendanceState.$2;

      if (!mounted) return;

      if (damagedDhols.isEmpty) {
        setState(() {
          _isStartMaintenanceEligible = false;
          _startMaintenanceIneligibilityReason =
              'No damaged dhol is available right now.';
        });
        return;
      }

      if (!isCurrentUserCheckedIn || isCurrentUserCheckedOut) {
        setState(() {
          _isStartMaintenanceEligible = false;
          _startMaintenanceIneligibilityReason =
              'Please check in first to start maintenance.';
        });
        return;
      }

      final isEligible =
          hasActiveMaintenanceDay &&
          !hasBlockingAssignment &&
          damagedDhols.isNotEmpty &&
          isCurrentUserCheckedIn &&
          !isCurrentUserCheckedOut;

      setState(() {
        _isStartMaintenanceEligible = isEligible;
        if (!hasActiveMaintenanceDay) {
          _startMaintenanceIneligibilityReason =
              'Maintenance day is not active.';
        } else if (hasBlockingAssignment) {
          _startMaintenanceIneligibilityReason =
              'You already have an active maintenance assigned.';
        } else if (damagedDhols.isEmpty) {
          _startMaintenanceIneligibilityReason =
              'No damaged dhol is available right now.';
        } else if (!isCurrentUserCheckedIn || isCurrentUserCheckedOut) {
          _startMaintenanceIneligibilityReason =
              'Please check in first to start maintenance.';
        } else {
          _startMaintenanceIneligibilityReason = null;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isStartMaintenanceEligible = eligibleByDefaults;
          _startMaintenanceIneligibilityReason = reason;
        });
      }
    } finally {
      _isEvaluatingStartMaintenanceEligibility = false;
      if (_hasPendingStartMaintenanceEligibilityRefresh) {
        _hasPendingStartMaintenanceEligibilityRefresh = false;
        unawaited(
          _refreshStartMaintenanceEligibility(forceBackendRefresh: true),
        );
      }
    }
  }

  PathakInstrumentMaintenance? get _currentUserLatestMaintenanceStatusItem {
    final items = _activeInstrumentMaintenances.where((item) {
      if (!_isInstrumentMaintenanceParticipant(item)) {
        return false;
      }

      final status = item.normalizedStatus;
      return status == 'under_maintenance' ||
          status == 'in_progress' ||
          status == 'active' ||
          status == 'started' ||
          status == 'pending_approval' ||
          status == 'pending' ||
          status == 'submitted' ||
          status == 'approved' ||
          status == 'rejected';
    }).toList();

    if (items.isEmpty) {
      return null;
    }

    int statusPriority(PathakInstrumentMaintenance item) {
      switch (item.normalizedStatus) {
        case 'under_maintenance':
        case 'in_progress':
        case 'active':
        case 'started':
          return 0;
        case 'pending_approval':
        case 'pending':
        case 'submitted':
          return 1;
        case 'approved':
          return 2;
        case 'rejected':
          return 3;
        default:
          return 4;
      }
    }

    items.sort((a, b) {
      final priorityDelta = statusPriority(a) - statusPriority(b);
      if (priorityDelta != 0) {
        return priorityDelta;
      }

      final startedAtA = _tryParseMaintenanceDate(a.startedAt);
      final startedAtB = _tryParseMaintenanceDate(b.startedAt);
      if (startedAtA == null && startedAtB == null) {
        return b.id.compareTo(a.id);
      }
      if (startedAtA == null) {
        return 1;
      }
      if (startedAtB == null) {
        return -1;
      }
      return startedAtB.compareTo(startedAtA);
    });

    return items.first;
  }

  String _instrumentMaintenanceStatusLabel(String status) {
    switch (status
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_')) {
      case 'pending_approval':
      case 'pending':
      case 'submitted':
        return 'Pending Approval';
      case 'under_maintenance':
        return 'Under Maintenance';
      case 'in_progress':
        return 'In Progress';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'active':
      case 'started':
      default:
        return 'Active';
    }
  }

  int _instrumentMaintenanceStatusPriority(PathakInstrumentMaintenance item) {
    switch (item.normalizedStatus) {
      case 'under_maintenance':
      case 'in_progress':
      case 'active':
      case 'started':
        return 0;
      case 'pending_approval':
      case 'pending':
      case 'submitted':
        return 1;
      case 'approved':
        return 2;
      case 'rejected':
        return 3;
      default:
        return 4;
    }
  }

  DateTime? _tryParseMaintenanceDate(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) return null;
    return DateTime.tryParse(trimmed);
  }

  String _formatMaintenanceStartedAt(String rawValue) {
    final parsed = _tryParseMaintenanceDate(rawValue);
    if (parsed == null) {
      return rawValue.trim().isEmpty ? '-' : rawValue;
    }

    final hour = parsed.hour == 0 ? 12 : ((parsed.hour - 1) % 12) + 1;
    final minute = parsed.minute.toString().padLeft(2, '0');
    final meridiem = parsed.hour >= 12 ? 'PM' : 'AM';
    final day = parsed.day.toString().padLeft(2, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    return '$day/$month/${parsed.year} $hour:$minute $meridiem';
  }

  // ignore: unused_element
  PathakInstrumentMaintenance? get _priorityActiveInstrumentMaintenance {
    if (_activeInstrumentMaintenances.isEmpty) {
      return null;
    }

    final items = List<PathakInstrumentMaintenance>.from(
      _activeInstrumentMaintenances,
    );
    items.sort((a, b) {
      final participantOrder =
          (_isInstrumentMaintenanceParticipant(a) ? 0 : 1) -
          (_isInstrumentMaintenanceParticipant(b) ? 0 : 1);
      if (participantOrder != 0) {
        return participantOrder;
      }

      final statusOrder =
          _instrumentMaintenanceStatusPriority(a) -
          _instrumentMaintenanceStatusPriority(b);
      if (statusOrder != 0) {
        return statusOrder;
      }

      final startedAtA = _tryParseMaintenanceDate(a.startedAt);
      final startedAtB = _tryParseMaintenanceDate(b.startedAt);
      if (startedAtA == null && startedAtB == null) {
        return b.id.compareTo(a.id);
      }
      if (startedAtA == null) {
        return 1;
      }
      if (startedAtB == null) {
        return -1;
      }
      return startedAtB.compareTo(startedAtA);
    });
    return items.first;
  }

  Future<void> _openMaintenanceScreenFromHome({
    int? maintenanceId,
    bool openSubmitOnStart = false,
    bool openStartOnStart = false,
  }) async {
    final openWithAdminCapabilities = _canReviewInstrumentMaintenances;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DholMaintenanceScreen(
          canManageInventory: openWithAdminCapabilities
              ? _canManageMaintenanceInventory
              : false,
          canApproveEntries: openWithAdminCapabilities
              ? _canApproveMaintenanceEntries
              : false,
          canCreateMaintenanceEvents: openWithAdminCapabilities
              ? _canCreateMaintenanceEvents
              : false,
          canApproveCompletionRequests: openWithAdminCapabilities
              ? _canApproveMaintenanceCompletions
              : false,
          isPathakAdminApprover: openWithAdminCapabilities
              ? _isPathakAdminOnly
              : false,
          approverGatId: _currentUserGatId,
          currentUserId: _currentUserId,
          currentUserName: _homeCurrentUserName,
          userInstrument: _userDetails?['instrument']?.toString(),
          openStartInstrumentMaintenanceOnStart: openStartOnStart,
          openInstrumentMaintenanceIdOnStart: maintenanceId,
          openSubmitForInstrumentMaintenanceOnStart: openSubmitOnStart,
        ),
      ),
    );
    await _loadActiveInstrumentMaintenances();
  }

  void _showHomeSnack(String message) {
    if (!mounted) return;
    final normalized = message.trim();
    if (normalized.isEmpty) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(normalized)));
  }

  String _normalizeStartMaintenanceErrorMessage(String rawMessage) {
    final trimmed = rawMessage.replaceFirst('Exception: ', '').trim();
    final normalized = trimmed.toLowerCase();
    if (normalized.contains('no active maintenance event found')) {
      return 'No active maintenance event available.';
    }
    if (normalized.contains('maintenance event is not active')) {
      return 'Maintenance event is no longer active.';
    }
    return trimmed;
  }

  Future<Set<int>?> _openMaintenancePartnerSelectorFromHome({
    required BuildContext parentContext,
    required Set<int> initialSelected,
    required List<CheckedInMaintenancePartner> partners,
  }) async {
    if (!parentContext.mounted) {
      return null;
    }

    final searchController = TextEditingController();

    if (kIsWeb) {
      final route = ModalRoute.of(parentContext);
      if (route != null && !route.isCurrent) {
        searchController.dispose();
        return null;
      }
    }

    final selected = await showDialog<Set<int>>(
      context: parentContext,
      useRootNavigator: false,
      builder: (dialogContext) {
        var searchQuery = '';
        final working = <int>{...initialSelected};

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filteredPartners = partners.where((partner) {
              final query = searchQuery.trim().toLowerCase();
              if (query.isEmpty) return true;
              final name = partner.fullName.toLowerCase();
              final phone = partner.phone.toLowerCase();
              return name.contains(query) || phone.contains(query);
            }).toList();

            return AlertDialog(
              title: const Text('Select Partners'),
              content: SizedBox(
                width: 520,
                height: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    TextField(
                      controller: searchController,
                      decoration: const InputDecoration(
                        labelText: 'Search by name or phone',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        setSheetState(() {
                          searchQuery = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: filteredPartners.isEmpty
                          ? const Center(
                              child: Text('No checked-in users found.'),
                            )
                          : Scrollbar(
                              child: ListView.builder(
                                itemCount: filteredPartners.length,
                                itemBuilder: (context, index) {
                                  final partner = filteredPartners[index];
                                  final isChecked = working.contains(
                                    partner.userId,
                                  );

                                  return CheckboxListTile(
                                    value: isChecked,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title: Text(partner.fullName),
                                    subtitle: Text(
                                      partner.phone.trim().isEmpty
                                          ? 'Phone unavailable'
                                          : partner.phone,
                                    ),
                                    onChanged: (value) {
                                      setSheetState(() {
                                        if (value == true) {
                                          working.add(partner.userId);
                                        } else {
                                          working.remove(partner.userId);
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(working),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: AppColors.primaryMaroon,
                  ),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    searchController.dispose();
    return selected;
  }

  Future<void> _openStartMaintenanceDialogFromHome() async {
    List<PathakDhol> damagedDhols;
    try {
      damagedDhols = await MaintenanceService.fetchDamagedPathakDhols();
    } catch (e) {
      _showHomeSnack(e.toString().replaceFirst('Exception: ', ''));
      return;
    }

    List<CheckedInMaintenancePartner> partners =
        <CheckedInMaintenancePartner>[];
    String? partnersLoadMessage;
    try {
      partners = await MaintenanceService.fetchCheckedInMaintenancePartners();
    } catch (e) {
      partnersLoadMessage = e.toString().replaceFirst('Exception: ', '');
    }

    if (!mounted) return;

    int? selectedDholId;
    final selectedPartnerIds = <int>{};
    String? successMessage;

    final started = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        var isSubmitting = false;
        String? submitErrorMessage;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Start Maintenance'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 520,
                  maxHeight: 520,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: selectedDholId,
                        decoration: const InputDecoration(
                          labelText: 'Dhol Number',
                          border: OutlineInputBorder(),
                        ),
                        items: damagedDhols
                            .map(
                              (item) => DropdownMenuItem<int>(
                                value: item.id,
                                child: Text('Dhol #${item.dholNumber}'),
                              ),
                            )
                            .toList(),
                        onChanged: isSubmitting
                            ? null
                            : (value) {
                                setDialogState(() {
                                  selectedDholId = value;
                                  submitErrorMessage = null;
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Partners (Optional)',
                          border: OutlineInputBorder(),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selectedPartnerIds.isEmpty
                                  ? 'No partners selected'
                                  : '${selectedPartnerIds.length} partner(s) selected',
                              style: const TextStyle(color: Colors.black54),
                            ),
                            if (selectedPartnerIds.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: partners
                                      .where(
                                        (partner) => selectedPartnerIds
                                            .contains(partner.userId),
                                      )
                                      .map(
                                        (partner) =>
                                            Chip(label: Text(partner.fullName)),
                                      )
                                      .toList(),
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: isSubmitting || partners.isEmpty
                                  ? null
                                  : () async {
                                      if (!dialogContext.mounted) return;
                                      final selected =
                                          await _openMaintenancePartnerSelectorFromHome(
                                            parentContext: dialogContext,
                                            initialSelected: selectedPartnerIds,
                                            partners: partners,
                                          );
                                      if (selected == null ||
                                          !dialogContext.mounted) {
                                        return;
                                      }
                                      setDialogState(() {
                                        selectedPartnerIds
                                          ..clear()
                                          ..addAll(selected);
                                      });
                                    },
                              icon: const Icon(Icons.group_add_outlined),
                              label: const Text('Select Partner'),
                            ),
                            if (partnersLoadMessage != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                partnersLoadMessage,
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (damagedDhols.isEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          'No damaged dhol is available right now.',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (submitErrorMessage != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          submitErrorMessage!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: (isSubmitting || selectedDholId == null)
                      ? null
                      : () async {
                          setDialogState(() {
                            isSubmitting = true;
                            submitErrorMessage = null;
                          });

                          try {
                            final response =
                                await MaintenanceService.startInstrumentMaintenance(
                                  instrumentId: selectedDholId!,
                                  participantUserIds: selectedPartnerIds
                                      .toList(),
                                );
                            successMessage =
                                response['message']?.toString() ??
                                'Maintenance started.';
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } catch (e) {
                            if (!dialogContext.mounted) {
                              return;
                            }
                            setDialogState(() {
                              isSubmitting = false;
                              submitErrorMessage =
                                  _normalizeStartMaintenanceErrorMessage(
                                    e.toString(),
                                  );
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: AppColors.primaryMaroon,
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Start Maintenance'),
                ),
              ],
            );
          },
        );
      },
    );

    if (started == true) {
      _showHomeSnack(successMessage ?? 'Maintenance started.');
      await _refreshMaintenanceDaysSilently();
      await _refreshStartMaintenanceEligibility(forceBackendRefresh: true);
    }
  }

  Future<String?> _validateStockRulesForHomeInstrumentSubmit({
    required PathakInstrumentMaintenance maintenance,
  }) async {
    final explicitEventId = maintenance.maintenanceEventId;
    final explicitEventDay = maintenance.linkedEventDay;
    if (explicitEventId == null && explicitEventDay == null) {
      return null;
    }

    final requests = await MaintenanceService.fetchInventoryRequests();
    final eventScopedRequests = requests.where((request) {
      if (explicitEventId != null && request.maintenanceEventId != null) {
        return request.maintenanceEventId == explicitEventId;
      }

      final linkedEventDay = request.linkedEventDay;
      if (linkedEventDay != null && explicitEventDay != null) {
        return linkedEventDay == explicitEventDay;
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
      return 'You have pending stock approval request(s). Submit maintenance only after stock approval.';
    }

    return null;
  }

  Future<void> _openSubmitInstrumentMaintenanceDialogFromHome(
    PathakInstrumentMaintenance item,
  ) async {
    PathakInstrumentMaintenance detail;
    try {
      detail = await MaintenanceService.fetchInstrumentMaintenanceDetail(
        item.id,
      );
    } catch (e) {
      _showHomeSnack(e.toString().replaceFirst('Exception: ', ''));
      return;
    }

    if (!mounted) return;

    final workPerformedController = TextEditingController(
      text: detail.workPerformed,
    );
    final remarksController = TextEditingController(text: detail.remarks);
    List<InventoryItem> homeInventory = <InventoryItem>[];
    List<InventoryRequestItem> allRequests = <InventoryRequestItem>[];

    try {
      homeInventory = await MaintenanceService.fetchInventory();
    } catch (_) {
      homeInventory = <InventoryItem>[];
    }

    try {
      allRequests = await MaintenanceService.fetchInventoryRequests();
    } catch (_) {
      allRequests = <InventoryRequestItem>[];
    }

    String? successMessage;
    int? createdCompletionRequestId;
    final resolvedDholNumber = detail.dholNumber.trim().isNotEmpty
        ? detail.dholNumber.trim()
        : item.dholNumber.trim();

    if (resolvedDholNumber.isEmpty) {
      _showHomeSnack(
        'Unable to load Dhol Number for this maintenance. Please refresh and try again.',
      );
      workPerformedController.dispose();
      remarksController.dispose();
      return;
    }

    final participantsText = detail.participants
        .map((participant) => participant.fullName.trim())
        .where((name) => name.isNotEmpty)
        .join(', ');

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        var isSubmitting = false;
        var canSubmit = workPerformedController.text.trim().isNotEmpty;
        String? submitErrorMessage;

        List<InventoryRequestItem> eventScopedUserStockRequests() {
          final scopedByUser = allRequests
              .where(_isInventoryRequestOwnedByCurrentUser)
              .toList();
          final explicitEventId = detail.maintenanceEventId;
          final explicitEventDay = detail.linkedEventDay;
          if (explicitEventId == null && explicitEventDay == null) {
            return scopedByUser;
          }

          return scopedByUser.where((request) {
            if (explicitEventId != null && request.maintenanceEventId != null) {
              return request.maintenanceEventId == explicitEventId;
            }

            final linkedEventDay = request.linkedEventDay;
            if (linkedEventDay != null && explicitEventDay != null) {
              return linkedEventDay == explicitEventDay;
            }

            return false;
          }).toList();
        }

        List<CompletionUsedItemPreview> stockUsedPreviews() {
          final approvedRequests = eventScopedUserStockRequests()
              .where(
                (request) =>
                    request.normalizedStatus.trim().toLowerCase() == 'approved',
              )
              .toList();
          return buildCompletionUsedItems(approvedRequests);
        }

        String? stockAvailabilityValidationMessage(
          List<CompletionUsedItemPreview> usedItems,
        ) {
          for (final usedItem in usedItems) {
            final inventoryMatch = homeInventory
                .where((inv) => inv.id == usedItem.inventoryItemId)
                .toList();
            if (inventoryMatch.isEmpty) {
              final itemName = usedItem.inventoryItemName.trim().isNotEmpty
                  ? usedItem.inventoryItemName.trim()
                  : 'Item #${usedItem.inventoryItemId}';
              return 'Stock item "$itemName" is not available in inventory.';
            }

            final inventoryItem = inventoryMatch.first;
            if (usedItem.quantityUsed > inventoryItem.quantityAvailable) {
              final itemName = usedItem.inventoryItemName.trim().isNotEmpty
                  ? usedItem.inventoryItemName.trim()
                  : inventoryItem.name;
              return 'Insufficient stock for "$itemName". Available: ${inventoryItem.quantityAvailable}, required: ${usedItem.quantityUsed}.';
            }
          }

          return null;
        }

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final autoStockUsedItems = stockUsedPreviews();
            return AlertDialog(
              title: Text('Submit Dhol #$resolvedDholNumber Maintenance'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 560,
                  maxHeight: 620,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Dhol Number',
                          border: OutlineInputBorder(),
                        ),
                        child: Text('Dhol #$resolvedDholNumber'),
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Participants',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          participantsText.isEmpty ? '-' : participantsText,
                        ),
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Maintenance Event',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          detail.maintenanceEventTitle.trim().isEmpty
                              ? '-'
                              : detail.maintenanceEventTitle,
                        ),
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Event Date',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          detail.maintenanceEventDate.trim().isEmpty
                              ? '-'
                              : detail.maintenanceEventDate,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: workPerformedController,
                        minLines: 2,
                        maxLines: 4,
                        onChanged: (value) {
                          setDialogState(() {
                            canSubmit = value.trim().isNotEmpty;
                            submitErrorMessage = null;
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: 'Work Performed',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: remarksController,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Remarks',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Stock Used',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (autoStockUsedItems.isEmpty)
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'No approved stock usage for this maintenance day.',
                            style: TextStyle(color: Colors.black54),
                          ),
                        )
                      else
                        ...autoStockUsedItems.map((usedItem) {
                          final inventoryMatch = homeInventory
                              .where(
                                (inv) => inv.id == usedItem.inventoryItemId,
                              )
                              .toList();
                          final availableQty = inventoryMatch.isNotEmpty
                              ? inventoryMatch.first.quantityAvailable
                              : null;
                          final itemName =
                              usedItem.inventoryItemName.trim().isNotEmpty
                              ? usedItem.inventoryItemName.trim()
                              : 'Item #${usedItem.inventoryItemId}';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.black12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        itemName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        availableQty == null
                                            ? 'Used ${usedItem.quantityUsed}'
                                            : 'Used ${usedItem.quantityUsed} | Available $availableQty',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      if (submitErrorMessage != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          submitErrorMessage!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: (!canSubmit || isSubmitting)
                      ? null
                      : () async {
                          setDialogState(() {
                            isSubmitting = true;
                            submitErrorMessage = null;
                          });

                          try {
                            final availabilityMessage =
                                stockAvailabilityValidationMessage(
                                  autoStockUsedItems,
                                );
                            if (availabilityMessage != null) {
                              if (!dialogContext.mounted) {
                                return;
                              }
                              setDialogState(() {
                                isSubmitting = false;
                                submitErrorMessage = availabilityMessage;
                              });
                              return;
                            }

                            final stockValidationMessage =
                                await _validateStockRulesForHomeInstrumentSubmit(
                                  maintenance: detail,
                                );
                            if (stockValidationMessage != null) {
                              if (!dialogContext.mounted) {
                                return;
                              }
                              setDialogState(() {
                                isSubmitting = false;
                                submitErrorMessage = stockValidationMessage;
                              });
                              return;
                            }

                            final response =
                                await MaintenanceService.submitInstrumentMaintenance(
                                  maintenanceId: detail.id,
                                  workPerformed: workPerformedController.text
                                      .trim(),
                                  remarks: remarksController.text.trim(),
                                );
                            createdCompletionRequestId = int.tryParse(
                              response['completion_request_id']?.toString() ??
                                  '',
                            );

                            final maintenancePayload = response['maintenance'];
                            if (maintenancePayload is Map) {
                              final map = Map<String, dynamic>.from(
                                maintenancePayload,
                              );
                              final updatedStatus =
                                  map['status']?.toString().trim().isNotEmpty ==
                                      true
                                  ? map['status']!.toString().trim()
                                  : map['status_display']
                                            ?.toString()
                                            .trim()
                                            .isNotEmpty ==
                                        true
                                  ? map['status_display']!.toString().trim()
                                  : null;

                              if (updatedStatus != null && mounted) {
                                final updatedItem = PathakInstrumentMaintenance(
                                  id: detail.id,
                                  instrumentId: detail.instrumentId,
                                  maintenanceEventId: detail.maintenanceEventId,
                                  maintenanceEventTitle:
                                      detail.maintenanceEventTitle,
                                  maintenanceEventDate:
                                      detail.maintenanceEventDate,
                                  dholNumber: detail.dholNumber,
                                  status: updatedStatus,
                                  startedByUserId: detail.startedByUserId,
                                  startedByName: detail.startedByName,
                                  startedAt: detail.startedAt,
                                  workPerformed: detail.workPerformed,
                                  remarks: detail.remarks,
                                  approverNote: detail.approverNote,
                                  rejectionRemarks: detail.rejectionRemarks,
                                  beforeImages: detail.beforeImages,
                                  afterImages: detail.afterImages,
                                  participants: detail.participants,
                                );

                                setState(() {
                                  final index = _activeInstrumentMaintenances
                                      .indexWhere(
                                        (item) => item.id == detail.id,
                                      );
                                  if (index >= 0) {
                                    _activeInstrumentMaintenances[index] =
                                        updatedItem;
                                  } else {
                                    _activeInstrumentMaintenances = [
                                      updatedItem,
                                      ..._activeInstrumentMaintenances,
                                    ];
                                  }
                                });
                              }
                            }

                            successMessage =
                                response['message']?.toString() ??
                                'Maintenance submitted successfully.';
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } catch (e) {
                            if (!dialogContext.mounted) {
                              return;
                            }
                            setDialogState(() {
                              isSubmitting = false;
                              submitErrorMessage = e.toString().replaceFirst(
                                'Exception: ',
                                '',
                              );
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: AppColors.primaryMaroon,
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit Maintenance'),
                ),
              ],
            );
          },
        );
      },
    );

    workPerformedController.dispose();
    remarksController.dispose();

    if (submitted == true) {
      _showHomeSnack(successMessage ?? 'Maintenance submitted successfully.');
      await _loadActiveInstrumentMaintenances();
      await _refreshMaintenanceDaysSilently();
      if (createdCompletionRequestId != null || _maintenanceDays.isNotEmpty) {
        await _loadMaintenanceCompletionStatuses();
      }
      await _refreshStartMaintenanceEligibility(forceBackendRefresh: true);
    }
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
    _maintenanceDaysRefreshTimer?.cancel();
    if (mounted) {
      setState(() {
        _maintenanceDays = <MaintenanceEvent>[];
        _completionStatusByEvent.clear();
        _activeInstrumentMaintenances = <PathakInstrumentMaintenance>[];
        _activeInstrumentMaintenanceErrorMessage = null;
      });
    }
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
          canDownloadAttendanceQr: _canDownloadAttendanceQr,
          canSetAttendanceLocation: _canSetAttendanceLocation,
          canViewAttendanceByUser: _canViewAttendanceByUser,
          canViewDocumentApprovals: _canViewDocumentApprovals,
          isPathakAdmin: _isPathakAdmin,
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
          showUsersStatusFilters: showStatusFilters,
          canManageTerms: _permissionBool(
            'manage_terms',
            fallback: _isPathakAdminOnly,
          ),
          canUpdateUserGroup: _permissionBool(
            'user_approval',
            fallback: _isPathakAdminOnly,
          ),
          isGatPramukh: _isGatPramukh,
          gatPramukhName:
              _userDetails?['gat_pramukh_name']?.toString() ??
              _userDetails?['gatPramukhName']?.toString(),
          canViewUserAnalysis: _permissionBool(
            'user_analysis',
            fallback: _isPathakAdminOnly,
          ),
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

  Widget _buildHomePhotosPanel({required bool isCompact}) {
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
                Icons.photo_library,
                color: AppColors.primaryMaroon,
                size: isCompact ? 16 : 18,
              ),
              SizedBox(width: isCompact ? 6 : 8),
              Text(
                'Pathak Moments',
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
            child: _isLoadingHomePhotos
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.accentYellow,
                    ),
                  )
                : _homeScreenSlides.isEmpty
                ? Center(
                    child: Text(
                      'Welcome to ${AppConfig.appDisplayName}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.primaryMaroon,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : Stack(
                    children: [
                      PageView.builder(
                        controller: _homePhotosPageController,
                        itemCount: _homeScreenSlides.length,
                        onPageChanged: (index) {
                          _currentHomePhotoIndex = index;
                          if (mounted) setState(() {});
                        },
                        itemBuilder: (_, index) {
                          final slide = _homeScreenSlides[index];
                          final imageUrl =
                              slide['image_url']?.toString().trim() ?? '';
                          final caption =
                              slide['caption']?.toString().trim() ?? '';

                          return ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) {
                                    return Container(
                                      color: Colors.black12,
                                      alignment: Alignment.center,
                                      child: const Text(
                                        'Image unavailable',
                                        style: TextStyle(
                                          color: AppColors.primaryMaroon,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                if (caption.isNotEmpty)
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      color: Colors.black.withValues(
                                        alpha: 0.45,
                                      ),
                                      child: Text(
                                        caption,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                      if (_homeScreenSlides.length > 1)
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${_currentHomePhotoIndex + 1}/${_homeScreenSlides.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
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
    if (_subscribedRoute != null) {
      appRouteObserver.unsubscribe(this);
      _subscribedRoute = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _notificationSocketService?.dispose().ignore();
    _fabAnimationController.dispose();
    _homePhotosTimer?.cancel();
    _maintenanceDaysRefreshTimer?.cancel();
    _pushSetupRetryTimer?.cancel();
    _homePhotosPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 390 || size.height < 760;
    final hasScheduledMaintenanceDays = _maintenanceDays.isNotEmpty;
    final hasUpcomingMirvnuks = _events.any(_isUpcomingMirvnuk);

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
                              child: hasUpcomingMirvnuks
                                  ? SingleChildScrollView(
                                      child: UpcomingEvents(
                                        events: _events,
                                        isPathakAdmin: _isPathakAdmin,
                                        onRefresh: _refreshEventsSection,
                                      ),
                                    )
                                  : _buildHomePhotosPanel(isCompact: isCompact),
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
                            canDownloadAttendanceQr: _canDownloadAttendanceQr,
                            canSetAttendanceLocation: _canSetAttendanceLocation,
                            canViewByUserAttendance: _canViewAttendanceByUser,
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
                                  await _openMaintenanceScreenFromHome();
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
                                        canDownloadAttendanceQr:
                                            _canDownloadAttendanceQr,
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
                                  await _openMaintenanceScreenFromHome();
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
                                      await showDialog<void>(
                                        context: context,
                                        builder: (dialogContext) => AlertDialog(
                                          title: const Text('Error'),
                                          content: const Text(
                                            'Could not load your gat info. Please try again.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.of(
                                                dialogContext,
                                              ).pop(),
                                              child: const Text('OK'),
                                            ),
                                          ],
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
