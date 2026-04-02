import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../providers/feature_flags_provider.dart';

class ProfileScreen extends StatelessWidget {
  final Map<String, dynamic> userDetails;

  /// Controls visibility of the "Update Profile" button
  // final bool showUpdateProfile;

  const ProfileScreen({
    super.key,
    required this.userDetails, // default hidden
  });

  @override
  Widget build(BuildContext context) {
    /// Prepare user details, excluding unnecessary keys
    final flags = Provider.of<FeatureFlagsProvider>(context).flags;
    final filteredDetails = userDetails.entries
        .where((entry) {
          if (entry.key == 'events' ||
              entry.key == 'role' ||
              entry.key == 'is_gat_pramukh' ||
              entry.key == 'approval_status') {
            return false;
          }

          final value = entry.value;
          if (value == null) {
            return false;
          }
          if (value is String && value.trim().isEmpty) {
            return false;
          }
          return true;
        })
        .map((entry) {
          final label =
              entry.key == 'joining_year' ||
                  entry.key == 'joiningYear' ||
                  entry.key == 'joined_year'
              ? 'JOINED YEAR'
              : entry.key.replaceAll('_', ' ').toUpperCase();
          return {'label': label, 'value': '${entry.value}'};
        })
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: AppColors.primaryMaroon,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            /// Profile avatar
            const _Avatar(),
            const SizedBox(height: 20),

            /// User details card
            _UserDetailsCard(
              details: filteredDetails,
              showUpdateProfile: flags?.showUpdateProfile ?? false,
            ),

            const SizedBox(height: 20),

            /// Logout button
            const _LogoutButton(),
          ],
        ),
      ),
    );
  }
}

///
/// Avatar widget with Hero animation
///
class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) {
    return const Hero(
      tag: 'profile-avatar',
      child: CircleAvatar(
        radius: 50,
        backgroundColor: AppColors.accentYellow,
        child: Icon(Icons.person, size: 50, color: AppColors.primaryMaroon),
      ),
    );
  }
}

///
/// Private widget for User Details section
///
class _UserDetailsCard extends StatelessWidget {
  final List<Map<String, String>> details;
  final bool showUpdateProfile;

  const _UserDetailsCard({
    required this.details,
    required this.showUpdateProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.background,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            /// Display user details in table format
            Table(
              columnWidths: const {
                0: FlexColumnWidth(3), // label column
                1: FlexColumnWidth(4), // value column
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: details.map((item) {
                return TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        item['label']!,
                        style: const TextStyle(
                          color: AppColors.primaryMaroon,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        item['value']!,
                        style: const TextStyle(color: AppColors.primaryMaroon),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),

            /// Conditionally show Update Profile button
            if (showUpdateProfile) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentYellow,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  // TODO: Navigate to Update Profile screen
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Update profile clicked!')),
                  );
                },
                icon: const Icon(Icons.edit),
                label: const Text('Update Profile'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

///
/// Logout button widget
///
class _LogoutButton extends StatelessWidget {
  const _LogoutButton();

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: () {
        // TODO: Clear session/token if required

        // Navigate to login screen and replace current screen
        Navigator.pushReplacementNamed(context, '/login');
      },
      icon: const Icon(Icons.logout),
      label: const Text('Logout'),
    );
  }
}
