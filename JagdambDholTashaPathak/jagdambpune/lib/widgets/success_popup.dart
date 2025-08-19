import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class SuccessPopup extends StatefulWidget {
  final String message;
  final VoidCallback? onClose;

  const SuccessPopup({super.key, required this.message, this.onClose});

  @override
  State<SuccessPopup> createState() => _SuccessPopupState();
}

class _SuccessPopupState extends State<SuccessPopup> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _scaleAnim = Tween<double>(begin: 0.7, end: 1.0).animate(_fadeAnim);

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: AlertDialog(
          backgroundColor: AppColors.primaryMaroon,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          contentPadding: const EdgeInsets.all(24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, color: AppColors.accentYellow, size: 64),
              const SizedBox(height: 16),
              Text(
                widget.message,
                style: const TextStyle(color: AppColors.textLight, fontSize: 18),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentYellow,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  if (widget.onClose != null) widget.onClose!();
                },
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
