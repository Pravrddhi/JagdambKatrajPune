import 'package:flutter/material.dart';

PageRouteBuilder<dynamic> slowPageRoute(Widget page,
    {int durationMs = 800, Offset beginOffset = const Offset(0.0, 1.0)}) {
  return PageRouteBuilder(
    transitionDuration: Duration(milliseconds: durationMs),
    pageBuilder: (_, animation, __) => page,
    transitionsBuilder: (_, animation, __, child) {
      final offsetAnimation = Tween<Offset>(
        begin: beginOffset,
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

      return SlideTransition(
        position: offsetAnimation,
        child: FadeTransition(opacity: animation, child: child),
      );
    },
  );
}
