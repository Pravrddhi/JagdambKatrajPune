import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/animated_navigation.dart'; // ✅ Reusable animation
import '../screens/document_center_screen.dart';
import '../screens/gat_details_screen.dart';
import '../screens/coming_soon_screen.dart';
import '../screens/attendance_module_screen.dart';
import '../screens/dhol_maintenance_screen.dart';
import '../screens/admin_operations_screen.dart';

class AppDrawer extends StatelessWidget {
  final String? firstName;
  final String? phoneNumber;
  final Map<String, dynamic>? userDetails;
  final VoidCallback onLogout;

  const AppDrawer({
    super.key,
    this.firstName,
    this.phoneNumber,
    this.userDetails,
    required this.onLogout,
  });

  Map<String, dynamic> get _permissions {
    final details = userDetails;
    if (details == null) return <String, dynamic>{};

    final topLevel = details['permissions'];
    if (topLevel is Map<String, dynamic>) return topLevel;
    if (topLevel is Map) return Map<String, dynamic>.from(topLevel);

    final nested = details['data'];
    if (nested is Map<String, dynamic>) {
      final nestedPermissions = nested['permissions'];
      if (nestedPermissions is Map<String, dynamic>) return nestedPermissions;
      if (nestedPermissions is Map) {
        return Map<String, dynamic>.from(nestedPermissions);
      }
    }
    if (nested is Map) {
      final nestedPermissions = nested['permissions'];
      if (nestedPermissions is Map<String, dynamic>) return nestedPermissions;
      if (nestedPermissions is Map) {
        return Map<String, dynamic>.from(nestedPermissions);
      }
    }

    return <String, dynamic>{};
  }

  bool _permissionBool(String key, {bool fallback = false}) {
    final permissions = _permissions;
    if (permissions.containsKey(key)) {
      return _parseBool(permissions[key]);
    }
    return fallback;
  }

  bool _permissionIsGatOnly(String key) {
    final permissions = _permissions;
    if (!permissions.containsKey(key)) return false;
    final normalized = permissions[key]?.toString().trim().toLowerCase();
    return normalized == 'gat_only';
  }

  void _navigateToProfile(BuildContext context) {
    Navigator.pop(context); // Close drawer first
    final details = userDetails;
    if (details != null) {
      AnimatedNavigation.pushProfile(context, details); // ✅ Central animation
    } else {
      // Fallback: Open empty profile
      AnimatedNavigation.pushProfile(context, {});
    }
  }

