import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'package:flutter/services.dart';

class PremiumInputBox extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType keyboardType;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final String? errorText;
  final FocusNode? focusNode;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;

  const PremiumInputBox({
    super.key,
    required this.controller,
    required this.label,
    this.keyboardType = TextInputType.text,
    this.maxLength,
    this.onChanged,
    this.errorText,
    this.focusNode, 
    this.inputFormatters,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.primaryMaroon,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.accentYellow.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TextFormField( // ✅ Use TextFormField instead of TextField
            controller: controller,
            keyboardType: keyboardType,
            maxLength: maxLength,
            style: const TextStyle(color: AppColors.textLight),
            focusNode: focusNode,
            onChanged: onChanged,
            inputFormatters: inputFormatters,
            validator: validator, // ✅ Now works correctly
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(color: AppColors.textLight),
              counterText: '',
              filled: true,
              fillColor: AppColors.primaryMaroon,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.transparent),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.accentYellow, width: 1.5),
              ),
              errorStyle: const TextStyle(color: AppColors.accentYellow),
            ),
          ),
        ),
      ],
    );
  }
}
