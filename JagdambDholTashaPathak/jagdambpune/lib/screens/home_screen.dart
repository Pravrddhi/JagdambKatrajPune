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
  bool _isNotificationsDialogOpen = false;
  late final AnimationController _fabAnimationController;
  late final Animation<double> _fabAnimation;

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

    // Start user initialization workflow
    _initializeUser();
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
      if (!mounted) return false;

      setState(() {
        _userDetails = userData;

        if (userData['events'] != null && userData['events'].isNotEmpty) {
          _events = List<Map<String, dynamic>>.from(userData['events']);
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
        _errorMessage = e.toString();
        _userDetails = null;
        _events = [];
      });
      return false;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

  Future<void> _showNotificationsDialog() async {
    if (_isNotificationsDialogOpen) return;
    _isNotificationsDialogOpen = true;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Consumer<NotificationProvider>(
          builder: (_, notificationProvider, __) {
            final notifications = notificationProvider.notifications;

            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Notifications'),
                  if (notifications.isNotEmpty)
                    TextButton(
                      onPressed: notificationProvider.clearAll,
                      child: const Text('Clear all'),
                    ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: notifications.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: Text('No notifications')),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: notifications.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final item = notifications[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(item.title),
                            subtitle: Text(item.message),
                            trailing: IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => notificationProvider
                                  .clearNotification(item.id),
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
    _isNotificationsDialogOpen = false;
  }

  @override
  void dispose() {
    _animationController.dispose();
    _fabAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Home'),
        backgroundColor: AppColors.primaryMaroon,
        actions: [
          Consumer<NotificationProvider>(
            builder: (_, notificationProvider, __) {
              final unreadCount = notificationProvider.unreadCount;

              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      onPressed: _showNotificationsDialog,
                      icon: const Icon(Icons.notifications),
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade700,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          constraints: const BoxConstraints(minWidth: 18),
                          child: Text(
                            unreadCount > 99 ? '99+' : unreadCount.toString(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
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
                  const SizedBox(height: 20),
                  Expanded(
                    child: _events.isNotEmpty
                        ? SingleChildScrollView(
                            child: UpcomingEvents(events: _events),
                          )
                        : const Center(
                            child: Text(
                              'No upcoming events',
                              style: TextStyle(color: AppColors.primaryMaroon),
                            ),
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
      floatingActionButton:
          (_userDetails != null && _userDetails!['role'] != 'vadak')
          ? SizedBox(
              width: 150,
              height: 150,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
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
