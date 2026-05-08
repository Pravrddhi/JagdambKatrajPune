import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../config/api_endpoints.dart';
import '../services/api_service.dart';
import '../services/authorized_api_service.dart';
import '../services/user_item_service.dart';
import '../theme/app_colors.dart';

class IDCardEditorScreen extends StatefulWidget {
  final Map<String, dynamic>? userDetails;
  final bool showAppBar;
  final int refreshTick;

  const IDCardEditorScreen({
    super.key,
    this.userDetails,
    this.showAppBar = true,
    this.refreshTick = 0,
  });

  @override
  State<IDCardEditorScreen> createState() => _IDCardEditorScreenState();
}

class _IDCardEditorScreenState extends State<IDCardEditorScreen> {
  static const String _defaultTemplateType = 'dhol';

  final ImagePicker _picker = ImagePicker();
  final TextEditingController _nameController = TextEditingController();
  final GlobalKey _cardRepaintKey = GlobalKey();

  File? _selectedImageFile;
  Uint8List? _selectedImageBytes;
  bool _isLoadingTemplateImage = false;
  bool _isPickingImage = false;
  bool _isResizingFrame = false;
  bool _isSubmitting = false;
  bool _isCapturing = false;
  String? _idCardDocumentStatus;
  String? _idCardRejectionReason;
  String? _idCardDocumentUrl;
  Uint8List? _pendingSubmittedCardBytes;
  Uint8List? _submittedCardBytes;
  String? _submittedCardBytesUrl;
  bool _isLoadingSubmittedCardBytes = false;
  String? _submittedCardBytesError;
  Uint8List? _templateImageBytes;
  String? _templateImageUrl; // used on web only
  static const double _minImageScale = 1.08;
  static const double _maxImageScale = 4.0;
  static const double _minFrameWidthFactor = 0.20;
  static const double _maxFrameWidthFactor = 0.92;
  static const double _minFrameHeightFactor = 0.12;
  static const double _maxFrameHeightFactor = 0.70;
  static const double _frameWidthStep = 0.005;
  static const double _cornerHandleSizeFactor = 0.010;
  static const double _cornerResizeBoost = 5.00;
  double _imageScale = _minImageScale;
  double _baseImageScale = _minImageScale;
  double _frameWidthFactor = 0.480;
  double _frameLeftFactor = 0.260;
  double _frameTopFactor = 0.340;
  double _frameHeightFactor = 0.320;
  Offset _imageOffset = Offset.zero;
  Offset _baseImageOffset = Offset.zero;
  Size _photoFrameSize = Size.zero;
  static const double _positionStep = 8.0;

  double _safeFactor(
    double? value, {
    required double min,
    required double max,
    required double fallback,
  }) {
    final v = value;
    if (v == null || !v.isFinite) {
      return fallback;
    }
    return v.clamp(min, max);
  }

  double _safeFinite(double? value, {required double fallback}) {
    final v = value;
    if (v == null || !v.isFinite) {
      return fallback;
    }
    return v;
  }

  bool get _hasSelectedImage {
    if (kIsWeb) {
      return _selectedImageBytes != null;
    }
    return _selectedImageFile != null;
  }

  String get _liveFrameSizeLabel {
    final widthPercent = (_frameWidthFactor * 100).toStringAsFixed(1);
    final heightPercent = (_frameHeightFactor * 100).toStringAsFixed(1);
    return 'W: $widthPercent%  H: $heightPercent%';
  }

  String get _normalizedIdCardStatus =>
      _idCardDocumentStatus?.trim().toLowerCase() ?? '';

  bool get _isIdCardInReview {
    final normalized = _normalizedIdCardStatus;
    return normalized == 'pending' ||
        normalized == 'in_review' ||
        normalized == 'under_review';
  }

  bool get _isIdCardLocked {
    final normalized = _normalizedIdCardStatus;
    return _isIdCardInReview || normalized == 'approved';
  }

  bool get _hasSubmittedCardUrl {
    return (_idCardDocumentUrl?.trim().isNotEmpty ?? false);
  }

  bool get _shouldShowSubmittedCard {
    final normalized = _normalizedIdCardStatus;
    if (normalized == 'rejected') {
      return false;
    }
    return _hasSubmittedCardUrl;
  }

  bool get _canSubmitIdCard {
    if (_isSubmitting) return false;
    final normalized = _normalizedIdCardStatus;
    return normalized.isEmpty || normalized == 'rejected';
  }

