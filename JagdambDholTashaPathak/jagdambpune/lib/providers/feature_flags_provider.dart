import 'package:flutter/foundation.dart';
import '../models/feature_flags.dart';
import '../services/api_service.dart';

class FeatureFlagsProvider with ChangeNotifier {
  FeatureFlags? _flags;
  bool _isLoading = false;
  String? _error;

  FeatureFlags? get flags => _flags;
  bool get isLoading => _isLoading;
  String? get error => _error;

  FeatureFlagsProvider() {
    fetchFeatureFlags();
  }

  Future<void> fetchFeatureFlags() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final fetchedFlags = await ApiService.fetchFeatureFlags();
      _flags = fetchedFlags;
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
