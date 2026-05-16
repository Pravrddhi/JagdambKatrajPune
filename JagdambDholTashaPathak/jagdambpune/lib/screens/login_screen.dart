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
import '../services/api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../widgets/common_button.dart';
import '../widgets/input_box.dart';
import '../widgets/dropdown.dart';
import 'package:provider/provider.dart';
import '../providers/feature_flags_provider.dart';
import '../web/screens/login_web_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const String _loginFailureMessage =
      ApiEndpoints.genericApiFailureMessage;
  static const List<String> _bloodGroups = <String>[
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

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

  String? _mapLoginFailureMessage(String message) {
    final normalized = message.toLowerCase();
    final canonical = normalized
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (normalized.trim() == 'invalid pin.' ||
        normalized.trim() == 'invalid pin' ||
        canonical == 'invalid pin') {
      return 'Invalid PIN. If you are not registered, please register first.';
    }

    return null;
  }

  String _extractLoginErrorMessageFromResponse(dynamic decoded) {
    if (decoded is Map) {
      final candidates = <dynamic>[
        decoded['message'],
        decoded['error'],
        decoded['detail'],
        decoded['msg'],
      ];

      final data = decoded['data'];
      if (data is Map) {
        candidates.addAll(<dynamic>[
          data['message'],
          data['error'],
          data['detail'],
          data['msg'],
        ]);
      }

      for (final item in candidates) {
        final text = item?.toString().trim() ?? '';
        if (text.isNotEmpty) {
          final mapped = _mapLoginFailureMessage(text);
          return mapped ?? text;
        }
      }
    }
    return _loginFailureMessage;
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

    final mapped = _mapLoginFailureMessage(cleaned);
    if (mapped != null) {
      return mapped;
    }

    return cleaned;
  }

  int _compareVersions(String current, String required) {
    final currentParts = current
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final requiredParts = required
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();

    final maxLen = currentParts.length > requiredParts.length
        ? currentParts.length
        : requiredParts.length;

    for (var i = 0; i < maxLen; i++) {
      final a = i < currentParts.length ? currentParts[i] : 0;
      final b = i < requiredParts.length ? requiredParts[i] : 0;
      if (a < b) return -1;
      if (a > b) return 1;
    }
    return 0;
  }

  Future<bool> _enforceUpdateAfterLoginIfRequired() async {
    if (kIsWeb || !mounted) return true;

    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    if (!isAndroid && !isIos) return true;

    await context.read<FeatureFlagsProvider>().fetchFeatureFlags(force: true);
    if (!mounted) return false;

    final flags = context.read<FeatureFlagsProvider>().flags;
    if (flags == null) return true;

    final packageInfo = await PackageInfo.fromPlatform();
    final appVersion = packageInfo.version;

    final minVersion = isAndroid
        ? flags.minAndroidVersion
        : flags.minIosVersion;
    final forceFlag = isAndroid
        ? flags.forceUpdateAndroid
        : flags.forceUpdateIos;
    final storeUrl = isAndroid ? flags.androidStoreUrl : flags.iosStoreUrl;

    final requiresByVersion =
        minVersion != null && _compareVersions(appVersion, minVersion) < 0;
    final requiresUpdate = forceFlag || requiresByVersion;

    if (!requiresUpdate || !mounted) {
      return true;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          title: const Text('Update Required'),
          content: Text(
            flags.updateMessage ??
                'A new version of the app is available. Please update to continue.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (storeUrl == null || storeUrl.trim().isEmpty) return;
                final uri = Uri.tryParse(storeUrl.trim());
                if (uri == null) return;
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );

    return false;
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
            _errorMessage = _extractLoginErrorMessageFromResponse(decoded);
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
      final permissionsPayload = data['permissions'];
      final isVadak = _toNullableBool(data['vadak']);

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
        final popupTitle = (rejectionTitle != null && rejectionTitle.isNotEmpty)
            ? rejectionTitle
            : 'Rejected !';
        final popupParts = <String>[
          if (rejectionMessage != null && rejectionMessage.isNotEmpty)
            rejectionMessage,
          if (rejectionComment != null && rejectionComment.isNotEmpty)
            rejectionComment,
        ];
        await _showRejectedDialogWithReregister(
          title: popupTitle,
          message: popupParts.isEmpty
              ? 'Your account has been rejected with below comment'
              : popupParts.join('\n\n'),
          payload: data,
          profileData: profileData,
          accessToken: accessToken,
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
          builder: (dCtx) => AlertDialog(
            title: const Text('Pending Approval !'),
            content: const Text('Please wait till admin approves the account'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      if (approvalStatus == 3) {
        await _showRejectedDialogWithReregister(
          title: 'Rejected !',
          message: approvalComment.isNotEmpty
              ? 'Your account has been rejected with below comment\n\n$approvalComment'
              : 'Your account has been rejected with below comment',
          payload: data,
          profileData: profileData,
          accessToken: accessToken,
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
      final gatIdValue =
          profileData['gat_id']?.toString() ?? data['gat_id']?.toString() ?? '';
      if (gatIdValue.isNotEmpty) {
        await storage.write(key: ApiEndpoints.gatIdKey, value: gatIdValue);
      }
      final gatNameValue =
          profileData['gat_name']?.toString() ??
          profileData['gat']?.toString() ??
          data['gat_name']?.toString() ??
          data['gat']?.toString() ??
          '';
      if (gatNameValue.isNotEmpty) {
        await storage.write(key: ApiEndpoints.gatNameKey, value: gatNameValue);
      }
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

      final initialPermissions = permissionsPayload is Map<String, dynamic>
          ? permissionsPayload
          : (permissionsPayload is Map
                ? Map<String, dynamic>.from(permissionsPayload)
                : null);

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

      final canProceed = await _enforceUpdateAfterLoginIfRequired();
      if (!canProceed || !mounted) return;

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            authToken: accessToken,
            phoneNumber: '',
            isRegistration: false,
            hasFcmToken: hasFcmToken,
            initialPermissions: initialPermissions,
            initialVadak: isVadak,
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
      if (mounted) {
        setState(() {
          _errorMessage = _friendlyErrorMessage(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingIn = false;
        });
      }
    }
  }

  Future<void> _clearStoredSessionForUnapprovedUser() async {
    await storage.delete(key: ApiEndpoints.accessTokenKey);
    await storage.delete(key: ApiEndpoints.refreshTokenKey);
    await storage.delete(key: ApiEndpoints.isGatPramukhKey);
    await storage.delete(key: ApiEndpoints.gatPramukhNameKey);
  }

  String _normalizeDigits(String value) => value.replaceAll(RegExp(r'\D'), '');

  dynamic _pickRejectedField(
    Map<String, dynamic> payload,
    Map<String, dynamic> profileData,
    List<String> keys,
  ) {
    final nested = payload['data'];
    for (final key in keys) {
      final fromProfile = profileData[key];
      if (fromProfile != null && fromProfile.toString().trim().isNotEmpty) {
        return fromProfile;
      }
      final fromPayload = payload[key];
      if (fromPayload != null && fromPayload.toString().trim().isNotEmpty) {
        return fromPayload;
      }
      if (nested is Map<String, dynamic>) {
        final fromNested = nested[key];
        if (fromNested != null && fromNested.toString().trim().isNotEmpty) {
          return fromNested;
        }
      }
      if (nested is Map) {
        final fromNested = nested[key];
        if (fromNested != null && fromNested.toString().trim().isNotEmpty) {
          return fromNested;
        }
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _showReregisterFormDialog({
    required Map<String, dynamic> payload,
    required Map<String, dynamic> profileData,
  }) async {
    final firstNameController = TextEditingController(
      text:
          _pickRejectedField(payload, profileData, [
            'first_name',
          ])?.toString() ??
          '',
    );
    final lastNameController = TextEditingController(
      text:
          _pickRejectedField(payload, profileData, ['last_name'])?.toString() ??
          '',
    );
    final dobController = TextEditingController(
      text:
          _pickRejectedField(payload, profileData, [
            'date_of_birth',
          ])?.toString() ??
          '',
    );
    final joiningYearController = TextEditingController(
      text:
          _pickRejectedField(payload, profileData, [
            'joining_year',
            'joiningYear',
            'joined_year',
          ])?.toString() ??
          '',
    );
    final emergencyNameController = TextEditingController(
      text:
          _pickRejectedField(payload, profileData, [
            'emergency_contact_name',
          ])?.toString() ??
          '',
    );
    final emergencyPhoneController = TextEditingController(
      text:
          _pickRejectedField(payload, profileData, [
            'emergency_contact_phone',
          ])?.toString() ??
          '',
    );

    final rawGender = _pickRejectedField(payload, profileData, [
      'gender',
      'sex',
    ])?.toString().trim();
    final normalizedGender = rawGender?.toLowerCase() ?? '';
    String selectedGender = switch (normalizedGender) {
      'f' || 'female' => 'Female',
      'm' || 'male' => 'Male',
      'other' || 'o' => 'Other',
      _ => 'Male',
    };

    final resolvedBloodGroup = _pickRejectedField(payload, profileData, [
      'blood_group',
    ])?.toString().trim().toUpperCase();
    String selectedBloodGroup = _bloodGroups.contains(resolvedBloodGroup ?? '')
        ? (resolvedBloodGroup ?? 'O+')
        : 'O+';

    DateTime? selectedDob = DateTime.tryParse(dobController.text.trim());
    final Map<String, String?> errors = {};

    final formResult = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            Widget errorText(String? msg) => msg != null
                ? Padding(
                    padding: const EdgeInsets.only(top: 4.0, left: 4.0),
                    child: Text(
                      msg,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  )
                : const SizedBox.shrink();

            return AlertDialog(
              title: const Text('Re-register Details'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PremiumInputBox(
                      controller: firstNameController,
                      label: 'First Name',
                      useLightStyle: true,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[a-zA-Z\s]'),
                        ),
                      ],
                    ),
                    errorText(errors['first_name']),
                    const SizedBox(height: 10),
                    PremiumInputBox(
                      controller: lastNameController,
                      label: 'Last Name',
                      useLightStyle: true,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[a-zA-Z\s]'),
                        ),
                      ],
                    ),
                    errorText(errors['last_name']),
                    const SizedBox(height: 10),
                    PremiumDropdown(
                      label: 'Gender',
                      value: selectedGender,
                      options: const ['Male', 'Female', 'Other'],
                      backgroundColor: Colors.white,
                      labelColor: AppColors.primaryMaroon,
                      textColor: AppColors.primaryMaroon,
                      dropdownMenuColor: Colors.white,
                      onChanged: (value) {
                        if (value == null) return;
                        setLocalState(() {
                          selectedGender = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () async {
                        final now = DateTime.now();
                        final maxDob = DateTime(
                          now.year - 16,
                          now.month,
                          now.day,
                        );
                        final currentDob = selectedDob;
                        final initial =
                            (currentDob != null && currentDob.isBefore(maxDob))
                            ? currentDob
                            : maxDob;
                        final picked = await showDatePicker(
                          context: dialogContext,
                          initialDate: initial,
                          firstDate: DateTime(1950),
                          lastDate: maxDob,
                        );
                        if (!dialogContext.mounted || picked == null) return;
                        setLocalState(() {
                          selectedDob = picked;
                          dobController.text =
                              '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                          errors['dob'] = null;
                        });
                      },
                      child: AbsorbPointer(
                        child: PremiumInputBox(
                          controller: dobController,
                          label: 'Date of Birth',
                          useLightStyle: true,
                        ),
                      ),
                    ),
                    errorText(errors['dob']),
                    const SizedBox(height: 10),
                    PremiumInputBox(
                      controller: joiningYearController,
                      label: 'Joining Year',
                      useLightStyle: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    errorText(errors['joining_year']),
                    const SizedBox(height: 10),
                    PremiumDropdown(
                      label: 'Blood Group',
                      value: selectedBloodGroup,
                      options: _bloodGroups,
                      backgroundColor: Colors.white,
                      labelColor: AppColors.primaryMaroon,
                      textColor: AppColors.primaryMaroon,
                      dropdownMenuColor: Colors.white,
                      onChanged: (value) {
                        if (value == null) return;
                        setLocalState(() {
                          selectedBloodGroup = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    PremiumInputBox(
                      controller: emergencyNameController,
                      label: 'Emergency Contact Name',
                      useLightStyle: true,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[a-zA-Z\s]'),
                        ),
                      ],
                    ),
                    errorText(errors['emergency_name']),
                    const SizedBox(height: 10),
                    PremiumInputBox(
                      controller: emergencyPhoneController,
                      label: 'Emergency Contact Phone',
                      useLightStyle: true,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    errorText(errors['emergency_phone']),
                  ],
                ),
              ),
              actions: [
                SizedBox(
                  width: 150,
                  child: PremiumButton(
                    text: 'Cancel',
                    isEnabled: true,
                    isLoading: false,
                    backgroundColor: Colors.white,
                    textColor: AppColors.primaryMaroon,
                    onPressed: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      Navigator.pop(dialogContext);
                    },
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: PremiumButton(
                    text: 'Re-register',
                    isEnabled: true,
                    isLoading: false,
                    onPressed: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      final firstName = firstNameController.text.trim();
                      final lastName = lastNameController.text.trim();
                      final emergencyName = emergencyNameController.text.trim();
                      final emergencyPhone = _normalizeDigits(
                        emergencyPhoneController.text.trim(),
                      );
                      final joiningYearText = joiningYearController.text.trim();
                      final joiningYear = int.tryParse(joiningYearText);
                      final now = DateTime.now();

                      // Collect all errors
                      errors['first_name'] = firstName.isEmpty
                          ? 'First name is required.'
                          : !RegExp(r'^[a-zA-Z\s]+$').hasMatch(firstName)
                          ? 'First name must contain only letters.'
                          : null;

                      errors['last_name'] = lastName.isEmpty
                          ? 'Last name is required.'
                          : !RegExp(r'^[a-zA-Z\s]+$').hasMatch(lastName)
                          ? 'Last name must contain only letters.'
                          : null;

                      final dob = selectedDob;
                      if (dob == null) {
                        errors['dob'] = 'Date of birth is required.';
                      } else {
                        int age = now.year - dob.year;
                        if (now.month < dob.month ||
                            (now.month == dob.month && now.day < dob.day)) {
                          age -= 1;
                        }
                        errors['dob'] = age < 16
                            ? 'You must be at least 16 years old.'
                            : null;
                      }

                      errors['joining_year'] = joiningYearText.isEmpty
                          ? 'Joining year is required.'
                          : (joiningYear == null ||
                                joiningYear < 1900 ||
                                joiningYear > now.year)
                          ? 'Enter a valid joining year.'
                          : null;

                      errors['emergency_name'] = emergencyName.isEmpty
                          ? 'Emergency contact name is required.'
                          : !RegExp(r'^[a-zA-Z\s]+$').hasMatch(emergencyName)
                          ? 'Must contain only letters.'
                          : emergencyName.toLowerCase() ==
                                    '${firstName.toLowerCase()} ${lastName.toLowerCase()}'
                                        .trim() ||
                                emergencyName.toLowerCase() ==
                                    firstName.toLowerCase() ||
                                emergencyName.toLowerCase() ==
                                    lastName.toLowerCase()
                          ? 'Emergency contact cannot be the same person as you.'
                          : null;

                      errors['emergency_phone'] = emergencyPhone.isEmpty
                          ? 'Emergency contact phone is required.'
                          : !RegExp(r'^\d{10}$').hasMatch(emergencyPhone)
                          ? 'Must be exactly 10 digits.'
                          : emergencyPhone == _phoneController.text.trim()
                          ? 'Emergency contact phone cannot be your own phone number.'
                          : null;

                      final hasErrors = errors.values.any((e) => e != null);
                      setLocalState(() {});
                      if (hasErrors) return;

                      Navigator.pop(dialogContext, <String, dynamic>{
                        'first_name': firstNameController.text.trim(),
                        'last_name': lastNameController.text.trim(),
                        'gender': selectedGender,
                        'date_of_birth': dobController.text.trim(),
                        'joining_year': joiningYear,
                        'blood_group': selectedBloodGroup,
                        'emergency_contact_name': emergencyNameController.text
                            .trim(),
                        'emergency_contact_phone': emergencyPhone,
                      });
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    return formResult;
  }

  Future<void> _showRejectedDialogWithReregister({
    required String title,
    required String message,
    required Map<String, dynamic> payload,
    required Map<String, dynamic> profileData,
    required String accessToken,
  }) async {
    await _clearStoredSessionForUnapprovedUser();
    if (!mounted) return;

    final canReregister = accessToken.trim().isNotEmpty;

    final dialogAction = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message),
            if (canReregister) ...[
              const SizedBox(height: 16),
              PremiumButton(
                text: 'Re-register',
                isEnabled: true,
                isLoading: false,
                onPressed: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  Navigator.pop(dialogCtx, 'reregister');
                },
              ),
            ],
            const SizedBox(height: 8),
            PremiumButton(
              text: 'OK',
              isEnabled: true,
              isLoading: false,
              backgroundColor: Colors.white,
              textColor: AppColors.primaryMaroon,
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                Navigator.pop(dialogCtx, 'ok');
              },
            ),
          ],
        ),
        actions: const [],
      ),
    );

    if (dialogAction != 'reregister' || !canReregister) {
      return;
    }

    final formPayload = await _showReregisterFormDialog(
      payload: payload,
      profileData: profileData,
    );
    if (formPayload == null) {
      return;
    }

    if (mounted) {
      setState(() {
        _isLoggingIn = true;
      });
    }

    try {
      final reRegisterPayload = <String, dynamic>{
        ...payload,
        ...profileData,
        ...formPayload,
      };

      await ApiService.requestReRegistration(
        accessToken: accessToken,
        userData: reRegisterPayload,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dCtx) => AlertDialog(
          title: const Text('Request Submitted'),
          content: const Text(
            'Re-registration request submitted successfully.',
          ),
          actions: [
            SizedBox(
              width: 90,
              child: PremiumButton(
                text: 'OK',
                isEnabled: true,
                isLoading: false,
                backgroundColor: Colors.white,
                textColor: AppColors.primaryMaroon,
                onPressed: () => Navigator.pop(dCtx),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dCtx) => AlertDialog(
          title: const Text('Request Failed'),
          content: Text(_friendlyErrorMessage(e)),
          actions: [
            SizedBox(
              width: 90,
              child: PremiumButton(
                text: 'OK',
                isEnabled: true,
                isLoading: false,
                backgroundColor: Colors.white,
                textColor: AppColors.primaryMaroon,
                onPressed: () => Navigator.pop(dCtx),
              ),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingIn = false;
        });
      }
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

    final mediaQuery = MediaQuery.of(context);
    final formBottomPadding = 24.0 + mediaQuery.padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.primaryMaroon,
      resizeToAvoidBottomInset: false,
      bottomNavigationBar: (flags?.showRegistration ?? false)
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
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
            )
          : null,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          FocusScope.of(context).unfocus();
          if (_errorMessage.isNotEmpty) {
            setState(() {
              _errorMessage = '';
            });
          }
        },
        child: Stack(
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
                                focusNode: _pinFocusNode,
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
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            if (_isLoggingIn) const LoggingInOverlay(),
          ],
        ),
      ),
    );
  }
}
