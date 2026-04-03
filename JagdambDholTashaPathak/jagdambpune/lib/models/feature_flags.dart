class FeatureFlags {
  final bool showUpdateProfile;
  final bool showRegistration;
  final bool showAutoAssignGat;
  final bool showIdCardSection;

  FeatureFlags({
    required this.showUpdateProfile,
    required this.showRegistration,
    required this.showAutoAssignGat,
    required this.showIdCardSection,
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
      showAutoAssignGat: _toBool(
        json['showAutoAssignGat'] ?? json['show_auto_assign_gat'],
      ),
      showIdCardSection: _toBool(
        json['showIdCardSection'] ?? json['show_id_card_section'],
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
