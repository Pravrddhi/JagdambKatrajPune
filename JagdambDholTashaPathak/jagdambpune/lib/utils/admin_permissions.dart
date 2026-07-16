/// Utility class for managing admin permissions from login API
class AdminPermissions {
  /// Parse and extract admin permissions from the login API permissions JSON
  static AdminPermissions fromPermissionsMap(
    Map<String, dynamic>? permissions,
  ) {
    if (permissions == null) {
      return AdminPermissions();
    }

    return AdminPermissions(
      canGenerateAttendanceQr:
          _parseBool(permissions['generate_attendance_qr']) ||
          _parseBool(permissions['attendance_qr_generation']),
      canDownloadAttendanceQr: _parseBool(
        permissions['download_attendance_qr'],
      ),
      canSetAttendanceLocation:
          _parseBool(permissions['set_attendance_location']) ||
          _parseBool(permissions['attendance_location_setting']),
      canViewAttendanceByUser:
          _parseBool(permissions['view_attendance_by_user']) ||
          _parseBool(permissions['attendance_view_by_user']),
      canViewDocumentApprovals:
          _parseBool(permissions['document_approval']) ||
          _parseBool(permissions['view_document_approvals']),
      canManageMaintenanceInventory:
          _parseBool(permissions['update_maintance_stock']) ||
          _parseBool(permissions['maintenance_inventory']),
      canApproveMaintenanceEntries:
          _parseBool(permissions['maintance_stock_approval']) ||
          _parseBool(permissions['maintenance_approval']),
      canCreateMaintenanceEvents:
          _parseBool(permissions['maintance_create_event']) ||
          _parseBool(permissions['maintenance_event_create']),
      canApproveMaintenanceCompletions: _parseBool(
        permissions['maintenance_approval'],
      ),
      canViewMaintenanceAnalysis:
          _parseBool(permissions['maintance_analysis']) ||
          _parseBool(permissions['maintenance_analysis']),
      canManageTerms: _parseBool(permissions['manage_terms']),
      canUpdateUserGroup: _parseBool(permissions['user_approval']),
      canViewUserAnalysis: _parseBool(permissions['user_analysis']),
      canManageHomeScreenPhotos: _parseBool(
        permissions['manage_home_screen_photos'],
      ),
    );
  }

  /// Parse and extract admin permissions from user details JSON
  /// This can be from the login response or from userDetails in HomeScreen
  static AdminPermissions fromUserDetails(Map<String, dynamic>? userDetails) {
    if (userDetails == null) {
      return AdminPermissions();
    }

    // Try to get permissions from top level or nested 'data'
    Map<String, dynamic>? permissions = userDetails['permissions'];
    if (permissions == null && userDetails['data'] is Map) {
      permissions = userDetails['data']['permissions'];
    }

    return fromPermissionsMap(permissions);
  }

  final bool canGenerateAttendanceQr;
  final bool canDownloadAttendanceQr;
  final bool canSetAttendanceLocation;
  final bool canViewAttendanceByUser;
  final bool canViewDocumentApprovals;
  final bool canManageMaintenanceInventory;
  final bool canApproveMaintenanceEntries;
  final bool canCreateMaintenanceEvents;
  final bool canApproveMaintenanceCompletions;
  final bool canViewMaintenanceAnalysis;
  final bool canManageTerms;
  final bool canUpdateUserGroup;
  final bool canViewUserAnalysis;
  final bool canManageHomeScreenPhotos;

  AdminPermissions({
    this.canGenerateAttendanceQr = false,
    this.canDownloadAttendanceQr = false,
    this.canSetAttendanceLocation = false,
    this.canViewAttendanceByUser = false,
    this.canViewDocumentApprovals = false,
    this.canManageMaintenanceInventory = false,
    this.canApproveMaintenanceEntries = false,
    this.canCreateMaintenanceEvents = false,
    this.canApproveMaintenanceCompletions = false,
    this.canViewMaintenanceAnalysis = false,
    this.canManageTerms = false,
    this.canUpdateUserGroup = false,
    this.canViewUserAnalysis = false,
    this.canManageHomeScreenPhotos = false,
  });

  /// Check if user has any admin permissions
  bool get hasAnyPermission =>
      canGenerateAttendanceQr ||
      canDownloadAttendanceQr ||
      canSetAttendanceLocation ||
      canViewAttendanceByUser ||
      canViewDocumentApprovals ||
      canManageMaintenanceInventory ||
      canApproveMaintenanceEntries ||
      canCreateMaintenanceEvents ||
      canApproveMaintenanceCompletions ||
      canViewMaintenanceAnalysis ||
      canManageTerms ||
      canUpdateUserGroup ||
      canViewUserAnalysis ||
      canManageHomeScreenPhotos;

  /// Convert to map for passing to AdminOperationsScreen
  Map<String, bool> toMap() => {
    'canGenerateAttendanceQr': canGenerateAttendanceQr,
    'canDownloadAttendanceQr': canDownloadAttendanceQr,
    'canSetAttendanceLocation': canSetAttendanceLocation,
    'canViewAttendanceByUser': canViewAttendanceByUser,
    'canViewDocumentApprovals': canViewDocumentApprovals,
    'canManageMaintenanceInventory': canManageMaintenanceInventory,
    'canApproveMaintenanceEntries': canApproveMaintenanceEntries,
    'canCreateMaintenanceEvents': canCreateMaintenanceEvents,
    'canApproveMaintenanceCompletions': canApproveMaintenanceCompletions,
    'canViewMaintenanceAnalysis': canViewMaintenanceAnalysis,
    'canManageTerms': canManageTerms,
    'canUpdateUserGroup': canUpdateUserGroup,
    'canViewUserAnalysis': canViewUserAnalysis,
    'canManageHomeScreenPhotos': canManageHomeScreenPhotos,
  };
}

/// Helper function to parse boolean values from various types
bool _parseBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value == 1;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }
  return false;
}
