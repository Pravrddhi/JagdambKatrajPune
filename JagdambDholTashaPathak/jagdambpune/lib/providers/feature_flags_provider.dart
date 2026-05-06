import 'package:flutter/foundation.dart';
import '../models/feature_flags.dart';
import '../services/api_service.dart';
import '../services/web_api_service.dart';

class FeatureFlagsProvider with ChangeNotifier {
  FeatureFlags? _flags;
  bool _isLoading = false;
  String? _error;
  DateTime? _lastFetchedAt;

  static const Duration _minRefreshInterval = Duration(seconds: 2);

  FeatureFlags? get flags => _flags;
  bool get isLoading => _isLoading;
  String? get error => _error;

  FeatureFlagsProvider() {
    fetchFeatureFlags(force: true);
  }

  Future<void> fetchFeatureFlags({bool force = false}) async {
    if (_isLoading) return;

    final lastFetchedAt = _lastFetchedAt;
    if (!force && lastFetchedAt != null) {
      final age = DateTime.now().difference(lastFetchedAt);
      if (age < _minRefreshInterval) return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final fetchedFlags = kIsWeb
          ? await WebApiService.fetchFeatureFlags()
          : await ApiService.fetchFeatureFlags();
      _flags = fetchedFlags;
      _lastFetchedAt = DateTime.now();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setFlags(FeatureFlags flags) {
    _flags = flags;
    notifyListeners();
  }
}
