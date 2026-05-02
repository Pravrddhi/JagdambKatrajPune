import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/feature_flags_provider.dart';
import '../theme/app_colors.dart';
import '../utils/animated_navigation.dart'; // ✅ Reusable animation
import '../screens/all_users_screen.dart';
import '../screens/document_center_screen.dart';
import '../screens/gat_details_screen.dart';
import '../screens/coming_soon_screen.dart';
import '../screens/attendance_module_screen.dart';
import '../screens/dhol_maintenance_screen.dart';
import '../screens/terms_conditions_manage_screen.dart';

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

  static const Set<String> _fixedGroups = <String>{
    'pathak_admin',
    'vadak',
    'maintance_admin',
    'management',
  };

  void _navigateToProfile(BuildContext context) {
    Navigator.pop(context); // Close drawer first
    if (userDetails != null) {
      AnimatedNavigation.pushProfile(
        context,
        userDetails!,
      ); // ✅ Central animation
    } else {
      // Fallback: Open empty profile
      AnimatedNavigation.pushProfile(context, {});
    }
  }

  void _navigateToAllUsers(BuildContext context) {
    Navigator.pop(context); // Close drawer first
    final showStatusFilters = _isPathakAdmin || !_isGatPramukh;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AllUsersScreen(
          showStatusFilters: showStatusFilters,
          isPathakAdmin: _isPathakAdmin,
          canUpdateUserGroup: _isPathakAdminOnly,
          isGatPramukh: _isGatPramukh,
          gatPramukhName:
              userDetails?['gat_pramukh_name']?.toString() ??
              userDetails?['gatPramukhName']?.toString(),
        ),
      ),
    );
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

    final showAutoAssignGat =
        context.read<FeatureFlagsProvider>().flags?.showAutoAssignGat ?? false;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GatDetailsScreen(
          selectedGatId: _isPathakAdmin ? null : selectedGatId,
          selectedGatName: _isPathakAdmin ? null : selectedGatName,
          showAutoAssignAction: _isPathakAdminOnly && showAutoAssignGat,
          isPathakAdmin: _isPathakAdmin,
          canCreateGat: _isPathakAdminOnly,
          useMyGatEndpoint: !_isPathakAdmin,
        ),
      ),
    );
  }

  bool get _isMaintanceAdmin {
    final details = userDetails;
    final groups = _normalizedGroups(details);
    final hasMaintenanceRole = groups.contains('maintance_admin');

    if (hasMaintenanceRole) return true;

    return _parseBool(details?['is_maintance_admin']) ||
        _parseBool(details?['is_maintaince_admin']) ||
        _parseBool(details?['is_maintenance_admin']) ||
        _parseBool(details?['isMaintenanceAdmin']) ||
        _parseBool(details?['isMaintainceAdmin']) ||
        _parseBool(details?['isMaintanceAdmin']);
  }

  bool get _canManageMaintenanceInventory =>
      _isMaintanceAdmin || _isPathakAdminOnly;

  bool get _canCreateMaintenanceEvents =>
      _isMaintanceAdmin || _isPathakAdminOnly;

  bool get _canApproveMaintenanceCompletions =>
      _isPathakAdminOnly || _isGatPramukh;

  bool get _canApproveMaintenanceEntries =>
      _isMaintanceAdmin || _isPathakAdminOnly || _isGatPramukh;

  void _navigateToMaintenance(BuildContext context) {
    Navigator.pop(context);
    final nested = userDetails?['data'];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DholMaintenanceScreen(
          canManageInventory: _canManageMaintenanceInventory,
          canApproveEntries: _canApproveMaintenanceEntries,
          canCreateMaintenanceEvents: _canCreateMaintenanceEvents,
          canApproveCompletionRequests: _canApproveMaintenanceCompletions,
          isPathakAdminApprover: _isPathakAdminOnly,
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
        builder: (context) =>
            DocumentCenterScreen(isPathakAdmin: _isPathakAdmin),
      ),
    );
  }

  void _navigateToAttendance(BuildContext context) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AttendanceModuleScreen(
          canGenerateQr: _canGenerateAttendanceQr,
          canSetAttendanceLocation: _canSetAttendanceLocation,
          canViewByUserAttendance: _canViewAttendanceByUser,
          isPathakAdmin: _isPathakAdmin,
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

  String _normalizeRole(dynamic value) {
    return value
            ?.toString()
            .trim()
            .toLowerCase()
            .replaceAll('-', '_')
            .replaceAll(' ', '_') ??
        '';
  }

  Set<String> _normalizedGroups(Map<String, dynamic>? details) {
    final resolved = <String>{};
    if (details == null) return resolved;

    final nested = details['data'];
    final groupSources = <dynamic>[
      details['groups'],
      details['group'],
      if (nested is Map<String, dynamic>) ...[
        nested['groups'],
        nested['group'],
      ],
      if (nested is Map) ...[nested['groups'], nested['group']],
    ];

    for (final source in groupSources) {
      if (source is String) {
        final normalized = _normalizeRole(source);
        if (_fixedGroups.contains(normalized)) {
          resolved.add(normalized);
        }
        continue;
      }
      if (source is! List) continue;
      for (final group in source) {
        final candidates = <dynamic>[
          group,
          if (group is Map<String, dynamic>) ...[
            group['name'],
            group['group'],
            group['group_name'],
            group['role'],
            group['role_name'],
            group['code'],
            group['slug'],
          ],
          if (group is Map) ...[
            group['name'],
            group['group'],
            group['group_name'],
            group['role'],
            group['role_name'],
            group['code'],
            group['slug'],
          ],
        ];

        for (final candidate in candidates) {
          final normalized = _normalizeRole(candidate);
          if (_fixedGroups.contains(normalized)) {
            resolved.add(normalized);
          }
        }
      }
    }

    final roleCandidates = <dynamic>[
      details['role'],
      details['user_role'],
      details['role_name'],
      details['userRole'],
      details['userType'],
      details['user_type'],
      details['type'],
      details['group'],
      details['group_name'],
    ];
    for (final candidate in roleCandidates) {
      final normalized = _normalizeRole(candidate);
      if (_fixedGroups.contains(normalized)) {
        resolved.add(normalized);
      }
    }

    return resolved;
  }

  /// True when the user has admin-level access:
  /// pathak_admin, management role, or gat-pramukh access.
  bool get _isAdminLike {
    if (userDetails == null) return false;
    final groups = _normalizedGroups(userDetails);
    final isRoleAdmin = groups.contains('pathak_admin');
    final isManagementRole =
        groups.contains('management') ||
        _parseBool(userDetails?['is_management']) ||
        _parseBool(userDetails?['isManagement']);
    final isGatPramukhFlag = _isGatPramukh;
    return isRoleAdmin || isManagementRole || isGatPramukhFlag;
  }

  bool get _isPathakAdminOnly {
    final details = userDetails;
    final groups = _normalizedGroups(details);
    final hasPathakAdminRole = groups.contains('pathak_admin');

    return hasPathakAdminRole ||
        _parseBool(details?['is_pathak_admin']) ||
        _parseBool(details?['isPathakAdmin']);
  }

  bool get _isPathakAdmin {
    return _isPathakAdminOnly;
  }

  bool get _canGenerateAttendanceQr {
    return _isPathakAdmin;
  }

  bool get _canSetAttendanceLocation {
    return _isPathakAdminOnly;
  }

  bool get _canViewAttendanceByUser {
    return _isPathakAdmin || _isGatPramukh;
  }

  bool get _isGatPramukh {
    if (userDetails == null) return false;
    final nested = userDetails!['data'];
    return _parseBool(userDetails!['is_gat_pramukh']) ||
        _parseBool(userDetails!['isGatPramukh']) ||
        (nested is Map<String, dynamic> &&
            (_parseBool(nested['is_gat_pramukh']) ||
                _parseBool(nested['isGatPramukh']))) ||
        (nested is Map &&
            (_parseBool(nested['is_gat_pramukh']) ||
                _parseBool(nested['isGatPramukh'])));
  }

  @override
  Widget build(BuildContext context) {
    final flags = context.watch<FeatureFlagsProvider>().flags;

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
          // Show Users for pathak_admin, management, and gat pramukhs.
          if (_isAdminLike)
            ListTile(
              leading: const Icon(Icons.people, color: AppColors.primaryMaroon),
              title: const Text(
                'Users',
                style: TextStyle(color: AppColors.primaryMaroon),
              ),
              onTap: () => _navigateToAllUsers(context),
            ),
          // Show Gat Details for pathak_admin and My Gat for all other logged-in users.
          if (userDetails != null && (flags?.showGat ?? true))
            ListTile(
              leading: const Icon(Icons.groups, color: AppColors.primaryMaroon),
              title: Text(
                _isPathakAdmin ? 'Gat Details' : 'My Gat',
                style: const TextStyle(color: AppColors.primaryMaroon),
              ),
              onTap: () => _navigateToGatDetails(context),
            ),
          if (flags?.showAttendance ?? true)
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
          if (flags?.showMaintenance ?? true)
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
          if (flags?.showDocuments ?? false)
            ListTile(
              leading: const Icon(Icons.badge, color: AppColors.primaryMaroon),
              title: const Text(
                'Documents',
                style: TextStyle(color: AppColors.primaryMaroon),
              ),
              onTap: () => _navigateToDocuments(context),
            ),
          if (_isPathakAdminOnly)
            ListTile(
              leading: const Icon(
                Icons.description,
                color: AppColors.primaryMaroon,
              ),
              title: const Text(
                'Manage Terms',
                style: TextStyle(color: AppColors.primaryMaroon),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TermsConditionsManageScreen(),
                  ),
                );
              },
            ),
          if (_isPathakAdmin && (flags?.showFinance ?? true))
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
