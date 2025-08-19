import 'package:flutter/material.dart';
import '../widgets/custom_dialog.dart';

class NotificationDialog {
  static void show(BuildContext context) {
    CustomDialog.show(
      context: context,
      title: "Add Notification",
      fields: [
        CustomDialogFormField(label: "Title", icon: Icons.title),
        CustomDialogFormField(label: "Message", icon: Icons.message),
        CustomDialogFormField(label: "Date", icon: Icons.calendar_today, isDate: true),
      ],
      onSubmit: (values) async {
        // Call your API to add notification here
        print(values);
      },
    );
  }
}
