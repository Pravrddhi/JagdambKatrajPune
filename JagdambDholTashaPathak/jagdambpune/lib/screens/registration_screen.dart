import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../theme/app_colors.dart';
import '../widgets/input_box.dart';
import '../widgets/common_button.dart';
import '../widgets/dropdown.dart';
import 'home_screen.dart';
import '../config/api_endpoints.dart';
import 'package:flutter/services.dart';
import '../services/bug_report_service.dart';

const FlutterSecureStorage _storage = FlutterSecureStorage();

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  static const String _termsAcceptedStorageKey =
      'terms_and_conditions_accepted';

  // Controllers for input fields
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _adhaarNumberController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();

  // Focus node to detect phone input losing focus
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _adhaarFocusNode = FocusNode();

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
  bool _isCheckingAdhaar = false;
  bool _isFormValid = false;
  bool isLoading = false;
  bool _hasAcceptedTerms = false;
  bool _isTermsLoading = false;
  String _termsErrorMessage = '';
  List<String> _termsAndConditions = const <String>[];

  // Cache for instruments list
  List<String> _instruments = [];

  // Debounce timer for phone input validation to reduce API calls
  Timer? _debounceTimer;
  Timer? _adhaarDebounceTimer;

  @override
  void initState() {
    super.initState();

    // Add listeners for real-time validation
    _firstNameController.addListener(_validateForm);
    _lastNameController.addListener(_validateForm);
    _phoneController.addListener(_validateForm);
    _adhaarNumberController.addListener(_validateForm);

    // Load instrument options from API
    _loadInstruments();
    _loadStoredTermsAcceptance();
    _loadTermsAndConditions();

    // Debounce phone input changes and on focus lost, check phone existence
    _phoneController.addListener(() {
      _onPhoneChanged(_phoneController.text.trim());
    });
    _adhaarNumberController.addListener(() {
      _onAdhaarChanged(_adhaarNumberController.text.trim());
    });
    _phoneFocusNode.addListener(() {
      if (!_phoneFocusNode.hasFocus) {
        _checkPhoneNumberExists(_phoneController.text.trim());
      }
    });
    _adhaarFocusNode.addListener(() {
      if (!_adhaarFocusNode.hasFocus) {
        _checkAdhaarNumberExists(_adhaarNumberController.text.trim());
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

  void _onAdhaarChanged(String value) {
    if (_adhaarDebounceTimer?.isActive ?? false) {
      _adhaarDebounceTimer!.cancel();
    }
    _adhaarDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (value.length == 4) {
        _checkAdhaarNumberExists(value);
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
        validateAdhaarNumber(_adhaarNumberController.text) &&
        selectedDob != null &&
        validateSelection(selectedSex) &&
        validateSelection(selectedInstrument) &&
        selectedJoiningYear != null &&
        _fieldErrors.values.every((error) => error == null);

    setState(() {
      _isFormValid = isValid;
    });
  }

  /// Validation helpers
  bool validateFirstName(String firstName) => firstName.trim().isNotEmpty;
  bool validateLastName(String lastName) => lastName.trim().isNotEmpty;
  bool validatePhone(String phone) => RegExp(r'^\d{10}$').hasMatch(phone);
  bool validateAdhaarNumber(String value) => RegExp(r'^\d{4}$').hasMatch(value);
  bool validateSelection(String? value) => value != null;

  bool _isAtLeast16(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    final hasNotHadBirthdayYet =
        now.month < dob.month || (now.month == dob.month && now.day < dob.day);
    if (hasNotHadBirthdayYet) {
      age -= 1;
    }
    return age >= 16;
  }

  Future<void> _showUnderAgePopup() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Access Denied'),
        content: const Text(
          'below 16 are not allowed please ask your parents to login',
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
        body: jsonEncode({
          'phone_number': phoneNumber,
          'pathak_id': ApiEndpoints.pathakIdInt,
        }),
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

  Future<bool> _checkAdhaarNumberExists(String adhaarNumber) async {
    if (!validateAdhaarNumber(adhaarNumber)) {
      return false;
    }

    setState(() {
      _isCheckingAdhaar = true;
      _fieldErrors['adhaar_number'] = null;
    });

    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.checkAdhaarNumber),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'adhaar_number': int.parse(adhaarNumber),
          'pathak_id': ApiEndpoints.pathakIdInt,
        }),
      );

      bool isDuplicate = false;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        isDuplicate = data['status'] == true;
      }

      setState(() {
        _isCheckingAdhaar = false;
        if (response.statusCode == 200) {
          if (isDuplicate) {
            _fieldErrors['adhaar_number'] =
                'Aadhaar number already registered.';
          }
        } else {
          _fieldErrors['adhaar_number'] = ApiEndpoints.genericApiFailureMessage;
        }
      });

      if (response.statusCode != 200) {
        await BugReportService.reportApiFailure(
          title: 'Check Aadhaar number API failed',
          errorMessage: response.body,
          pageUrl: '/registration',
          statusCode: response.statusCode,
          endpoint: ApiEndpoints.checkAdhaarNumber,
        );
      }

      _validateForm();
      return isDuplicate;
    } catch (e) {
      await BugReportService.reportApiFailure(
        title: 'Check Aadhaar number API exception',
        errorMessage: e.toString(),
        pageUrl: '/registration',
        endpoint: ApiEndpoints.checkAdhaarNumber,
      );
      setState(() {
        _isCheckingAdhaar = false;
        _fieldErrors['adhaar_number'] = ApiEndpoints.genericApiFailureMessage;
      });
      _validateForm();
      return false;
    }
  }

  Future<String> _getDeviceId() async {
    const AndroidId androidIdPlugin = AndroidId();
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final androidId = await androidIdPlugin.getId();
      return androidId ?? 'unknown';
    }
    if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? 'unknown';
    }
    return 'unsupported_platform';
  }

  String? _extractFirstErrorText(dynamic value) {
    if (value == null) return null;
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    if (value is List && value.isNotEmpty) {
      final first = value.first;
      if (first is String && first.trim().isNotEmpty) {
        return first.trim();
      }
    }
    return null;
  }

  void _applyRegistrationApiErrors(String responseBody) {
    String? resolvedError;
    String? phoneError;
    String? adhaarError;

    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        // Some backends return field errors at top-level, others nest under "message".
        final dynamic messagePayload = decoded['message'];
        final List<dynamic> payloadsToScan = [decoded];
        if (messagePayload is Map<String, dynamic>) {
          payloadsToScan.add(messagePayload);
        }

        for (final payload in payloadsToScan) {
          if (payload is! Map<String, dynamic>) continue;

          phoneError ??= _extractFirstErrorText(payload['phone_number']);
          adhaarError ??= _extractFirstErrorText(payload['adhaar_number']);
          resolvedError ??= _extractFirstErrorText(payload['device_id']);
        }

        resolvedError ??= _extractFirstErrorText(decoded['detail']);
        resolvedError ??= _extractFirstErrorText(decoded['error']);
        if (resolvedError == null) {
          final messageText = decoded['message'];
          if (messageText is String && messageText.trim().isNotEmpty) {
            resolvedError = messageText.trim();
          }
        }
      }
    } catch (_) {
      // Keep generic fallback below for non-JSON responses.
    }

    setState(() {
      _fieldErrors['phone_number'] = phoneError;
      _fieldErrors['adhaar_number'] = adhaarError;
      _errorMessage = resolvedError ?? ApiEndpoints.genericApiFailureMessage;
    });
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
    if (!validateAdhaarNumber(_adhaarNumberController.text)) {
      errors['adhaar_number'] = "Aadhaar number must be exactly 4 digits.";
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
    if (selectedJoiningYear == null) {
      errors['joining_year'] = 'Please select joining year.';
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

    if (!_hasAcceptedTerms) {
      setState(() {
        _errorMessage = 'Please accept Terms & Conditions to continue.';
      });
      return;
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
          "adhaar_number": int.tryParse(_adhaarNumberController.text),
          "first_name": _firstNameController.text,
          "last_name": _lastNameController.text,
          "gender": selectedSex,
          "instrument": selectedInstrument,
          "pathak_id": ApiEndpoints.pathakIdInt,
          "dob": selectedDob != null
              ? '${selectedDob!.year}-${selectedDob!.month.toString().padLeft(2, '0')}-${selectedDob!.day.toString().padLeft(2, '0')}'
              : null,
          "joining_year": selectedJoiningYear,
          "has_accepted_terms": _hasAcceptedTerms,
          "device_id": await _getDeviceId(),
        }),
      );

      setState(() => isLoading = false);

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final accessToken = data['access_token'];
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

        _applyRegistrationApiErrors(response.body);
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

  Future<void> _loadStoredTermsAcceptance() async {
    try {
      final stored = await _storage.read(key: _termsAcceptedStorageKey);
      if (!mounted) return;
      setState(() {
        _hasAcceptedTerms = stored == 'true';
      });
    } catch (_) {
      // Non-blocking: checkbox remains unchecked if storage is unavailable.
    }
  }

  Future<void> _setTermsAcceptance(bool accepted) async {
    setState(() {
      _hasAcceptedTerms = accepted;
      if (accepted &&
          _errorMessage == 'Please accept Terms & Conditions to continue.') {
        _errorMessage = null;
      }
    });
    try {
      await _storage.write(
        key: _termsAcceptedStorageKey,
        value: accepted ? 'true' : 'false',
      );
    } catch (_) {
      // Non-blocking: local persistence failure should not break form interaction.
    }
  }

  Future<void> _loadTermsAndConditions() async {
    if (_isTermsLoading) return;

    setState(() {
      _isTermsLoading = true;
      _termsErrorMessage = '';
    });

    try {
      final uri = Uri.parse(
        '${ApiEndpoints.termsAndConditions}?pathak_id=${ApiEndpoints.pathakIdInt}',
      );
      final response = await http.get(uri, headers: ApiEndpoints.jsonHeaders());

      if (response.statusCode != 200) {
        await BugReportService.reportApiFailure(
          title: 'Terms and conditions API failed',
          errorMessage: response.body,
          pageUrl: '/registration',
          statusCode: response.statusCode,
          endpoint: ApiEndpoints.termsAndConditions,
        );
        if (!mounted) return;
        setState(() {
          _termsErrorMessage = ApiEndpoints.genericApiFailureMessage;
          _termsAndConditions = const <String>[];
        });
        return;
      }

      final decoded = jsonDecode(response.body);
      final termsRaw = (decoded is Map<String, dynamic>)
          ? decoded['terms_and_conditions']
          : null;
      final parsedTerms = termsRaw is List
          ? termsRaw
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList()
          : <String>[];

      if (!mounted) return;
      setState(() {
        _termsAndConditions = parsedTerms;
      });
    } catch (e) {
      await BugReportService.reportApiFailure(
        title: 'Terms and conditions API exception',
        errorMessage: e.toString(),
        pageUrl: '/registration',
        endpoint: ApiEndpoints.termsAndConditions,
      );
      if (!mounted) return;
      setState(() {
        _termsErrorMessage = ApiEndpoints.serverUnreachableMessage;
        _termsAndConditions = const <String>[];
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isTermsLoading = false;
      });
    }
  }

  Future<void> _showTermsDialog() async {
    if (_isTermsLoading) return;
    if (_termsAndConditions.isEmpty) {
      await _loadTermsAndConditions();
    }
    if (!mounted) return;

    final terms = _termsAndConditions;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Terms and Conditions'),
        content: SizedBox(
          width: double.maxFinite,
          child: terms.isEmpty
              ? Text(
                  _termsErrorMessage.isNotEmpty
                      ? _termsErrorMessage
                      : 'No terms available right now.',
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: terms.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, index) =>
                      Text('${index + 1}. ${terms[index]}'),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _setTermsAcceptance(true);
              if (!mounted) return;
              Navigator.pop(context);
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Clean up controllers and focus node to prevent memory leaks
    _phoneController.dispose();
    _adhaarNumberController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneFocusNode.dispose();
    _adhaarFocusNode.dispose();

    _debounceTimer?.cancel();
    _adhaarDebounceTimer?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIos = Platform.isIOS;
    final mediaQuery = MediaQuery.of(context);
    final formBottomPadding =
        (isIos ? 32.0 : 16.0) +
        mediaQuery.padding.bottom +
        mediaQuery.viewInsets.bottom;

    return Scaffold(
      backgroundColor: AppColors.primaryMaroon,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(24, 72, 24, formBottomPadding),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 72,
                        maxWidth: 520,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
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
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[a-zA-Z\s]'),
                              ),
                            ],
                          ),
                          if (_fieldErrors['first_name'] != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 4.0,
                                left: 4.0,
                              ),
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
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[a-zA-Z\s]'),
                              ),
                            ],
                          ),
                          if (_fieldErrors['last_name'] != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 4.0,
                                left: 4.0,
                              ),
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
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
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
                              padding: const EdgeInsets.only(
                                top: 4.0,
                                left: 4.0,
                              ),
                              child: Text(
                                _fieldErrors['phone_number']!,
                                style: const TextStyle(
                                  color: AppColors.accentYellow,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          PremiumInputBox(
                            controller: _adhaarNumberController,
                            label: "Aadhaar Number (Last 4 digits)",
                            keyboardType: TextInputType.number,
                            maxLength: 4,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            focusNode: _adhaarFocusNode,
                          ),
                          if (_isCheckingAdhaar)
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
                                    'Checking Aadhaar number...',
                                    style: TextStyle(
                                      color: AppColors.accentYellow,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (_fieldErrors['adhaar_number'] != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 4.0,
                                left: 4.0,
                              ),
                              child: Text(
                                _fieldErrors['adhaar_number']!,
                                style: const TextStyle(
                                  color: AppColors.accentYellow,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          PremiumDropdown(
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
                              padding: const EdgeInsets.only(
                                top: 4.0,
                                left: 4.0,
                              ),
                              child: Text(
                                _fieldErrors['sex']!,
                                style: const TextStyle(
                                  color: AppColors.accentYellow,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
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
                                if (!_isAtLeast16(picked)) {
                                  setState(() {
                                    selectedDob = null;
                                    _fieldErrors['dob'] =
                                        'You must be 16 years old';
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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
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
                              padding: const EdgeInsets.only(
                                top: 4.0,
                                left: 4.0,
                              ),
                              child: Text(
                                _fieldErrors['dob']!,
                                style: const TextStyle(
                                  color: AppColors.accentYellow,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          PremiumDropdown(
                            label: "Joining Year",
                            value: selectedJoiningYear?.toString(),
                            options: List.generate(
                              DateTime.now().year >= 2011
                                  ? (DateTime.now().year - 2011 + 1)
                                  : 0,
                              (index) =>
                                  (DateTime.now().year - index).toString(),
                            ),
                            onChanged: (val) {
                              setState(() {
                                selectedJoiningYear = int.tryParse(val ?? '');
                              });
                              _validateForm();
                            },
                          ),
                          const SizedBox(height: 16),
                          PremiumDropdown(
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
                              padding: const EdgeInsets.only(
                                top: 4.0,
                                left: 4.0,
                              ),
                              child: Text(
                                _fieldErrors['instrument']!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _showTermsDialog,
                            child: const Text(
                              'View Terms & Accept',
                              style: TextStyle(
                                color: AppColors.primaryMaroon,
                                decoration: TextDecoration.underline,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            _hasAcceptedTerms
                                ? 'Terms accepted'
                                : 'Terms not accepted',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _hasAcceptedTerms
                                  ? AppColors.accentYellow
                                  : AppColors.textLight,
                              fontSize: 12,
                            ),
                          ),
                          if (_isTermsLoading)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.accentYellow,
                                ),
                              ),
                            ),
                          if (_termsErrorMessage.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                _termsErrorMessage,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.accentYellow,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              bottom: mediaQuery.padding.bottom + 16,
              left: 24,
              right: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_errorMessage != null) ...[
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.accentYellow),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                  ],
                  PremiumButton(
                    text: "Register",
                    isEnabled: _isFormValid && _hasAcceptedTerms && !isLoading,
                    isLoading: isLoading,
                    onPressed: _isFormValid && _hasAcceptedTerms && !isLoading
                        ? _register
                        : null,
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => Navigator.of(context).pop(),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(
                      Icons.arrow_back,
                      color: AppColors.accentYellow,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
