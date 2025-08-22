import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// A customizable button widget with a scaling animation when enabled,
/// and built-in loading indicator support.
class PremiumButton extends StatefulWidget {
  final String text;                 // Button label text
  final bool isEnabled;             // Whether button is enabled (clickable)
  final bool isLoading;             // Whether to show loading spinner
  final VoidCallback? onPressed;    // Callback invoked on press
  final Color? backgroundColor;     // Optional background color override
  final Color? textColor;           // Optional text color override

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
  late final AnimationController _controller;    // Controls the scaling animation
  late final Animation<double> _scaleAnimation;  // Tween for scaling the button

  @override
  void initState() {
    super.initState();

    // Initialize the animation controller for 300 milliseconds duration
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Scale animation from 95% size (shrunk) to 105% (slightly enlarged)
    // Uses easeInOut for smooth transition
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant PremiumButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    // When the button becomes enabled from a disabled state,
    // play the scale animation once to draw attention subtly.
    if (widget.isEnabled && !oldWidget.isEnabled && mounted) {
      _controller.forward().then((_) {
        if (mounted) _controller.reverse();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();  // Dispose animation controller to avoid memory leaks
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,  // Animate button scaling
      child: SizedBox(
        width: double.infinity, // Make button fill horizontal space
        child: ElevatedButton(
          // Disable button if not enabled or currently loading
          onPressed: widget.isEnabled && !widget.isLoading ? widget.onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.backgroundColor ?? AppColors.accentYellow,
            foregroundColor: widget.textColor ?? AppColors.primaryMaroon,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            disabledBackgroundColor: AppColors.disabled,
            disabledForegroundColor: AppColors.textLight,
          ),
          // Show loading spinner if loading, else show button text
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
