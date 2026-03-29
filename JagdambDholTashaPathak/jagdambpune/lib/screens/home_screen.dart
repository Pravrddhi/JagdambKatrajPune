import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import '../widgets/setpin_dialog.dart';
import '../theme/app_colors.dart';
import '../components/app_drawer.dart';
import '../components/upcoming_events.dart';
import '../components/mirvnuk_dialog.dart';
import '../components/notification_dialog.dart';
import '../services/fcm_service.dart';
import '../services/user_service.dart';
import '../components/get_emergency_details.dart';
import '../providers/notification_provider.dart';
import '../config/api_endpoints.dart';

const storage = FlutterSecureStorage();

class HomeScreen extends StatefulWidget {
  final String authToken;
  final String phoneNumber;
  final bool isRegistration;

  const HomeScreen({
    super.key,
    required this.authToken,
    required this.phoneNumber,
    required this.isRegistration,
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

  late final AnimationController _animationController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

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
  int _currentSayingIndex = 0;

  @override
  void initState() {
    super.initState();

    // Initialize welcome text animations
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
        );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );

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

  /// Initialize user info depending on registration status
  Future<void> _initializeUser() async {
    final fcmService = FCMService();
    fcmService.listenTokenRefresh();
    await fcmService.requestNotificationPermission();

    if (widget.isRegistration) {
      Future.delayed(const Duration(seconds: 2), () async {
        accessToken = await showSetPinDialog(
          context,
          widget.phoneNumber,
          false,
        );

        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Success'),
            content: const Text('Registration successful.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );

        // Defer emergency details to first successful login after registration.
        await storage.write(
          key: _showEmergencyAfterFirstLoginKey,
          value: 'true',
        );

        if (!mounted) return;
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
      });
    } else {
      String? token = await storage.read(key: 'access_token');
      if (token != null && token.isNotEmpty) {
        accessToken = token;
        await fcmService.syncCurrentTokenToServer(isLogin: false);
        final loaded = await _loadUserDetails(accessToken);
        if (!mounted || !loaded) return;
        await _showEmergencyDialogOnFirstLoginIfNeeded(accessToken);
      } else {
        await fcmService.syncCurrentTokenToServer(isLogin: false);
        final loaded = await _loadUserDetails(widget.authToken);
        if (!mounted || !loaded) return;
        await _showEmergencyDialogOnFirstLoginIfNeeded(widget.authToken);
      }
    }
  }

  Future<void> _showEmergencyDialogOnFirstLoginIfNeeded(String token) async {
    final shouldShow =
        await storage.read(key: _showEmergencyAfterFirstLoginKey) == 'true';

    if (!shouldShow || !mounted) {
      return;
    }

    await EmergencyContactDialog.show(context, token);
    await storage.write(key: _showEmergencyAfterFirstLoginKey, value: 'false');
  }

  /// Wrapper to handle loading/error state while fetching user details
  Future<bool> _loadUserDetails(String token) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userData = await UserService.fetchUserDetails(token);
      final storedIsGatPramukhRaw = await storage.read(
        key: ApiEndpoints.isGatPramukhKey,
      );
      final storedGatPramukhName = await storage.read(
        key: ApiEndpoints.gatPramukhNameKey,
      );

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

      if (!mounted) return false;

      setState(() {
        _userDetails = mergedUserData;

        if (mergedUserData['events'] != null &&
            mergedUserData['events'].isNotEmpty) {
          _events = List<Map<String, dynamic>>.from(mergedUserData['events']);
        } else {
          _events = [];
        }
      });

      _animationController.forward();
      return true;
    } on UserInactiveException {
      if (!mounted) return false;
      final isRegistration = widget.isRegistration;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Pending Approval'),
          content: Text(
            isRegistration
                ? 'Your registration is successful! Your account is pending admin approval. You will be able to login once approved.'
                : 'Your account is inactive. Please ask the admin to approve your account.',
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
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      return false;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _errorMessage = ApiEndpoints.genericApiFailureMessage;
        _userDetails = null;
        _events = [];
      });
      return false;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value == 1;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  bool get _isPathakAdmin {
    final role = _userDetails?['role']?.toString().trim().toLowerCase();
    return role == 'pathak_admin' || role == 'pathak-admin';
  }

  bool get _isGatPramukh {
    final userDetails = _userDetails;
    if (userDetails == null) {
      return false;
    }

    final role = userDetails['role']?.toString().trim().toLowerCase();
    final isRoleGatPramukh = role == 'gat_pramukh' || role == 'gat-pramukh';

    return isRoleGatPramukh ||
        _parseBool(userDetails['is_gat_pramukh']) ||
        _parseBool(userDetails['isGatPramukh']);
  }

  bool get _canOpenMirvunkForm {
    final role = _userDetails?['role']?.toString().trim().toLowerCase();
    return _userDetails != null && role != 'vadak';
  }

  bool get _canSendNotification {
    return _isPathakAdmin || _isGatPramukh;
  }

  bool get _hasFabActions {
    return _canOpenMirvunkForm || _canSendNotification;
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

  Widget _buildNotificationsPanel() {
    return Consumer<NotificationProvider>(
      builder: (_, notificationProvider, __) {
        final notifications = notificationProvider.notifications;

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
                  if (notifications.isNotEmpty)
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
                        notifications.length > 99
                            ? '99+'
                            : notifications.length.toString(),
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
                          return Container(
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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

  Widget _buildMotivationalSayingsPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.accentYellow.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.auto_awesome,
                color: AppColors.primaryMaroon,
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'Motivation Corner',
                style: TextStyle(
                  color: AppColors.primaryMaroon,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
                    style: const TextStyle(
                      color: AppColors.primaryMaroon,
                      fontSize: 18,
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

  @override
  void dispose() {
    _animationController.dispose();
    _fabAnimationController.dispose();
    _sayingsTimer?.cancel();
    _sayingsPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Home'),
        backgroundColor: AppColors.primaryMaroon,
        actions: const [],
      ),
      drawer: AppDrawer(
        firstName: _userDetails?['first_name'],
        phoneNumber: _userDetails?['phone_number'],
        userDetails: _userDetails,
        onLogout: _handleLogout,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _errorMessage != null
            ? Center(
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: AppColors.accentYellow),
                ),
              )
            : _userDetails != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SlideTransition(
                    position: _slideAnimation,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Text(
                        'Welcome, ${_userDetails?['first_name'] ?? ''}!',
                        style: const TextStyle(
                          color: AppColors.primaryMaroon,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        Expanded(flex: 3, child: _buildNotificationsPanel()),
                        const SizedBox(height: 12),
                        Expanded(
                          flex: 7,
                          child: _events.isNotEmpty
                              ? SingleChildScrollView(
                                  child: UpcomingEvents(events: _events),
                                )
                              : _buildMotivationalSayingsPanel(),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.accentYellow),
              )
            : Container(), // show empty container if none of above
      ),
      floatingActionButton: _hasFabActions
          ? SizedBox(
              width: 150,
              height: 150,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  if (_canOpenMirvunkForm)
                    Positioned(
                      bottom: 80,
                      right: 0,
                      child: ScaleTransition(
                        scale: _fabAnimation,
                        child: FloatingActionButton(
                          heroTag: 'add_mirvnuk',
                          mini: true,
                          backgroundColor: AppColors.accentYellow,
                          onPressed: () async {
                            _toggleFabMenu();
                            await MirvunkForm.open(context);
                            String? token = await storage.read(
                              key: 'access_token',
                            );
                            if (token != null && token.isNotEmpty) {
                              _loadUserDetails(token);
                            }
                          },
                          child: const Icon(Icons.event),
                        ),
                      ),
                    ),
                  if (_canSendNotification)
                    Positioned(
                      bottom: 0,
                      right: 80,
                      child: ScaleTransition(
                        scale: _fabAnimation,
                        child: FloatingActionButton(
                          heroTag: 'add_notification',
                          mini: true,
                          backgroundColor: AppColors.accentYellow,
                          onPressed: () async {
                            _toggleFabMenu();
                            await NotificationForm.open(context);
                          },
                          child: const Icon(Icons.notifications),
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
            )
          : null,
    );
  }
}
