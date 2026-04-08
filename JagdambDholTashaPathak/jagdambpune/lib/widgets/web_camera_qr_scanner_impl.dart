// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';

/// Web-native QR scanner widget.
/// Uses browser getUserMedia → CanvasElement frame capture → jsQR decoding.
/// Does NOT use mobile_scanner (which throws MissingPluginException on web).
class WebCameraQrScannerWidget extends StatefulWidget {
  final ValueChanged<String> onQrDetected;
  final ValueChanged<String>? onError;

  /// Called with a handle that lets the parent stop the camera stream.
  final ValueChanged<VoidCallback>? onReady;

  const WebCameraQrScannerWidget({
    super.key,
    required this.onQrDetected,
    this.onError,
    this.onReady,
  });

  @override
  State<WebCameraQrScannerWidget> createState() =>
      _WebCameraQrScannerWidgetState();
}

class _WebCameraQrScannerWidgetState extends State<WebCameraQrScannerWidget> {
  static int _idCounter = 0;
  late final String _viewId;

  html.DivElement? _container;
  html.VideoElement? _video;
  html.CanvasElement? _canvas;
  html.MediaStream? _stream;
  Timer? _scanTimer;

  bool _started = false;
  bool _starting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _viewId = 'web-qr-scanner-${_idCounter++}';
    _buildDom();
    // Register the view factory before the widget is first built
    ui.platformViewRegistry.registerViewFactory(_viewId, (_) => _container!);
    // Start camera after the first frame so the HtmlElementView is in the DOM
    WidgetsBinding.instance.addPostFrameCallback((_) => _startCamera());
  }

  void _buildDom() {
    _video = html.VideoElement()
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true')
      ..style.cssText =
          'width:100%;height:100%;object-fit:cover;display:block;';

    _canvas = html.CanvasElement()..style.display = 'none';

    _container = html.DivElement()
      ..style.cssText =
          'width:100%;height:100%;background:#000;overflow:hidden;position:relative;'
      ..children.addAll([_video!, _canvas!]);
  }

  Future<void> _startCamera() async {
    if (_started || _starting || !mounted) return;
    _starting = true;

    try {
      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        _reportError('Camera API not supported in this browser.');
        return;
      }

      _stream = await mediaDevices.getUserMedia({
        'video': {
          'facingMode': {'ideal': 'environment'},
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        },
        'audio': false,
      });

      _video!.srcObject = _stream;
      _started = true;

      // Wait for video to be ready before scanning
      await _video!.onCanPlay.first;

      // Expose stop handle to parent
      widget.onReady?.call(_stopCamera);

      _scanTimer = Timer.periodic(
        const Duration(milliseconds: 350),
        (_) => _scanFrame(),
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      String errMsg;
      if (msg.contains('notallowederror') || msg.contains('permission')) {
        errMsg =
            'Camera permission denied.\n\nTo fix:\n• Click the camera icon in the browser address bar\n• Set Camera to "Allow"\n• Reload the page';
      } else if (msg.contains('notfounderror') || msg.contains('no camera')) {
        errMsg = 'No camera device found on this device.';
      } else if (msg.contains('notreadableerror') || msg.contains('in use')) {
        errMsg =
            'Camera is in use by another app or tab. Close it and try again.';
      } else {
        errMsg = 'Camera error. Please reload and try again.\n($e)';
      }
      _reportError(errMsg);
    } finally {
      _starting = false;
    }
  }

  void _reportError(String msg) {
    if (!mounted) return;
    setState(() => _errorMessage = msg);
    widget.onError?.call(msg);
  }

  void _scanFrame() {
    if (!_started || _video == null || _canvas == null) return;
    if (_video!.readyState < 2) return; // not enough data

    final w = _video!.videoWidth;
    final h = _video!.videoHeight;
    if (w == 0 || h == 0) return;

    _canvas!.width = w;
    _canvas!.height = h;
    // dart:html uses drawImageScaled for the (source, dx, dy, dw, dh) form
    _canvas!.context2D.drawImageScaled(_video!, 0, 0, w, h);

    final imageData = _canvas!.context2D.getImageData(0, 0, w, h);

    if (!js.context.hasProperty('jsQR')) return;

    try {
      // jsQR(data, width, height) — options param omitted, defaults are fine
      final result = js.context.callMethod('jsQR', [imageData.data, w, h]);
      if (result != null) {
        final data = (result as js.JsObject)['data']?.toString();
        if (data != null && data.isNotEmpty && mounted) {
          widget.onQrDetected(data);
        }
      }
    } catch (_) {}
  }

  void _stopCamera() {
    _scanTimer?.cancel();
    _scanTimer = null;
    if (_stream != null) {
      for (final track in _stream!.getTracks()) {
        track.stop();
      }
      _stream = null;
    }
    _started = false;
  }

  @override
  void dispose() {
    _stopCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.white, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _errorMessage = null;
                  _started = false;
                  _starting = false;
                });
                _startCamera();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    return HtmlElementView(viewType: _viewId);
  }
}
