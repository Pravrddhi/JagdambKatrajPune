import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:jagdhambtrustpune/config/api_endpoints.dart';
import 'package:jagdhambtrustpune/theme/app_colors.dart';
import '../widgets/button.dart';
import '../widgets/input_box.dart'; // import your custom input box
import '../widgets/dropDown.dart';

class EmergencyContactDialog {
  static Future<void> show(BuildContext context,String token) async {
    final formKey = GlobalKey<FormState>();
    TextEditingController nameController = TextEditingController();
    TextEditingController phoneController = TextEditingController();
    String? selectedBloodGroup;
    bool isLoading = false;

    List<String> bloodGroups = ["A+", "A-", "B+", "B-", "O+", "O-", "AB+", "AB-"];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: AppColors.primaryMaroon,
              title: Text("Emergency Details", style: TextStyle(color: AppColors.accentYellow)),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Custom input box for name
                      PremiumInputBox(
                        controller: nameController,
                        label: "Emergency Name",
                        inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                          ],
                        validator: (value) {
                          if (value == null || value.isEmpty) return "Emergency Name is required.";
                          return null;
                        },
                      ),
                      SizedBox(height: 10),
                      // Custom input box for phone
                      PremiumInputBox(
                        controller: phoneController,
                        label: "Emergency Phone",
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (value) {
                          if (value == null || value.isEmpty) return "Emergency Phone is required.";
                          return null;
                        },
                      ),
                      SizedBox(height: 10),
                      // Dropdown for blood group
                      PremiumDropDown(
                        value: selectedBloodGroup,
                        label: "Select Blood Group",
                        options: bloodGroups,
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
              actions: [
                PremiumButton(
                  text: "Update",
                  isEnabled: !isLoading,
                  backgroundColor: AppColors.accentYellow,
                  textColor: AppColors.primaryMaroon,
                  isLoading: isLoading,
                  onPressed: () async {
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
                          SnackBar(content: Text("Emergency contact updated successfully",selectionColor: AppColors.accentYellow,)),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Failed to update emergency contact",selectionColor: AppColors.accentYellow,)),
                        );
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // API call with token
  static Future<bool> _submitEmergencyContact(
      String name, String phone, String bloodGroup, String token) async {
    final url = Uri.parse(ApiEndpoints.getEmergencyContacts);

    try {
      final response = await http.put(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({
          "emergency_contact_name": name,
          "emergency_contact_phone": phone,
          "blood_group": bloodGroup,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data["success"] == true;
      }
      return false;
    } catch (e) {
      print("Error submitting emergency contact: $e");
      return false;
    }
  }
}
