import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/animated_navigation.dart'; // ✅ Reusable animation
import '../screens/all_users_screen.dart';
import '../screens/gat_details_screen.dart';

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
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const GatDetailsScreen()),
    );
  }

  bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value == 1;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  /// True when the user has admin-level access:
  /// either the pathak_admin role or is flagged as a gat pramukh.
  bool get _isAdminLike {
    if (userDetails == null) return false;
    final role = userDetails!['role']?.toString().trim().toLowerCase();
    final isRoleAdmin = role == 'pathak_admin' || role == 'pathak-admin';
    final isRoleGatPramukh = role == 'gat_pramukh' || role == 'gat-pramukh';
    final isGatPramukhFlag =
        _parseBool(userDetails!['is_gat_pramukh']) ||
        _parseBool(userDetails!['isGatPramukh']);
    return isRoleAdmin || isRoleGatPramukh || isGatPramukhFlag;
  }

  bool get _isPathakAdmin {
    final role = userDetails?['role']?.toString().trim().toLowerCase();
    return role == 'pathak_admin' || role == 'pathak-admin';
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
          // Show Gat Details only for pathak_admin
          if (_isPathakAdmin)
            ListTile(
              leading: const Icon(Icons.groups, color: AppColors.primaryMaroon),
              title: const Text(
                'Gat Details',
                style: TextStyle(color: AppColors.primaryMaroon),
              ),
              onTap: () => _navigateToGatDetails(context),
            ),
          const Spacer(),
        ],
      ),
    );
  }
}
