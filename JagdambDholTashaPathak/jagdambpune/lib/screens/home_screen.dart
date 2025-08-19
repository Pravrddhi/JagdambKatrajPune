import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../widgets/setpin_dialog.dart';
import '../config/api_endpoints.dart';
import '../theme/app_colors.dart';
import '../widgets/app_drawer.dart';
import '../components/get_emergency_details.dart';
import '../components/upcoming_events.dart';
import '../components/mirvnuk_dialog.dart';
import '../components/notification_dialog.dart';

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
  Map<String, dynamic>? _userDetails;
  bool _isLoading = false;
  String? _errorMessage;
  String accessToken = '';
  List<Map<String, dynamic>> _events = [];

  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  final LocalAuthentication auth = LocalAuthentication();
  final FlutterSecureStorage storage = const FlutterSecureStorage();

  // FAB variables
  bool _isFabOpen = false;
  late AnimationController _fabAnimationController;
  late Animation<double> _fabAnimation;

  @override
  void initState() {
    super.initState();

    // Main animations
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

    // FAB animations
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fabAnimation = CurvedAnimation(
      parent: _fabAnimationController,
      curve: Curves.easeInOut,
    );

    _initializeUser();
  }

  Future<void> _initializeUser() async {
    if (widget.isRegistration) {
      Future.delayed(const Duration(seconds: 2), () async {
        accessToken = await showSetPinDialog(
          context,
          widget.phoneNumber,
          false,
        );
        await EmergencyContactDialog.show(context, accessToken);
        _fetchUserDetails(accessToken);
      });
    } else {
      String? token = await storage.read(key: 'access_token');
      if (token != null && token.isNotEmpty) {
        accessToken = token;
        _fetchUserDetails(accessToken);
      } else {
        _fetchUserDetails(widget.authToken);
      }
    }
  }

  Future<void> _fetchUserDetails(String token) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse(ApiEndpoints.getUserDetails),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == true && data['data'] != null) {
          setState(() {
            _userDetails = data['data'];
            if (data['data']['events'] != null &&
                data['data']['events'].isNotEmpty) {
              _events = List<Map<String, dynamic>>.from(data['data']['events']);
            } else {
              _events = [];
            }
          });
          _animationController.forward();
        } else {
          setState(() {
            _errorMessage = data['message'] ?? 'Failed to load user details';
          });
        }
      } else if (response.statusCode == 403 || response.statusCode == 404) {
        setState(() {
          _errorMessage = 'User not found.';
        });
      } else {
        setState(() {
          _errorMessage =
              'Failed to load user details (Code: ${response.statusCode})';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error: $e';
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
        email: _userDetails?['email'],
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

                      // Scrollable Upcoming Events
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
                : const Center(
                    child: CircularProgressIndicator(color: AppColors.accentYellow),
                  ),
      ),
      floatingActionButton:
          (_userDetails != null && _userDetails!['role'] != 'Vadak')
              ? SizedBox(
                  width: 150,
                  height: 150,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      // Add Mirvnuk
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
                              await AddMirvnukDialog.show(context);
                              String? token =
                                  await storage.read(key: 'access_token');
                              if (token != null && token.isNotEmpty) {
                                _fetchUserDetails(token);
                              }
                            },
                            child: const Icon(Icons.event),
                          ),
                        ),
                      ),
                      // Add Notification
                      Positioned(
                        bottom: 0,
                        right: 80,
                        child: ScaleTransition(
                          scale: _fabAnimation,
                          child: FloatingActionButton(
                            heroTag: 'add_notification',
                            mini: true,
                            backgroundColor: AppColors.accentYellow,
                            onPressed: () {
                              _toggleFabMenu();
                              NotificationDialog.show(context);
                            },
                            child: const Icon(Icons.notifications),
                          ),
                        ),
                      ),
                      // Main FAB
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
