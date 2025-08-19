import 'package:flutter/material.dart';
import '../theme/app_colors.dart'; // adjust path as per your project
import '../components/link_launcher.dart';

class UpcomingEvents extends StatelessWidget {
  final List<Map<String, dynamic>> events;

  const UpcomingEvents({Key? key, required this.events}) : super(key: key);

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
                    SizedBox(height: 40), // space for close button
                    Text(
                      event['name'] ?? '',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryMaroon,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('Date: ${event['date'] ?? ''}'),
                    Text('Location: ${event['location'] ?? ''}'),
                    const SizedBox(height: 10),
                    Text(event['description'] ?? ''),
                    if (event['map_link'] != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            LinkLauncher.openLink(
                              event['map_link'],
                            );
                          },
                          child: const Text(
                            'View on Map',
                            style: TextStyle(color: AppColors.primaryMaroon),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Close button in top-left corner
              Positioned(
                top: 8,
                left: 8,
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
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.9,
                ),
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
                          Text(
                            event['name'] ?? '',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryMaroon,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Date: ${event['date'] ?? ''}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          Text(
                            'Location: ${event['location'] ?? ''}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            event['description'] ?? '',
                            style: const TextStyle(fontSize: 14),
                          ),
                          if (event['map_link'] != null)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {
                                  // TODO: open map link
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
