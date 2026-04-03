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
        final mediaQuery = MediaQuery.of(context);
        final screenHeight = mediaQuery.size.height;
        final bottomInset = mediaQuery.viewInsets.bottom;
        const verticalInset = 10.0;
        final availableHeight =
            (screenHeight - bottomInset - (verticalInset * 2)).clamp(
              220.0,
              screenHeight,
            );

        return AlertDialog(
          insetPadding: const EdgeInsets.all(10),
          backgroundColor: Colors.white,
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryMaroon,
            ),
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: availableHeight),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [...fields],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentYellow,
                foregroundColor: AppColors.primaryMaroon,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () async {
                await onSubmit();
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text(
                'Submit',
                style: TextStyle(color: AppColors.primaryMaroon),
              ),
            ),
          ],
        );
      },
    );
  }
}
