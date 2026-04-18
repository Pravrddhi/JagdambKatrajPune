import 'package:flutter/material.dart';

import '../models/maintenance_models.dart';
import '../theme/app_colors.dart';

class CompletionUsedItemPreview {
  final int inventoryItemId;
  final String inventoryItemName;
  final int quantityUsed;

  const CompletionUsedItemPreview({
    required this.inventoryItemId,
    required this.inventoryItemName,
    required this.quantityUsed,
  });

  Map<String, int> toPayload() {
    return <String, int>{
      'inventory_item_id': inventoryItemId,
      'quantity_used': quantityUsed,
    };
  }
}

class CompletionSubmissionInput {
  final String workNotes;
  final List<Map<String, int>> usedItems;

  const CompletionSubmissionInput({
    required this.workNotes,
    required this.usedItems,
  });
}

List<CompletionUsedItemPreview> buildCompletionUsedItems(
  List<InventoryRequestItem> approvedRequests,
) {
  final usedItemsByStockId = <int, CompletionUsedItemPreview>{};

  for (final request in approvedRequests) {
    final existing = usedItemsByStockId[request.inventoryItem];
    if (existing == null) {
      usedItemsByStockId[request.inventoryItem] = CompletionUsedItemPreview(
        inventoryItemId: request.inventoryItem,
        inventoryItemName: request.inventoryItemName,
        quantityUsed: request.requestedQuantity,
      );
      continue;
    }

    usedItemsByStockId[request.inventoryItem] = CompletionUsedItemPreview(
      inventoryItemId: existing.inventoryItemId,
      inventoryItemName: existing.inventoryItemName,
      quantityUsed: existing.quantityUsed + request.requestedQuantity,
    );
  }

  return usedItemsByStockId.values.toList();
}

Future<CompletionSubmissionInput?> showMaintenanceCompletionDialog({
  required BuildContext context,
  required String eventTitle,
  required List<CompletionUsedItemPreview> usedItems,
}) async {
  return showDialog<CompletionSubmissionInput>(
    context: context,
    builder: (dialogContext) {
      return _MaintenanceCompletionDialog(
        eventTitle: eventTitle,
        usedItems: usedItems,
      );
    },
  );
}

class _MaintenanceCompletionDialog extends StatefulWidget {
  final String eventTitle;
  final List<CompletionUsedItemPreview> usedItems;

  const _MaintenanceCompletionDialog({
    required this.eventTitle,
    required this.usedItems,
  });

  @override
  State<_MaintenanceCompletionDialog> createState() =>
      _MaintenanceCompletionDialogState();
}

class _MaintenanceCompletionDialogState
    extends State<_MaintenanceCompletionDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _workNotesController = TextEditingController();

  @override
  void dispose() {
    _workNotesController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final submission = CompletionSubmissionInput(
      workNotes: _workNotesController.text.trim(),
      usedItems: widget.usedItems.map((item) => item.toPayload()).toList(),
    );

    Navigator.of(context).pop(submission);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Submit Completion: ${widget.eventTitle}'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _workNotesController,
                decoration: const InputDecoration(labelText: 'Work Notes'),
                maxLines: 2,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Work notes is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Used Items',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 8),
              if (widget.usedItems.isEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'No approved stock requests for this maintenance day.',
                    style: TextStyle(color: Colors.black54),
                  ),
                )
              else
                ...widget.usedItems.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '- ${item.inventoryItemName.trim().isNotEmpty ? item.inventoryItemName : 'Item #${item.inventoryItemId}'} x${item.quantityUsed}',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: AppColors.primaryMaroon),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            foregroundColor: AppColors.primaryMaroon,
          ),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
