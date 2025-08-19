import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/registration_screen.dart';
import 'screens/home_screen.dart';
import 'screens/reset_pin.dart';
import 'theme/app_colors.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My App',
      theme: ThemeData(
        primaryColor: AppColors.primaryMaroon,
        scaffoldBackgroundColor: AppColors.primaryMaroon,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primaryMaroon,
          foregroundColor: AppColors.textLight,
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegistrationScreen(),
        '/resetPin': (context) => const ResetPinScreen(),
        // '/home': (context) => const HomeScreenWrapper(),
      },
    );
  }
}

// A wrapper to extract args and pass to HomeScreen
// class HomeScreenWrapper extends StatelessWidget {
//   const HomeScreenWrapper({super.key});

//   @override
//   Widget build(BuildContext context) {
//     final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;

//     return HomeScreen(
//       authToken: args?['accessToken'] ?? '',
//     );
//   }
// }
