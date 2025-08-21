import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/animated_navigation.dart'; // ✅ Reusable animation

class AppDrawer extends StatelessWidget {
  final String? firstName;
  final String? email;
  final Map<String, dynamic>? userDetails;
  final VoidCallback onLogout;

  const AppDrawer({
    super.key,
    this.firstName,
    this.email,
    this.userDetails,
    required this.onLogout,
  });

  void _navigateToProfile(BuildContext context) {
    Navigator.pop(context); // Close drawer first
    if (userDetails != null) {
      AnimatedNavigation.pushProfile(context, userDetails!); // ✅ Central animation
    } else {
      // Fallback: Open empty profile
      AnimatedNavigation.pushProfile(context, {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.background,
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: AppColors.primaryMaroon),
            currentAccountPicture: Hero(
              tag: 'profile-avatar',
              child: CircleAvatar(
                backgroundColor: AppColors.accentYellow,
                child: Icon(Icons.person, color: AppColors.primaryMaroon, size: 40),
              ),
            ),
            accountName: Text(firstName ?? 'User', style: const TextStyle(color: AppColors.textLight)),
            accountEmail: Text(email ?? '', style: const TextStyle(color: AppColors.textLight54)),
          ),
          ListTile(
            leading: const Icon(Icons.person, color: AppColors.primaryMaroon),
            title: const Text('Profile', style: TextStyle(color: AppColors.primaryMaroon)),
            onTap: () => _navigateToProfile(context),
          ),
          const Spacer(),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.primaryMaroon),
            title: const Text('Logout', style: TextStyle(color: AppColors.primaryMaroon)),
            onTap: onLogout,
          ),
        ],
      ),
    );
  }
}
