import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../widgets/input_box.dart';
import 'common_button.dart';
import '../config/api_endpoints.dart';
import '../services/bug_report_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Opens a blocking dialog to set or reset a 6-digit PIN.
///
/// Returns the new access token for first-time PIN setup flows.
Future<String> showSetPinDialog(
  BuildContext context,
  String phoneNumber, {
  required bool isResetFlow,
}) async {
  final pinController = TextEditingController();
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  const storage = FlutterSecureStorage();
  String? errorText;
  bool isLoading = false;

  return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              Future<void> submitPin() async {
                if (!formKey.currentState!.validate()) return;

                setState(() => isLoading = true);

                try {
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
                    // Reset flow only confirms PIN update and sends the user
                    // back to login. Registration flow receives fresh tokens.
                    if (isResetFlow) {
                      Navigator.of(dialogContext).pop();
                      Navigator.of(
                        dialogContext,
                      ).pushReplacementNamed('/login');
                    } else {
                      await storage.write(
                        key: 'access_token',
                        value: data['access_token'],
                      );
                      await storage.write(
                        key: 'refresh_token',
                        value: data['refresh_token'],
                      );
                      Navigator.of(dialogContext).pop(data['access_token']);
                    }
                  } else {
                    await BugReportService.reportApiFailure(
                      title: 'Set PIN API failed',
                      errorMessage: response.body,
                      pageUrl: '/set-pin',
                      statusCode: response.statusCode,
                      endpoint: ApiEndpoints.setPin,
                    );
                    setState(() {
                      errorText = ApiEndpoints.genericApiFailureMessage;
                    });
                  }
                } catch (e) {
                  await BugReportService.reportApiFailure(
                    title: 'Set PIN API exception',
                    errorMessage: e.toString(),
                    pageUrl: '/set-pin',
                    endpoint: ApiEndpoints.setPin,
                  );
                  setState(() {
                    isLoading = false;
                    errorText = ApiEndpoints.genericApiFailureMessage;
                  });
                }
              }

              return AlertDialog(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: Text(
                  isResetFlow ? 'Reset PIN' : 'Set PIN',
                  style: const TextStyle(color: AppColors.primaryMaroon),
                ),
                content: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PremiumInputBox(
                        controller: pinController,
                        label: "PIN (6 digits)",
                        useLightStyle: true,
                        isPin: true,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        isPassword: true,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          if (value == null || value.length != 6) {
                            return 'Enter a valid 6-digit PIN';
                          }
                          return null;
                        },
                      ),
                      if (errorText != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            errorText!,
                            style: const TextStyle(
                              color: AppColors.primaryMaroon,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  PremiumButton(
                    text: "Set PIN",
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
