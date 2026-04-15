import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../config/api_endpoints.dart';
import '../services/bug_report_service.dart';
import '../widgets/set_pin_dialog.dart';
import '../widgets/common_button.dart';
import '../widgets/input_box.dart';
import '../theme/app_colors.dart';

class ResetPinScreen extends StatefulWidget {
  const ResetPinScreen({super.key});

  @override
  State<ResetPinScreen> createState() => _ResetPinScreenState();
}

class _ResetPinScreenState extends State<ResetPinScreen> {
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController adhaarController = TextEditingController();

  bool isLoading = false;
  String errorMessage = '';
  bool _isPhoneNumberValid = false;
  bool _isAdhaarValid = false;
  bool _isCheckingPhone = false;
  bool _isPhoneRegistered = false;
  String? _lastCheckedPhone;

  // Flow state: 'verify', 'confirm'
  String _currentStep = 'verify';
  Map<String, dynamic>? _verifiedUserDetails;

  @override
  void initState() {
    super.initState();
    phoneController.addListener(_validatePhoneNumber);
    adhaarController.addListener(_validateAdhaarNumber);
  }

  @override
  void dispose() {
    phoneController.removeListener(_validatePhoneNumber);
    adhaarController.removeListener(_validateAdhaarNumber);
    phoneController.dispose();
    adhaarController.dispose();
    super.dispose();
  }

  void _validatePhoneNumber() {
    final phone = phoneController.text.trim();
    final isValid = phone.length == 10;

    if (isValid != _isPhoneNumberValid) {
      setState(() {
        _isPhoneNumberValid = isValid;
        if (isValid) {
          errorMessage = '';
        } else {
          _isPhoneRegistered = false;
          _lastCheckedPhone = null;
        }
      });
    }

    if (isValid && phone != _lastCheckedPhone) {
      _checkPhoneNumberExists(phone);
    }
  }

  void _validateAdhaarNumber() {
    final adhaar = adhaarController.text.trim();
    final isValid = adhaar.length == 4;

    if (isValid != _isAdhaarValid) {
      setState(() {
        _isAdhaarValid = isValid;
        if (isValid) {
          errorMessage = '';
        }
      });
    }
  }

