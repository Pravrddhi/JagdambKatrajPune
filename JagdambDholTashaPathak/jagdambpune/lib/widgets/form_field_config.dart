import 'package:flutter/material.dart';

class FormFieldConfig {
  final String key;
  final String label;
  final IconData icon;
  final TextEditingController controller;
  final FieldType type;
  final bool isMultiline;

  FormFieldConfig({
    required this.key,
    required this.label,
    required this.icon,
    required this.controller,
    this.type = FieldType.text,
    this.isMultiline = false,
  });
}

enum FieldType { text, date, multiline }