  String _firstNonEmpty(Iterable<dynamic> values) {
    for (final raw in values) {
      final text = raw?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  String _resolveAbsoluteUrl(String? rawUrl) {
    final value = rawUrl?.trim() ?? '';
    if (value.isEmpty) {
      return '';
    }

    Uri configuredRoot() {
      final root = Uri.parse(ApiEndpoints.apiRootUrl);
      final host = root.host.trim().toLowerCase();
      final isLocal =
          host == 'localhost' || host == '127.0.0.1' || host == '::1';
      // Don't upgrade to https when a non-standard port is in use —
      // the server is likely HTTP-only on that port (e.g. 8080).
      final hasNonStandardPort =
          root.hasPort && root.port != 80 && root.port != 443;

      if (root.scheme == 'http' && !isLocal && !hasNonStandardPort) {
        return root.replace(scheme: 'https');
      }
      return root;
    }

    String fromConfiguredRoot({required String path, String? query}) {
      final root = configuredRoot();
      final normalizedPath = path.startsWith('/') ? path : '/$path';
      final resolved = root.resolve(normalizedPath);
      if (query == null || query.isEmpty) {
        return resolved.toString();
      }
      return resolved.replace(query: query).toString();
    }

    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme) {
      return value;
    }

    if (value.startsWith('/media/')) {
      return fromConfiguredRoot(path: value);
    }

    final base = configuredRoot();
    final resolved = base.resolve(value);
    return resolved.toString();
  }

  String get _idCardSubmitLabel {
    if (_isSubmitting) return 'Submitting...';

    switch (_normalizedIdCardStatus) {
      case 'pending':
      case 'in_review':
      case 'under_review':
        return 'ID Card In Review';
      case 'approved':
        return 'ID Card Approved';
      case 'rejected':
        return 'Submit Again';
      default:
        return 'Submit for Review';
    }
  }

  @override
  void initState() {
    super.initState();
    _nameController.text = _resolvedFullName;
    _refreshFromApi();
  }

  @override
  void didUpdateWidget(covariant IDCardEditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshTick != oldWidget.refreshTick) {
      _refreshFromApi();
    }
  }

  void _refreshFromApi() {
    _loadTemplateImage();
    _loadIdCardDocumentStatus();
  }

  Future<void> _loadIdCardDocumentStatus() async {
    try {
      final docs = await ApiService.fetchMyDocuments();
      final idCardDocs = docs.where((doc) {
        final type = doc['document_type']?.toString().trim().toLowerCase();
        return type == 'id_card';
      }).toList();

      if (!mounted) return;

      if (idCardDocs.isEmpty) {
        setState(() {
          _idCardDocumentStatus = null;
          _idCardRejectionReason = null;
          _idCardDocumentUrl = null;
          _pendingSubmittedCardBytes = null;
          _submittedCardBytes = null;
          _submittedCardBytesUrl = null;
          _submittedCardBytesError = null;
        });
        return;
      }

      idCardDocs.sort((a, b) {
        final aDate = DateTime.tryParse(a['created_at']?.toString() ?? '');
        final bDate = DateTime.tryParse(b['created_at']?.toString() ?? '');
        if (aDate != null && bDate != null) {
          return bDate.compareTo(aDate);
        }
        final aId = int.tryParse(a['id']?.toString() ?? '') ?? 0;
        final bId = int.tryParse(b['id']?.toString() ?? '') ?? 0;
        return bId.compareTo(aId);
      });

      final latest = idCardDocs.first;
      final status = latest['status']?.toString().trim().toLowerCase();
      final rejectionReason = latest['rejection_reason']?.toString().trim();
      final documentUrl = _firstNonEmpty([
        latest['document_url'],
        latest['document'],
        latest['document_file'],
        latest['file_url'],
        latest['url'],
      ]);

      if (!mounted) return;
      setState(() {
        _idCardDocumentStatus = status;
        _idCardRejectionReason =
            (rejectionReason == null || rejectionReason.isEmpty)
            ? null
            : rejectionReason;
        final resolvedUrl = _resolveAbsoluteUrl(documentUrl);
        _idCardDocumentUrl = resolvedUrl.isEmpty ? null : resolvedUrl;
        if (!_isIdCardLocked) {
          _pendingSubmittedCardBytes = null;
          _submittedCardBytes = null;
          _submittedCardBytesUrl = null;
          _submittedCardBytesError = null;
        }
      });

      if (!kIsWeb) {
        await _prefetchSubmittedCardBytes();
      }
    } catch (_) {
      // Keep editor usable if status API fails.
    }
  }

