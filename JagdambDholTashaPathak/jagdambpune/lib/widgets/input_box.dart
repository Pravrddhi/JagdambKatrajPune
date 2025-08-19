import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'package:flutter/services.dart';

class PremiumInputBox extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType keyboardType;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final String? errorText;
  final FocusNode? focusNode;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;
  final bool isPassword;

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
  });

  @override
  State<PremiumInputBox> createState() => _PremiumInputBoxState();
}

class _PremiumInputBoxState extends State<PremiumInputBox> {
  bool _obscurePassword = true;

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
          child: TextFormField(
            controller: widget.controller,
            keyboardType: widget.keyboardType,
            maxLength: widget.maxLength,
            style: const TextStyle(color: AppColors.textLight),
            focusNode: widget.focusNode,
            onChanged: widget.onChanged,
            inputFormatters: widget.inputFormatters,
            validator: widget.validator,
            obscureText: widget.isPassword ? _obscurePassword : false,
            decoration: InputDecoration(
              labelText: widget.label,
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
                borderSide:
                    const BorderSide(color: AppColors.accentYellow, width: 1.5),
              ),
              errorStyle: const TextStyle(color: AppColors.accentYellow),
              suffixIcon: widget.isPassword
                  ? IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
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
          ),
        ),
      ],
    );
  }
}
