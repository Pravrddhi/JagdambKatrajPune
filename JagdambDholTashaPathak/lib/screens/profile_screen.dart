import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ProfileScreen extends StatelessWidget {
  final Map<String, dynamic> userDetails;

  const ProfileScreen({super.key, required this.userDetails});

  @override
  Widget build(BuildContext context) {
    final details = [
      {'label': 'First Name', 'value': '${userDetails['first_name'] ?? 'N/A'}'},
      {'label': 'Last Name', 'value': '${userDetails['last_name'] ?? 'N/A'}'},
      {'label': 'Phone Number', 'value': '${userDetails['phone_number'] ?? 'N/A'}'},
      {'label': 'Instrument', 'value': '${userDetails['instrument'] ?? 'N/A'}'},
      {'label': 'Sex', 'value': '${userDetails['sex'] ?? 'N/A'}'},
    ];

    return Scaffold(
      backgroundColor: AppColors.primaryMaroon,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: AppColors.primaryMaroon,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Hero(
              tag: 'profile-avatar',
              child: CircleAvatar(
                radius: 50,
                backgroundColor: AppColors.accentYellow,
                child: Icon(Icons.person, size: 50, color: AppColors.primaryMaroon),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              color: AppColors.primaryMaroon,
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Table(
                  columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(4)},
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: details.map((item) {
                    return TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(item['label']!,
                              style: const TextStyle(color: AppColors.accentYellow, fontWeight: FontWeight.bold)),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(item['value']!,
                              style: const TextStyle(color: AppColors.textLight)),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // ElevatedButton.icon(
            //   style: ElevatedButton.styleFrom(
            //     backgroundColor: AppColors.accentYellow,
            //     foregroundColor: Colors.black,
            //     padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            //     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            //   ),
            //   onPressed: () {
            //     ScaffoldMessenger.of(context).showSnackBar(
            //       const SnackBar(content: Text('Update profile clicked!')),
            //     );
            //   },
            //   icon: const Icon(Icons.edit),
            //   label: const Text('Update Profile'),
            // ),
          ],
        ),
      ),
    );
  }
}
