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

  /// True when the user has admin-level access:
  /// pathak_admin/management roles or gat-pramukh access.
  bool get _isAdminLike {
    if (userDetails == null) return false;
    final role = userDetails!['role']?.toString().trim().toLowerCase();
    final isRoleAdmin = role == 'pathak_admin' || role == 'pathak-admin';
    final isRoleManagement = role == 'management';
    final isRoleGatPramukh = role == 'gat_pramukh' || role == 'gat-pramukh';
    final isGatPramukhFlag =
        _parseBool(userDetails!['is_gat_pramukh']) ||
        _parseBool(userDetails!['isGatPramukh']);
    return isRoleAdmin ||
        isRoleManagement ||
        isRoleGatPramukh ||
        isGatPramukhFlag;
  }

  bool get _isPathakAdminOnly {
    final role = userDetails?['role']?.toString().trim().toLowerCase();
    return role == 'pathak_admin' || role == 'pathak-admin';
  }

  bool get _isPathakAdmin {
    return _isPathakAdminOnly || _isManagement;
  }

  bool get _isManagement {
    final role = userDetails?['role']?.toString().trim().toLowerCase();
    return role == 'management';
  }

  bool get _isSuperuser {
    final role = userDetails?['role']?.toString().trim().toLowerCase();
    return role == 'superuser';
  }

  bool get _canGenerateAttendanceQr {
    return _isPathakAdmin || _isManagement;
  }

  bool get _canSetAttendanceLocation {
    return _isPathakAdminOnly;
  }

  bool get _canViewAttendanceByUser {
    return _isPathakAdmin || _isManagement || _isSuperuser || _isGatPramukh;
  }

  bool get _isGatPramukh {
    if (userDetails == null) return false;
    final role = userDetails!['role']?.toString().trim().toLowerCase();
    final isRoleGatPramukh = role == 'gat_pramukh' || role == 'gat-pramukh';
    return isRoleGatPramukh ||
        _parseBool(userDetails!['is_gat_pramukh']) ||
        _parseBool(userDetails!['isGatPramukh']);
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
          // Show Users for pathak_admin and gat pramukhs
          if (_isAdminLike)
            ListTile(
              leading: const Icon(Icons.people, color: AppColors.primaryMaroon),
              title: const Text(
                'Users',
                style: TextStyle(color: AppColors.primaryMaroon),
              ),
              onTap: () => _navigateToAllUsers(context),
            ),
          // Show Gat Details for pathak_admin/management and My Gat for all other logged-in users.
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
              onTap: () => _navigateToComingSoon(context, 'Maintenance'),
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
