import 'package:flutter/material.dart';

import '../config/api_endpoints.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/input_box.dart';

class NotificationForm {
  static Future<void> open(
    BuildContext context, {
    int? targetGatId,
    String? targetGatName,
  }) async {
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _NotificationDialog(
        parentContext: context,
        targetGatId: targetGatId,
        targetGatName: targetGatName,
      ),
    );
  }
}

class _NotificationDialog extends StatefulWidget {
  final BuildContext parentContext;
  final int? targetGatId;
  final String? targetGatName;

  const _NotificationDialog({
    required this.parentContext,
    this.targetGatId,
    this.targetGatName,
  });

  @override
  State<_NotificationDialog> createState() => _NotificationDialogState();
}

class _NotificationDialogState extends State<_NotificationDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final title = _titleController.text.trim();
    final message = _messageController.text.trim();

    setState(() {
      _isSubmitting = true;
    });

    try {
      await ApiService.sendBroadcastNotification(
        title: title,
        message: message,
        targetType: widget.targetGatId != null ? 'gat' : null,
        targetGat: widget.targetGatId,
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(ApiEndpoints.genericApiFailureMessage)),
      );
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
    final bottomInset = mediaQuery.viewInsets.bottom;
    const verticalInset = 20.0;

    final availableHeight = (screenHeight - bottomInset - (verticalInset * 2))
        .clamp(220.0, screenHeight);

    return AlertDialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      contentPadding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.accentYellow.withAlpha(70),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.campaign_rounded,
              color: AppColors.primaryMaroon,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Send Notification',
              style: TextStyle(
                color: AppColors.primaryMaroon,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: availableHeight),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This message will be delivered to targeted users.',
                  style: TextStyle(
                    color: AppColors.primaryMaroon,
                    fontSize: 13,
                  ),
                ),
                if (widget.targetGatId != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentYellow.withAlpha(60),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Target: ${widget.targetGatName ?? 'Selected Gat'}',
                      style: const TextStyle(
                        color: AppColors.primaryMaroon,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                PremiumInputBox(
                  controller: _titleController,
                  label: 'Notification Title',
                  useLightStyle: true,
                  maxLength: 80,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Notification title is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                PremiumInputBox(
                  controller: _messageController,
                  label: 'Notification Message',
                  useLightStyle: true,
                  maxLength: 400,
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Notification message is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  '${_messageController.text.trim().length}/400 characters',
                  style: TextStyle(
                    color: AppColors.primaryMaroon.withAlpha(170),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: AppColors.primaryMaroon),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _isSubmitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accentYellow,
            foregroundColor: AppColors.primaryMaroon,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          icon: _isSubmitting
              ? const SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_rounded, size: 16),
          label: Text(_isSubmitting ? 'Sending...' : 'Send'),
        ),
      ],
    );
  }
}
