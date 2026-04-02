import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import '../theme/app_colors.dart';
import '../widgets/input_box.dart';
import '../widgets/common_button.dart';
import '../widgets/drop_down.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:android_id/android_id.dart';
import 'home_screen.dart';
import '../config/api_endpoints.dart';
import 'package:flutter/services.dart';
import '../services/fcm_service.dart';
import '../services/bug_report_service.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final LocalAuthentication _auth = LocalAuthentication();

  // Controllers for input fields
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();

  // Focus node to detect phone input losing focus
  final FocusNode _phoneFocusNode = FocusNode();

  // Error tracking
  Map<String, String?> errors = {};
  Map<String, String?> _fieldErrors = {};
  String? _errorMessage;

  // Dropdown selections
  String? selectedSex;
  String? selectedInstrument;
  DateTime? selectedDob;
  int? selectedJoiningYear;

  // Loading states
  bool _isCheckingPhone = false;
  bool _isFormValid = false;
  bool isLoading = false;

  // Cache for instruments list
  List<String> _instruments = [];

  // Debounce timer for phone input validation to reduce API calls
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();

    // Add listeners for real-time validation
    _firstNameController.addListener(_validateForm);
    _lastNameController.addListener(_validateForm);
    _phoneController.addListener(_validateForm);

    // Load instrument options from API
    _loadInstruments();

    // Debounce phone input changes and on focus lost, check phone existence
    _phoneController.addListener(() {
      _onPhoneChanged(_phoneController.text.trim());
    });
    _phoneFocusNode.addListener(() {
      if (!_phoneFocusNode.hasFocus) {
        _checkPhoneNumberExists(_phoneController.text.trim());
      }
    });
  }

  /// Called on phone input change with debounce to minimize API calls
  void _onPhoneChanged(String value) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (value.length == 10) {
        _checkPhoneNumberExists(value);
      }
    });
  }

  /// Fetch instruments from server for dropdown based on pathak_id
  Future<List<String>> _fetchInstruments(int pathakId) async {
    final url = Uri.parse("${ApiEndpoints.getInstruments}/$pathakId/");
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        final rawInstruments = _extractInstrumentList(data);

        return rawInstruments
            .map(_instrumentNameFromItem)
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList();
      } else {
        await BugReportService.reportApiFailure(
          title: 'Fetch instruments API failed',
          errorMessage: response.body,
          pageUrl: '/registration',
          statusCode: response.statusCode,
          endpoint: ApiEndpoints.getInstruments,
        );
        return [];
      }
    } catch (e) {
      await BugReportService.reportApiFailure(
        title: 'Fetch instruments API exception',
        errorMessage: e.toString(),
        pageUrl: '/registration',
        endpoint: ApiEndpoints.getInstruments,
      );
      return [];
    }
  }

  List<dynamic> _extractInstrumentList(dynamic data) {
    if (data is List) {
      return data;
    }

    if (data is Map<String, dynamic>) {
      const listKeys = [
        'instruments',
        'data',
        'results',
        'instrument_list',
        'instrument_names',
        'items',
      ];

      for (final key in listKeys) {
        final payload = data[key];
        if (payload is List) {
          return payload;
        }
      }

      for (final value in data.values) {
        if (value is List) {
          return value;
        }
      }
    }

    return <dynamic>[];
  }

  String _instrumentNameFromItem(dynamic item) {
    if (item is String) {
      return item.trim();
    }

    if (item is Map) {
      const nameKeys = [
        'name',
        'instrument',
        'title',
        'instrument_name',
        'instrumentName',
        'label',
        'value',
      ];

      for (final key in nameKeys) {
        final value = item[key];
        if (value != null) {
          final normalized = value.toString().trim();
          if (normalized.isNotEmpty) {
            return normalized;
          }
        }
      }
    }

    return item.toString().trim();
  }

  /// Loads instruments and updates UI state with results
  void _loadInstruments() async {
    int pathakId = int.tryParse(ApiEndpoints.pathakId.toString()) ?? 0;
    if (pathakId == 0) return;

    List<String> instruments = await _fetchInstruments(pathakId);
    setState(() {
      _instruments = instruments;
    });
  }

  /// Validate form fields and update form valid state
  void _validateForm() {
    final isValid =
        validateFirstName(_firstNameController.text) &&
        validateLastName(_lastNameController.text) &&
        validatePhone(_phoneController.text) &&
        selectedDob != null &&
        validateSelection(selectedSex) &&
        validateSelection(selectedInstrument) &&
        _fieldErrors.values.every((error) => error == null);

    setState(() {
      _isFormValid = isValid;
    });
  }

  /// Validation helpers
  bool validateFirstName(String firstName) => firstName.trim().isNotEmpty;
  bool validateLastName(String lastName) => lastName.trim().isNotEmpty;
  bool validatePhone(String phone) => RegExp(r'^\d{10}$').hasMatch(phone);
  bool validateSelection(String? value) => value != null;

  bool _isAtLeast18(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    final hasNotHadBirthdayYet =
        now.month < dob.month || (now.month == dob.month && now.day < dob.day);
    if (hasNotHadBirthdayYet) {
      age -= 1;
    }
    return age >= 18;
  }

  Future<void> _showUnderAgePopup() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Access Denied'),
        content: const Text(
          'below 18 are not allowed please ask your parents to login',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Check via API if phone number already registered
  Future<void> _checkPhoneNumberExists(String phoneNumber) async {
    if (phoneNumber.length != 10) return;

    setState(() {
      _isCheckingPhone = true;
      _fieldErrors['phone_number'] = null;
    });

    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.checkPhoneNumber),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone_number': phoneNumber}),
      );

      setState(() {
        _isCheckingPhone = false;
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final exists = data['status'] as bool;
          if (exists) {
            _fieldErrors['phone_number'] = "Phone number already registered.";
          }
        } else {
          _fieldErrors['phone_number'] = ApiEndpoints.genericApiFailureMessage;
        }
      });

      if (response.statusCode != 200) {
        await BugReportService.reportApiFailure(
          title: 'Check phone number API failed',
          errorMessage: response.body,
          pageUrl: '/registration',
          statusCode: response.statusCode,
          endpoint: ApiEndpoints.checkPhoneNumber,
        );
      }
    } catch (e) {
      await BugReportService.reportApiFailure(
        title: 'Check phone number API exception',
        errorMessage: e.toString(),
        pageUrl: '/registration',
        endpoint: ApiEndpoints.checkPhoneNumber,
      );
      setState(() {
        _isCheckingPhone = false;
        _fieldErrors['phone_number'] = ApiEndpoints.genericApiFailureMessage;
      });
    }
    _validateForm();
  }

  /// Get unique device ID for Android or iOS platforms
  Future<String> _getDeviceId() async {
    const AndroidId androidIdPlugin = AndroidId();
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      String? androidId = await androidIdPlugin.getId();
      return androidId ?? "unknown";
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? "unknown";
    } else {
      return "unsupported_platform";
    }
  }

  /// Submits registration data to backend API
  Future<void> _register() async {
    // Manual field validations, setting error messages
    errors.clear();

    if (!validateFirstName(_firstNameController.text)) {
      errors['first_name'] = "First name is required.";
    }
    if (!validateLastName(_lastNameController.text)) {
      errors['last_name'] = "Last name is required.";
    }
    if (!validatePhone(_phoneController.text)) {
      errors['phone_number'] = "Phone number must be 10 digits only.";
    }
    if (selectedDob == null) {
      errors['dob'] = 'Date of Birth is required.';
    }
    if (!validateSelection(selectedSex)) {
      errors['sex'] = "Please select a gender.";
    }
    if (!validateSelection(selectedInstrument)) {
      errors['instrument'] = "Please select an instrument.";
    }

    if (errors.isNotEmpty) {
      setState(() {
        _fieldErrors = errors;
        _errorMessage = null;
      });
      return;
    } else {
      setState(() {
        _fieldErrors.clear();
      });
    }

    setState(() {
      isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.register),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "phone_number": _phoneController.text,
          "first_name": _firstNameController.text,
          "last_name": _lastNameController.text,
          "gender": selectedSex,
          "instrument": selectedInstrument,
          "dob": selectedDob != null
              ? '${selectedDob!.year}-${selectedDob!.month.toString().padLeft(2, '0')}-${selectedDob!.day.toString().padLeft(2, '0')}'
              : null,
          "joining_year": selectedJoiningYear,
          "device_id": await _getDeviceId(),
          "pathak_id": ApiEndpoints.pathakId,
        }),
      );

      setState(() => isLoading = false);

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final accessToken = data['access_token'];
        // Ask for notification permission right after successful registration,
        // before the set-PIN dialog appears on the next screen.
        await FCMService().requestNotificationPermission();
        await _promptBiometricAfterNotificationPermission();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomeScreen(
              authToken: accessToken,
              phoneNumber: _phoneController.text,
              isRegistration: true,
            ),
          ),
        );
      } else {
        await BugReportService.reportApiFailure(
          title: 'Registration API failed',
          errorMessage: response.body,
          pageUrl: '/registration',
          statusCode: response.statusCode,
          endpoint: ApiEndpoints.register,
        );

        setState(() {
          _errorMessage = ApiEndpoints.genericApiFailureMessage;
        });
      }
    } catch (e) {
      await BugReportService.reportApiFailure(
        title: 'Registration API exception',
        errorMessage: e.toString(),
        pageUrl: '/registration',
        endpoint: ApiEndpoints.register,
      );
      setState(() {
        isLoading = false;
        _errorMessage = ApiEndpoints.genericApiFailureMessage;
      });
    }
  }

  Future<void> _promptBiometricAfterNotificationPermission() async {
    try {
      final isSupported = await _auth.isDeviceSupported();
      if (!isSupported) return;
      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return;
      await _auth.authenticate(
        localizedReason: 'Enable biometric for quick login',
        options: const AuthenticationOptions(
          stickyAuth: false,
          biometricOnly: true,
        ),
      );
    } catch (_) {
      // Skip silently if biometric is unavailable or user cancels.
    }
  }

  @override
  void dispose() {
    // Clean up controllers and focus node to prevent memory leaks
    _phoneController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneFocusNode.dispose();

    _debounceTimer?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryMaroon,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Back button top-left aligned
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  color: AppColors.accentYellow,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(height: 8),

              // Splash logo image
              Image.asset(
                'assets/logos/splash_logo.png',
                height: 120,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 32),

              // First Name input
              PremiumInputBox(
                controller: _firstNameController,
                label: "First Name",
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                ],
              ),
              if (_fieldErrors['first_name'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, left: 4.0),
                  child: Text(
                    _fieldErrors['first_name']!,
                    style: const TextStyle(
                      color: AppColors.accentYellow,
                      fontSize: 13,
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // Last Name input
              PremiumInputBox(
                controller: _lastNameController,
                label: "Last Name",
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                ],
              ),
              if (_fieldErrors['last_name'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, left: 4.0),
                  child: Text(
                    _fieldErrors['last_name']!,
                    style: const TextStyle(
                      color: AppColors.accentYellow,
                      fontSize: 13,
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // Phone Number input
              PremiumInputBox(
                controller: _phoneController,
                label: "Phone Number",
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                focusNode: _phoneFocusNode,
              ),
              if (_isCheckingPhone)
                const Padding(
                  padding: EdgeInsets.only(top: 8.0, left: 4.0),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.accentYellow,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Checking phone number...',
                        style: TextStyle(
                          color: AppColors.accentYellow,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              else if (_fieldErrors['phone_number'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, left: 4.0),
                  child: Text(
                    _fieldErrors['phone_number']!,
                    style: const TextStyle(
                      color: AppColors.accentYellow,
                      fontSize: 13,
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // Gender dropdown
              PremiumDropDown(
                label: "Gender",
                value: selectedSex,
                options: const ["Male", "Female", "Other"],
                onChanged: (val) {
                  setState(() {
                    selectedSex = val;
                  });
                  _validateForm();
                },
              ),
              if (_fieldErrors['sex'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, left: 4.0),
                  child: Text(
                    _fieldErrors['sex']!,
                    style: const TextStyle(
                      color: AppColors.accentYellow,
                      fontSize: 13,
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // Date of Birth picker
              GestureDetector(
                onTap: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDob ?? DateTime(2000),
                    firstDate: DateTime(1950),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null && picked != selectedDob) {
                    setState(() {
                      selectedDob = picked;
                      _fieldErrors.remove('dob');
                    });
                    if (!_isAtLeast18(picked)) {
                      setState(() {
                        selectedDob = null;
                        _fieldErrors['dob'] = 'You must be 18 years old';
                      });
                      await _showUnderAgePopup();
                    }
                    _validateForm();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryMaroon,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accentYellow.withAlpha(77),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        selectedDob != null
                            ? '${selectedDob!.day}/${selectedDob!.month}/${selectedDob!.year}'
                            : 'Date of Birth',
                        style: const TextStyle(
                          color: AppColors.textLight,
                          fontSize: 16,
                        ),
                      ),
                      const Icon(
                        Icons.calendar_today,
                        color: AppColors.accentYellow,
                      ),
                    ],
                  ),
                ),
              ),
              if (_fieldErrors['dob'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, left: 4.0),
                  child: Text(
                    _fieldErrors['dob']!,
                    style: const TextStyle(
                      color: AppColors.accentYellow,
                      fontSize: 13,
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // Joining Year dropdown
              PremiumDropDown(
                label: "Joining Year",
                value: selectedJoiningYear?.toString(),
                options: List.generate(
                  30,
                  (index) => (DateTime.now().year - index).toString(),
                ),
                onChanged: (val) {
                  setState(() {
                    selectedJoiningYear = int.tryParse(val ?? '');
                  });
                  _validateForm();
                },
              ),
              const SizedBox(height: 16),

              // Instrument dropdown
              PremiumDropDown(
                label: "Instrument",
                value: selectedInstrument,
                options: _instruments,
                onChanged: (val) {
                  setState(() {
                    selectedInstrument = val;
                  });
                  _validateForm();
                },
              ),
              if (_fieldErrors['instrument'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, left: 4.0),
                  child: Text(
                    _fieldErrors['instrument']!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
              const SizedBox(height: 24),

              // Register button with loading spinner and enabling logic
              PremiumButton(
                text: "Register",
                isEnabled: _isFormValid && !isLoading,
                isLoading: isLoading,
                onPressed: _isFormValid && !isLoading ? _register : null,
              ),

              // Display general error messages if any
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: AppColors.accentYellow),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
