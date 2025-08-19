import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/app_colors.dart';
import '../widgets/input_box.dart';
import '../widgets/button.dart';
import '../widgets/dropDown.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:android_id/android_id.dart';
import 'home_screen.dart';
import '../config/api_endpoints.dart';
import 'package:flutter/services.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final FocusNode _phoneFocusNode = FocusNode();
  final errors = <String, String?>{};
  String? _errorMessage;
  String? selectedSex;
  String? selectedInstrument;
  bool _isCheckingPhone = false;
  bool _isFormValid = false;

  @override
  void initState() {
    super.initState();
    _firstNameController.addListener(_validateForm);
    _lastNameController.addListener(_validateForm);
    _phoneController.addListener(_validateForm);
    _phoneFocusNode.addListener(() {
      if (!_phoneFocusNode.hasFocus) {
        _checkPhoneNumberExists(_phoneController.text.trim());
      }
    });
  }

  void _validateForm() {
    final isValid =
        _firstNameController.text.trim().isNotEmpty &&
        _lastNameController.text.trim().isNotEmpty &&
        _phoneController.text.length == 10 &&
        selectedSex != null &&
        selectedInstrument != null &&
        _fieldErrors.values.every((error) => error == null);

    setState(() {
      _isFormValid = isValid;
    });
  }

  Map<String, String?> _fieldErrors = {};

  bool isLoading = false;
  bool _isNumeric(String s) {
    return RegExp(r'^\d+$').hasMatch(s);
  }

  Future<void> _checkPhoneNumberExists(String phoneNumber) async {
    if (phoneNumber.length != 10) return; // Basic validation

    setState(() {
      _isCheckingPhone = true;
      _fieldErrors['phone_number'] = null; // clear previous error
    });

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
        _fieldErrors['phone_number'] = "Error checking phone number.";
      }
    });
    _validateForm();
  }

  Future<String> _getDeviceId() async {
    final AndroidId androidIdPlugin = AndroidId();
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

  Future<void> _register() async {
    if (_firstNameController.text.trim().isEmpty) {
      errors['first_name'] = "First name is required.";
    }
    if (_lastNameController.text.trim().isEmpty) {
      errors['last_name'] = "Last name is required.";
    }
    if (_phoneController.text.length != 10 ||
        !_isNumeric(_phoneController.text)) {
      errors['phone_number'] = "Phone number must be 10 digits only.";
    }
    if (selectedSex == null) {
      errors['sex'] = "Please select a gender.";
    }
    if (selectedInstrument == null) {
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
        _fieldErrors.clear(); // Clear previous field errors
      });
    }
    @override
    void initState() {
      super.initState();
      _phoneFocusNode.addListener(() {
        if (!_phoneFocusNode.hasFocus) {
          _checkPhoneNumberExists(_phoneController.text.trim());
        }
      });
    }

    setState(() {
      isLoading = true;
      _errorMessage = null; // Clear any previous error
    });
    final response = await http.post(
      Uri.parse(ApiEndpoints.register),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "phone_number": _phoneController.text,
        "first_name": _firstNameController.text,
        "last_name": _lastNameController.text,
        "sex": selectedSex,
        "instrument": selectedInstrument,
        "device_id": await _getDeviceId(),
        "pathak_id": ApiEndpoints.pathak_id,
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
      final data = jsonDecode(response.body);
      setState(() {
        if (data != null &&
            data.containsKey('message') &&
            data['message'] is Map) {
          final messageMap = data['message'] as Map<String, dynamic>;

          // Get the first key's value
          final firstKey = messageMap.keys.first;
          final firstValue = messageMap[firstKey];

          // If it's a list, take the first item
          if (firstValue is List && firstValue.isNotEmpty) {
            _errorMessage = firstValue.first;
          } else {
            _errorMessage = firstValue.toString();
          }
        } else {
          _errorMessage = "Registration failed";
        }
      });
    }
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
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  color: AppColors.accentYellow,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(height: 8),

              Image.asset(
                'assets/logos/splash_logo.png',
                height: 120,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 32),

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
              PremiumInputBox(
                controller: _phoneController,
                label: "Phone Number",
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                focusNode: _phoneFocusNode,
              ),
              if (_fieldErrors['phone_number'] != null)
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
              PremiumDropDown(
                label: "Sex",
                value: selectedSex,
                options: ["Male", "Female", "Transgender"],
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
              PremiumDropDown(
                label: "Instrument",
                value: selectedInstrument,
                options: ["Dhol", "Tasha", "Dhwaj"],
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
              PremiumButton(
                text: "Register",
                isEnabled: _isFormValid && !isLoading,
                isLoading: isLoading,
                onPressed: _isFormValid && !isLoading
                    ? () {
                        _register();
                      }
                    : null,
              ),
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
