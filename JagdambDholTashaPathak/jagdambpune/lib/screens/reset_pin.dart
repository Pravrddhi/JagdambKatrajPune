import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_endpoints.dart';
import '../components/get_device_id.dart';
import '../services/bug_report_service.dart';
import '../widgets/setpin_dialog.dart';
import '../widgets/common_button.dart';
import '../widgets/input_box.dart';
import '../theme/app_colors.dart';
import 'package:flutter/services.dart';

class ResetPinScreen extends StatefulWidget {
  const ResetPinScreen({super.key});

  @override
  State<ResetPinScreen> createState() => _ResetPinScreenState();
}

class _ResetPinScreenState extends State<ResetPinScreen> {
  final TextEditingController phoneController =
      TextEditingController(); // Controller for phone input
  bool isLoading = false; // Loading indicator
  String errorMessage = ''; // Error message display string
  bool _isPhoneNumberValid = false; // Tracks if phone input length is valid

  @override
  void initState() {
    super.initState();
    phoneController.addListener(
      _validatePhoneNumber,
    ); // Validate phone length on input changes
  }

  @override
  void dispose() {
    // Remove listener and dispose controller to prevent memory leaks
    phoneController.removeListener(_validatePhoneNumber);
    phoneController.dispose();
    super.dispose();
  }

  /// Validates whether phone number has 10 digits and updates UI state
  void _validatePhoneNumber() {
    final isValid = phoneController.text.length == 10;
    if (isValid != _isPhoneNumberValid) {
      setState(() {
        _isPhoneNumberValid = isValid;
        if (isValid) errorMessage = ''; // Clear error if input now valid
      });
    }
  }

  /// Calls API to verify device and phone number combination, then proceeds
  Future<void> verifyAndProceed() async {
    final phoneNumber = phoneController.text.trim();

    // Basic validation check before API call
    if (phoneNumber.isEmpty || phoneNumber.length < 10) {
      setState(() => errorMessage = "Enter valid phone number");
      return;
    }

    setState(() {
      isLoading = true; // Show spinner during API call
      errorMessage = ''; // Clear previous error
    });

    final deviceId = await getDeviceId(); // Obtain unique device id
    print(deviceId);

    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.verifyDevicePhone),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"device_id": deviceId, "phone_number": phoneNumber}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Verification successful, proceed to set PIN dialog
        print(data);
        Navigator.pop(context); // Close current screen
        showSetPinDialog(context, phoneNumber, true);
      } else {
        // API returned error, show message if present
        await BugReportService.reportApiFailure(
          title: 'Verify device phone API failed',
          errorMessage: response.body,
          pageUrl: '/reset-pin',
          statusCode: response.statusCode,
          endpoint: ApiEndpoints.verifyDevicePhone,
        );
        setState(() {
          errorMessage = ApiEndpoints.genericApiFailureMessage;
        });
      }
    } catch (e) {
      // Network or parsing error
      await BugReportService.reportApiFailure(
        title: 'Verify device phone API exception',
        errorMessage: e.toString(),
        pageUrl: '/reset-pin',
        endpoint: ApiEndpoints.verifyDevicePhone,
      );
      setState(() {
        errorMessage = ApiEndpoints.genericApiFailureMessage;
      });
    } finally {
      // Stop loading spinner whether success or failure
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Reset PIN")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "Enter your registered phone number to reset your PIN.",
                style: TextStyle(color: AppColors.accentYellow),
              ),
              const SizedBox(height: 20),

              // Phone number input box
              PremiumInputBox(
                controller: phoneController,
                label: "Phone Number",
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                errorText: errorMessage.isNotEmpty ? errorMessage : null,
              ),

              const SizedBox(height: 20),

              // Verify button with loading state and disable if phone invalid
              PremiumButton(
                text: "Verify",
                isEnabled: _isPhoneNumberValid && !isLoading,
                isLoading: isLoading,
                backgroundColor: AppColors.accentYellow,
                onPressed: _isPhoneNumberValid ? verifyAndProceed : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
