import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ComingSoonScreen extends StatelessWidget {
  final String featureTitle;

  const ComingSoonScreen({super.key, required this.featureTitle});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(featureTitle),
        backgroundColor: AppColors.primaryMaroon,
        foregroundColor: AppColors.textLight,
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.construction_rounded,
                size: 54,
                color: AppColors.primaryMaroon,
              ),
              SizedBox(height: 14),
              Text(
                'Coming Soon',
                style: TextStyle(
                  color: AppColors.primaryMaroon,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'This feature is under development.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.primaryMaroon, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
