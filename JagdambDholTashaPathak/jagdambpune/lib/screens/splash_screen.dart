import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _logoController;   // Controls the drop animation of logo
  late final AnimationController _scaleController;  // Controls the scaling bounce animation
  late final Animation<double> _dropAnimation;      // Animation for logo drop with bounce
  late final Animation<double> _scaleAnimation;     // Animation for scaling (bounce)

  @override
  void initState() {
    super.initState();

    // Initialize drop animation controller for smooth drop (~4 seconds)
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );

    // Initialize scale animation controller for bounce effect (~2.5 seconds)
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    // Drop animation: logo moves vertically from above screen to center with bounce effect
    _dropAnimation = Tween<double>(begin: -1.0, end: 0.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.bounceOut),
    );

    // Scale animation: bounce scaling from 0.8x to 1.2x to normal size
    _scaleAnimation = TweenSequence([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.8, end: 1.2).chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.2, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
    ]).animate(_scaleController);

    // Play drop animation first, then scale animation sequentially
    _logoController.forward().then((_) {
      _scaleController.forward();
    });

    // After animations complete (6.5s), navigate to LoginScreen with fade transition
    Timer(const Duration(milliseconds: 6500), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        pageBuilder: (_, __, ___) => const LoginScreen(),
        transitionDuration: const Duration(milliseconds: 1200),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ));
    });
  }

  @override
  void dispose() {
    // Dispose animation controllers to release resources
    _logoController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: AppColors.primaryMaroon, // Maroon background color
      body: AnimatedBuilder(
        animation: Listenable.merge([_dropAnimation, _scaleAnimation]),
        builder: (context, child) {
          final scale = _scaleAnimation.value;
          // Transform widget for vertical drop and scaling bounce animations
          return Transform.translate(
            offset: Offset(0, _dropAnimation.value * screenHeight * 0.55),
            child: Transform.scale(
              scale: scale,
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Soft warm glow behind logo for subtle effect
                    Container(
                      width: MediaQuery.of(context).size.width * 0.55,
                      height: MediaQuery.of(context).size.width * 0.55,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.5),
                            blurRadius: 60 * scale,
                            spreadRadius: 8 * scale,
                          ),
                        ],
                      ),
                    ),
                    child!,  // The logo image passed into AnimatedBuilder
                  ],
                ),
              ),
            ),
          );
        },
        // Logo image passed once, reused in animation builder to improve performance
        child: Image.asset(
          'assets/logos/splash_logo.png',
          width: MediaQuery.of(context).size.width * 0.55,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
