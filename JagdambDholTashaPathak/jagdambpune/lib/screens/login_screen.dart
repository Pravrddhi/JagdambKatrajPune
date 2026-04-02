import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import '../components/get_device_id.dart';
import '../../theme/app_colors.dart';
import '../widgets/logging_in_overlay.dart';
import '../config/api_endpoints.dart';
import 'home_screen.dart';
import '../services/fcm_service.dart';
import '../services/bug_report_service.dart';
import '../services/web_api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../widgets/common_button.dart';
import '../widgets/input_box.dart';
import 'package:provider/provider.dart';
import '../providers/feature_flags_provider.dart';
import '../web/screens/login_web_screen.dart';
import '../components/get_emergency_details.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const String _loginFailureMessage = 'Something went wrong';
  static const String _showEmergencyAfterFirstLoginKey =
      'show_emergency_after_first_login';

  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();

  final LocalAuthentication auth = LocalAuthentication();
  final storage = const FlutterSecureStorage();
  bool _isLoggingIn = false;
  String _errorMessage = '';
  bool _isDeviceRegistered = false;

  String _friendlyErrorMessage(Object error) {
    final raw = error.toString().trim();
    const prefix = 'Exception: ';
    if (raw.startsWith(prefix)) {
      return raw.substring(prefix.length).trim();
    }
    return raw;
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<FeatureFlagsProvider>().fetchFeatureFlags(force: true);
    });

    _pinFocusNode.addListener(() {
      if (_pinFocusNode.hasFocus && _errorMessage.isNotEmpty) {
        setState(() {
          _errorMessage = '';
        });
      }
    });

    if (!kIsWeb) {
      _checkDeviceRegistration();
    }
  }

  Future<void> _checkDeviceRegistration() async {
    try {
      String deviceId = await getDeviceId();
      final response = await http.post(
        Uri.parse(ApiEndpoints.checkDeviceRegistration),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'device_id': deviceId}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['status'] == true) {
        setState(() => _isDeviceRegistered = true);
        // Only auto-attempt biometric if device is registered
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _attemptBiometricLogin();
        });
      } else {
        await BugReportService.reportApiFailure(
          title: 'Check device registration failed',
          errorMessage: response.body,
          pageUrl: '/login',
          statusCode: response.statusCode,
          endpoint: ApiEndpoints.checkDeviceRegistration,
        );
      }
    } catch (e) {
      await BugReportService.reportApiFailure(
        title: 'Check device registration exception',
        errorMessage: e.toString(),
        pageUrl: '/login',
        endpoint: ApiEndpoints.checkDeviceRegistration,
      );
      // Network error — skip biometric silently
    }
  }

  Future<void> _attemptBiometricLogin() async {
    try {
      bool canCheckBiometrics = await auth.canCheckBiometrics;
      bool isDeviceSupported = await auth.isDeviceSupported();

      if (!isDeviceSupported) {
        setState(() {
          _errorMessage = 'This device does not support biometrics.';
        });
        return;
      }

      final availableBiometrics = await auth.getAvailableBiometrics();
      if (availableBiometrics.isEmpty) {
        setState(() {
          _errorMessage =
              'No biometrics enrolled. Please set up fingerprint or face unlock in device settings.';
        });
        return;
      }

      if (!canCheckBiometrics) {
        setState(() {
          _errorMessage = 'Biometric hardware is unavailable.';
        });
        return;
      }

      bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Please authenticate to login',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (didAuthenticate) {
        String? storedPin = await storage.read(key: ApiEndpoints.pinKey);
        if (storedPin != null && storedPin.length == 6) {
          _pinController.text = storedPin;
          await _login();
        } else {
          setState(() {
            _errorMessage = 'Please login manually.';
          });
        }
      }
    } on PlatformException catch (e) {
      setState(() {
        _errorMessage = 'Biometric authentication error: ${e.message}';
      });
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final bool isWeb = kIsWeb;
    final String pin = _pinController.text.trim();
    final String phoneNumber = _phoneController.text.trim();
    final String password = _passwordController.text;

    if (isWeb) {
      if (phoneNumber.length != 10) {
        setState(() {
          _errorMessage = 'Please enter a valid 10-digit phone number.';
        });
        return;
      }
      if (password.isEmpty) {
        setState(() {
          _errorMessage = 'Please enter your password.';
        });
        return;
      }
    } else {
      if (pin.isEmpty || pin.length < 6) {
        setState(() {
          _errorMessage = 'Please enter a valid 6-digit PIN.';
        });
        return;
      }
    }

    setState(() {
      _isLoggingIn = true;
    });

    try {
      final Map<String, dynamic> data;

      if (isWeb) {
        data = await WebApiService.loginWithPassword(
          phoneNumber: phoneNumber,
          password: password,
        );
      } else {
        final response = await http.post(
          Uri.parse(ApiEndpoints.loginWithPin),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'pin': pin, 'device_id': await getDeviceId()}),
        );

        final decoded = jsonDecode(response.body);
        final bool isSuccessful =
            response.statusCode == 200 && decoded['status'] == true;
        if (!isSuccessful) {
          await BugReportService.reportApiFailure(
            title: 'Login API failed',
            errorMessage: response.body,
            pageUrl: '/login',
            statusCode: response.statusCode,
            endpoint: ApiEndpoints.loginWithPin,
          );
          setState(() {
            _errorMessage = _loginFailureMessage;
          });
          return;
        }
        data = decoded;
      }

      final isGatPramukh =
          data['is_gat_pramukh'] == true ||
          data['is_gat_pramukh']?.toString().toLowerCase() == 'true' ||
          data['is_gat_pramukh']?.toString() == '1';
      final profileData = data['data'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(data['data'])
          : const <String, dynamic>{};

      await storage.write(
        key: ApiEndpoints.accessTokenKey,
        value: data['access_token'],
      );
      await storage.write(
        key: ApiEndpoints.refreshTokenKey,
        value: data['refresh_token'],
      );
      await storage.write(
        key: ApiEndpoints.isGatPramukhKey,
        value: isGatPramukh.toString(),
      );
      await storage.write(
        key: ApiEndpoints.gatPramukhNameKey,
        value:
            profileData['gat_pramukh_name']?.toString() ??
            data['gat_pramukh_name']?.toString() ??
            '',
      );
      final joiningYearValue =
          profileData['joining_year'] ??
          profileData['joiningYear'] ??
          profileData['joined_year'];
      if (joiningYearValue != null) {
        await storage.write(
          key: 'joining_year',
          value: joiningYearValue.toString(),
        );
      }

      if (isWeb) {
        try {
          final rawFlag = await storage.read(
            key: _showEmergencyAfterFirstLoginKey,
          );
          final shouldShowEmergency = rawFlag == 'true' || rawFlag == '1';
          if (shouldShowEmergency && mounted) {
            await EmergencyContactDialog.show(context, data['access_token']);
            await storage.write(
              key: _showEmergencyAfterFirstLoginKey,
              value: 'false',
            );
          }
        } catch (_) {
          // Emergency dialog must not block successful login on web.
        }
      }

      try {
        String? fcmToken = await FCMService().getFcmToken(isLogin: false);
        if (fcmToken != null) {
          await FCMService().sendTokenToServer(fcmToken);
        }
      } catch (_) {
        // FCM setup must not block successful login.
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            authToken: data['access_token'],
            phoneNumber: '',
            isRegistration: false,
          ),
        ),
      );
    } catch (e) {
      await BugReportService.reportApiFailure(
        title: 'Login API exception',
        errorMessage: e.toString(),
        pageUrl: '/login',
        endpoint: isWeb
            ? ApiEndpoints.passwordLogin
            : ApiEndpoints.loginWithPin,
      );
      setState(() {
        _errorMessage = isWeb ? _friendlyErrorMessage(e) : _loginFailureMessage;
      });
    } finally {
      setState(() {
        _isLoggingIn = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final flagsProvider = Provider.of<FeatureFlagsProvider>(context);
    final flags = flagsProvider.flags;
    if (kIsWeb) {
      return Scaffold(
        backgroundColor: AppColors.primaryMaroon,
        body: Stack(
          children: [
            LoginWebScreen(
              phoneController: _phoneController,
              passwordController: _passwordController,
              errorMessage: _errorMessage,
              isLoggingIn: _isLoggingIn,
              showRegistration: flags?.showRegistration ?? false,
              isFeatureFlagsLoading:
                  flagsProvider.isLoading && flagsProvider.flags == null,
              onLogin: _login,
              onRegistrationTap: () {
                Navigator.pushNamed(context, '/register');
              },
              onResetPinTap: () {
                Navigator.pushNamed(context, '/resetPin');
              },
              onPhoneChanged: (_) {
                if (_errorMessage.isNotEmpty) {
                  setState(() {
                    _errorMessage = '';
                  });
                }
              },
              onPasswordChanged: (_) {
                if (_errorMessage.isNotEmpty) {
                  setState(() {
                    _errorMessage = '';
                  });
                }
              },
            ),
            if (_isLoggingIn) const LoggingInOverlay(),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.primaryMaroon,
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/logos/splash_logo.png',
                        height: 120,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Login',
                        style: TextStyle(
                          color: AppColors.textLight,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 32),
                      PremiumInputBox(
                        controller: _pinController,
                        label: 'Enter 6-digit PIN',
                        isPin: true,
                        onChanged: (_) {
                          if (_errorMessage.isNotEmpty) {
                            setState(() {
                              _errorMessage = '';
                            });
                          }
                        },
                      ),
                      if (_errorMessage.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _errorMessage,
                            style: const TextStyle(
                              color: AppColors.errorRed,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      PremiumButton(
                        text: 'Login',
                        onPressed: _login,
                        isLoading: _isLoggingIn,
                        isEnabled: !_isLoggingIn,
                      ),
                      if (_isDeviceRegistered) ...[
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: _attemptBiometricLogin,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.fingerprint,
                                color: AppColors.accentYellow,
                                size: 32,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Login with Biometric',
                                style: TextStyle(
                                  color: AppColors.accentYellow,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (flags?.showRegistration ?? false) ...[
                            GestureDetector(
                              onTap: () {
                                Navigator.pushNamed(context, '/register');
                              },
                              child: const Text(
                                "Registration",
                                style: TextStyle(
                                  color: AppColors.accentYellow,
                                  decoration: TextDecoration.underline,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ] else ...[
                            GestureDetector(
                              onTap: () {
                                Navigator.pushNamed(context, '/resetPin');
                              },
                              child: const Text(
                                "Reset PIN",
                                style: TextStyle(
                                  color: AppColors.accentYellow,
                                  decoration: TextDecoration.underline,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          if (_isLoggingIn) const LoggingInOverlay(),
        ],
      ),
    );
  }
}
