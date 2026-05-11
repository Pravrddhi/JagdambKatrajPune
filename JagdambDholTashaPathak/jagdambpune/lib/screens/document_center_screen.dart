import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/api_endpoints.dart';
import '../providers/feature_flags_provider.dart';
import '../services/api_service.dart';
import 'id_card_editor_screen.dart';
import '../theme/app_colors.dart';
import '../utils/web_file_picker.dart';

class DocumentCenterScreen extends StatefulWidget {
  final bool isPathakAdmin;
  final Map<String, dynamic>? userDetails;

  const DocumentCenterScreen({
    super.key,
    required this.isPathakAdmin,
    this.userDetails,
  });

  @override
  State<DocumentCenterScreen> createState() => _DocumentCenterScreenState();
}

class _DocumentCenterScreenState extends State<DocumentCenterScreen>
    with SingleTickerProviderStateMixin {
  static const int _maxLongestEdge = 1600;
  static const int _targetMaxUploadBytes = 1500 * 1024;

  static const Map<String, String> _documentTypeLabels = {
    'adhaar_card': 'Aadhaar Card',
    'pan_card': 'PAN Card',
    'personal_photo': 'Personal Photo',
    'agreement_document': 'Agreement Document',
  };

  // 'pii' or 'agreement'
  String _selectedCategory = 'pii';

  final ImagePicker _imagePicker = ImagePicker();
  String _selectedDocumentType = 'adhaar_card';
  Uint8List? _selectedBytes;
  String? _selectedFileName;
  bool _isPicking = false;
  bool _isUploading = false;
  bool _isLoadingAdminDocuments = false;
  int _adminCurrentPage = 1;
  int _adminTotalCount = 0;
  final int _adminPageSize = 20;
  String _adminStatusFilter = 'pending';
  String _adminDocumentTypeFilter = 'all';
  List<Map<String, dynamic>> _adminDocuments = <Map<String, dynamic>>[];
  final Set<int> _reviewingDocumentIds = <int>{};
  List<Map<String, dynamic>> _myDocuments = <Map<String, dynamic>>[];
  bool _isLoadingMyDocuments = false;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _uploadSectionKey = GlobalKey();
  late final TabController _userTabController;
  int _lastUserTabIndex = 0;
  int _idCardRefreshTick = 0;

  @override
  void initState() {
    super.initState();
    _userTabController = TabController(length: 2, vsync: this)
      ..addListener(_handleUserTabChange);
    if (widget.isPathakAdmin) {
      _loadAdminDocuments();
    } else {
      _loadMyDocuments();
    }
  }

  void _handleUserTabChange() {
    if (_userTabController.indexIsChanging) {
      return;
    }
    if (_userTabController.index == _lastUserTabIndex) {
      return;
    }

    _lastUserTabIndex = _userTabController.index;
    if (_lastUserTabIndex == 0) {
      _loadMyDocuments();
      return;
    }

    setState(() {
      _idCardRefreshTick++;
    });
  }

  @override
  void dispose() {
    _userTabController
      ..removeListener(_handleUserTabChange)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMyDocuments() async {
    setState(() {
      _isLoadingMyDocuments = true;
    });
    try {
      final docs = await ApiService.fetchMyDocuments();
      if (!mounted) return;
      setState(() {
        _myDocuments = docs;
      });
    } catch (_) {
      // supplementary — silently fail
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMyDocuments = false;
        });
      }
    }
  }

  void _scrollToUploadSection() {
    final ctx = _uploadSectionKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  bool _isAllowedJpegFileName(String fileName) {
    final lowerFileName = fileName.trim().toLowerCase();
    return lowerFileName.endsWith('.jpg') || lowerFileName.endsWith('.jpeg');
  }

  bool _isJpegBytes(Uint8List bytes) {
    // JPEG files begin with FF D8 FF.
    return bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;
  }

  String _ensureJpegFileName(String fileName, {required String fallback}) {
    final trimmed = fileName.trim();
    final base = trimmed.isEmpty ? fallback : trimmed;
    if (_isAllowedJpegFileName(base)) {
      return base;
    }
    final dotIndex = base.lastIndexOf('.');
    final nameWithoutExt = dotIndex > 0 ? base.substring(0, dotIndex) : base;
    return '$nameWithoutExt.jpg';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }

  Uint8List? _toOptimizedJpegBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return _isJpegBytes(bytes) ? bytes : null;
    }

    final oriented = img.bakeOrientation(decoded);
    img.Image processed = oriented;

    final longestEdge = oriented.width >= oriented.height
        ? oriented.width
        : oriented.height;
    if (longestEdge > _maxLongestEdge) {
      final scale = _maxLongestEdge / longestEdge;
      processed = img.copyResize(
        oriented,
        width: (oriented.width * scale).round(),
        height: (oriented.height * scale).round(),
        interpolation: img.Interpolation.linear,
      );
    }

    const qualitySteps = <int>[82, 74, 68, 62];
    List<int> encoded = img.encodeJpg(processed, quality: qualitySteps.first);
    for (final quality in qualitySteps.skip(1)) {
      if (encoded.length <= _targetMaxUploadBytes) {
        break;
      }
      encoded = img.encodeJpg(processed, quality: quality);
    }

    return Uint8List.fromList(encoded);
  }

  String _normalizePickedFileName(XFile pickedFile, ImageSource source) {
    final rawName = pickedFile.name.trim();
    if (rawName.isEmpty) {
      return source == ImageSource.camera
          ? 'captured_document.jpg'
          : 'selected_document.jpg';
    }

    if (_isAllowedJpegFileName(rawName)) {
      return rawName;
    }

    if (!rawName.contains('.')) {
      return '$rawName.jpg';
    }

    return rawName;
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_isPicking || _isUploading) {
      return;
    }

    setState(() {
      _isPicking = true;
    });

    try {
      if (kIsWeb) {
        // On web, bypass the image_picker plugin channel entirely and use the
        // browser's native file input via dart:html to avoid channel errors.
        // input.click() inside pickJpegFile is synchronous, so gesture context
        // is preserved even when called from a bottom-sheet onTap.
        final result = await pickJpegFile(
          useCamera: source == ImageSource.camera,
        );
        if (result == null) {
          return;
        }
        final rawName = result.value.trim();
        final convertedBytes = _toOptimizedJpegBytes(result.key);
        if (convertedBytes == null) {
          _showSnackBar('Only JPG and JPEG images are supported.');
          return;
        }
        final normalizedName = _ensureJpegFileName(
          rawName,
          fallback: 'selected_document.jpg',
        );
        if (!mounted) return;
        setState(() {
          _selectedBytes = convertedBytes;
          _selectedFileName = normalizedName;
        });
        return;
      }

      final pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 90,
      );

      if (pickedFile == null) {
        return;
      }

      final bytes = await pickedFile.readAsBytes();
      final convertedBytes = _toOptimizedJpegBytes(bytes);
      if (convertedBytes == null) {
        _showSnackBar('Only JPG and JPEG images are supported.');
        return;
      }
      final normalizedFileName = _ensureJpegFileName(
        _normalizePickedFileName(pickedFile, source),
        fallback: source == ImageSource.camera
            ? 'captured_document.jpg'
            : 'selected_document.jpg',
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _selectedBytes = convertedBytes;
        _selectedFileName = normalizedFileName;
      });
    } catch (error) {
      _showSnackBar(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  Future<void> _uploadDocument() async {
    if (_isUploading) {
      return;
    }
    if (_selectedBytes == null || _selectedFileName == null) {
      _showSnackBar('Please select a JPG or JPEG image first.');
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final response = await ApiService.uploadDocument(
        documentType: _selectedDocumentType,
        fileBytes: _selectedBytes!,
        fileName: _selectedFileName!,
      );

      if (!mounted) {
        return;
      }

      // Reset the form after a successful upload.
      setState(() {
        _selectedBytes = null;
        _selectedFileName = null;
        _selectedCategory = 'pii';
        _selectedDocumentType = 'adhaar_card';
      });

      if (widget.isPathakAdmin) {
        _loadAdminDocuments(page: 1);
      } else {
        _loadMyDocuments();
      }

      _showSnackBar(response['message']?.toString() ?? 'Document uploaded.');
    } catch (error) {
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadAdminDocuments({int page = 1}) async {
    if (!widget.isPathakAdmin) {
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
    final trimmed = _resolveDocumentUrl(url);
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

  String _resolveDocumentUrl(String? rawUrl) {
    final value = rawUrl?.trim() ?? '';
    if (value.isEmpty) {
      return '';
    }

    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme) {
      return value;
    }

    final root = Uri.parse(ApiEndpoints.apiRootUrl);
    final normalizedPath = value.startsWith('/') ? value : '/$value';
    return root.resolve(normalizedPath).toString();
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
    final trimmedUrl = _resolveDocumentUrl(documentUrl);
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

  Widget _buildAdminReviewSection() {
    final totalPages = _adminTotalCount == 0
        ? 1
        : ((_adminTotalCount - 1) ~/ _adminPageSize) + 1;

    return _SectionCard(
      title: 'Review Documents',
      subtitle:
          'Review uploaded documents for users in your pathak. Use filters to inspect pending, approved, or rejected submissions.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          _InfoRow(
            label: 'Phone',
            value: document['uploaded_by_phone']?.toString() ?? '-',
          ),
          _InfoRow(
            label: 'Type',
            value: _documentTypeLabel(document['document_type']?.toString()),
          ),
          _InfoRow(
            label: 'Created At',
            value: document['created_at']?.toString() ?? '-',
          ),
          if (reviewedBy != null && reviewedBy.isNotEmpty)
            _InfoRow(label: 'Reviewed By', value: reviewedBy),
          if (reviewedAt != null && reviewedAt.isNotEmpty)
            _InfoRow(label: 'Reviewed At', value: reviewedAt),
          if (rejectionReason.trim().isNotEmpty)
            _InfoRow(label: 'Reason', value: rejectionReason),
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

  Widget _buildMyDocumentsSection({required bool showIdCardTab}) {
    if (_isLoadingMyDocuments) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_myDocuments.isEmpty) {
      return const SizedBox.shrink();
    }

    // Show only the latest document per type so a re-uploaded pending item
    // replaces the previous rejected card instead of creating a duplicate.
    final latestByType = <String, Map<String, dynamic>>{};
    for (final doc in _myDocuments) {
      final rawType = doc['document_type']?.toString().trim();
      final fallbackId = doc['id']?.toString() ?? '';
      final key = (rawType == null || rawType.isEmpty)
          ? '__unknown_$fallbackId'
          : rawType;

      final existing = latestByType[key];
      if (existing == null) {
        latestByType[key] = doc;
        continue;
      }

      final existingAt = DateTime.tryParse(
        existing['created_at']?.toString() ?? '',
      );
      final incomingAt = DateTime.tryParse(doc['created_at']?.toString() ?? '');
      final shouldReplace =
          incomingAt != null &&
          (existingAt == null || incomingAt.isAfter(existingAt));

      if (shouldReplace) {
        latestByType[key] = doc;
      }
    }

    final displayDocuments = latestByType.values.toList()
      ..sort((a, b) {
        final aAt = DateTime.tryParse(a['created_at']?.toString() ?? '');
        final bAt = DateTime.tryParse(b['created_at']?.toString() ?? '');
        if (aAt == null && bAt == null) return 0;
        if (aAt == null) return 1;
        if (bAt == null) return -1;
        return bAt.compareTo(aAt);
      });

    return _SectionCard(
      title: 'My Documents',
      subtitle: 'Status of your submitted documents.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...displayDocuments.map((doc) {
            final status = doc['status']?.toString().toLowerCase() ?? '';
            final type = _documentTypeLabel(doc['document_type']?.toString());
            final reason = doc['rejection_reason']?.toString() ?? '';
            final createdAt = doc['created_at']?.toString() ?? '';
            final docType = doc['document_type']?.toString() ?? '';

            Color statusColor;
            IconData statusIcon;
            String statusLabel;
            switch (status) {
              case 'approved':
                statusColor = Colors.green.shade700;
                statusIcon = Icons.check_circle;
                statusLabel = 'Approved';
                break;
              case 'rejected':
                statusColor = Colors.red.shade700;
                statusIcon = Icons.cancel;
                statusLabel = 'Rejected';
                break;
              default:
                statusColor = Colors.orange.shade700;
                statusIcon = Icons.hourglass_empty;
                statusLabel = 'Pending';
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(statusIcon, color: statusColor, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          type,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (createdAt.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Submitted: $createdAt',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (status == 'rejected' && reason.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Reason: $reason',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (status == 'rejected' && docType != 'id_card') ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          setState(() {
                            if (_documentTypeLabels.containsKey(docType)) {
                              _selectedDocumentType = docType;
                              _selectedCategory =
                                  (docType == 'adhaar_card' ||
                                      docType == 'pan_card' ||
                                      docType == 'personal_photo')
                                  ? 'pii'
                                  : 'agreement';
                            }
                            _selectedBytes = null;
                            _selectedFileName = null;
                          });
                          _scrollToUploadSection();
                          await Future<void>.delayed(
                            const Duration(milliseconds: 220),
                          );
                          if (!mounted) {
                            return;
                          }
                          await _showImageSourcePicker();
                        },
                        icon: const Icon(Icons.upload_file, size: 18),
                        label: const Text('Upload Again'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade700),
                        ),
                      ),
                    ),
                  ],
                  if (status == 'rejected' && docType == 'id_card') ...[
                    const SizedBox(height: 10),
                    Text(
                      showIdCardTab
                          ? 'Use the ID Card tab to submit your ID card again.'
                          : 'ID Card resubmission is currently unavailable.',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _showImageSourcePicker() async {
    if (_isPicking || _isUploading) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.photo_camera,
                    color: AppColors.primaryMaroon,
                  ),
                  title: const Text(
                    'Take Photo',
                    style: TextStyle(color: AppColors.primaryMaroon),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _pickImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.photo_library,
                    color: AppColors.primaryMaroon,
                  ),
                  title: const Text(
                    'Choose from Gallery',
                    style: TextStyle(color: AppColors.primaryMaroon),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _pickImage(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDocumentsContent({required bool showIdCardTab}) {
    return SafeArea(
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.isPathakAdmin) ...[
              _buildMyDocumentsSection(showIdCardTab: showIdCardTab),
              const SizedBox(height: 16),
            ],
            _SectionCard(
              key: _uploadSectionKey,
              title: 'Upload Document',
              subtitle: 'Upload photo as JPG.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Document Category',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'pii',
                        child: Text('PII Document'),
                      ),
                      DropdownMenuItem(
                        value: 'agreement',
                        child: Text('Agreement Document'),
                      ),
                    ],
                    onChanged: _isUploading
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              _selectedCategory = value;
                              _selectedDocumentType = value == 'pii'
                                  ? 'adhaar_card'
                                  : 'agreement_document';
                            });
                          },
                  ),
                  const SizedBox(height: 12),
                  if (_selectedCategory == 'pii')
                    DropdownButtonFormField<String>(
                      value: _selectedDocumentType,
                      decoration: const InputDecoration(
                        labelText: 'PII Document Type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'adhaar_card',
                          child: Text('Aadhaar Card'),
                        ),
                        DropdownMenuItem(
                          value: 'pan_card',
                          child: Text('PAN Card'),
                        ),
                        DropdownMenuItem(
                          value: 'personal_photo',
                          child: Text('Personal Photo'),
                        ),
                      ],
                      onChanged: _isUploading
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() {
                                _selectedDocumentType = value;
                              });
                            },
                    )
                  else
                    DropdownButtonFormField<String>(
                      value: _selectedDocumentType,
                      decoration: const InputDecoration(
                        labelText: 'Agreement Type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'agreement_document',
                          child: Text(
                            'Agreement Document (more types coming soon)',
                          ),
                        ),
                      ],
                      onChanged: _isUploading
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() {
                                _selectedDocumentType = value;
                              });
                            },
                    ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: (_isPicking || _isUploading)
                        ? null
                        : _showImageSourcePicker,
                    icon: _isPicking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file),
                    label: Text(
                      _isPicking
                          ? 'Loading Photo...'
                          : _selectedFileName == null
                          ? 'Add JPG Image'
                          : 'Replace Image',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryMaroon,
                      side: const BorderSide(color: AppColors.primaryMaroon),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Upload photo as JPG.',
                    style: TextStyle(
                      color: AppColors.primaryMaroon,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  if (_selectedFileName != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Selected: $_selectedFileName',
                      style: const TextStyle(
                        color: AppColors.primaryMaroon,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_selectedBytes != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Optimized size: ${_formatBytes(_selectedBytes!.length)}',
                        style: TextStyle(
                          color: AppColors.primaryMaroon.withValues(alpha: 0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                  if (_selectedBytes != null) ...[
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _selectedBytes!,
                        height: 220,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed:
                        (_isUploading ||
                            _isPicking ||
                            _selectedBytes == null ||
                            _selectedFileName == null)
                        ? null
                        : _uploadDocument,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryMaroon,
                      foregroundColor: AppColors.textLight,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _isUploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.textLight,
                              ),
                            ),
                          )
                        : const Text('Upload Document'),
                  ),
                ],
              ),
            ),
            if (widget.isPathakAdmin) ...[
              const SizedBox(height: 16),
              _buildAdminReviewSection(),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showIdCardTab =
        context.watch<FeatureFlagsProvider>().flags?.showIdCard ?? false;

    if (widget.isPathakAdmin) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Document Center'),
          backgroundColor: AppColors.primaryMaroon,
          foregroundColor: AppColors.textLight,
        ),
        body: _buildDocumentsContent(showIdCardTab: showIdCardTab),
      );
    }

    if (!showIdCardTab) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Document Center'),
          backgroundColor: AppColors.primaryMaroon,
          foregroundColor: AppColors.textLight,
        ),
        body: _buildDocumentsContent(showIdCardTab: false),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Document Center'),
        backgroundColor: AppColors.primaryMaroon,
        foregroundColor: AppColors.textLight,
        bottom: TabBar(
          controller: _userTabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.description_outlined), text: 'Documents'),
            Tab(icon: Icon(Icons.credit_card), text: 'ID Card'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _userTabController,
        children: [
          _buildDocumentsContent(showIdCardTab: true),
          IDCardEditorScreen(
            refreshTick: _idCardRefreshTick,
            userDetails: widget.userDetails,
            showAppBar: false,
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.primaryMaroon,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: AppColors.primaryMaroon, height: 1.4),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            color: AppColors.primaryMaroon,
            fontSize: 14,
            height: 1.4,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
