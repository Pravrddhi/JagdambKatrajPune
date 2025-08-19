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
  late final AnimationController _logoController;
  late final AnimationController _scaleController;
  late final Animation<double> _dropAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Smooth drop ~4s
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );

    // Bounce/scale ~2.5s
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    // Drop from top with bounce
    _dropAnimation = Tween<double>(begin: -1.0, end: 0.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.bounceOut),
    );

    // Scale bounce
    _scaleAnimation = TweenSequence([
      TweenSequenceItem(
          tween: Tween<double>(begin: 0.8, end: 1.2).chain(CurveTween(curve: Curves.easeOut)), weight: 50),
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.2, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 50),
    ]).animate(_scaleController);

    // Start sequential animations
    _logoController.forward().then((_) {
      _scaleController.forward();
    });

    // Navigate to login after 6.5s
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
    _logoController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: AppColors.primaryMaroon, // 🔹 Maroon background
      body: AnimatedBuilder(
        animation: Listenable.merge([_dropAnimation, _scaleAnimation]),
        builder: (context, child) {
          final scale = _scaleAnimation.value;
          return Transform.translate(
            offset: Offset(0, _dropAnimation.value * screenHeight * 0.55),
            child: Transform.scale(
              scale: scale,
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 🔹 Warm soft glow behind logo
                    Container(
                      width: MediaQuery.of(context).size.width * 0.55,
                      height: MediaQuery.of(context).size.width * 0.55,
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.5),
                            blurRadius: 60 * scale,
                            spreadRadius: 8 * scale,
                          ),
                        ],
                        shape: BoxShape.circle,
                      ),
                    ),
                    // Logo image
                    child!,
                  ],
                ),
              ),
            ),
          );
        },
        child: Image.asset(
          'assets/logos/splash_logo.png',
          width: MediaQuery.of(context).size.width * 0.55,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
