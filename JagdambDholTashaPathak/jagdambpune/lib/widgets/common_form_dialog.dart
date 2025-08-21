import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class CommonDialogForm {
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
          insetPadding: const EdgeInsets.all(10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and Close button in same row
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
                      icon: const Icon(Icons.close, color: AppColors.primaryMaroon),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...fields,
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryMaroon,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () async {
                      await onSubmit();
                      Navigator.of(context).pop();
                    },
                    child: const Text(
                      "Submit",
                      style: TextStyle(color: AppColors.accentYellow),
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
