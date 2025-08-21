import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/primary_button.dart';

class OtpDialog extends StatefulWidget {
  final void Function(String otp) onSubmit;

  const OtpDialog({super.key, required this.onSubmit});

  @override
  State<OtpDialog> createState() => _OtpDialogState();
}

class _OtpDialogState extends State<OtpDialog> {
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.primaryMaroon,
      title: const Text("Enter OTP", style: TextStyle(color: AppColors.textLight)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(6, (index) {
              return SizedBox(
                width: 40,
                child: TextField(
                  controller: _otpControllers[index],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  style: const TextStyle(color: AppColors.textLight, fontSize: 18),
                  decoration: const InputDecoration(
                    hintText: '*',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 18),
                    counterText: "",
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white70),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.accentYellow),
                    ),
                  ),
                  onChanged: (value) {
                    if (value.isNotEmpty && index < 5) {
                      FocusScope.of(context).nextFocus();
                    }
                    if (value.isEmpty && index > 0) {
                      FocusScope.of(context).previousFocus();
                    }
                  },
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            text: "Submit OTP",
            onPressed: () {
              final otp = _otpControllers.map((c) => c.text).join();
              if (otp.length == 6) {
                Navigator.pop(context);
                widget.onSubmit(otp);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Please enter 6-digit OTP',
                    style: TextStyle(color: AppColors.errorRed),
                  ),
                  backgroundColor: Colors.black87, // optional for better contrast
                ),
              );
              }
            },
          ),
        ],
      ),
    );
  }
}
