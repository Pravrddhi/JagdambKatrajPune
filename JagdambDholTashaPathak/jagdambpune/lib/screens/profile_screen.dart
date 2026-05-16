import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../providers/feature_flags_provider.dart';

class ProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userDetails;

  const ProfileScreen({super.key, required this.userDetails});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value == 1;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  bool _isGatPramukh(Map<String, dynamic> details) {
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

  String? _gatName(Map<String, dynamic> details) {
    final nested = details['data'];
    final candidates = <dynamic>[
      details['gat_name'],
      details['gatName'],
      details['gat'],
      if (nested is Map<String, dynamic>) ...[
        nested['gat_name'],
        nested['gatName'],
        nested['gat'],
      ],
      if (nested is Map) ...[
        nested['gat_name'],
        nested['gatName'],
        nested['gat'],
      ],
    ];

    for (final candidate in candidates) {
      final value = candidate?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  String _gatPramukhBannerText(Map<String, dynamic> details) {
    final gatName = _gatName(details);
    if (gatName != null && gatName.isNotEmpty) {
      return 'You are gat pramukh of $gatName';
    }
    return 'You are gat pramukh';
  }

  @override
  Widget build(BuildContext context) {
    final flags = Provider.of<FeatureFlagsProvider>(context).flags;

    final filteredDetails = widget.userDetails.entries
        .where((entry) {
          if (entry.key == 'events' ||
              entry.key == 'data' ||
              entry.key == 'groups' ||
              entry.key == 'group' ||
              entry.key == 'role' ||
              entry.key == 'permissions' ||
              entry.key == 'vadak' ||
              entry.key == 'is_vadak' ||
              entry.key == 'isVadak' ||
              entry.key == 'status' ||
              entry.key == 'is_gat_pramukh' ||
              entry.key == 'has_fcm_token' ||
              entry.key == 'hasFcmToken' ||
              entry.key == 'approval_status' ||
              entry.key == 'approval_comment' ||
              entry.key == 'approvalComment') {
            return false;
          }
          final value = entry.value;
          if (value == null) return false;
          if (value is String && value.trim().isEmpty) return false;
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
            const _Avatar(),
            const SizedBox(height: 20),
            if (_isGatPramukh(widget.userDetails))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Align(
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.accentYellow.withValues(alpha: 0.3),
                          Colors.white,
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppColors.accentYellow.withValues(alpha: 0.85),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.workspace_premium_outlined,
                          size: 14,
                          color: AppColors.primaryMaroon,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _gatPramukhBannerText(widget.userDetails),
                          style: const TextStyle(
                            color: AppColors.primaryMaroon,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            _UserDetailsCard(
              details: filteredDetails,
              showUpdateProfile: flags?.showUpdateProfile ?? false,
            ),
            const SizedBox(height: 20),
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
                  // Placeholder until the update-profile flow is implemented.
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
        // Current logout flow only redirects to login.

        // Navigate to login screen and replace current screen
        Navigator.pushReplacementNamed(context, '/login');
      },
      icon: const Icon(Icons.logout),
      label: const Text('Logout'),
    );
  }
}
