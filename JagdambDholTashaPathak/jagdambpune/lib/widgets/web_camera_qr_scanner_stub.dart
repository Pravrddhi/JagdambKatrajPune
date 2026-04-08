import 'package:flutter/widgets.dart';

/// Stub used on non-web platforms. Never rendered.
class WebCameraQrScannerWidget extends StatelessWidget {
  final ValueChanged<String> onQrDetected;
  final ValueChanged<String>? onError;
  final ValueChanged<VoidCallback>? onReady;

  const WebCameraQrScannerWidget({
    super.key,
    required this.onQrDetected,
    this.onError,
    this.onReady,
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
