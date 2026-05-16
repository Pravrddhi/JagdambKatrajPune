import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import '../config/api_endpoints.dart';

class RequestCounts {
  final int documentApprovals;
  final int maintenanceRequests;
  final int userApprovals;
  final int completionRequests;

  RequestCounts({
    this.documentApprovals = 0,
    this.maintenanceRequests = 0,
    this.userApprovals = 0,
    this.completionRequests = 0,
  });

  int get total =>
      documentApprovals +
      maintenanceRequests +
      userApprovals +
      completionRequests;
}

class RequestCountsProvider with ChangeNotifier {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  RequestCounts _counts = RequestCounts();
  bool _isLoading = false;
  String? _error;

  RequestCounts get counts => _counts;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchRequestCounts({
    bool isPathakAdmin = false,
    bool canViewDocumentApprovals = false,
    bool canManageMaintenanceInventory = false,
    bool canApproveMaintenanceEntries = false,
    bool canApproveMaintenanceCompletions = false,
  }) async {
    if (_isLoading) return;

    _isLoading = true;
    _error = null;
    _safeNotifyListeners();

    try {
      final token = await _storage.read(key: ApiEndpoints.accessTokenKey);
      if (token == null) {
        _counts = RequestCounts();
        _isLoading = false;
        _safeNotifyListeners();
        return;
      }

      final headers = ApiEndpoints.authorizedHeaders(token);
      int documentApprovals = 0;
      int maintenanceRequests = 0;
      int userApprovals = 0;
      int completionRequests = 0;

      // Fetch document approvals count
      if (canViewDocumentApprovals) {
        try {
          final docUri = Uri.parse(ApiEndpoints.listPathakDocuments);
          final docResponse = await http
              .get(docUri, headers: headers)
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () => http.Response('{}', 408),
              );

          if (docResponse.statusCode == 200) {
            final docData = jsonDecode(docResponse.body);
            final docs = docData['results'] ?? [];
            documentApprovals = (docs as List)
                .where((d) => d['status'] == 'pending')
                .length;
          }
        } catch (e) {
          // Silently fail, use 0
        }
      }

      // Fetch maintenance inventory requests count
      if (canManageMaintenanceInventory || canApproveMaintenanceEntries) {
        try {
          final maintUri = Uri.parse(
            '${ApiEndpoints.maintenanceInventoryRequests}?status=pending',
          );
          final maintResponse = await http
              .get(maintUri, headers: headers)
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () => http.Response('{}', 408),
              );

          if (maintResponse.statusCode == 200) {
            final maintData = jsonDecode(maintResponse.body);
            final requests = maintData['results'] ?? [];
            maintenanceRequests = (requests as List).length;
          }
        } catch (e) {
          // Silently fail, use 0
        }
      }

      // Fetch completion requests count
      if (canApproveMaintenanceCompletions) {
        try {
          final completionUri = Uri.parse(
            '${ApiEndpoints.maintenanceCompletionRequests}?status=pending',
          );
          final completionResponse = await http
              .get(completionUri, headers: headers)
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () => http.Response('{}', 408),
              );

          if (completionResponse.statusCode == 200) {
            final completionData = jsonDecode(completionResponse.body);
            final completions = completionData['results'] ?? [];
            completionRequests = (completions as List).length;
          }
        } catch (e) {
          // Silently fail, use 0
        }
      }

      // Fetch user approvals count (pathak_admin only)
      if (isPathakAdmin) {
        try {
          final userUri = Uri.parse(
            '${ApiEndpoints.fetchAllUsers}?status=pending',
          );
          final userResponse = await http
              .get(userUri, headers: headers)
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () => http.Response('{}', 408),
              );

          if (userResponse.statusCode == 200) {
            final userData = jsonDecode(userResponse.body);
            final users = userData['results'] ?? [];
            userApprovals = (users as List)
                .where((u) => u['approval_status'] == 'pending')
                .length;
          }
        } catch (e) {
          // Silently fail, use 0
        }
      }

      _counts = RequestCounts(
        documentApprovals: documentApprovals,
        maintenanceRequests: maintenanceRequests,
        userApprovals: userApprovals,
        completionRequests: completionRequests,
      );
    } catch (e) {
      _error = e.toString();
      _counts = RequestCounts();
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  void _safeNotifyListeners() {
    try {
      notifyListeners();
    } catch (e) {
      // Silently ignore if provider is disposed
    }
  }

  void clearCounts() {
    _counts = RequestCounts();
    _safeNotifyListeners();
  }
}
