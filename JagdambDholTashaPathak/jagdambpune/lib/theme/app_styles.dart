import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppStyles {
  static InputDecoration inputDecoration(String label, {String? hintText}) => InputDecoration(
        labelText: label,
        hintText: hintText,
        labelStyle: const TextStyle(color: AppColors.textLight),
        hintStyle: const TextStyle(color: AppColors.textLight54),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.accentYellow),
          borderRadius: BorderRadius.circular(10),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.accentYellow, width: 2),
          borderRadius: BorderRadius.circular(10),
        ),
      );

  static const TextStyle infoText = TextStyle(color: AppColors.accentYellow);

  static const TextStyle errorText = TextStyle(color: AppColors.errorRed);

  static const buttonText = TextStyle(fontWeight: FontWeight.bold);
}
