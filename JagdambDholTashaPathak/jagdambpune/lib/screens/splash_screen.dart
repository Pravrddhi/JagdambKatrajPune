import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/feature_flags_provider.dart';
import '../theme/app_colors.dart';
import '../config/app_config.dart';
import 'login_screen.dart';
import '../web/screens/new_registration_web_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController
  _logoController; // Controls the drop animation of logo
  late final AnimationController
  _scaleController; // Controls the scaling bounce animation
  late final Animation<double>
  _dropAnimation; // Animation for logo drop with bounce
  late final Animation<double>
  _scaleAnimation; // Animation for scaling (bounce)
  Timer? _navigationTimer;
  bool _splashDelayCompleted = false;
  bool _didNavigateToLogin = false;
  FeatureFlagsProvider? _featureFlagsProvider;
  bool _isShowingServerDownDialog = false;

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
        tween: Tween<double>(
          begin: 0.8,
          end: 1.2,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.2,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
    ]).animate(_scaleController);

    // Play drop animation first, then scale animation sequentially
    _logoController.forward().then((_) {
      _scaleController.forward();
    });

    // Keep existing splash duration, but only navigate when server is reachable.
    _navigationTimer = Timer(const Duration(milliseconds: 6500), () {
      if (!mounted) return;
      _splashDelayCompleted = true;
      _tryNavigateToLogin();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _featureFlagsProvider = context.read<FeatureFlagsProvider>();
      _featureFlagsProvider?.addListener(_onFeatureFlagsChanged);
      _featureFlagsProvider?.fetchFeatureFlags(force: true);
      _onFeatureFlagsChanged();
    });
  }

  void _onFeatureFlagsChanged() {
    if (!mounted) {
      return;
    }

    final provider = _featureFlagsProvider;
    if (provider == null) return;

    final error = provider.error?.trim() ?? '';
    final hasServerFailure = error.isNotEmpty;
    if (hasServerFailure) {
      _showServerDownDialog();
      return;
    }

    _closeServerDownDialogIfOpen();
    _tryNavigateToLogin();
  }

  Future<void> _showServerDownDialog() async {
    if (!mounted || _isShowingServerDownDialog) return;

    _isShowingServerDownDialog = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WillPopScope(
        onWillPop: () async => false,
        child: const AlertDialog(
          title: Text(
            'Server is Under Maintenance. Contact Admin for more details...',
          ),
          content: Text('Pratik Shinde 9767704126'),
        ),
      ),
    );

    _isShowingServerDownDialog = false;
  }

  void _closeServerDownDialogIfOpen() {
    if (!mounted || !_isShowingServerDownDialog) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  void _tryNavigateToLogin() {
    if (!mounted || _didNavigateToLogin) return;

    if (!_splashDelayCompleted) return;

    final provider = _featureFlagsProvider;
    final hasServerFailure = (provider?.error?.trim().isNotEmpty ?? false);
    if (hasServerFailure || _isShowingServerDownDialog) {
      return;
    }

    if (kIsWeb) {
      final basePath = Uri.base.path.trim();
      final noTrailingSlash = basePath.endsWith('/') && basePath.length > 1
          ? basePath.substring(0, basePath.length - 1)
          : basePath;
      if (noTrailingSlash == '/new_registration' ||
          noTrailingSlash.contains('/new_registration')) {
        _didNavigateToLogin = true;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const NewRegistrationWebScreen(),
            transitionDuration: const Duration(milliseconds: 700),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
        return;
      }
    }

    _didNavigateToLogin = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const LoginScreen(),
        transitionDuration: const Duration(milliseconds: 1200),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    // Dispose animation controllers to release resources
    _featureFlagsProvider?.removeListener(_onFeatureFlagsChanged);
    _navigationTimer?.cancel();
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
                            color: Colors.orange.withAlpha(128), // 0.5 * 255
                            blurRadius: 60 * scale,
                            spreadRadius: 8 * scale,
                          ),
                        ],
                      ),
                    ),
                    child!, // The logo image passed into AnimatedBuilder
                  ],
                ),
              ),
            ),
          );
        },
        // Logo image passed once, reused in animation builder to improve performance
        child: Image.asset(
          AppConfig.logoAsset,
          width: MediaQuery.of(context).size.width * 0.55,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
