import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_colors.dart';

class NotificationForm {
  static Future<void> open(BuildContext context) async {
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _NotificationDialog(parentContext: context),
    );
  }
}

class _NotificationDialog extends StatefulWidget {
  final BuildContext parentContext;

  const _NotificationDialog({required this.parentContext});

  @override
  State<_NotificationDialog> createState() => _NotificationDialogState();
}

class _NotificationDialogState extends State<_NotificationDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  bool _isSubmitting = false;
  String? _inlineError;

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final title = _titleController.text.trim();
    final message = _messageController.text.trim();

    if (title.isEmpty || message.isEmpty) {
      setState(() {
        _inlineError = 'Title and message are required.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _inlineError = null;
    });

    try {
      await ApiService.sendBroadcastNotification(
        title: title,
        message: message,
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final parentContext = widget.parentContext;
        if (!parentContext.mounted) return;
        ScaffoldMessenger.of(parentContext).showSnackBar(
          const SnackBar(content: Text('Notification sent successfully!')),
        );
      });
    } catch (e) {
      if (!mounted) return;

      final errorText = e.toString().toLowerCase();
      if (errorText.contains('session expired') ||
          errorText.contains('login again') ||
          errorText.contains('no access token found')) {
        Navigator.of(context).pop();

        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final parentContext = widget.parentContext;
          if (!parentContext.mounted) return;

          await showDialog<void>(
            context: parentContext,
            builder: (sessionDialogContext) => AlertDialog(
              title: const Text('Session Expired'),
              content: const Text(
                'Your session has expired. Please login again.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(sessionDialogContext),
                  child: const Text('OK'),
                ),
              ],
            ),
          );

          if (!parentContext.mounted) return;
          Navigator.of(
            parentContext,
          ).pushNamedAndRemoveUntil('/login', (route) => false);
        });

        return;
      }

      setState(() {
        _inlineError = 'Failed to send notification: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(10),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Send Notification',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryMaroon,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.primaryMaroon),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                prefixIcon: Icon(Icons.title, color: AppColors.primaryMaroon),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _messageController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Message',
                prefixIcon: Icon(Icons.message, color: AppColors.primaryMaroon),
                border: OutlineInputBorder(),
              ),
            ),
            if (_inlineError != null) ...[
              const SizedBox(height: 10),
              Text(_inlineError!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentYellow,
                  foregroundColor: AppColors.primaryMaroon,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryMaroon,
                        ),
                      )
                    : const Text(
                        'Submit',
                        style: TextStyle(color: AppColors.primaryMaroon),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
