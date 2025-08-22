import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../widgets/setpin_dialog.dart';
import '../theme/app_colors.dart';
import '../components/app_drawer.dart';
import '../components/upcoming_events.dart';
import '../components/mirvnuk_dialog.dart';
import '../components/notification_dialog.dart';
import '../services/fcm_service.dart';
import '../services/user_service.dart';
import '../components/get_emergency_details.dart';

final storage = const FlutterSecureStorage();

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
  Map<String, dynamic>? _userDetails;           // User profile data
  bool _isLoading = false;                       // Loading indicator
  String? _errorMessage;                         // Error messages
  String accessToken = '';                       // Current access token
  List<Map<String, dynamic>> _events = [];      // User's upcoming events

  late final AnimationController _animationController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  bool _isFabOpen = false;
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
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(
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
    if (widget.isRegistration) {
      Future.delayed(const Duration(seconds: 2), () async {
        accessToken = await showSetPinDialog(
          context,
          widget.phoneNumber,
          false,
        );

        await EmergencyContactDialog.show(context, accessToken);

        String? fcmToken = await FCMService().getFcmToken(isLogin: false);
        if (fcmToken != null) {
          await FCMService().sendTokenToServer(fcmToken);
        }

        _loadUserDetails(accessToken);
      });
    } else {
      String? token = await storage.read(key: 'access_token');
      if (token != null && token.isNotEmpty) {
        accessToken = token;
        _loadUserDetails(accessToken);
      } else {
        _loadUserDetails(widget.authToken);
      }
    }
  }

  /// Wrapper to handle loading/error state while fetching user details
  Future<void> _loadUserDetails(String token) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userData = await UserService.fetchUserDetails(token);
      if (!mounted) return;

      setState(() {
        _userDetails = userData;

        if (userData['events'] != null && userData['events'].isNotEmpty) {
          _events = List<Map<String, dynamic>>.from(userData['events']);
        } else {
          _events = [];
        }
      });

      _animationController.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _userDetails = null;
        _events = [];
      });
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
                        child:
                            CircularProgressIndicator(color: AppColors.accentYellow),
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
                              String? token = await storage.read(key: 'access_token');
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
