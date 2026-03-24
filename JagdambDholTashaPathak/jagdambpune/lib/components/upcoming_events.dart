import 'package:flutter/material.dart';
import '../theme/app_colors.dart'; // adjust path as per your project
import '../components/link_launcher.dart';

class UpcomingEvents extends StatelessWidget {
  final List<Map<String, dynamic>> events;

  const UpcomingEvents({super.key, required this.events});

  void _showEventPopup(BuildContext context, Map<String, dynamic> event) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(10),
          child: Stack(
            children: [
              // Scrollable event details
              SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 40), // space for close button
                    Text(
                      event['name'] ?? '',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryMaroon,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (event['date'] != null)
                      Text(
                        'Date: ${event['date']}',
                        style: const TextStyle(
                          color: AppColors.primaryMaroon,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    if (event['time_from'] != null && event['time_to'] != null)
                      Text(
                        'Time: ${event['time_from']} → ${event['time_to']}',
                        style: const TextStyle(
                          color: AppColors.primaryMaroon,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    if (event['location'] != null)
                      Text(
                        'Location: ${event['location']}',
                        style: const TextStyle(
                          color: AppColors.primaryMaroon,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    if (event['duration'] != null)
                      Text(
                        'Duration: ${event['duration']}',
                        style: const TextStyle(
                          color: AppColors.primaryMaroon,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    const SizedBox(height: 10),
                    if (event['description'] != null && event['description']!.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Description:',
                            style: TextStyle(
                              color: AppColors.primaryMaroon,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            event['description']!,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              // Close button in top-right corner
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: AppColors.primaryMaroon),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Upcoming Mirvnuks:',
          style: TextStyle(
            color: AppColors.primaryMaroon,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Column(
          children: events.map((event) {
            return Center(
              child: SizedBox(
                width: screenWidth * 0.95, // card almost full screen
                child: InkWell(
                  onTap: () => _showEventPopup(context, event),
                  child: Card(
                    elevation: 3,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title and duration
                          Text(
                            event['name'] ?? '',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryMaroon,
                            ),
                          ),
                          const SizedBox(height: 5),
                          if (event['duration'] != null)
                            Text(
                              'Duration: ${event['duration']}',
                              style: const TextStyle(
                                color: AppColors.primaryMaroon,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          const SizedBox(height: 8),
                          if (event['date'] != null)
                            Text(
                              'Date: ${event['date']}',
                              style: const TextStyle(
                                color: AppColors.primaryMaroon,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          const SizedBox(height: 8),
                          // View on Map button on card
                          if (event['map_link'] != null)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {
                                  LinkLauncher.openLink(event['map_link']);
                                },
                                child: const Text(
                                  'View on Map',
                                  style: TextStyle(
                                    color: AppColors.primaryMaroon,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
