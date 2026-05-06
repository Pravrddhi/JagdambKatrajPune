import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../theme/app_colors.dart';

class DocumentApprovalPanel extends StatefulWidget {
  final bool enabled;

  const DocumentApprovalPanel({super.key, required this.enabled});

  @override
  State<DocumentApprovalPanel> createState() => _DocumentApprovalPanelState();
}

class _DocumentApprovalPanelState extends State<DocumentApprovalPanel> {
  static const Map<String, String> _documentTypeLabels = {
    'adhaar_card': 'Aadhaar Card',
    'pan_card': 'PAN Card',
    'personal_photo': 'Personal Photo',
    'agreement_document': 'Agreement Document',
  };

  bool _isLoadingAdminDocuments = false;
  int _adminCurrentPage = 1;
  int _adminTotalCount = 0;
  final int _adminPageSize = 20;
  String _adminStatusFilter = 'pending';
  String _adminDocumentTypeFilter = 'all';
  List<Map<String, dynamic>> _adminDocuments = <Map<String, dynamic>>[];
  final Set<int> _reviewingDocumentIds = <int>{};

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _loadAdminDocuments();
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadAdminDocuments({int page = 1}) async {
    if (!widget.enabled) {
      return;
    }

    setState(() {
      _isLoadingAdminDocuments = true;
    });

    try {
      final response = await ApiService.fetchPathakDocuments(
        status: _adminStatusFilter == 'all' ? null : _adminStatusFilter,
        documentType: _adminDocumentTypeFilter == 'all'
            ? null
            : _adminDocumentTypeFilter,
        page: page,
        pageSize: _adminPageSize,
      );

      if (!mounted) {
        return;
      }

      final data = response['data'];
      final items = data is List
          ? data
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : <Map<String, dynamic>>[];

      setState(() {
        _adminCurrentPage = page;
        _adminTotalCount = response['count'] is int
            ? response['count'] as int
            : int.tryParse(response['count']?.toString() ?? '0') ?? 0;
        _adminDocuments = items;
      });
    } catch (error) {
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAdminDocuments = false;
        });
      }
    }
  }

  Future<void> _openDocumentUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      _showSnackBar('Document URL is not available.');
      return;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      _showSnackBar('Invalid document URL.');
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      _showSnackBar('Unable to open document URL.');
    }
  }

  Future<void> _approveDocument(int documentId) async {
    await _reviewDocument(documentId: documentId, status: 'approved');
  }

  Future<void> _rejectDocument(int documentId) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reject Document'),
          content: TextField(
            controller: controller,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'Explain why the document is being rejected',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryMaroon,
                foregroundColor: AppColors.textLight,
              ),
              child: const Text('Reject'),
            ),
          ],
        );
      },
    );

    final normalizedReason = result?.trim();
    if (normalizedReason == null || normalizedReason.isEmpty) {
      return;
    }

    await _reviewDocument(
      documentId: documentId,
      status: 'rejected',
      reason: normalizedReason,
    );
  }

  Future<void> _reviewDocument({
    required int documentId,
    required String status,
    String? reason,
  }) async {
    setState(() {
      _reviewingDocumentIds.add(documentId);
    });

    try {
      final response = await ApiService.reviewDocument(
        documentId: documentId,
        status: status,
        reason: reason,
      );

      if (!mounted) {
        return;
      }

      _showSnackBar(
        response['message']?.toString() ?? 'Document reviewed successfully.',
      );
      await _loadAdminDocuments(page: _adminCurrentPage);
    } catch (error) {
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _reviewingDocumentIds.remove(documentId);
        });
      }
    }
  }

  String _documentTypeLabel(String? value) {
    return _documentTypeLabels[value] ?? value ?? '-';
  }

  String _statusLabel(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return '-';
    }
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  Color _statusColor(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'approved':
        return Colors.green.shade700;
      case 'rejected':
        return Colors.red.shade700;
      default:
        return Colors.orange.shade700;
    }
  }

  Widget _buildDocumentThumbnail(String documentUrl) {
    final trimmedUrl = documentUrl.trim();
    if (trimmedUrl.isEmpty) {
      return _buildThumbnailPlaceholder('Preview unavailable');
    }

    return InkWell(
      onTap: () => _openDocumentUrl(trimmedUrl),
      borderRadius: BorderRadius.circular(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Image.network(
            trimmedUrl,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) {
                return child;
              }
              return Container(
                color: Colors.white,
                alignment: Alignment.center,
                child: const CircularProgressIndicator(),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return _buildThumbnailPlaceholder('Tap to open document');
            },
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailPlaceholder(String message) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primaryMaroon.withValues(alpha: 0.16),
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.image_outlined,
                color: AppColors.primaryMaroon,
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.primaryMaroon,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdminDocumentCard(Map<String, dynamic> document) {
    final documentId = document['id'] is int
        ? document['id'] as int
        : int.tryParse(document['id']?.toString() ?? '');
    final isReviewing =
        documentId != null && _reviewingDocumentIds.contains(documentId);
    final status = document['status']?.toString();
    final rejectionReason = document['rejection_reason']?.toString() ?? '';
    final reviewedBy = document['reviewed_by_name']?.toString();
    final reviewedAt = document['reviewed_at']?.toString();
    final documentUrl = document['document_url']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primaryMaroon.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  document['uploaded_by_name']?.toString() ?? 'Unknown user',
                  style: const TextStyle(
                    color: AppColors.primaryMaroon,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _statusColor(status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _statusLabel(status),
                  style: TextStyle(
                    color: _statusColor(status),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _DocumentInfoRow(
            label: 'Phone',
            value: document['uploaded_by_phone']?.toString() ?? '-',
          ),
          _DocumentInfoRow(
            label: 'Type',
            value: _documentTypeLabel(document['document_type']?.toString()),
          ),
          _DocumentInfoRow(
            label: 'Created At',
            value: document['created_at']?.toString() ?? '-',
          ),
          if (reviewedBy != null && reviewedBy.isNotEmpty)
            _DocumentInfoRow(label: 'Reviewed By', value: reviewedBy),
          if (reviewedAt != null && reviewedAt.isNotEmpty)
            _DocumentInfoRow(label: 'Reviewed At', value: reviewedAt),
          if (rejectionReason.trim().isNotEmpty)
            _DocumentInfoRow(label: 'Reason', value: rejectionReason),
          const SizedBox(height: 6),
          SizedBox(
            height: 180,
            width: double.infinity,
            child: _buildDocumentThumbnail(documentUrl),
          ),
          const SizedBox(height: 10),
          const Text(
            'Tap the preview to open the full document.',
            style: TextStyle(
              color: AppColors.primaryMaroon,
              fontSize: 12,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: documentUrl.trim().isEmpty
                      ? null
                      : () => _openDocumentUrl(documentUrl),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open Full Document'),
                ),
              ),
            ],
          ),
          if (status?.toLowerCase() == 'pending' && documentId != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: isReviewing
                        ? null
                        : () => _approveDocument(documentId),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                    ),
                    child: isReviewing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text('Approve'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: isReviewing
                        ? null
                        : () => _rejectDocument(documentId),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade700),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'You do not have access to document approvals.',
            style: TextStyle(
              color: AppColors.primaryMaroon,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final totalPages = _adminTotalCount == 0
        ? 1
        : ((_adminTotalCount - 1) ~/ _adminPageSize) + 1;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Review uploaded documents for users in your pathak. Use filters to inspect pending, approved, or rejected submissions.',
            style: TextStyle(
              color: AppColors.primaryMaroon,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['pending', 'approved', 'rejected', 'all']
                .map(
                  (status) => ChoiceChip(
                    label: Text(_statusLabel(status)),
                    selected: _adminStatusFilter == status,
                    onSelected: _isLoadingAdminDocuments
                        ? null
                        : (_) {
                            setState(() {
                              _adminStatusFilter = status;
                            });
                            _loadAdminDocuments(page: 1);
                          },
                    selectedColor: AppColors.accentYellow,
                    labelStyle: const TextStyle(
                      color: AppColors.primaryMaroon,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _adminDocumentTypeFilter,
            decoration: const InputDecoration(
              labelText: 'Document Type Filter',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All Document Types')),
              DropdownMenuItem(
                value: 'adhaar_card',
                child: Text('Aadhaar Card'),
              ),
              DropdownMenuItem(value: 'pan_card', child: Text('PAN Card')),
              DropdownMenuItem(
                value: 'personal_photo',
                child: Text('Personal Photo'),
              ),
              DropdownMenuItem(
                value: 'agreement_document',
                child: Text('Agreement Document'),
              ),
            ],
            onChanged: _isLoadingAdminDocuments
                ? null
                : (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _adminDocumentTypeFilter = value;
                    });
                    _loadAdminDocuments(page: 1);
                  },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$_adminTotalCount documents found',
                  style: const TextStyle(
                    color: AppColors.primaryMaroon,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _isLoadingAdminDocuments
                    ? null
                    : () => _loadAdminDocuments(page: _adminCurrentPage),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_isLoadingAdminDocuments)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_adminDocuments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No documents found for the selected filters.',
                style: TextStyle(color: AppColors.primaryMaroon, height: 1.4),
              ),
            )
          else
            Column(
              children: _adminDocuments
                  .map((document) => _buildAdminDocumentCard(document))
                  .toList(),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isLoadingAdminDocuments || _adminCurrentPage <= 1
                      ? null
                      : () => _loadAdminDocuments(page: _adminCurrentPage - 1),
                  child: const Text('Previous'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Page $_adminCurrentPage of $totalPages',
                  style: const TextStyle(color: AppColors.primaryMaroon),
                ),
              ),
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _isLoadingAdminDocuments ||
                          _adminCurrentPage >= totalPages
                      ? null
                      : () => _loadAdminDocuments(page: _adminCurrentPage + 1),
                  child: const Text('Next'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DocumentInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _DocumentInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              '$label:',
              style: const TextStyle(
                color: AppColors.primaryMaroon,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.primaryMaroon),
            ),
          ),
        ],
      ),
    );
  }
}
