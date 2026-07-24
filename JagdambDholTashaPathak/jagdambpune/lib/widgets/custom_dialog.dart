import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Defines a form field specification for the custom dialog
class CustomDialogFormField {
  final String label; // Label for the input
  final IconData? icon; // Optional icon prefix
  final bool requiredField; // Whether input is mandatory (default: true)
  final bool isDate; // Whether this field is a date picker
  final Function(dynamic)? onChanged; // Callback on value change
  final String? Function(String?)? validator; // Optional validator function

  CustomDialogFormField({
    required this.label,
    this.icon,
    this.requiredField = true,
    this.isDate = false,
    this.onChanged,
    this.validator,
  });
}

/// The custom dialog widget to display form fields and Submit button
class CustomDialog {
  /// Shows the dialog with given title, fields, and async onSubmit callback
  static Future<void> show({
    required BuildContext context,
    required String title,
    required List<CustomDialogFormField> fields,
    required Future<void> Function(Map<String, dynamic>) onSubmit,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) =>
          _CustomDialogForm(title: title, fields: fields, onSubmit: onSubmit),
    );
  }
}

/// Internal stateful widget implementing the dialog form UI
class _CustomDialogForm extends StatefulWidget {
  final String title;
  final List<CustomDialogFormField> fields;
  final Future<void> Function(Map<String, dynamic>) onSubmit;

  const _CustomDialogForm({
    required this.title,
    required this.fields,
    required this.onSubmit,
  });

  @override
  State<_CustomDialogForm> createState() => _CustomDialogFormState();
}

class _CustomDialogFormState extends State<_CustomDialogForm> {
  final _formKey = GlobalKey<FormState>(); // Form key to validate and save
  final Map<String, dynamic> values = {}; // Map storing current input values
  bool _isSubmitting = false; // Tracks submission/loading state

  /// Checks whether all required fields are valid and non-empty
  bool get _isFormValid {
    for (var field in widget.fields) {
      if (field.requiredField &&
          (values[field.label] == null ||
              values[field.label].toString().isEmpty)) {
        return false;
      }
      // For date fields, check value is DateTime and not in past
      if (field.isDate &&
          values[field.label] is DateTime &&
          (values[field.label] as DateTime).isBefore(DateTime.now())) {
        return false;
      }
    }
    return true;
  }

  /// Provides consistent input decoration per field with optional icon
  InputDecoration _inputDecoration(CustomDialogFormField field) {
    return InputDecoration(
      labelText: field.label,
      prefixIcon: field.icon != null
          ? Icon(field.icon, color: AppColors.primaryMaroon)
          : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primaryMaroon, width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final bottomInset = mediaQuery.viewInsets.bottom;
    final availableHeight = (screenHeight - bottomInset - 40).clamp(
      220.0,
      screenHeight,
    );

    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.white,
      title: Text(
        widget.title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: AppColors.primaryMaroon,
        ),
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: availableHeight),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var field in widget.fields) ...[
                  if (!field.isDate)
                    TextFormField(
                      decoration: _inputDecoration(field),
                      validator:
                          field.validator ??
                          (val) =>
                              field.requiredField &&
                                  (val == null || val.isEmpty)
                              ? 'Required'
                              : null,
                      onChanged: (val) {
                        values[field.label] = val;
                        setState(() {});
                        field.onChanged?.call(val);
                      },
                    ),
                  if (field.isDate)
                    _DatePickerField(
                      label: field.label,
                      icon: field.icon,
                      onChanged: (val) {
                        values[field.label] = val;
                        setState(() {});
                      },
                    ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isFormValid && !_isSubmitting
              ? () async {
                  setState(() => _isSubmitting = true);
                  await widget.onSubmit(values);
                  if (mounted) {
                    setState(() => _isSubmitting = false);
                    Navigator.pop(context);
                  }
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isFormValid
                ? AppColors.accentYellow
                : Colors.grey[400],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(
                  'Submit',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryMaroon,
                  ),
                ),
        ),
      ],
    );
  }
}

/// A text field that opens a date picker dialog when tapped, showing the chosen date, and validates it.
class _DatePickerField extends StatefulWidget {
  final String label;
  final IconData? icon;
  final Function(DateTime) onChanged;

  const _DatePickerField({
    required this.label,
    this.icon,
    required this.onChanged,
  });

  @override
  State<_DatePickerField> createState() => _DatePickerFieldState();
}

class _DatePickerFieldState extends State<_DatePickerField> {
  final TextEditingController _controller =
      TextEditingController(); // To display formatted date text
  DateTime? _selectedDate; // Holds selected date

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      readOnly: true, // Prevents keyboard input
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: widget.icon != null
            ? Icon(widget.icon, color: AppColors.primaryMaroon)
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppColors.primaryMaroon,
            width: 2,
          ),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
      validator: (_) {
        if (_selectedDate == null) return 'Please select a date';
        if (_selectedDate!.isBefore(DateTime.now())) {
          return 'Date cannot be in the past';
        }
        return null;
      },
      onTap: () async {
        DateTime? picked = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime.now(),
          lastDate: DateTime(2100),
        );

        if (picked != null) {
          // Update the text form field and notify the parent
          setState(() {
            _selectedDate = picked;
            _controller.text =
                "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
            widget.onChanged(picked);
          });
        }
      },
    );
  }
}
