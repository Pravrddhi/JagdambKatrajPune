import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_colors.dart';
import '../utils/animated_navigation.dart'; // ✅ Reusable animation
import '../screens/document_center_screen.dart';
import '../screens/gat_details_screen.dart';
import '../screens/coming_soon_screen.dart';
import '../screens/attendance_module_screen.dart';
import '../screens/dhol_maintenance_screen.dart';
import '../screens/admin_operations_screen.dart';
import '../providers/request_counts_provider.dart';

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

  bool get _canUpdateUserGroup {
    return _permissionBool('user_approval', fallback: _isPathakAdminOnly);
  }

  bool get _canManageTerms {
    return _permissionBool('manage_terms', fallback: _isPathakAdminOnly);
  }

  bool get _showAdminAttendanceTab {
    return _canSetAttendanceLocation || _canGenerateAttendanceQr;
  }

  bool get _showAdminUsersTab {
    return _canUpdateUserGroup;
  }

  bool get _showAdminDocumentApprovalsTab {
    return _canViewDocumentApprovals;
  }

  bool get _showAdminMaintenanceApprovalsTab {
    return _canManageMaintenanceInventory ||
        _canApproveMaintenanceEntries ||
        _canCreateMaintenanceEvents ||
        _canApproveMaintenanceCompletions;
  }

  bool get _showAdminMaintenanceAnalysisTab {
    return _canViewMaintenanceAnalysis;
  }

  bool get _showAdminManageTermsTab {
    return _canManageTerms;
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
          canDownloadAttendanceQr: _canDownloadAttendanceQr,
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
          canDownloadAttendanceQr: _canDownloadAttendanceQr,
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
          canViewUserAnalysis: _permissionBool(
            'user_analysis',
            fallback: _isPathakAdminOnly,
          ),
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

  bool get _canDownloadAttendanceQr {
    return _permissionBool(
      'download_attendance_qr',
      fallback: _canGenerateAttendanceQr,
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
    // Get the request counts provider and fetch counts on drawer open
    final requestCountsProvider = Provider.of<RequestCountsProvider>(
      context,
      listen: false,
    );

    // Schedule fetch after frame to avoid blocking UI
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!requestCountsProvider.isLoading) {
        requestCountsProvider.fetchRequestCounts(
          isPathakAdmin: _isPathakAdmin,
          canViewDocumentApprovals: _canViewDocumentApprovals,
          canManageMaintenanceInventory: _canManageMaintenanceInventory,
          canApproveMaintenanceEntries: _canApproveMaintenanceEntries,
          canApproveMaintenanceCompletions: _canApproveMaintenanceCompletions,
        );
      }
    });

    return Drawer(
      backgroundColor: AppColors.background,
      child: ListView(
        padding: EdgeInsets.zero,
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
            Consumer<RequestCountsProvider>(
              builder: (context, provider, _) {
                return _buildAdminSection(
                  context,
                  totalCount: provider.counts.total,
                  documentApprovalsCount: provider.counts.documentApprovals,
                  maintenanceCount:
                      provider.counts.maintenanceRequests +
                      provider.counts.completionRequests,
                );
              },
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
          Consumer<RequestCountsProvider>(
            builder: (context, provider, _) {
              final maintenanceCount =
                  provider.counts.maintenanceRequests +
                  provider.counts.completionRequests;
              return _buildDrawerItemWithBadge(
                context,
                icon: Icons.build_circle,
                title: 'Maintenance',
                count: maintenanceCount,
                onTap: () => _navigateToMaintenance(context),
              );
            },
          ),
          Consumer<RequestCountsProvider>(
            builder: (context, provider, _) {
              return _buildDrawerItemWithBadge(
                context,
                icon: Icons.badge,
                title: 'Documents',
                count: provider.counts.documentApprovals,
                onTap: () => _navigateToDocuments(context),
              );
            },
          ),
          if (_isPathakAdmin)
            _buildDrawerItemWithBadge(
              context,
              icon: Icons.account_balance_wallet,
              title: 'Finance',
              count: 0,
              onTap: () => _navigateToComingSoon(context, 'Finance'),
            ),
        ],
      ),
    );
  }

  Widget _buildAdminSection(
    BuildContext context, {
    required int totalCount,
    required int documentApprovalsCount,
    required int maintenanceCount,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: const Icon(
          Icons.admin_panel_settings,
          color: AppColors.primaryMaroon,
        ),
        iconColor: AppColors.primaryMaroon,
        collapsedIconColor: AppColors.primaryMaroon,
        title: Row(
          children: [
            const Text(
              'Admin',
              style: TextStyle(color: AppColors.primaryMaroon),
            ),
            if (totalCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.errorRed,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  totalCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        children: [
          if (_showAdminAttendanceTab)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              leading: const Icon(
                Icons.qr_code_2,
                color: AppColors.primaryMaroon,
              ),
              title: const Text(
                'Attendance',
                style: TextStyle(color: AppColors.primaryMaroon),
              ),
              onTap: () =>
                  _navigateToAdminOperations(context, initialTabIndex: 0),
            ),
          if (_showAdminUsersTab)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              leading: const Icon(Icons.group, color: AppColors.primaryMaroon),
              title: const Text(
                'Users',
                style: TextStyle(color: AppColors.primaryMaroon),
              ),
              onTap: () =>
                  _navigateToAdminOperations(context, initialTabIndex: 1),
            ),
          if (_showAdminDocumentApprovalsTab)
            _buildAdminSubItemWithBadge(
              icon: Icons.badge,
              title: 'Document Approvals',
              count: documentApprovalsCount,
              onTap: () =>
                  _navigateToAdminOperations(context, initialTabIndex: 2),
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
            ),
          if (_showAdminMaintenanceApprovalsTab)
            _buildAdminSubItemWithBadge(
              icon: Icons.build_circle,
              title: 'Maintenance Approvals',
              count: maintenanceCount,
              onTap: () =>
                  _navigateToAdminOperations(context, initialTabIndex: 3),
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
            ),
          if (_showAdminMaintenanceAnalysisTab)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              leading: const Icon(
                Icons.analytics,
                color: AppColors.primaryMaroon,
              ),
              title: const Text(
                'Maintenance Analysis',
                style: TextStyle(color: AppColors.primaryMaroon),
              ),
              onTap: () =>
                  _navigateToAdminOperations(context, initialTabIndex: 4),
            ),
          if (_showAdminManageTermsTab)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              leading: const Icon(Icons.rule, color: AppColors.primaryMaroon),
              title: const Text(
                'Manage Terms',
                style: TextStyle(color: AppColors.primaryMaroon),
              ),
              onTap: () =>
                  _navigateToAdminOperations(context, initialTabIndex: 5),
            ),
        ],
      ),
    );
  }

  /// Build a drawer item with an optional count badge
  Widget _buildDrawerItemWithBadge(
    BuildContext context, {
    required IconData icon,
    required String title,
    required int count,
    required VoidCallback onTap,
    EdgeInsetsGeometry? contentPadding,
  }) {
    return ListTile(
      contentPadding: contentPadding,
      leading: Icon(icon, color: AppColors.primaryMaroon),
      title: Row(
        children: [
          Text(title, style: const TextStyle(color: AppColors.primaryMaroon)),
          if (count > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.errorRed,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _buildAdminSubItemWithBadge({
    required IconData icon,
    required String title,
    required int count,
    required VoidCallback onTap,
    EdgeInsetsGeometry? contentPadding,
  }) {
    return ListTile(
      contentPadding: contentPadding,
      leading: Icon(icon, color: AppColors.primaryMaroon),
      title: Row(
        children: [
          Text(title, style: const TextStyle(color: AppColors.primaryMaroon)),
          if (count > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.errorRed,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}