  Future<void> _checkPhoneNumberExists(String phoneNumber) async {
    if (phoneNumber.length != 10 || _isCheckingPhone) return;

    setState(() {
      _isCheckingPhone = true;
      _isPhoneRegistered = false;
      errorMessage = '';
    });

    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.checkPhoneNumber),
        headers: ApiEndpoints.jsonHeaders(),
        body: jsonEncode({
          'phone_number': phoneNumber,
          'pathak_id': ApiEndpoints.pathakIdInt,
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final exists = data['status'] == true;
        setState(() {
          _lastCheckedPhone = phoneNumber;
          _isPhoneRegistered = exists;
          if (!exists) {
            errorMessage = 'Phone number not registered.';
          }
        });
      } else {
        await BugReportService.reportApiFailure(
          title: 'Check phone number API failed for reset pin',
          errorMessage: response.body,
          pageUrl: '/reset-pin',
          statusCode: response.statusCode,
          endpoint: ApiEndpoints.checkPhoneNumber,
        );
        setState(() {
          _isPhoneRegistered = false;
          errorMessage = ApiEndpoints.genericApiFailureMessage;
        });
      }
    } catch (e) {
      await BugReportService.reportApiFailure(
        title: 'Check phone number API exception for reset pin',
        errorMessage: e.toString(),
        pageUrl: '/reset-pin',
        endpoint: ApiEndpoints.checkPhoneNumber,
      );
      if (!mounted) return;
      setState(() {
        _isPhoneRegistered = false;
        errorMessage = ApiEndpoints.genericApiFailureMessage;
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isCheckingPhone = false;
      });
    }
  }

  Map<String, dynamic> _buildEnteredUserDetails() {
    final phone = phoneController.text.trim();
    final adhaar = adhaarController.text.trim();
    return {
      'phone_number': '+91$phone',
      'name': 'Verified user',
      'adhaar_number': adhaar,
    };
  }

  Future<Map<String, dynamic>?> _checkPhoneAdhaarMatch({
    required String phoneNumber,
    required String adhaarNumber,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.checkAdhaarNumber),
        headers: ApiEndpoints.jsonHeaders(),
        body: jsonEncode({
          'phone_number': phoneNumber,
          'adhaar_number': int.parse(adhaarNumber),
          'pathak_id': ApiEndpoints.pathakIdInt,
        }),
      );

      if (response.statusCode != 200) {
        await BugReportService.reportApiFailure(
          title: 'Verify phone + Aadhaar match API failed',
          errorMessage: response.body,
          pageUrl: '/reset-pin',
          statusCode: response.statusCode,
          endpoint: ApiEndpoints.checkAdhaarNumber,
        );
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final isMatch = data['status'] == true;
      if (!isMatch) {
        setState(() {
          errorMessage =
              data['message']?.toString() ??
              'Phone number and Aadhaar details do not match.';
        });
        return null;
      }

      final dynamic user = data['user'] ?? data['user_details'] ?? data['data'];
      if (user is Map<String, dynamic>) {
        return user;
      }
      return _buildEnteredUserDetails();
    } catch (e) {
      await BugReportService.reportApiFailure(
        title: 'Verify phone + Aadhaar match API exception',
        errorMessage: e.toString(),
        pageUrl: '/reset-pin',
        endpoint: ApiEndpoints.checkAdhaarNumber,
      );
      setState(() {
        errorMessage = ApiEndpoints.genericApiFailureMessage;
      });
      return null;
    }
  }

  String _maskPhoneNumber(String rawPhone) {
    final digits = rawPhone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return rawPhone;

    final last4 = digits.substring(digits.length - 4);
    if (digits.length == 10) {
      return '+91******$last4';
    }
    final maskedPrefix = '*' * (digits.length - 4);
    return '$maskedPrefix$last4';
  }

  Future<void> _verifyUserDetails() async {
    final phoneNumber = phoneController.text.trim();
    final adhaarNumber = adhaarController.text.trim();

    if (phoneNumber.isEmpty || phoneNumber.length < 10) {
      setState(() => errorMessage = 'Enter valid phone number');
      return;
    }

    if (adhaarNumber.isEmpty || adhaarNumber.length < 4) {
      setState(() => errorMessage = 'Enter valid Aadhaar last 4 digits');
      return;
    }

    if (!_isPhoneRegistered) {
      setState(() => errorMessage = 'Phone number not registered.');
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    final matchedUser = await _checkPhoneAdhaarMatch(
      phoneNumber: phoneNumber,
      adhaarNumber: adhaarNumber,
    );

    if (!mounted) return;

    if (matchedUser == null) {
      setState(() {
        isLoading = false;
      });
      return;
    }

    setState(() {
      _verifiedUserDetails = matchedUser;
      _currentStep = 'confirm';
      isLoading = false;
    });
  }

  Future<void> _confirmUserAndResetPin(bool isCorrectUser) async {
    if (!isCorrectUser) {
      setState(() {
        _currentStep = 'verify';
        _verifiedUserDetails = null;
        errorMessage = '';
      });
      return;
    }

    await showSetPinDialog(
      context,
      phoneController.text.trim(),
      isResetFlow: true,
      adhaarNumber: adhaarController.text.trim(),
    );
  }

  void _goBack() {
    if (_currentStep == 'confirm') {
      setState(() {
        _currentStep = 'verify';
        errorMessage = '';
      });
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset PIN'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goBack,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Center(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _currentStep == 'verify'
                  ? _buildVerifyStep()
                  : _buildConfirmStep(),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildVerifyStep() {
    return [
      const Text(
        'Enter your registered phone number and Aadhaar last 4 digits.',
        style: TextStyle(color: AppColors.primaryMaroon, fontSize: 14),
      ),
      const SizedBox(height: 20),
      PremiumInputBox(
        controller: phoneController,
        label: 'Phone Number',
        keyboardType: TextInputType.phone,
        maxLength: 10,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        errorText: errorMessage.isNotEmpty ? errorMessage : null,
      ),
      const SizedBox(height: 12),
      PremiumInputBox(
        controller: adhaarController,
        label: 'Aadhaar (Last 4 Digits)',
        keyboardType: TextInputType.number,
        maxLength: 4,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
      if (_isCheckingPhone)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text(
                'Checking phone number...',
                style: TextStyle(color: AppColors.primaryMaroon, fontSize: 12),
              ),
            ],
          ),
        ),
      const SizedBox(height: 20),
      PremiumButton(
        text: 'Verify Details',
        isEnabled:
            _isPhoneNumberValid &&
            _isAdhaarValid &&
            _isPhoneRegistered &&
            !_isCheckingPhone &&
            !isLoading,
        isLoading: isLoading,
        backgroundColor: AppColors.accentYellow,
        onPressed:
            (_isPhoneNumberValid &&
                _isAdhaarValid &&
                _isPhoneRegistered &&
                !_isCheckingPhone)
            ? _verifyUserDetails
            : null,
      ),
    ];
  }

  List<Widget> _buildConfirmStep() {
    final user = _verifiedUserDetails ?? const <String, dynamic>{};
    final name =
        user['full_name']?.toString() ??
        user['name']?.toString() ??
        user['first_name']?.toString() ??
        'N/A';
    final phone =
        user['phone_number']?.toString() ?? '+91${phoneController.text.trim()}';
    final maskedPhone = _maskPhoneNumber(phone);
    final adhaarLast4 =
        user['adhaar_number']?.toString() ?? adhaarController.text.trim();

    return [
      const Text(
        'Is this your account?',
        style: TextStyle(
          color: AppColors.primaryMaroon,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primaryMaroon.withAlpha(90)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Name: $name',
              style: const TextStyle(color: AppColors.primaryMaroon),
            ),
            const SizedBox(height: 6),
            Text(
              'Phone: $maskedPhone',
              style: const TextStyle(color: AppColors.primaryMaroon),
            ),
            const SizedBox(height: 6),
            Text(
              'Aadhaar (Last 4): $adhaarLast4',
              style: const TextStyle(color: AppColors.primaryMaroon),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      PremiumButton(
        text: 'Yes, this is me',
        isEnabled: !isLoading,
        isLoading: false,
        backgroundColor: AppColors.accentYellow,
        onPressed: () => _confirmUserAndResetPin(true),
      ),
      const SizedBox(height: 12),
      PremiumButton(
        text: 'No, go back',
        isEnabled: !isLoading,
        isLoading: false,
        backgroundColor: AppColors.primaryMaroon,
        textColor: Colors.white,
        onPressed: () => _confirmUserAndResetPin(false),
      ),
    ];
  }
}
