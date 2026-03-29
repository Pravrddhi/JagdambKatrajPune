class FeatureFlags {
  final bool showUpdateProfile;
  final bool showRegistration;

  FeatureFlags({
    required this.showUpdateProfile,
    required this.showRegistration,
  });

  /// Factory constructor to create FeatureFlags from API JSON
  factory FeatureFlags.fromJson(Map<String, dynamic> json) {
    return FeatureFlags(
      showUpdateProfile: _toBool(
        json['showUpdateProfile'] ?? json['show_update_profile'],
      ),
      showRegistration: _toBool(
        json['showRegistration'] ?? json['show_registration'],
      ),
    );
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }
}
