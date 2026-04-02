import 'package:flutter/material.dart';

import '../config/api_endpoints.dart';
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
        _inlineError = ApiEndpoints.genericApiFailureMessage;
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
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    const verticalInset = 20.0;

    final availableHeight = (screenHeight - bottomInset - (verticalInset * 2))
        .clamp(220.0, screenHeight);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: availableHeight),
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.accentYellow.withValues(
                              alpha: 0.3,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: const Icon(
                            Icons.notifications_active,
                            color: AppColors.primaryMaroon,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Send Notification',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryMaroon,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: AppColors.primaryMaroon,
                          ),
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Enter title and message to notify all targeted users.',
                      style: TextStyle(color: AppColors.primaryMaroon),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _titleController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        hintText: 'Eg: Practice Update',
                        prefixIcon: Icon(
                          Icons.title,
                          color: AppColors.primaryMaroon,
                        ),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _messageController,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        alignLabelWithHint: true,
                        labelText: 'Message',
                        hintText: 'Write your notification message here...',
                        prefixIcon: Icon(
                          Icons.message,
                          color: AppColors.primaryMaroon,
                        ),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_inlineError != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          border: Border.all(color: Colors.red.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _inlineError!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentYellow,
                          foregroundColor: AppColors.primaryMaroon,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
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
                                'Send Notification',
                                style: TextStyle(
                                  color: AppColors.primaryMaroon,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
