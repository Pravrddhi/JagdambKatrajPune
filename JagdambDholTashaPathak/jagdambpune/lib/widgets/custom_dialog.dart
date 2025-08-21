import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class CustomDialogFormField {
  final String label;
  final IconData? icon;
  final bool requiredField;
  final bool isDate;
  final Function(dynamic)? onChanged;
  final String? Function(String?)? validator;

  CustomDialogFormField({
    required this.label,
    this.icon,
    this.requiredField = true,
    this.isDate = false,
    this.onChanged,
    this.validator,
  });
}

class CustomDialog {
  static Future<void> show({
    required BuildContext context,
    required String title,
    required List<CustomDialogFormField> fields,
    required Future<void> Function(Map<String, dynamic>) onSubmit,
  }) async {
    await showGeneralDialog(
      context: context,
      barrierLabel: title,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, __, ___) => _CustomDialogForm(
        title: title,
        fields: fields,
        onSubmit: onSubmit,
      ),
      transitionBuilder: (_, anim, __, child) {
        final curvedAnim =
            CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.3),
              end: Offset.zero,
            ).animate(curvedAnim),
            child: ScaleTransition(scale: curvedAnim, child: child),
          ),
        );
      },
    );
  }
}

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
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> values = {};
  bool _isSubmitting = false;

  bool get _isFormValid {
    for (var field in widget.fields) {
      if (field.requiredField &&
          (values[field.label] == null ||
              values[field.label].toString().isEmpty)) {
        return false;
      }
      if (field.isDate &&
          values[field.label] is DateTime &&
          (values[field.label] as DateTime).isBefore(DateTime.now())) {
        return false;
      }
    }
    return true;
  }

  InputDecoration _inputDecoration(CustomDialogFormField field) {
    return InputDecoration(
      labelText: field.label,
      prefixIcon:
          field.icon != null ? Icon(field.icon, color: AppColors.primaryMaroon) : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.primaryMaroon, width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 60.0),
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Color(0xFFFFF8E1), Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                )
              ],
            ),
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      width: double.infinity,
                      height: 60,
                      color: AppColors.primaryMaroon,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 60),
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.accentYellow,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: SingleChildScrollView(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              for (var field in widget.fields) ...[
                                if (!field.isDate)
                                  TextFormField(
                                    decoration: _inputDecoration(field),
                                    validator: field.validator ??
                                        (val) => field.requiredField &&
                                                (val == null || val.isEmpty)
                                            ? 'Required'
                                            : null,
                                    onChanged: (val) {
                                      values[field.label] = val;
                                      setState(() {});
                                      if (field.onChanged != null) field.onChanged!(val);
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
                              const SizedBox(height: 10),
                              ElevatedButton(
                                onPressed: _isFormValid && !_isSubmitting
                                    ? () async {
                                        setState(() => _isSubmitting = true);
                                        await widget.onSubmit(values);
                                        setState(() => _isSubmitting = false);
                                      }
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isFormValid
                                      ? AppColors.accentYellow
                                      : Colors.grey[400],
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 12),
                                ),
                                child: const Text(
                                  'Submit',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryMaroon,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: 12,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: AppColors.accentYellow),
                    onPressed: () => Navigator.pop(context),
                    iconSize: 24,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DatePickerField extends StatefulWidget {
  final String label;
  final IconData? icon;
  final Function(DateTime) onChanged;

  const _DatePickerField({required this.label, this.icon, required this.onChanged});

  @override
  State<_DatePickerField> createState() => _DatePickerFieldState();
}

class _DatePickerFieldState extends State<_DatePickerField> {
  final TextEditingController _controller = TextEditingController();
  DateTime? _selectedDate;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon:
            widget.icon != null ? Icon(widget.icon, color: AppColors.primaryMaroon) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.primaryMaroon, width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
      validator: (_) {
        if (_selectedDate == null) return 'Please select a date';
        if (_selectedDate!.isBefore(DateTime.now())) return 'Date cannot be in the past';
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
