import 'package:flutter/material.dart';

class LoggingInOverlay extends StatelessWidget {
  const LoggingInOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        // Semi-transparent black background
        Opacity(
          opacity: 0.5,
          child: ModalBarrier(
            dismissible: false,
            color: Colors.black,
          ),
        ),
        // Centered loading indicator and text
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Logging in...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
