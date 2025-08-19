import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../widgets/input_box.dart';
import '../widgets/button.dart';
import '../config/api_endpoints.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

Future<String> showSetPinDialog(
  BuildContext context,
  String phoneNumber,
  bool isReset,
) async {
  TextEditingController pinController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final storage = const FlutterSecureStorage();
  String? errorText;
  bool isLoading = false;

  return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              Future<void> submitPin() async {
                if (!_formKey.currentState!.validate()) return;

                setState(() => isLoading = true);

                final response = await http.post(
                  Uri.parse(ApiEndpoints.setPin),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'phone_number': phoneNumber,
                    'pin': pinController.text,
                  }),
                );

                setState(() => isLoading = false);

                if (response.statusCode == 200) {
                  final data = jsonDecode(response.body);
                  await storage.write(key: 'pin', value: pinController.text);
                  if (isReset) {
                    // If it's a reset flow, navigate to the login screen
                    Navigator.of(dialogContext).pop();
                    Navigator.of(dialogContext).pushReplacementNamed('/login');
                  } else {
                    Navigator.of(dialogContext).pop(data['access_token']);
                  }
                } else {
                  final errorData = jsonDecode(response.body);
                  setState(() {
                    errorText = errorData['message'] ?? 'Something went wrong';
                  });
                }
              }

              return AlertDialog(
                backgroundColor: AppColors.primaryMaroon,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: Text(isReset ? 'Reset PIN' : 'Enter PIN',style: TextStyle(color: AppColors.accentYellow)),
                content: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PremiumInputBox(
                        controller: pinController,
                        label: "PIN (6 digits)",
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        isPassword: true,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          if (value == null || value.length != 6)
                            return 'Enter a valid 6-digit PIN';
                          return null;
                        },
                      ),
                      if (errorText != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            errorText!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  PremiumButton(
                    text: "Set Pin",
                    isEnabled: !isLoading,
                    isLoading: isLoading,
                    onPressed: submitPin,
                  ),
                ],
              );
            },
          );
        },
      ) ??
      '';
}
