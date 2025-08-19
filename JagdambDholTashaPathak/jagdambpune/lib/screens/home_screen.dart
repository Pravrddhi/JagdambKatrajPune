import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
// import 'dart:io';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// import 'package:device_info_plus/device_info_plus.dart';
// import 'package:android_id/android_id.dart';
import '../widgets/setpin_dialog.dart';
import '../config/api_endpoints.dart';
import '../theme/app_colors.dart';
import '../widgets/app_drawer.dart';
import '../widgets/input_box.dart';
import '../widgets/button.dart';
import '../components/upcoming_events.dart';

final storage = const FlutterSecureStorage();

class HomeScreen extends StatefulWidget {
  final String authToken;
  final String phoneNumber;
  final bool isRegistration;
  final storage = const FlutterSecureStorage();
  const HomeScreen({
    super.key,
    required this.authToken,
    required this.phoneNumber,
    required this.isRegistration,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
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

  @override
  void initState() {
    super.initState();

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
    if (widget.isRegistration) {
      Future.delayed(const Duration(seconds: 2), () async {
        accessToken = await showSetPinDialog(
          context,
          widget.phoneNumber,
          false,
        );
        _fetchUserDetails(accessToken);
      });
    } else {
      // If not login, fetch user details directly
      _fetchUserDetails(widget.authToken);
    }
  }

  Future<void> _fetchUserDetails(String accessToken) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse(ApiEndpoints.getUserDetails),
        headers: {
          'Authorization': 'Bearer $accessToken',
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
      } else if (response.statusCode == 403) {
        _errorMessage = 'User not found.';
      } else if (response.statusCode == 404) {
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

  @override
  void dispose() {
    _animationController.dispose();
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
                  // const Text(
                  //   'Live updates will be shown here',
                  //   style: TextStyle(
                  //     color: AppColors.primaryMaroon,
                  //     fontSize: 18,
                  //   ),
                  // ),
                  if (_events.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    UpcomingEvents(events: _events),
                  ],
                ],
              )
            : const Center(
                child: CircularProgressIndicator(color: AppColors.accentYellow),
              ),
      ),
    );
  }
}
