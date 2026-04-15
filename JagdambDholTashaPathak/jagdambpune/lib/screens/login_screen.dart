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
import '../services/bug_report_service.dart';
import '../services/web_api_service.dart';
import '../services/fcm_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../widgets/common_button.dart';
import '../widgets/input_box.dart';
import 'package:provider/provider.dart';
import '../providers/feature_flags_provider.dart';
import '../web/screens/login_web_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const String _loginFailureMessage =
      ApiEndpoints.genericApiFailureMessage;

  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();

  final LocalAuthentication auth = LocalAuthentication();
  final FCMService _fcmService = FCMService();
  final storage = const FlutterSecureStorage();
  bool _isLoggingIn = false;
  String _errorMessage = '';
  bool _isDeviceRegistered = false;

  bool? _toNullableBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }
    return null;
  }

  bool? _extractHasFcmToken(Map<String, dynamic> payload) {
    final topLevel = _toNullableBool(payload['has_fcm_token']);
    if (topLevel != null) return topLevel;

    final nested = payload['data'];
    if (nested is Map<String, dynamic>) {
      return _toNullableBool(nested['has_fcm_token']);
    }

    return null;
  }

  String _friendlyErrorMessage(Object error) {
    final raw = error.toString().trim();
    const prefix = 'Exception: ';
    final cleaned = raw.startsWith(prefix)
        ? raw.substring(prefix.length).trim()
        : raw;

    if (cleaned.isEmpty) {
      return ApiEndpoints.genericApiFailureMessage;
    }

    final normalized = cleaned.toLowerCase();
    if (normalized.contains('socketexception') ||
        normalized.contains('failed host lookup') ||
        normalized.contains('timed out') ||
        normalized.contains('timeout')) {
      return ApiEndpoints.serverUnreachableMessage;
    }

    return cleaned;
  }

  @override
  void initState() {
    super.initState();

    if (!kIsWeb) {
      _refreshStoredBiometricState();
    }

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
  }

  Future<void> _refreshStoredBiometricState() async {
    final storedPin = await storage.read(key: ApiEndpoints.pinKey);
    if (!mounted) return;

    setState(() {
      _isDeviceRegistered = storedPin != null && storedPin.length == 6;
    });
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
    final String webPin = _passwordController.text;

    if (isWeb) {
      if (phoneNumber.length != 10) {
        setState(() {
          _errorMessage = 'Please enter a valid 10-digit phone number.';
        });
        return;
      }
      if (webPin.isEmpty || webPin.length < 6) {
        setState(() {
          _errorMessage = 'Please enter a valid 6-digit PIN.';
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
          pin: webPin,
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
      final accessToken =
          data['access_token']?.toString() ??
          profileData['access_token']?.toString() ??
          '';
      final refreshToken =
          data['refresh_token']?.toString() ??
          profileData['refresh_token']?.toString() ??
          '';
      final hasFcmToken = _extractHasFcmToken(data);

      if (accessToken.isEmpty) {
        setState(() {
          _errorMessage = _loginFailureMessage;
        });
        return;
      }
      final shouldShowRejectionPopup = data['show_rejection_popup'] == true;
      final rejectionTitle = data['rejection_title']?.toString().trim();
      final rejectionMessage = data['rejection_message']?.toString().trim();
      final rejectionComment = data['rejection_comment']?.toString().trim();

      if (shouldShowRejectionPopup) {
        await _clearStoredSessionForUnapprovedUser();
        if (!mounted) return;
        final popupTitle = (rejectionTitle != null && rejectionTitle.isNotEmpty)
            ? rejectionTitle
            : 'Rejected !';
        final popupParts = <String>[
          if (rejectionMessage != null && rejectionMessage.isNotEmpty)
            rejectionMessage,
          if (rejectionComment != null && rejectionComment.isNotEmpty)
            rejectionComment,
        ];
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: Text(popupTitle),
            content: Text(
              popupParts.isEmpty
                  ? 'Your account has been rejected with below comment'
                  : popupParts.join('\n\n'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      final rawApprovalStatus =
          profileData['approval_status'] ?? data['approval_status'];
      final approvalStatus = rawApprovalStatus is int
          ? rawApprovalStatus
          : int.tryParse(rawApprovalStatus?.toString() ?? '');
      final approvalComment =
          profileData['approval_comment']?.toString().trim().isNotEmpty == true
          ? profileData['approval_comment'].toString().trim()
          : data['approval_comment']?.toString().trim() ?? '';

      if (approvalStatus == 0) {
        await _clearStoredSessionForUnapprovedUser();
        if (!mounted) return;
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
        return;
      }

      if (approvalStatus == 3) {
        await _clearStoredSessionForUnapprovedUser();
        if (!mounted) return;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Rejected !'),
            content: Text(
              approvalComment.isNotEmpty
                  ? 'Your account has been rejected with below comment\n\n$approvalComment'
                  : 'Your account has been rejected with below comment',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      await storage.write(key: ApiEndpoints.accessTokenKey, value: accessToken);
      if (!isWeb) {
        await storage.write(key: ApiEndpoints.pinKey, value: pin);
        if (mounted) {
          setState(() {
            _isDeviceRegistered = true;
          });
        }
      }
      if (refreshToken.isNotEmpty) {
        await storage.write(
          key: ApiEndpoints.refreshTokenKey,
          value: refreshToken,
        );
      }
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

      // Re-fetch feature flags now that the auth token is stored so the
      // drawer correctly reflects this user's configuration.
      if (mounted) {
        context.read<FeatureFlagsProvider>().fetchFeatureFlags(force: true);
      }

      if (!isWeb) {
        try {
          // Always sync token after successful mobile login.
          _fcmService.listenTokenRefresh();
          await _fcmService.syncCurrentTokenToServer(isLogin: false);
        } catch (_) {
          // Non-blocking: login should continue even if FCM sync fails.
        }
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            authToken: accessToken,
            phoneNumber: '',
            isRegistration: false,
            hasFcmToken: hasFcmToken,
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

  Future<void> _clearStoredSessionForUnapprovedUser() async {
    await storage.delete(key: ApiEndpoints.accessTokenKey);
    await storage.delete(key: ApiEndpoints.refreshTokenKey);
    await storage.delete(key: ApiEndpoints.isGatPramukhKey);
    await storage.delete(key: ApiEndpoints.gatPramukhNameKey);
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

    final mediaQuery = MediaQuery.of(context);
    final formBottomPadding =
        24.0 + mediaQuery.padding.bottom + mediaQuery.viewInsets.bottom;

    return Scaffold(
      backgroundColor: AppColors.primaryMaroon,
      body: Stack(
        children: [
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(32, 24, 32, formBottomPadding),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 24,
                        maxWidth: 520,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Image.asset(
                              'assets/logos/splash_logo.png',
                              height: 120,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Login',
                              textAlign: TextAlign.center,
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
                                  textAlign: TextAlign.center,
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
                                child: const Center(
                                  child: Wrap(
                                    alignment: WrapAlignment.center,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      Icon(
                                        Icons.fingerprint,
                                        color: AppColors.accentYellow,
                                        size: 32,
                                      ),
                                      Text(
                                        'Login with Biometric',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: AppColors.accentYellow,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            Center(
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.pushNamed(context, '/resetPin');
                                },
                                child: const Text(
                                  'Reset PIN',
                                  style: TextStyle(
                                    color: AppColors.accentYellow,
                                    decoration: TextDecoration.underline,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 80),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          if (flags?.showRegistration ?? false)
            Positioned(
              bottom: mediaQuery.padding.bottom + 24,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Divider(
                    color: Colors.white24,
                    indent: 48,
                    endIndent: 48,
                    thickness: 1,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'New to Pathak?  ',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushNamed(context, '/register');
                        },
                        child: const Text(
                          'Register',
                          style: TextStyle(
                            color: AppColors.accentYellow,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                            decorationColor: AppColors.accentYellow,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (_isLoggingIn) const LoggingInOverlay(),
        ],
      ),
    );
  }
}
