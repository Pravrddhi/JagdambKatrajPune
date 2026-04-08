import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:jagdhambtrustpune/config/api_endpoints.dart';
import 'package:jagdhambtrustpune/services/bug_report_service.dart';
import 'package:jagdhambtrustpune/theme/app_colors.dart';
import 'package:jagdhambtrustpune/services/authorized_api_service.dart';
import '../widgets/input_box.dart'; // import your custom input box
import '../widgets/dropdown.dart';

class EmergencyContactDialog {
  static Future<void> show(BuildContext context, String token) async {
    final formKey = GlobalKey<FormState>();
    TextEditingController nameController = TextEditingController();
    TextEditingController phoneController = TextEditingController();
    String? selectedBloodGroup;
    bool isLoading = false;

    List<String> bloodGroups = [
      "A+",
      "A-",
      "B+",
      "B-",
      "O+",
      "O-",
      "AB+",
      "AB-",
    ];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // Remove viewInsets so the keyboard never pushes the dialog.
            // The dialog is scrollable internally so content stays reachable.
            return MediaQuery.removeViewInsets(
              context: context,
              removeBottom: true,
              child: AlertDialog(
                backgroundColor: Colors.white,
                titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                contentPadding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
                actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                title: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.accentYellow.withAlpha(70),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.health_and_safety_rounded,
                        color: AppColors.primaryMaroon,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        "Emergency Details",
                        style: TextStyle(
                          color: AppColors.primaryMaroon,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 400),
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Keep these details up to date for emergencies.",
                            style: TextStyle(
                              color: AppColors.primaryMaroon,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Custom input box for name
                          PremiumInputBox(
                            controller: nameController,
                            label: "Emergency Name",
                            useLightStyle: true,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[a-zA-Z\s]'),
                              ),
                            ],
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return "Emergency Name is required.";
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),
                          // Custom input box for phone
                          PremiumInputBox(
                            controller: phoneController,
                            label: "Emergency Phone",
                            useLightStyle: true,
                            keyboardType: TextInputType.phone,
                            maxLength: 10,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return "Emergency Phone is required.";
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),
                          // Dropdown for blood group
                          PremiumDropdown(
                            value: selectedBloodGroup,
                            label: "Select Blood Group",
                            options: bloodGroups,
                            backgroundColor: Colors.white,
                            labelColor: AppColors.primaryMaroon,
                            textColor: AppColors.primaryMaroon,
                            dropdownMenuColor: Colors.white,
                            onChanged: (value) {
                              setState(() {
                                selectedBloodGroup = value;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isLoading
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: AppColors.primaryMaroon),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: isLoading
                        ? null
                        : () async {
                            if (formKey.currentState!.validate()) {
                              setState(() {
                                isLoading = true;
                              });

                              bool success = await _submitEmergencyContact(
                                nameController.text.trim(),
                                phoneController.text.trim(),
                                selectedBloodGroup!,
                                token,
                              );

                              setState(() {
                                isLoading = false;
                              });

                              if (success) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "Emergency contact updated successfully",
                                      selectionColor: AppColors.accentYellow,
                                    ),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      ApiEndpoints.genericApiFailureMessage,
                                      selectionColor: AppColors.accentYellow,
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentYellow,
                      foregroundColor: AppColors.primaryMaroon,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    icon: isLoading
                        ? const SizedBox(
                            height: 14,
                            width: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline, size: 16),
                    label: Text(isLoading ? 'Updating...' : 'Update'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // API call with token
  static Future<bool> _submitEmergencyContact(
    String name,
    String phone,
    String bloodGroup,
    String token,
  ) async {
    final url = Uri.parse(ApiEndpoints.getEmergencyContacts);

    try {
      final response = await AuthorizedApiService.sendWithAutoRefresh(
        token,
        (accessToken) => http.put(
          url,
          headers: ApiEndpoints.authorizedHeaders(accessToken),
          body: jsonEncode({
            "emergency_contact_name": name,
            "emergency_contact_phone": phone,
            "blood_group": bloodGroup,
          }),
        ),
      );

      if (response == null) {
        return false;
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data["success"] == true;
      }

      await BugReportService.reportApiFailure(
        title: 'Emergency contact update API failed',
        errorMessage: response.body,
        pageUrl: '/emergency-contact',
        statusCode: response.statusCode,
        endpoint: ApiEndpoints.getEmergencyContacts,
      );
      return false;
    } catch (e) {
      await BugReportService.reportApiFailure(
        title: 'Emergency contact update API exception',
        errorMessage: e.toString(),
        pageUrl: '/emergency-contact',
        endpoint: ApiEndpoints.getEmergencyContacts,
      );
      return false;
    }
  }
}