  void _navigateToGatDetails(BuildContext context) {
    Navigator.pop(context); // Close drawer first
    final selectedGatId = int.tryParse(
      userDetails?['gat_id']?.toString() ??
          userDetails?['gatId']?.toString() ??
          '',
    );
    final selectedGatName =
        userDetails?['gat_name']?.toString() ??
        userDetails?['gatName']?.toString() ??
        userDetails?['gat']?.toString();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GatDetailsScreen(
          selectedGatId: _isPathakAdmin ? null : selectedGatId,
          selectedGatName: _isPathakAdmin ? null : selectedGatName,
          showAutoAssignAction: _canAddAssignGat,
          isPathakAdmin: _isPathakAdmin,
          canCreateGat: _canAddAssignGat,
          useMyGatEndpoint: !_isPathakAdmin,
        ),
      ),
    );
  }

  bool get _canAddAssignGat {
    return _permissionBool('add_asign_gat', fallback: _isPathakAdminOnly);
  }

  bool get _canManageMaintenanceInventory =>
      _permissionBool('update_maintance_stock');

  bool get _canCreateMaintenanceEvents =>
      _permissionBool('maintance_create_event');

  bool get _canApproveMaintenanceCompletions =>
      _permissionBool('maintenance_approval', fallback: _isGatPramukh) ||
      _permissionIsGatOnly('maintenance_approval');

  bool get _canApproveMaintenanceEntries =>
      _permissionBool('maintance_stock_approval');

  bool get _canViewMaintenanceAnalysis =>
      _permissionBool('maintance_analysis') ||
      _permissionBool('maintance_analysis_by_user');

  bool get _isVadak {
    final details = userDetails;
    if (details == null) return false;

    final nested = details['data'];
    return _parseBool(details['vadak']) ||
        _parseBool(details['is_vadak']) ||
        _parseBool(details['isVadak']) ||
        (nested is Map<String, dynamic> &&
            (_parseBool(nested['vadak']) ||
                _parseBool(nested['is_vadak']) ||
                _parseBool(nested['isVadak']))) ||
        (nested is Map &&
            (_parseBool(nested['vadak']) ||
                _parseBool(nested['is_vadak']) ||
                _parseBool(nested['isVadak'])));
  }

  bool get _canViewDocumentApprovals {
    return _permissionBool('document_approval', fallback: _isPathakAdmin);
  }

  void _navigateToMaintenance(BuildContext context) {
    Navigator.pop(context);
    final nested = userDetails?['data'];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DholMaintenanceScreen(
          // Direct drawer maintenance is always user-mode.
          // Admin maintenance actions are available in Admin > Maintenance tabs.
          canManageInventory: false,
          canApproveEntries: false,
          canCreateMaintenanceEvents: false,
          canApproveCompletionRequests: false,
          isPathakAdminApprover: false,
          approverGatId: int.tryParse(
            userDetails?['gat_id']?.toString() ??
                userDetails?['gatId']?.toString() ??
                (nested is Map<String, dynamic>
                    ? nested['gat_id']?.toString()
                    : null) ??
                (nested is Map<String, dynamic>
                    ? nested['gatId']?.toString()
                    : null) ??
                (nested is Map ? nested['gat_id']?.toString() : null) ??
                (nested is Map ? nested['gatId']?.toString() : null) ??
                '',
          ),
          currentUserId: int.tryParse(
            userDetails?['id']?.toString() ??
                userDetails?['user_id']?.toString() ??
                userDetails?['userId']?.toString() ??
                '',
          ),
          currentUserName:
              '${userDetails?['first_name'] ?? ''} ${userDetails?['last_name'] ?? ''}'
                  .trim(),
          userInstrument: userDetails?['instrument']?.toString(),
        ),
      ),
    );
  }

  void _navigateToComingSoon(BuildContext context, String title) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ComingSoonScreen(featureTitle: title),
      ),
    );
  }

  void _navigateToDocuments(BuildContext context) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DocumentCenterScreen(
          isPathakAdmin: false,
          userDetails: userDetails,
        ),
      ),
    );
  }

  void _navigateToAttendance(BuildContext context) {
    Navigator.pop(context);
    final showAdminFunctionsInDrawer = !_isAdminLike;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AttendanceModuleScreen(
          canGenerateQr: showAdminFunctionsInDrawer
              ? _canGenerateAttendanceQr
              : false,
          canSetAttendanceLocation: showAdminFunctionsInDrawer
              ? _canSetAttendanceLocation
              : false,
          canViewByUserAttendance: _canViewAttendanceByUser,
          isPathakAdmin: _isPathakAdmin,
        ),
      ),
    );
  }

  void _navigateToAdminOperations(
    BuildContext context, {
    int initialTabIndex = 0,
  }) {
    Navigator.pop(context);
    final nested = userDetails?['data'];
    final showStatusFilters = _isPathakAdmin || !_isGatPramukh;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminOperationsScreen(
          initialTabIndex: initialTabIndex,
          canGenerateAttendanceQr: _canGenerateAttendanceQr,
          canSetAttendanceLocation: _canSetAttendanceLocation,
          canViewAttendanceByUser: _canViewAttendanceByUser,
          isPathakAdmin: _isPathakAdmin,
          canViewDocumentApprovals: _canViewDocumentApprovals,
          canManageMaintenanceInventory: _canManageMaintenanceInventory,
          canApproveMaintenanceEntries: _canApproveMaintenanceEntries,
          canCreateMaintenanceEvents: _canCreateMaintenanceEvents,
          canApproveMaintenanceCompletions: _canApproveMaintenanceCompletions,
          canViewMaintenanceAnalysis: _canViewMaintenanceAnalysis,
          isPathakAdminApprover:
              _isPathakAdminOnly || _permissionBool('maintenance_approval'),
          approverGatId: int.tryParse(
            userDetails?['gat_id']?.toString() ??
                userDetails?['gatId']?.toString() ??
                (nested is Map<String, dynamic>
                    ? nested['gat_id']?.toString()
                    : null) ??
                (nested is Map<String, dynamic>
                    ? nested['gatId']?.toString()
                    : null) ??
                (nested is Map ? nested['gat_id']?.toString() : null) ??
                (nested is Map ? nested['gatId']?.toString() : null) ??
                '',
          ),
          currentUserId: int.tryParse(
            userDetails?['id']?.toString() ??
                userDetails?['user_id']?.toString() ??
                userDetails?['userId']?.toString() ??
                '',
          ),
          currentUserName:
              '${userDetails?['first_name'] ?? ''} ${userDetails?['last_name'] ?? ''}'
                  .trim(),
          userInstrument: userDetails?['instrument']?.toString(),
          canManageTerms: _permissionBool(
            'manage_terms',
            fallback: _isPathakAdminOnly,
          ),
          showUsersStatusFilters: showStatusFilters,
          canUpdateUserGroup: _permissionBool(
            'user_approval',
            fallback: _isPathakAdminOnly,
          ),
          isGatPramukh: _isGatPramukh,
          gatPramukhName:
              userDetails?['gat_pramukh_name']?.toString() ??
              userDetails?['gatPramukhName']?.toString(),
        ),
      ),
    );
  }

  bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value == 1;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  /// True when the user has admin-level access:
  /// pathak_admin, management role, or gat-pramukh access.
  bool get _isAdminLike {
    if (userDetails == null) return false;
    final hasPermissionsAdmin =
        _permissionBool('attendance_settings') ||
        _permissionBool('user_approval') ||
        _permissionBool('update_maintance_stock') ||
        _permissionBool('maintance_stock_approval') ||
        _permissionBool('maintance_create_event') ||
        _permissionBool('maintance_analysis') ||
        _permissionBool('maintance_analysis_by_user') ||
        _canApproveMaintenanceEntries ||
        _canApproveMaintenanceCompletions ||
        _permissionBool('document_approval') ||
        _permissionBool('manage_terms');
    final isGatPramukhFlag = _isGatPramukh;
    return hasPermissionsAdmin || isGatPramukhFlag;
  }

  bool get _isPathakAdminOnly {
    return _permissionBool(
      'user_approval',
      fallback: _permissionBool(
        'attendance_settings',
        fallback: _permissionBool(
          'document_approval',
          fallback: _permissionBool(
            'manage_terms',
            fallback: _permissionBool('add_asign_gat'),
          ),
        ),
      ),
    );
  }

  bool get _isPathakAdmin {
    return _isPathakAdminOnly ||
        _permissionBool('update_maintance_stock') ||
        _permissionBool('maintance_stock_approval') ||
        _permissionBool('maintance_create_event') ||
        _permissionBool('maintance_analysis') ||
        _permissionBool('maintance_analysis_by_user') ||
        _canApproveMaintenanceCompletions;
  }

  bool get _canGenerateAttendanceQr {
    return _permissionBool(
      'generate_attendance_qr',
      fallback: _permissionBool(
        'attendance_settings',
        fallback: _isPathakAdmin,
      ),
    );
  }

  bool get _canSetAttendanceLocation {
    return _permissionBool('attendance_settings', fallback: _isPathakAdminOnly);
  }

  bool get _canViewAttendanceByUser {
    return _isPathakAdmin || _isGatPramukh;
  }

  bool get _isGatPramukh {
    final details = userDetails;
    if (details == null) return false;
    final nested = details['data'];
    return _parseBool(details['is_gat_pramukh']) ||
        _parseBool(details['isGatPramukh']) ||
        (nested is Map<String, dynamic> &&
            (_parseBool(nested['is_gat_pramukh']) ||
                _parseBool(nested['isGatPramukh']))) ||
        (nested is Map &&
            (_parseBool(nested['is_gat_pramukh']) ||
                _parseBool(nested['isGatPramukh'])));
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.background,
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: AppColors.primaryMaroon),
            currentAccountPicture: const Hero(
              tag: 'profile-avatar',
              child: CircleAvatar(
                backgroundColor: AppColors.accentYellow,
                child: Icon(
                  Icons.person,
                  color: AppColors.primaryMaroon,
                  size: 40,
                ),
              ),
            ),
            accountName: Text(
              firstName ?? 'User',
              style: const TextStyle(color: AppColors.textLight),
            ),
            accountEmail: Text(
              phoneNumber ?? '',
              style: const TextStyle(color: AppColors.textLight54),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person, color: AppColors.primaryMaroon),
            title: const Text(
              'Profile',
              style: TextStyle(color: AppColors.primaryMaroon),
            ),
            onTap: () => _navigateToProfile(context),
          ),
          if (!_isVadak && _isAdminLike)
            ListTile(
              leading: const Icon(
                Icons.admin_panel_settings,
                color: AppColors.primaryMaroon,
              ),
              title: const Text(
                'Admin',
                style: TextStyle(color: AppColors.primaryMaroon),
              ),
              onTap: () => _navigateToAdminOperations(context),
            ),
          // Show Gat Details for pathak_admin and My Gat for all other logged-in users.
          if (userDetails != null)
            ListTile(
              leading: const Icon(Icons.groups, color: AppColors.primaryMaroon),
              title: Text(
                _isPathakAdmin ? 'Gat Details' : 'My Gat',
                style: const TextStyle(color: AppColors.primaryMaroon),
              ),
              onTap: () => _navigateToGatDetails(context),
            ),
          ListTile(
            leading: const Icon(
              Icons.fact_check,
              color: AppColors.primaryMaroon,
            ),
            title: const Text(
              'Attendance',
              style: TextStyle(color: AppColors.primaryMaroon),
            ),
            onTap: () => _navigateToAttendance(context),
          ),
          ListTile(
            leading: const Icon(
              Icons.build_circle,
              color: AppColors.primaryMaroon,
            ),
            title: const Text(
              'Maintenance',
              style: TextStyle(color: AppColors.primaryMaroon),
            ),
            onTap: () => _navigateToMaintenance(context),
          ),
          ListTile(
            leading: const Icon(Icons.badge, color: AppColors.primaryMaroon),
            title: const Text(
              'Documents',
              style: TextStyle(color: AppColors.primaryMaroon),
            ),
            onTap: () => _navigateToDocuments(context),
          ),
          if (_isPathakAdmin)
            ListTile(
              leading: const Icon(
                Icons.account_balance_wallet,
                color: AppColors.primaryMaroon,
              ),
              title: const Text(
                'Finance',
                style: TextStyle(color: AppColors.primaryMaroon),
              ),
              onTap: () => _navigateToComingSoon(context, 'Finance'),
            ),
          const Spacer(),
        ],
      ),
    );
  }
}
