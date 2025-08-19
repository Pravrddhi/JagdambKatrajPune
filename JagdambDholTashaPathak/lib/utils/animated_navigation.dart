// lib/utils/animated_navigation.dart

import 'package:flutter/material.dart';
import '../screens/profile_screen.dart';

class AnimatedNavigation {
  /// Profile screen navigation with slide-up + fade animation
  static void pushProfile(BuildContext context, Map<String, dynamic> userDetails) {
    Navigator.of(context).push(_slideUpFadeRoute(
      ProfileScreen(userDetails: userDetails),
    ));
  }

  /// Example placeholder: use same animation for settings
  static void pushSettings(BuildContext context, Widget settingsScreen) {
    Navigator.of(context).push(_slideUpFadeRoute(settingsScreen));
  }

  /// Example placeholder: use same animation for upcoming premium feature
  static void pushPremiumFeature(BuildContext context, Widget premiumScreen) {
    Navigator.of(context).push(_slideUpFadeRoute(premiumScreen));
  }

  /// Core animation function: Slide-up + Fade-in
  static PageRouteBuilder _slideUpFadeRoute(Widget page) {
    return PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        final slideAnimation = Tween<Offset>(
          begin: const Offset(0, 0.2), // start slightly below
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack));

        final fadeAnimation = Tween<double>(begin: 0, end: 1).animate(animation);

        return SlideTransition(
          position: slideAnimation,
          child: FadeTransition(
            opacity: fadeAnimation,
            child: child,
          ),
        );
      },
    );
  }
}
