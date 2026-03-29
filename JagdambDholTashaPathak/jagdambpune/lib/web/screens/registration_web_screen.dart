import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../components/get_device_id.dart';
import '../../config/api_endpoints.dart';
import '../../services/bug_report_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common_button.dart';
import '../../widgets/drop_down.dart';
import '../../widgets/input_box.dart';
import '../../screens/home_screen.dart';

class RegistrationWebScreen extends StatefulWidget {
  const RegistrationWebScreen({super.key});

  @override
  State<RegistrationWebScreen> createState() => _RegistrationWebScreenState();
}

class _RegistrationWebScreenState extends State<RegistrationWebScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final FocusNode _phoneFocusNode = FocusNode();

  Map<String, String?> errors = {};
  Map<String, String?> _fieldErrors = {};
  String? _errorMessage;

  String? selectedSex;
  String? selectedInstrument;

  bool _isCheckingPhone = false;
  bool _isFormValid = false;
  bool isLoading = false;

  List<String> _instruments = [];
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();

    _firstNameController.addListener(_validateForm);
    _lastNameController.addListener(_validateForm);
    _phoneController.addListener(_validateForm);

    _loadInstruments();

    _phoneController.addListener(() {
      _onPhoneChanged(_phoneController.text.trim());
    });
    _phoneFocusNode.addListener(() {
      if (!_phoneFocusNode.hasFocus) {
        _checkPhoneNumberExists(_phoneController.text.trim());
      }
    });
  }

  void _onPhoneChanged(String value) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (value.length == 10) {
        _checkPhoneNumberExists(value);
      }
    });
  }

  Future<List<String>> _fetchInstruments(int pathakId) async {
    final url = Uri.parse("${ApiEndpoints.getInstruments}/$pathakId");
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data["status"] == true) {
          List<dynamic> instruments = data["instruments"];
          return instruments.map((e) => e.toString()).toList();
        }
        return [];
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

  void _loadInstruments() async {
    int pathakId = int.tryParse(ApiEndpoints.pathakId.toString()) ?? 0;
    if (pathakId == 0) return;

    List<String> instruments = await _fetchInstruments(pathakId);
    setState(() {
      _instruments = instruments;
    });
  }

  void _validateForm() {
    final isValid =
        validateFirstName(_firstNameController.text) &&
        validateLastName(_lastNameController.text) &&
        validatePhone(_phoneController.text) &&
        validateSelection(selectedSex) &&
        validateSelection(selectedInstrument) &&
        _fieldErrors.values.every((error) => error == null);

    setState(() {
      _isFormValid = isValid;
    });
  }

  bool validateFirstName(String firstName) => firstName.trim().isNotEmpty;
  bool validateLastName(String lastName) => lastName.trim().isNotEmpty;
  bool validatePhone(String phone) => RegExp(r'^\d{10}$').hasMatch(phone);
  bool validateSelection(String? value) => value != null;

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
            _fieldErrors['phone_number'] = 'Phone number already registered.';
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

  Future<void> _register() async {
    errors.clear();

    if (!validateFirstName(_firstNameController.text)) {
      errors['first_name'] = 'First name is required.';
    }
    if (!validateLastName(_lastNameController.text)) {
      errors['last_name'] = 'Last name is required.';
    }
    if (!validatePhone(_phoneController.text)) {
      errors['phone_number'] = 'Phone number must be 10 digits only.';
    }
    if (!validateSelection(selectedSex)) {
      errors['sex'] = 'Please select a gender.';
    }
    if (!validateSelection(selectedInstrument)) {
      errors['instrument'] = 'Please select an instrument.';
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
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone_number': _phoneController.text,
          'first_name': _firstNameController.text,
          'last_name': _lastNameController.text,
          'gender': selectedSex,
          'instrument': selectedInstrument,
          'device_id': await getDeviceId(),
          'pathak_id': ApiEndpoints.pathakId,
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

  @override
  void dispose() {
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
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 30,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      color: AppColors.primaryMaroon,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Image.asset(
                    'assets/logos/splash_logo.png',
                    height: 110,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Registration',
                    style: TextStyle(
                      color: AppColors.primaryMaroon,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  PremiumInputBox(
                    controller: _firstNameController,
                    label: 'First Name',
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                    ],
                    useLightStyle: true,
                  ),
                  if (_fieldErrors['first_name'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0, left: 4.0),
                      child: Text(
                        _fieldErrors['first_name']!,
                        style: const TextStyle(
                          color: AppColors.errorRed,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  PremiumInputBox(
                    controller: _lastNameController,
                    label: 'Last Name',
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                    ],
                    useLightStyle: true,
                  ),
                  if (_fieldErrors['last_name'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0, left: 4.0),
                      child: Text(
                        _fieldErrors['last_name']!,
                        style: const TextStyle(
                          color: AppColors.errorRed,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  PremiumInputBox(
                    controller: _phoneController,
                    label: 'Phone Number',
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    focusNode: _phoneFocusNode,
                    useLightStyle: true,
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
                                AppColors.primaryMaroon,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Checking phone number...',
                            style: TextStyle(
                              color: AppColors.primaryMaroon,
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
                          color: AppColors.errorRed,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  PremiumDropDown(
                    label: 'Gender',
                    value: selectedSex,
                    options: const ['Male', 'Female', 'Other'],
                    onChanged: (val) {
                      setState(() {
                        selectedSex = val;
                      });
                      _validateForm();
                    },
                    backgroundColor: Colors.white,
                    labelColor: AppColors.primaryMaroon,
                    textColor: AppColors.primaryMaroon,
                    dropdownMenuColor: Colors.white,
                  ),
                  if (_fieldErrors['sex'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0, left: 4.0),
                      child: Text(
                        _fieldErrors['sex']!,
                        style: const TextStyle(
                          color: AppColors.errorRed,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  PremiumDropDown(
                    label: 'Instrument',
                    value: selectedInstrument,
                    options: _instruments,
                    onChanged: (val) {
                      setState(() {
                        selectedInstrument = val;
                      });
                      _validateForm();
                    },
                    backgroundColor: Colors.white,
                    labelColor: AppColors.primaryMaroon,
                    textColor: AppColors.primaryMaroon,
                    dropdownMenuColor: Colors.white,
                  ),
                  if (_fieldErrors['instrument'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0, left: 4.0),
                      child: Text(
                        _fieldErrors['instrument']!,
                        style: const TextStyle(
                          color: AppColors.errorRed,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  PremiumButton(
                    text: 'Register',
                    isEnabled: _isFormValid && !isLoading,
                    isLoading: isLoading,
                    onPressed: _isFormValid && !isLoading ? _register : null,
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.errorRed),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
