import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PremiumDropDown extends StatelessWidget {
  final String? value;
  final List<String> options;
  final String label;
  final void Function(String?) onChanged;

  const PremiumDropDown({
    super.key,
    required this.value,
    required this.options,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
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
          child: DropdownButtonFormField<String>(
            value: value,
            items: options
                .map((option) => DropdownMenuItem<String>(
                      value: option,
                      child: Text(option, style: const TextStyle(color: AppColors.textLight)),
                    ))
                .toList(),
            onChanged: onChanged,
            dropdownColor: AppColors.primaryMaroon,
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(color: AppColors.textLight),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.transparent),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.accentYellow, width: 1.5),
              ),
            ),
            style: const TextStyle(color: AppColors.textLight),
            iconEnabledColor: AppColors.textLight,
          ),
        ),
      ],
    );
  }
}
