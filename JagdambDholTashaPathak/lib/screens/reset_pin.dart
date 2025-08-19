import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_endpoints.dart';
import '../components/get_device_id.dart';
import '../widgets/setpin_dialog.dart';
import '../widgets/button.dart';
import '../widgets/input_box.dart';
import '../theme/app_colors.dart';
import 'package:flutter/services.dart';


class ResetPinScreen extends StatefulWidget {
  const ResetPinScreen({Key? key}) : super(key: key);

  @override
  State<ResetPinScreen> createState() => _ResetPinScreenState();
}

class _ResetPinScreenState extends State<ResetPinScreen> {
  final TextEditingController phoneController = TextEditingController();
  bool isLoading = false;
  String errorMessage = '';
  bool _isPhoneNumberValid = false;

  @override
  void initState() {
    super.initState();
    phoneController.addListener(_validatePhoneNumber);
  }

  @override
  void dispose() {
    phoneController.removeListener(_validatePhoneNumber);
    phoneController.dispose();
    super.dispose();
  }

  void _validatePhoneNumber() {
    final isValid = phoneController.text.length == 10;
    if (isValid != _isPhoneNumberValid) {
      setState(() {
        _isPhoneNumberValid = isValid;
        if (isValid) errorMessage = '';
      });
    }
  }

  Future<void> verifyAndProceed() async {
    final phoneNumber = phoneController.text.trim();
    if (phoneNumber.isEmpty || phoneNumber.length < 10) {
      setState(() => errorMessage = "Enter valid phone number");
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    final deviceId = await getDeviceId();

    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.verifyDevicePhone),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "device_id": deviceId,
          "phone_number": phoneNumber,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        Navigator.pop(context); // Close current screen
        showSetPinDialog(context, phoneNumber, true);
      } else {
        setState(() {
          errorMessage = data['message'] ?? "Device and phone do not match";
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = "Network error. Please try again.";
      });
    } finally {
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

            PremiumInputBox(
              controller: phoneController,
              label: "Phone Number",
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              errorText: errorMessage.isEmpty ? null : errorMessage,
            ),

            const SizedBox(height: 20),

            PremiumButton(
              text: "Verify",
              isEnabled: _isPhoneNumberValid && !isLoading,
              isLoading: isLoading,
              backgroundColor: AppColors.primaryMaroon, // ✅ updated
              onPressed: _isPhoneNumberValid ? verifyAndProceed : null,
            ),
          ],
        ),
      ),
      ),
    );
  }
}
