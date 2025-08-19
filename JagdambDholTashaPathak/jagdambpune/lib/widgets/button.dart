import 'package:flutter/material.dart';
import '../theme/app_colors.dart';


class PremiumButton extends StatefulWidget {
  final String text;
  final bool isEnabled;
  final bool isLoading;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? textColor;

  const PremiumButton({
    super.key,
    required this.text,
    required this.isEnabled,
    required this.isLoading,
    this.onPressed,
    this.backgroundColor,
    this.textColor,
  });

  @override
  State<PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<PremiumButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.05)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(covariant PremiumButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isEnabled && !oldWidget.isEnabled && mounted) {
      _controller.forward().then((_) {
        if (mounted) _controller.reverse();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: widget.isEnabled && !widget.isLoading ? widget.onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.backgroundColor ?? AppColors.accentYellow,
            foregroundColor: widget.textColor ?? Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            disabledBackgroundColor: AppColors.disabled,
            disabledForegroundColor: Colors.white,
          ),
          child: widget.isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                )
              : Text(
                  widget.text,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
        ),
      ),
    );
  }
}
