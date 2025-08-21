import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../theme/app_colors.dart';
import '../config/api_endpoints.dart';
import '../widgets/common_form_dialog.dart';

class NotificationForm {
  static Future<void> open(BuildContext context) {
    final titleController = TextEditingController();
    final messageController = TextEditingController();

    return CommonDialogForm.show(
      context: context,
      title: "Add Notification",
      fields: [
        TextFormField(
          controller: titleController,
          decoration: const InputDecoration(
            labelText: "Title",
            prefixIcon: Icon(Icons.title, color: AppColors.primaryMaroon),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: messageController,
          decoration: const InputDecoration(
            labelText: "Message",
            prefixIcon: Icon(Icons.message, color: AppColors.primaryMaroon),
            border: OutlineInputBorder(),
          ),
        ),
      ],
      onSubmit: () async {
        String? accessToken =
            await const FlutterSecureStorage().read(key: 'access_token');

        final url = Uri.parse(ApiEndpoints.createNotification);
        final headers = {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        };
        final body = jsonEncode({
          "target_type": "broadcast",
          "title": titleController.text,
          "message": messageController.text,
        });

        final response = await http.post(url, headers: headers, body: body);
        if (response.statusCode == 200 || response.statusCode == 201) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Notification added successfully!")),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed: ${response.statusCode} ${response.body}")),
          );
        }
      },
    );
  }
}
