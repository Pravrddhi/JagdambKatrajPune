import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// A reusable common dialog form widget.
/// Accepts a list of input fields and a submit callback.
class CommonDialogForm {
  /// Shows a dialog with a customizable title, input fields, and a submit button.
  ///
  /// - [context] BuildContext to display the dialog.
  /// - [title] Title text shown at top.
  /// - [fields] List of input field widgets shown in the dialog.
  /// - [onSubmit] Async callback executed when submit button is pressed.
  ///
  /// Returns a Future that resolves when the dialog is closed.
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required List<Widget> fields,
    required Future<void> Function() onSubmit,
  }) {
    return showDialog<T>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(10), // Padding around dialog edges
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12), // Rounded corners
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row with close button aligned right
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryMaroon,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: AppColors.primaryMaroon,
                      ),
                      onPressed: () {
                        Navigator.of(context).pop(); // Close dialog on icon tap
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Insert all field widgets provided in the fields list
                ...fields,
                const SizedBox(height: 12),
                // Submit button row with full width
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentYellow,
                      foregroundColor: AppColors.primaryMaroon,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () async {
                      await onSubmit(); // Await async submit callback
                      Navigator.of(context).pop(); // Close dialog after submit
                    },
                    child: const Text(
                      "Submit",
                      style: TextStyle(color: AppColors.primaryMaroon),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
