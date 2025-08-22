import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'package:flutter/services.dart';

/// A customizable input box widget supporting text, password, and PIN inputs,
/// with consistent styling and optional validation/error display.
class PremiumInputBox extends StatefulWidget {
  final TextEditingController controller;                    // Controller for input text
  final String label;                                         // Label text for input
  final TextInputType keyboardType;                          // Keyboard type to use
  final int? maxLength;                                       // Maximum input length
  final ValueChanged<String>? onChanged;                     // Callback on text change
  final String? errorText;                                    // Optional error text to display below input
  final FocusNode? focusNode;                                 // Optional focus node
  final List<TextInputFormatter>? inputFormatters;           // Optional input formatters
  final FormFieldValidator<String>? validator;               // Optional validation function
  final bool isPassword;                                      // Whether to obscure text (password mode)
  final bool isPin;                                           // Whether input is PIN-type

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
    this.isPassword = false,
    this.isPin = false,
  });

  @override
  State<PremiumInputBox> createState() => _PremiumInputBoxState();
}

class _PremiumInputBoxState extends State<PremiumInputBox> {
  bool _obscurePassword = true;   // Tracks obscure state for password/PIN

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Container providing background color, rounded corners, and shadow
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
          // TextFormField for user input
          child: TextFormField(
            controller: widget.controller,
            keyboardType: widget.isPin ? TextInputType.number : widget.keyboardType,
            maxLength: widget.isPin ? 6 : widget.maxLength,
            style: TextStyle(
              color: AppColors.textLight,
              letterSpacing: widget.isPin ? 24 : null,  // Extra spacing for PIN inputs
              fontSize: 20,
              fontWeight: FontWeight.w500,
            ),
            focusNode: widget.focusNode,
            onChanged: widget.onChanged,
            inputFormatters: widget.isPin
                ? <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ]
                : widget.inputFormatters,
            validator: widget.validator,
            obscureText: (widget.isPassword || widget.isPin) ? _obscurePassword : false,
            obscuringCharacter: widget.isPin ? '*' : '•',
            decoration: InputDecoration(
              labelText: widget.label,
              labelStyle: const TextStyle(color: AppColors.textLight),
              counterText: '',   // Hide default length counter
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
              // Show visibility toggle icon for password or PIN types
              suffixIcon: (widget.isPassword || widget.isPin)
                  ? IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility : Icons.visibility_off,
                        color: AppColors.accentYellow,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    )
                  : null,
            ),
            textAlign: widget.isPin ? TextAlign.center : TextAlign.start,
          ),
        ),

        // Display error text below input if provided
        if (widget.errorText != null && widget.errorText!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 8),
            child: Text(
              widget.errorText!,
              style: const TextStyle(
                color: AppColors.accentYellow,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}
