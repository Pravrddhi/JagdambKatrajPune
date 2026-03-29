import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common_button.dart';
import '../../widgets/input_box.dart';
import 'package:flutter/services.dart';

class LoginWebScreen extends StatelessWidget {
  final TextEditingController phoneController;
  final TextEditingController passwordController;
  final String errorMessage;
  final bool isLoggingIn;
  final bool showRegistration;
  final bool isFeatureFlagsLoading;
  final VoidCallback onLogin;
  final VoidCallback onRegistrationTap;
  final VoidCallback onResetPinTap;
  final ValueChanged<String>? onPhoneChanged;
  final ValueChanged<String>? onPasswordChanged;

  const LoginWebScreen({
    super.key,
    required this.phoneController,
    required this.passwordController,
    required this.errorMessage,
    required this.isLoggingIn,
    required this.showRegistration,
    required this.isFeatureFlagsLoading,
    required this.onLogin,
    required this.onRegistrationTap,
    required this.onResetPinTap,
    this.onPhoneChanged,
    this.onPasswordChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 30,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/logos/splash_logo.png',
                  height: 110,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Login',
                  style: TextStyle(
                    color: AppColors.primaryMaroon,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 32),
                PremiumInputBox(
                  controller: phoneController,
                  label: 'Enter 10-digit phone number',
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  useLightStyle: true,
                  onChanged: onPhoneChanged,
                ),
                const SizedBox(height: 14),
                PremiumInputBox(
                  controller: passwordController,
                  label: 'Enter password',
                  isPassword: true,
                  useLightStyle: true,
                  onChanged: onPasswordChanged,
                ),
                if (errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      errorMessage,
                      style: const TextStyle(
                        color: AppColors.errorRed,
                        fontSize: 14,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                PremiumButton(
                  text: 'Login',
                  onPressed: onLogin,
                  isLoading: isLoggingIn,
                  isEnabled: !isLoggingIn,
                ),
                const SizedBox(height: 16),
                if (isFeatureFlagsLoading)
                  const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primaryMaroon,
                    ),
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (showRegistration)
                        GestureDetector(
                          onTap: onRegistrationTap,
                          child: const Text(
                            'Registration',
                            style: TextStyle(
                              color: AppColors.primaryMaroon,
                              decoration: TextDecoration.underline,
                              fontSize: 14,
                            ),
                          ),
                        )
                      else
                        GestureDetector(
                          onTap: onResetPinTap,
                          child: const Text(
                            'Reset PIN',
                            style: TextStyle(
                              color: AppColors.primaryMaroon,
                              decoration: TextDecoration.underline,
                              fontSize: 14,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
