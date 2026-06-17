import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/api_endpoints.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';

class HomeScreenPhotoManagePanel extends StatefulWidget {
  const HomeScreenPhotoManagePanel({super.key});

  @override
  State<HomeScreenPhotoManagePanel> createState() =>
      _HomeScreenPhotoManagePanelState();
}

class _HomeScreenPhotoManagePanelState
    extends State<HomeScreenPhotoManagePanel> {
  final ImagePicker _picker = ImagePicker();
  final Set<int> _selectedPhotoIds = <int>{};

  List<Map<String, dynamic>> _photos = <Map<String, dynamic>>[];
  bool _isLoading = false;
  bool _isUploading = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _showMessageDialog(
    String message, {
    String title = 'Message',
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadPhotos() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final photos = await ApiService.fetchManageHomeScreenPhotos();
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _selectedPhotoIds.removeWhere(
          (id) => !_photos.any((p) => (p['id'] as num?)?.toInt() == id),
        );
      });
    } catch (e) {
      await _showMessageDialog(
        e.toString().replaceFirst('Exception: ', ''),
        title: 'Error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>?> _openUploadMetaDialog() async {
    final captionController = TextEditingController();
    var isActive = true;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Upload Photo'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: captionController,
                  decoration: const InputDecoration(
                    labelText: 'Caption (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                CheckboxListTile(
                  value: isActive,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (value) {
                    setDialogState(() {
                      isActive = value ?? true;
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop({
                    'caption': captionController.text.trim(),
                    'is_active': isActive,
                  });
                },
                child: const Text('Continue'),
              ),
            ],
          ),
        );
      },
    );

    captionController.dispose();
    return result;
  }

  Future<bool> _confirmUploadPreview({
    required Uint8List imageBytes,
    required String fileName,
    required String caption,
    required bool isActive,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Preview Photo'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    imageBytes,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 180,
                      color: Colors.black12,
                      alignment: Alignment.center,
                      child: const Text('Preview unavailable'),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'File: $fileName',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text('Active: ${isActive ? 'Yes' : 'No'}'),
                if (caption.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Caption: $caption'),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Upload'),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  Future<void> _uploadPhoto() async {
    if (_isUploading) return;

    final metadata = await _openUploadMetaDialog();
    if (metadata == null) return;

    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    final caption = metadata['caption']?.toString().trim() ?? '';
    final isActive = metadata['is_active'] == true;
    final shouldUpload = await _confirmUploadPreview(
      imageBytes: bytes,
      fileName: picked.name,
      caption: caption,
      isActive: isActive,
    );
    if (!shouldUpload || !mounted) return;

    setState(() {
      _isUploading = true;
    });

    try {
      final response = await ApiService.uploadHomeScreenPhoto(
        imageBytes: bytes,
        fileName: picked.name,
        caption: caption,
        isActive: isActive,
      );

      final message = response['message']?.toString().trim();
      await _showMessageDialog(
        message != null && message.isNotEmpty
            ? message
            : 'Home screen photo uploaded successfully.',
        title: 'Success',
      );
      await _loadPhotos();
    } catch (e) {
      await _showMessageDialog(
        e.toString().replaceFirst('Exception: ', ''),
        title: 'Error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _deleteSelectedPhotos() async {
    if (_isDeleting || _selectedPhotoIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Photos'),
        content: Text(
          'Are you sure you want to delete ${_selectedPhotoIds.length} selected photo(s)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      final response = await ApiService.deleteHomeScreenPhotos(
        photoIds: _selectedPhotoIds.toList(),
      );
      final message = response['message']?.toString().trim();
      await _showMessageDialog(
        message != null && message.isNotEmpty
            ? message
            : 'Photos deleted successfully.',
        title: 'Success',
      );
      if (!mounted) return;
      setState(() {
        _selectedPhotoIds.clear();
      });
      await _loadPhotos();
    } catch (e) {
      await _showMessageDialog(
        e.toString().replaceFirst('Exception: ', ''),
        title: 'Error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  String _captionFrom(Map<String, dynamic> photo) {
    final caption = photo['caption']?.toString().trim() ?? '';
    return caption;
  }

  String? _imageUrlFrom(Map<String, dynamic> photo) {
    final imageUrl = _resolvePhotoUrl(photo['image_url']?.toString());
    if (imageUrl.isNotEmpty) return imageUrl;
    final image = _resolvePhotoUrl(photo['image']?.toString());
    if (image.isNotEmpty) return image;
    return null;
  }

  String _resolvePhotoUrl(String? rawUrl) {
    final value = rawUrl?.trim() ?? '';
    if (value.isEmpty) {
      return '';
    }

    Uri configuredRoot() {
      final root = Uri.parse(ApiEndpoints.apiRootUrl);
      final host = root.host.trim().toLowerCase();
      final isLocal =
          host == 'localhost' || host == '127.0.0.1' || host == '::1';
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
    return base.resolve(value).toString();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: _isUploading ? null : _uploadPhoto,
                icon: _isUploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_a_photo),
                label: Text(_isUploading ? 'Uploading...' : 'Upload'),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: (_selectedPhotoIds.isEmpty || _isDeleting)
                    ? null
                    : _deleteSelectedPhotos,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                icon: _isDeleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.delete),
                label: Text(
                  _isDeleting
                      ? 'Deleting...'
                      : 'Delete (${_selectedPhotoIds.length})',
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _isLoading ? null : _loadPhotos,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _photos.isEmpty
              ? const Center(
                  child: Text(
                    'No home screen photos found.',
                    style: TextStyle(color: AppColors.primaryMaroon),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _photos.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, index) {
                    final photo = _photos[index];
                    final id = (photo['id'] as num?)?.toInt();
                    final selected =
                        id != null && _selectedPhotoIds.contains(id);
                    final imageUrl = _imageUrlFrom(photo);
                    final caption = _captionFrom(photo);
                    final isActive = photo['is_active'] == true;

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? AppColors.accentYellow
                              : Colors.black12,
                        ),
                      ),
                      child: ListTile(
                        onTap: id == null
                            ? null
                            : () {
                                setState(() {
                                  if (selected) {
                                    _selectedPhotoIds.remove(id);
                                  } else {
                                    _selectedPhotoIds.add(id);
                                  }
                                });
                              },
                        leading: Checkbox(
                          value: selected,
                          onChanged: id == null
                              ? null
                              : (value) {
                                  setState(() {
                                    if (value == true) {
                                      _selectedPhotoIds.add(id);
                                    } else {
                                      _selectedPhotoIds.remove(id);
                                    }
                                  });
                                },
                        ),
                        title: Text(
                          caption.isNotEmpty ? caption : 'No caption',
                          style: const TextStyle(
                            color: AppColors.primaryMaroon,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ID: ${id ?? '-'} • Active: ${isActive ? 'Yes' : 'No'}',
                              ),
                              const SizedBox(height: 8),
                              if (imageUrl != null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    imageUrl,
                                    height: 140,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) {
                                      return Container(
                                        height: 140,
                                        color: Colors.black12,
                                        alignment: Alignment.center,
                                        child: const Text('Image unavailable'),
                                      );
                                    },
                                  ),
                                )
                              else
                                Container(
                                  height: 90,
                                  alignment: Alignment.center,
                                  color: Colors.black12,
                                  child: const Text('No image URL'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
