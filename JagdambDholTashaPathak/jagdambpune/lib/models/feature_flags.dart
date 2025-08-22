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
      showUpdateProfile: json['showUpdateProfile'] ?? false,
      showRegistration: json['showRegistration'] ?? false,
    );
  }
}
