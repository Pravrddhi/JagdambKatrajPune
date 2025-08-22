import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// A styled dropdown form field widget with consistent design
class PremiumDropDown extends StatelessWidget {
  final String? value;                  // Currently selected option value
  final List<String> options;          // List of available options
  final String label;                  // Label displayed for the dropdown
  final void Function(String?) onChanged; // Callback when selection changes

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
        // Container providing background, rounded corners, and subtle shadow
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.primaryMaroon,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.accentYellow.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4), // Shadow offset downwards
              ),
            ],
          ),

          // DropdownButtonFormField enables form integration and validation
          child: DropdownButtonFormField<String>(
            value: value,
            items: options
                .map(
                  (option) => DropdownMenuItem<String>(
                    value: option,
                    child: Text(option,
                        style: const TextStyle(color: AppColors.textLight)),
                  ),
                )
                .toList(),
            onChanged: onChanged,
            dropdownColor: AppColors.primaryMaroon,
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(color: AppColors.textLight),

              // Transparent border when enabled to use container's rounded corners
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.transparent),
              ),
              // Yellow border on focus to highlight the field
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.accentYellow,
                  width: 1.5,
                ),
              ),
            ),

            // Style for selected option text
            style: const TextStyle(color: AppColors.textLight),

            // Color of the dropdown arrow icon
            iconEnabledColor: AppColors.textLight,
          ),
        ),
      ],
    );
  }
}
