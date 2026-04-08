class FeatureFlags {
  final bool showUpdateProfile;
  final bool showRegistration;
  final bool showGat;
  final bool showAttendance;
  final bool showMaintenance;
  final bool showFinance;
  final bool showDocuments;
  final bool showMirvnukLiveTracking;

  FeatureFlags({
    required this.showUpdateProfile,
    required this.showRegistration,
    required this.showGat,
    required this.showAttendance,
    required this.showMaintenance,
    required this.showFinance,
    required this.showDocuments,
    required this.showMirvnukLiveTracking,
  });

  // Backward-compatible aliases used in existing UI code.
  bool get showAutoAssignGat => showGat;
  bool get showIdCardSection => showDocuments;
  bool get showIdCard => showDocuments;

  /// Factory constructor to create FeatureFlags from API JSON.
  ///
  /// When a flag key is absent from the API response, [_toBool] falls back to
  /// [defaultWhenNull].  The defaults here mirror the `?? true / ?? false`
  /// fallbacks used throughout the drawer so that a partial server response
  /// (or a freshly-configured pathak where some keys are missing) still shows
  /// the expected UI.
  factory FeatureFlags.fromJson(Map<String, dynamic> json) {
    return FeatureFlags(
      showUpdateProfile: _toBool(
        json['showUpdateProfile'] ?? json['show_update_profile'],
        defaultWhenNull: true,
      ),
      showRegistration: _toBool(
        json['showRegistration'] ?? json['show_registration'],
        defaultWhenNull: true,
      ),
      showGat: _toBool(
        json['showGat'] ??
            json['show_gat'] ??
            json['showAutoAssignGat'] ??
            json['show_auto_assign_gat'],
        defaultWhenNull: true,
      ),
      showAttendance: _toBool(
        json['showAttendance'] ?? json['show_attendance'],
        defaultWhenNull: true,
      ),
      showMaintenance: _toBool(
        json['showMaintance'] ??
            json['showMaintenance'] ??
            json['show_maintance'] ??
            json['show_maintenance'],
        defaultWhenNull: true,
      ),
      showFinance: _toBool(
        json['showFinance'] ?? json['show_finance'],
        defaultWhenNull: true,
      ),
      showDocuments: _toBool(
        json['showDocuments'] ??
            json['show_documents'] ??
            json['showIdCard'] ??
            json['show_id_card'] ??
            json['showIdCardSection'] ??
            json['show_id_card_section'],
        defaultWhenNull: false,
      ),
      showMirvnukLiveTracking: _toBool(
        json['showMirvnukLiveTracking'] ?? json['show_mirvnuk_live_tracking'],
        defaultWhenNull: false,
      ),
    );
  }

  static bool _toBool(dynamic value, {bool defaultWhenNull = false}) {
    if (value == null) return defaultWhenNull;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return defaultWhenNull;
  }
}
