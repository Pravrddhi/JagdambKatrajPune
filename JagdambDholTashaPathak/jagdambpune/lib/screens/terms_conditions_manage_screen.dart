import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/api_endpoints.dart';
import '../services/authorized_api_service.dart';
import '../services/bug_report_service.dart';
import '../theme/app_colors.dart';

class TermsConditionsManageScreen extends StatefulWidget {
  const TermsConditionsManageScreen({super.key});

  @override
  State<TermsConditionsManageScreen> createState() =>
      _TermsConditionsManageScreenState();
}

class _TermsConditionsManageScreenState
    extends State<TermsConditionsManageScreen> {
  static const int _maxTerms = 5;

  bool _isLoading = false;
  bool _isSubmitting = false;
  String _errorMessage = '';
  List<Map<String, dynamic>> _terms = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _fetchTerms();
  }

  Future<void> _fetchTerms() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await AuthorizedApiService.sendWithAutoRefresh(
        null,
        (token) => http.get(
          Uri.parse(ApiEndpoints.termsAndConditionsManage),
          headers: ApiEndpoints.authorizedHeaders(token),
        ),
      );

      if (response == null) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Session expired. Please login again.';
          _isLoading = false;
        });
        return;
      }

      final decoded = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : <String, dynamic>{};

      if (response.statusCode == 200 &&
          decoded is Map<String, dynamic> &&
          decoded['status'] == true) {
        final rawTerms = decoded['terms'];
        final parsed = <Map<String, dynamic>>[];
        if (rawTerms is List) {
          for (final item in rawTerms) {
            if (item is Map<String, dynamic>) {
              final id = int.tryParse(item['id']?.toString() ?? '');
              final text = item['text']?.toString().trim() ?? '';
              if (id != null && text.isNotEmpty) {
                parsed.add(<String, dynamic>{'id': id, 'text': text});
              }
            }
          }
        }

        if (!mounted) return;
        setState(() {
          _terms = parsed;
          _isLoading = false;
        });
        return;
      }

      await BugReportService.reportApiFailure(
        title: 'Terms manage list API failed',
        errorMessage: response.body,
        pageUrl: '/terms-manage',
        statusCode: response.statusCode,
        endpoint: ApiEndpoints.termsAndConditionsManage,
      );

      if (!mounted) return;
      setState(() {
        _errorMessage = decoded is Map<String, dynamic>
            ? decoded['message']?.toString() ??
                  ApiEndpoints.genericApiFailureMessage
            : ApiEndpoints.genericApiFailureMessage;
        _isLoading = false;
      });
    } catch (e) {
      await BugReportService.reportApiFailure(
        title: 'Terms manage list API exception',
        errorMessage: e.toString(),
        pageUrl: '/terms-manage',
        endpoint: ApiEndpoints.termsAndConditionsManage,
      );

      if (!mounted) return;
      setState(() {
        _errorMessage = ApiEndpoints.serverUnreachableMessage;
        _isLoading = false;
      });
    }
  }

  Future<void> _createTerm(String text) async {
    await _mutateTerm(
      method: 'POST',
      payload: <String, dynamic>{'text': text},
      failureTitle: 'Terms manage create API failed',
      exceptionTitle: 'Terms manage create API exception',
    );
  }

  Future<void> _updateTerm(int termId, String text) async {
    await _mutateTerm(
      method: 'PUT',
      payload: <String, dynamic>{'term_id': termId, 'text': text},
      failureTitle: 'Terms manage update API failed',
      exceptionTitle: 'Terms manage update API exception',
    );
  }

  Future<void> _deleteTerm(int termId) async {
    await _mutateTerm(
      method: 'DELETE',
      payload: <String, dynamic>{'term_id': termId},
      failureTitle: 'Terms manage delete API failed',
      exceptionTitle: 'Terms manage delete API exception',
    );
  }

  Future<void> _mutateTerm({
    required String method,
    required Map<String, dynamic> payload,
    required String failureTitle,
    required String exceptionTitle,
  }) async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final response = await AuthorizedApiService.sendWithAutoRefresh(null, (
        token,
      ) {
        final uri = Uri.parse(ApiEndpoints.termsAndConditionsManage);
        final headers = ApiEndpoints.authorizedHeaders(token);
        final body = jsonEncode(payload);

        switch (method) {
          case 'POST':
            return http.post(uri, headers: headers, body: body);
          case 'PUT':
            return http.put(uri, headers: headers, body: body);
          case 'DELETE':
            return http.delete(uri, headers: headers, body: body);
          default:
            throw UnsupportedError('Unsupported method: $method');
        }
      });

      if (response == null) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Session expired. Please login again.';
        });
        return;
      }

      final decoded = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : <String, dynamic>{};

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          decoded is Map<String, dynamic> &&
          decoded['status'] == true) {
        await _fetchTerms();
        return;
      }

      await BugReportService.reportApiFailure(
        title: failureTitle,
        errorMessage: response.body,
        pageUrl: '/terms-manage',
        statusCode: response.statusCode,
        endpoint: ApiEndpoints.termsAndConditionsManage,
      );

      if (!mounted) return;
      setState(() {
        _errorMessage = decoded is Map<String, dynamic>
            ? decoded['message']?.toString() ??
                  ApiEndpoints.genericApiFailureMessage
            : ApiEndpoints.genericApiFailureMessage;
      });
    } catch (e) {
      await BugReportService.reportApiFailure(
        title: exceptionTitle,
        errorMessage: e.toString(),
        pageUrl: '/terms-manage',
        endpoint: ApiEndpoints.termsAndConditionsManage,
      );

      if (!mounted) return;
      setState(() {
        _errorMessage = ApiEndpoints.serverUnreachableMessage;
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Future<void> _openTermDialog({Map<String, dynamic>? existing}) async {
    final controller = TextEditingController(
      text: existing?['text']?.toString() ?? '',
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            existing == null ? 'Add Term' : 'Edit Term',
            style: const TextStyle(color: AppColors.primaryMaroon),
          ),
          content: TextField(
            controller: controller,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
              hintText: 'Enter term and condition text',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryMaroon,
              ),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: AppColors.primaryMaroon,
              ),
              onPressed: _isSubmitting
                  ? null
                  : () async {
                      final text = controller.text.trim();
                      if (text.isEmpty) return;

                      Navigator.pop(dialogContext);
                      if (existing == null) {
                        await _createTerm(text);
                      } else {
                        final id = int.tryParse(
                          existing['id']?.toString() ?? '',
                        );
                        if (id != null) {
                          await _updateTerm(id, text);
                        }
                      }
                    },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(int termId) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Delete Term',
          style: TextStyle(color: AppColors.primaryMaroon),
        ),
        content: const Text(
          'Are you sure you want to delete this term?',
          style: TextStyle(color: AppColors.primaryMaroon),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryMaroon,
            ),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              foregroundColor: AppColors.primaryMaroon,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      await _deleteTerm(termId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Manage Terms & Conditions'),
        backgroundColor: AppColors.primaryMaroon,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _fetchTerms,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Total terms: ${_terms.length} / $_maxTerms',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryMaroon,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_errorMessage.isNotEmpty)
                    Text(
                      _errorMessage,
                      style: const TextStyle(color: AppColors.errorRed),
                    ),
                  const SizedBox(height: 8),
                  if (_terms.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Text(
                        'No terms added yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.primaryMaroon),
                      ),
                    ),
                  ..._terms.map((term) {
                    final id = int.tryParse(term['id']?.toString() ?? '');
                    final text = term['text']?.toString() ?? '';
                    return Card(
                      color: Colors.white,
                      margin: const EdgeInsets.only(top: 10),
                      child: ListTile(
                        title: Text(
                          text,
                          style: const TextStyle(
                            color: AppColors.primaryMaroon,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              color: AppColors.primaryMaroon,
                              onPressed: id == null || _isSubmitting
                                  ? null
                                  : () => _openTermDialog(existing: term),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              color: AppColors.errorRed,
                              onPressed: id == null || _isSubmitting
                                  ? null
                                  : () => _confirmDelete(id),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      foregroundColor: AppColors.primaryMaroon,
                    ),
                    onPressed: (_terms.length >= _maxTerms || _isSubmitting)
                        ? null
                        : () => _openTermDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Term'),
                  ),
                  if (_terms.length >= _maxTerms)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Maximum 5 terms are allowed per pathak.',
                        style: TextStyle(color: AppColors.primaryMaroon),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