  Future<void> _prefetchSubmittedCardBytes() async {
    if (!_shouldShowSubmittedCard) {
      return;
    }

    final url = _idCardDocumentUrl?.trim() ?? '';
    if (url.isEmpty) {
      return;
    }

    if (_submittedCardBytes != null && _submittedCardBytesUrl == url) {
      return;
    }
    if (_isLoadingSubmittedCardBytes) {
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoadingSubmittedCardBytes = true;
      _submittedCardBytesError = null;
    });

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        throw Exception('status ${response.statusCode}');
      }

      if (!mounted) return;
      setState(() {
        _submittedCardBytes = response.bodyBytes;
        _submittedCardBytesUrl = url;
        _submittedCardBytesError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submittedCardBytes = null;
        _submittedCardBytesUrl = null;
        _submittedCardBytesError = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingSubmittedCardBytes = false;
      });
    }
  }

  Future<void> _loadTemplateImage() async {
    if (!mounted) return;
    setState(() {
      _isLoadingTemplateImage = true;
    });

    try {
      final query = <String, dynamic>{
        'pathak_id': _resolvedPathakId,
        'template_type': _resolvedTemplateType,
      };
      final uri = ApiEndpoints.buildUri(ApiEndpoints.idTemplateImages, query);

      final response = await AuthorizedApiService.sendWithAutoRefresh(
        null,
        (token) =>
            http.get(uri, headers: ApiEndpoints.authorizedHeaders(token)),
      );

      if (response == null) {
        return;
      }
      if (response.statusCode != 200) {
        return;
      }

      final decoded = jsonDecode(response.body);
      final templates = _extractTemplateList(decoded);
      if (templates.isEmpty) {
        if (!mounted) return;
        setState(() {
          _templateImageBytes = null;
        });
        return;
      }

      final String? selectedUrl = _pickTemplateImageUrl(templates);
      if (!mounted) return;
      final resolvedUrl = _resolveAbsoluteUrl(selectedUrl);
      if (resolvedUrl.isEmpty) {
        setState(() {
          _templateImageBytes = null;
        });
        return;
      }

      // On web: Image.network handles loading (avoids CORS fetch restrictions).
      // On mobile: fetch bytes with auth headers for protected media URLs.
      if (kIsWeb) {
        if (!mounted) return;
        setState(() {
          _templateImageUrl = resolvedUrl;
          _templateImageBytes = null;
        });
      } else {
        // Fetch image bytes with auth headers so protected media URLs work.
        final imgResponse = await AuthorizedApiService.sendWithAutoRefresh(
          null,
          (token) => http.get(
            Uri.parse(resolvedUrl),
            headers: {'Authorization': 'Bearer $token'},
          ),
        );
        if (!mounted) return;
        if (imgResponse != null &&
            imgResponse.statusCode == 200 &&
            imgResponse.bodyBytes.isNotEmpty) {
          setState(() {
            _templateImageBytes = imgResponse.bodyBytes;
            _templateImageUrl = null;
          });
        } else {
          setState(() {
            _templateImageBytes = null;
            _templateImageUrl = null;
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTemplateImage = false;
        });
      }
    }
  }

  int get _resolvedPathakId {
    final details = widget.userDetails;
    if (details != null) {
      final nested = details['data'];
      final dynamic candidate =
          details['pathak_id'] ??
          details['pathak'] ??
          (nested is Map<String, dynamic>
              ? (nested['pathak_id'] ?? nested['pathak'])
              : null) ??
          (nested is Map ? (nested['pathak_id'] ?? nested['pathak']) : null);

      if (candidate is int) {
        return candidate;
      }
      if (candidate is String) {
        final parsed = int.tryParse(candidate);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return ApiEndpoints.pathakIdInt;
  }

  String get _resolvedTemplateType {
    final details = widget.userDetails;
    if (details != null) {
      final nested = details['data'];
      final dynamic candidate =
          details['instrument'] ??
          details['instrument_name'] ??
          details['instrumentName'] ??
          (nested is Map<String, dynamic>
              ? (nested['instrument'] ??
                    nested['instrument_name'] ??
                    nested['instrumentName'])
              : null) ??
          (nested is Map
              ? (nested['instrument'] ??
                    nested['instrument_name'] ??
                    nested['instrumentName'])
              : null);

      final normalized = candidate?.toString().trim().toLowerCase() ?? '';
      if (normalized == 'dhol' || normalized == 'tasha') {
        return normalized;
      }
    }
    return _defaultTemplateType;
  }

  String? _pickTemplateImageUrl(List<dynamic> templates) {
    String? activeTyped;
    String? typedAnyState;
    String? activeAnyType;
    String? fallbackUrl;

    bool parseBool(dynamic value) {
      if (value is bool) return value;
      if (value is num) return value == 1;
      final normalized = value?.toString().trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }

    for (final item in templates) {
      if (item is! Map) continue;

      final imageUrl =
          item['image']?.toString().trim() ??
          item['image_url']?.toString().trim() ??
          item['template_image']?.toString().trim() ??
          item['url']?.toString().trim() ??
          '';
      if (imageUrl.isEmpty) {
        continue;
      }
      fallbackUrl ??= imageUrl;

      final isActive = parseBool(item['is_active']);
      final type = item['template_type']?.toString().trim().toLowerCase();
      if (type == _resolvedTemplateType) {
        typedAnyState ??= imageUrl;
        if (isActive) {
          activeTyped ??= imageUrl;
        }
      }
      if (isActive) {
        activeAnyType ??= imageUrl;
      }
    }

    return activeTyped ?? typedAnyState ?? activeAnyType ?? fallbackUrl;
  }

  List<dynamic> _extractTemplateList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is! Map) return const <dynamic>[];

    final data = decoded['data'];
    if (data is List) return data;

    final results = decoded['results'];
    if (results is List) return results;

    // Some APIs return the template object directly under data/template.
    if (data is Map) {
      final nestedList = data['results'] ?? data['items'] ?? data['templates'];
      if (nestedList is List) return nestedList;

      final single = data['template'] ?? data;
      if (single is Map) return <dynamic>[single];
    }

    final template = decoded['template'];
    if (template is Map) return <dynamic>[template];

    return const <dynamic>[];
  }

  String get _resolvedFullName {
    final details = widget.userDetails;
    if (details == null) return '';

    final nested = details['data'];
    final firstName =
        details['first_name']?.toString().trim() ??
        (nested is Map<String, dynamic>
            ? nested['first_name']?.toString().trim()
            : null) ??
        (nested is Map ? nested['first_name']?.toString().trim() : null) ??
        '';
    final lastName =
        details['last_name']?.toString().trim() ??
        (nested is Map<String, dynamic>
            ? nested['last_name']?.toString().trim()
            : null) ??
        (nested is Map ? nested['last_name']?.toString().trim() : null) ??
        '';
    final fullName = '$firstName $lastName'.trim();
    if (fullName.isNotEmpty) {
      return fullName;
    }
    return details['name']?.toString().trim() ??
        (nested is Map<String, dynamic>
            ? nested['name']?.toString().trim()
            : null) ??
        (nested is Map ? nested['name']?.toString().trim() : null) ??
        '';
  }

  String get _bloodGroup {
    final details = widget.userDetails;
    if (details == null) return '--';

    final nested = details['data'];
    final value =
        details['blood_group']?.toString().trim() ??
        details['bloodGroup']?.toString().trim() ??
        (nested is Map<String, dynamic>
            ? nested['blood_group']?.toString().trim()
            : null) ??
        (nested is Map<String, dynamic>
            ? nested['bloodGroup']?.toString().trim()
            : null) ??
        (nested is Map ? nested['blood_group']?.toString().trim() : null) ??
        (nested is Map ? nested['bloodGroup']?.toString().trim() : null) ??
        '';
    return value.isEmpty ? '--' : value.toUpperCase();
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() {
      _isPickingImage = true;
    });

    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 90);
      if (picked == null || !mounted) return;

      Uint8List? pickedBytes;
      if (kIsWeb) {
        pickedBytes = await picked.readAsBytes();
      }

      setState(() {
        _selectedImageFile = kIsWeb ? null : File(picked.path);
        _selectedImageBytes = pickedBytes;
        _imageScale = _minImageScale;
        _baseImageScale = _minImageScale;
        _imageOffset = Offset.zero;
        _baseImageOffset = Offset.zero;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Unable to pick image: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isPickingImage = false;
        });
      }
    }
  }

  Future<void> _openImageSourcePicker() async {
    if (_isPickingImage || _isIdCardLocked) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickImage(ImageSource.camera);
                },
              ),
              if (_hasSelectedImage)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Remove current photo'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    setState(() {
                      _selectedImageFile = null;
                      _selectedImageBytes = null;
                      _imageScale = _minImageScale;
                      _baseImageScale = _minImageScale;
                      _imageOffset = Offset.zero;
                      _baseImageOffset = Offset.zero;
                    });
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submitForReview({bool fromDialog = false}) async {
    if (_isSubmitting) return;

    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Please enter your name in Marathi.')),
        );
      return;
    }
    if (!_hasSelectedImage) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Please upload your image first.')),
        );
      return;
    }

    // Close the preview dialog before submitting (if called from within it)
    if (fromDialog && mounted) {
      Navigator.of(context).pop();
    }

    if (!mounted) return;
    setState(() {
      _isSubmitting = true;
      _isCapturing = true;
    });
    // Wait one frame so Flutter repaints the card without controls.
    await Future<void>.delayed(Duration.zero);

    // Guard against navigation/hot-reload disposing the view during the delay.
    if (!mounted) return;

    try {
      // Capture the card widget as PNG bytes
      final boundary =
          _cardRepaintKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Could not capture card image. Please try again.');
      }
      final ui.Image image;
      try {
        image = await boundary.toImage(pixelRatio: 2.0);
      } catch (e) {
        throw Exception('Could not capture card image. Please try again.');
      }
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('Failed to encode card as PNG.');
      }
      final pngBytes = byteData.buffer.asUint8List();

      final uploadResponse = await ApiService.uploadDocument(
        documentType: 'id_card',
        fileBytes: pngBytes,
        fileName: 'id_card.png',
      );

      // Add an ID card entry to the user's items list with status pending.
      try {
        await UserItemService.createItem({
          'item_name': 'ID Card',
          'item_type': 'id_card',
          'status': 'pending',
          'payment_status': 'pending',
        });
      } catch (_) {
        // Non-fatal — document already submitted; item creation failure
        // should not block the success message.
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('ID card submitted for review successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      final uploadedUrl = _firstNonEmpty([
        uploadResponse['document_url'],
        uploadResponse['document'],
        uploadResponse['document_file'],
        uploadResponse['file_url'],
        uploadResponse['url'],
      ]);

      setState(() {
        _idCardDocumentStatus = 'pending';
        _idCardRejectionReason = null;
        final resolvedUrl = _resolveAbsoluteUrl(uploadedUrl);
        _idCardDocumentUrl = resolvedUrl.isEmpty ? null : resolvedUrl;
        // Immediate fallback so template does not flash while backend list refreshes.
        _pendingSubmittedCardBytes = pngBytes;
        _submittedCardBytes = pngBytes;
        _submittedCardBytesUrl = _idCardDocumentUrl;
        _submittedCardBytesError = null;
      });

      await _loadIdCardDocumentStatus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _isCapturing = false;
        });
      }
    }
  }

  Future<void> _showPreview() async {
    FocusScope.of(context).unfocus();
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Please enter your name in Marathi.')),
        );
      return;
    }
    if (!_hasSelectedImage) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Please upload your image first.')),
        );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ID Card Preview',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  _buildCardPreview(maxWidth: 360, isPreview: true),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('ID Card'),
              backgroundColor: AppColors.primaryMaroon,
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RepaintBoundary(
                key: _cardRepaintKey,
                child: _buildCardPreview(
                  isPreview: _isIdCardLocked || _isCapturing,
                ),
              ),
              const SizedBox(height: 16),
              _buildNameField(),
              if (_idCardDocumentStatus == 'rejected' &&
                  _idCardRejectionReason != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Previous rejection reason: $_idCardRejectionReason',
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _buildBloodGroupCard(),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _showPreview,
                icon: const Icon(Icons.preview),
                label: const Text('Preview'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryMaroon,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: _canSubmitIdCard ? _submitForReview : null,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : (_idCardDocumentStatus == 'approved'
                          ? const Icon(Icons.check_circle_outline)
                          : _idCardDocumentStatus == 'pending'
                          ? const Icon(Icons.hourglass_top_outlined)
                          : const Icon(Icons.send_outlined)),
                label: Text(_idCardSubmitLabel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _idCardDocumentStatus == 'approved'
                      ? Colors.green.shade700
                      : _idCardDocumentStatus == 'pending'
                      ? Colors.grey.shade500
                      : AppColors.accentYellow,
                  foregroundColor:
                      _idCardDocumentStatus == null ||
                          _idCardDocumentStatus == 'rejected'
                      ? AppColors.primaryMaroon
                      : Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNameField() {
    return TextField(
      controller: _nameController,
      textCapitalization: TextCapitalization.words,
      enabled: !_isIdCardLocked,
      inputFormatters: [LengthLimitingTextInputFormatter(32)],
      onChanged: (_) {
        setState(() {});
      },
      decoration: InputDecoration(
        labelText: 'Name in Marathi',
        hintText: 'उदा. मेघलाल महेंद्र सावंत',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        prefixIcon: const Icon(Icons.badge_outlined),
      ),
    );
  }

  Widget _buildBloodGroupCard() {
    return Card(
      child: ListTile(
        leading: const Icon(
          Icons.bloodtype_outlined,
          color: AppColors.primaryMaroon,
        ),
        title: const Text('Blood Group'),
        subtitle: Text(
          _bloodGroup,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildCardPreview({double? maxWidth, bool isPreview = false}) {
    final preview = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth ?? 420),
        child: AspectRatio(
          aspectRatio: 768 / 1152,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              final hasLockedSubmittedCard = _shouldShowSubmittedCard;

              return ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildTemplateBackground(),
                    if (hasLockedSubmittedCard)
                      Positioned.fill(child: _buildSubmittedCardLayer()),
                    if (!hasLockedSubmittedCard) ...[
                      _buildInteractivePhotoLayer(
                        width,
                        height,
                        isPreview: isPreview,
                      ),
                      Positioned(
                        left: width * 0.10,
                        right: width * 0.10,
                        top: height * 0.685,
                        height: height * 0.075,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.center,
                          child: Text(
                            _nameController.text.trim().isEmpty
                                ? 'तुमचे नाव'
                                : _nameController.text.trim(),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            style: const TextStyle(fontFamily: 'Shreelipi4642')
                                .merge(
                                  TextStyle(
                                    color: Colors.white,
                                    fontSize: width * 0.062,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                    height: 1.1,
                                    shadows: const [
                                      Shadow(
                                        color: Color(0xCC000000),
                                        offset: Offset(1.5, 1.5),
                                        blurRadius: 4,
                                      ),
                                      Shadow(
                                        color: Color(0x66000000),
                                        offset: Offset(3, 3),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: width * 0.52,
                        top: height * 0.774,
                        child: Text(
                          _bloodGroup,
                          textAlign: TextAlign.left,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: width * 0.053,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(12), child: preview),
    );
  }

  Widget _buildSubmittedCardLayer() {
    final pendingBytes = _pendingSubmittedCardBytes;
    if (pendingBytes != null && pendingBytes.isNotEmpty) {
      return Image.memory(pendingBytes, fit: BoxFit.cover);
    }

    final submittedBytes = _submittedCardBytes;
    if (submittedBytes != null && submittedBytes.isNotEmpty) {
      return Image.memory(submittedBytes, fit: BoxFit.cover);
    }

    final submittedUrl = _idCardDocumentUrl?.trim() ?? '';
    if (kIsWeb && submittedUrl.isNotEmpty) {
      return Image.network(
        submittedUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const ColoredBox(color: Color(0xFFE0E0E0)),
      );
    }

    if (_isLoadingSubmittedCardBytes) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if ((_submittedCardBytesError?.trim().isNotEmpty ?? false) && !kIsWeb) {
      return ColoredBox(
        color: const Color(0xFFE0E0E0),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Unable to load submitted card.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return const ColoredBox(color: Color(0xFFE0E0E0));
  }

  Widget _buildInteractivePhotoLayer(
    double width,
    double height, {
    bool isPreview = false,
  }) {
    // Frame factors are editable so users can fine tune and resize from corners.
    final frameWidth = width * _frameWidthFactor;
    final frameLeft = width * _frameLeftFactor;
    final photoRect = Rect.fromLTWH(
      frameLeft,
      height * _frameTopFactor,
      frameWidth,
      height * _frameHeightFactor,
    );
    _photoFrameSize = Size(photoRect.width, photoRect.height);

    return Positioned.fromRect(
      rect: photoRect,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(38),
        child: ColoredBox(
          color: Colors.white,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openImageSourcePicker,
            onScaleStart: (_) {
              _baseImageScale = _imageScale;
              _baseImageOffset = _imageOffset;
            },
            onScaleUpdate: (details) {
              if (!_hasSelectedImage || _isIdCardLocked) {
                return;
              }
              setState(() {
                final nextScale = (_baseImageScale * details.scale).clamp(
                  _minImageScale,
                  _maxImageScale,
                );
                _imageScale = nextScale;
                _imageOffset = _clampImageOffset(
                  _baseImageOffset + details.focalPointDelta,
                  scale: nextScale,
                );
              });
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: !_hasSelectedImage
                      ? Center(
                          child: _isPickingImage
                              ? const SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primaryMaroon,
                                  ),
                                )
                              : const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.add_a_photo_outlined,
                                      color: Colors.grey,
                                      size: 36,
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Tap to upload',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                        )
                      : ClipRect(
                          child: Transform.translate(
                            offset: _imageOffset,
                            child: Transform.scale(
                              scale: _imageScale,
                              child: SizedBox.expand(
                                child: _buildPickedImage(),
                              ),
                            ),
                          ),
                        ),
                ),
                if (_hasSelectedImage && !isPreview)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildFrameControlButton(
                          icon: Icons.photo_camera_outlined,
                          tooltip: 'Change photo',
                          onTap: _openImageSourcePicker,
                        ),
                        const SizedBox(width: 6),
                        _buildFrameControlButton(
                          icon: Icons.refresh,
                          tooltip: 'Reset position',
                          onTap: _resetImageAdjustments,
                        ),
                        const SizedBox(width: 6),
                        _buildFrameControlButton(
                          icon: Icons.width_normal,
                          tooltip: 'Frame width -',
                          onTap: () => _setFrameWidthFactor(
                            _frameWidthFactor - _frameWidthStep,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _buildFrameControlButton(
                          icon: Icons.width_wide,
                          tooltip: 'Frame width +',
                          onTap: () => _setFrameWidthFactor(
                            _frameWidthFactor + _frameWidthStep,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_hasSelectedImage && !isPreview)
                  Positioned(
                    bottom: 8,
                    left: 8,
                    right: 8,
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      runAlignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _buildFrameControlButton(
                          icon: Icons.remove,
                          tooltip: 'Zoom out',
                          onTap: () => _setScale(_imageScale - 0.06),
                        ),
                        _buildFrameControlButton(
                          icon: Icons.keyboard_arrow_left,
                          tooltip: 'Move left',
                          onTap: () => _nudgeImage(-_positionStep, 0),
                        ),
                        _buildFrameControlButton(
                          icon: Icons.keyboard_arrow_up,
                          tooltip: 'Move up',
                          onTap: () => _nudgeImage(0, -_positionStep),
                        ),
                        _buildFrameControlButton(
                          icon: Icons.keyboard_arrow_down,
                          tooltip: 'Move down',
                          onTap: () => _nudgeImage(0, _positionStep),
                        ),
                        _buildFrameControlButton(
                          icon: Icons.keyboard_arrow_right,
                          tooltip: 'Move right',
                          onTap: () => _nudgeImage(_positionStep, 0),
                        ),
                        _buildFrameControlButton(
                          icon: Icons.add,
                          tooltip: 'Zoom in',
                          onTap: () => _setScale(_imageScale + 0.06),
                        ),
                      ],
                    ),
                  ),
                if (_hasSelectedImage && _isResizingFrame && !isPreview)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          child: Text(
                            _liveFrameSizeLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_hasSelectedImage && !isPreview)
                  ..._buildCornerHandles(width, height),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPickedImage() {
    if (kIsWeb) {
      final bytes = _selectedImageBytes;
      if (bytes == null) {
        return const SizedBox.shrink();
      }
      return Image.memory(bytes, fit: BoxFit.cover);
    }

    final file = _selectedImageFile;
    if (file == null) {
      return const SizedBox.shrink();
    }
    return Image.file(file, fit: BoxFit.cover);
  }

  Widget _buildTemplateBackground() {
    if (_isLoadingTemplateImage) {
      return const Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Color(0xFFE0E0E0)),
          Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ],
      );
    }

    // Web: use Image.network (img tag bypasses CORS restrictions).
    if (kIsWeb) {
      final url = _templateImageUrl;
      if (url == null || url.isEmpty) {
        return const ColoredBox(color: Color(0xFFE0E0E0));
      }
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const ColoredBox(color: Color(0xFFE0E0E0)),
      );
    }

    // Mobile: use pre-fetched bytes.
    final bytes = _templateImageBytes;
    if (bytes == null || bytes.isEmpty) {
      return const ColoredBox(color: Color(0xFFE0E0E0));
    }
    return Image.memory(bytes, fit: BoxFit.cover);
  }

  void _nudgeImage(double dx, double dy) {
    if (!_hasSelectedImage) return;
    setState(() {
      _imageOffset = _clampImageOffset(
        Offset(_imageOffset.dx + dx, _imageOffset.dy + dy),
        scale: _imageScale,
      );
    });
  }

  void _resetImageAdjustments() {
    if (!_hasSelectedImage) return;
    setState(() {
      _imageScale = _minImageScale;
      _baseImageScale = _minImageScale;
      _imageOffset = Offset.zero;
      _baseImageOffset = Offset.zero;
    });
  }

  void _setScale(double value) {
    if (!_hasSelectedImage) return;
    final next = value.clamp(_minImageScale, _maxImageScale);
    setState(() {
      _imageScale = next;
      _baseImageScale = next;
      _imageOffset = _clampImageOffset(_imageOffset, scale: next);
    });
  }

  void _setFrameWidthFactor(double value) {
    final next = value.clamp(_minFrameWidthFactor, _maxFrameWidthFactor);
    setState(() {
      final centerX = _frameLeftFactor + (_frameWidthFactor / 2);
      _frameWidthFactor = next;
      _frameLeftFactor = (centerX - (_frameWidthFactor / 2)).clamp(
        0.0,
        1.0 - _frameWidthFactor,
      );
      _imageOffset = _clampImageOffset(_imageOffset, scale: _imageScale);
    });
  }

  List<Widget> _buildCornerHandles(double width, double height) {
    final shortestSide = width < height ? width : height;
    final handleSize = shortestSide * _cornerHandleSizeFactor;
    final frameLeft = width * _frameLeftFactor;
    final frameTop = height * _frameTopFactor;
    final frameWidth = width * _frameWidthFactor;
    final frameHeight = height * _frameHeightFactor;

    return [
      _buildCornerHandle(
        left: frameLeft - (handleSize / 2),
        top: frameTop - (handleSize / 2),
        size: handleSize,
        onPanStart: () {
          if (_isResizingFrame) return;
          setState(() {
            _isResizingFrame = true;
          });
        },
        onPanUpdate: (delta) =>
            _resizeFrameFromCorner(delta, width, height, corner: 'tl'),
        onPanEnd: () {
          if (!_isResizingFrame) return;
          setState(() {
            _isResizingFrame = false;
          });
        },
      ),
      _buildCornerHandle(
        left: frameLeft + frameWidth - (handleSize / 2),
        top: frameTop - (handleSize / 2),
        size: handleSize,
        onPanStart: () {
          if (_isResizingFrame) return;
          setState(() {
            _isResizingFrame = true;
          });
        },
        onPanUpdate: (delta) =>
            _resizeFrameFromCorner(delta, width, height, corner: 'tr'),
        onPanEnd: () {
          if (!_isResizingFrame) return;
          setState(() {
            _isResizingFrame = false;
          });
        },
      ),
      _buildCornerHandle(
        left: frameLeft - (handleSize / 2),
        top: frameTop + frameHeight - (handleSize / 2),
        size: handleSize,
        onPanStart: () {
          if (_isResizingFrame) return;
          setState(() {
            _isResizingFrame = true;
          });
        },
        onPanUpdate: (delta) =>
            _resizeFrameFromCorner(delta, width, height, corner: 'bl'),
        onPanEnd: () {
          if (!_isResizingFrame) return;
          setState(() {
            _isResizingFrame = false;
          });
        },
      ),
      _buildCornerHandle(
        left: frameLeft + frameWidth - (handleSize / 2),
        top: frameTop + frameHeight - (handleSize / 2),
        size: handleSize,
        onPanStart: () {
          if (_isResizingFrame) return;
          setState(() {
            _isResizingFrame = true;
          });
        },
        onPanUpdate: (delta) =>
            _resizeFrameFromCorner(delta, width, height, corner: 'br'),
        onPanEnd: () {
          if (!_isResizingFrame) return;
          setState(() {
            _isResizingFrame = false;
          });
        },
      ),
    ];
  }

  Widget _buildCornerHandle({
    required double left,
    required double top,
    required double size,
    required VoidCallback onPanStart,
    required ValueChanged<Offset> onPanUpdate,
    required VoidCallback onPanEnd,
  }) {
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onPanStart: (_) => onPanStart(),
        onPanUpdate: (details) => onPanUpdate(details.delta),
        onPanEnd: (_) => onPanEnd(),
        onPanCancel: onPanEnd,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primaryMaroon, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _resizeFrameFromCorner(
    Offset delta,
    double cardWidth,
    double cardHeight, {
    required String corner,
  }) {
    if (!cardWidth.isFinite || !cardHeight.isFinite) {
      return;
    }
    if (cardWidth <= 0 || cardHeight <= 0) {
      return;
    }

    final dx = _safeFinite(
      (delta.dx / cardWidth) * _cornerResizeBoost,
      fallback: 0.0,
    );
    final dy = _safeFinite(
      (delta.dy / cardHeight) * _cornerResizeBoost,
      fallback: 0.0,
    );

    var left = _frameLeftFactor;
    var top = _frameTopFactor;
    var width = _frameWidthFactor;
    var frameHeight = _frameHeightFactor;

    switch (corner) {
      case 'tl':
        left += dx;
        top += dy;
        width -= dx;
        frameHeight -= dy;
        break;
      case 'tr':
        top += dy;
        width += dx;
        frameHeight -= dy;
        break;
      case 'bl':
        left += dx;
        width -= dx;
        frameHeight += dy;
        break;
      default: // br
        width += dx;
        frameHeight += dy;
        break;
    }

    width = _safeFactor(
      width,
      min: _minFrameWidthFactor,
      max: _maxFrameWidthFactor,
      fallback: _frameWidthFactor,
    );
    frameHeight = _safeFactor(
      frameHeight,
      min: _minFrameHeightFactor,
      max: _maxFrameHeightFactor,
      fallback: _frameHeightFactor,
    );
    left = _safeFactor(
      left,
      min: 0.0,
      max: 1.0 - width,
      fallback: _frameLeftFactor,
    );
    top = _safeFactor(
      top,
      min: 0.0,
      max: 1.0 - frameHeight,
      fallback: _frameTopFactor,
    );

    setState(() {
      _frameLeftFactor = left;
      _frameTopFactor = top;
      _frameWidthFactor = width;
      _frameHeightFactor = frameHeight;
      _imageOffset = _clampImageOffset(_imageOffset, scale: _imageScale);
    });
  }

  Offset _clampImageOffset(Offset candidate, {required double scale}) {
    if (!_photoFrameSize.width.isFinite || !_photoFrameSize.height.isFinite) {
      return Offset.zero;
    }
    if (_photoFrameSize == Size.zero || !scale.isFinite) {
      return candidate;
    }

    final rawDx = ((_photoFrameSize.width * scale) - _photoFrameSize.width) / 2;
    final rawDy =
        ((_photoFrameSize.height * scale) - _photoFrameSize.height) / 2;
    final maxDx = _safeFinite(rawDx, fallback: 0.0).abs();
    final maxDy = _safeFinite(rawDy, fallback: 0.0).abs();
    final safeDx = _safeFinite(candidate.dx, fallback: 0.0);
    final safeDy = _safeFinite(candidate.dy, fallback: 0.0);

    return Offset(safeDx.clamp(-maxDx, maxDx), safeDy.clamp(-maxDy, maxDy));
  }

  Widget _buildFrameControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(icon, size: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
