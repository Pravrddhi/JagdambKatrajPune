import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_endpoints.dart';
import '../services/bug_report_service.dart';
import '../services/authorized_api_service.dart';
import '../theme/app_colors.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class MirvnukForm {
  static Future<void> open(BuildContext context) async {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController dateController = TextEditingController();
    final TextEditingController timeFromController = TextEditingController();
    final TextEditingController timeToController = TextEditingController();
    final TextEditingController locationController = TextEditingController();
    final TextEditingController mapLinkController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();

    const storage = FlutterSecureStorage();
    int currentStep = 0;
    bool isSubmitting = false;

    bool isValidMapLink(String value) {
      final parsed = Uri.tryParse(value.trim());
      return parsed != null && parsed.hasScheme && parsed.host.isNotEmpty;
    }

    bool isEndAfterStart() {
      if (timeFromController.text.isEmpty || timeToController.text.isEmpty) {
        return false;
      }
      final startParts = timeFromController.text.split(':');
      final endParts = timeToController.text.split(':');
      if (startParts.length != 2 || endParts.length != 2) {
        return false;
      }
      final startMinutes =
          int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
      final endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
      return endMinutes > startMinutes;
    }

    bool isStepValid(int step) {
      switch (step) {
        case 0:
          return nameController.text.trim().isNotEmpty &&
              dateController.text.trim().isNotEmpty &&
              timeFromController.text.trim().isNotEmpty &&
              timeToController.text.trim().isNotEmpty &&
              isEndAfterStart();
        case 1:
          return locationController.text.trim().isNotEmpty &&
              mapLinkController.text.trim().isNotEmpty &&
              isValidMapLink(mapLinkController.text);
        case 2:
          return descriptionController.text.trim().isNotEmpty;
        default:
          return false;
      }
    }

    await showDialog(
      context: context,
      builder: (dialogContext) {
        final mediaQuery = MediaQuery.of(dialogContext);
        final screenHeight = mediaQuery.size.height;
        final bottomInset = mediaQuery.viewInsets.bottom;
        const verticalInset = 10.0;
        final availableHeight =
            (screenHeight - bottomInset - (verticalInset * 2)).clamp(
              260.0,
              screenHeight,
            );

        return StatefulBuilder(
          builder: (dialogContext, setState) {
            String stepTitle;
            String stepSubtitle;
            switch (currentStep) {
              case 0:
                stepTitle = 'Basic Details';
                stepSubtitle = 'Name, date and timing';
                break;
              case 1:
                stepTitle = 'Location';
                stepSubtitle = 'Address and map link';
                break;
              default:
                stepTitle = 'Description';
                stepSubtitle = 'Final details and submit';
            }

            return AlertDialog(
              insetPadding: const EdgeInsets.all(10),
              backgroundColor: Colors.white,
              titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              contentPadding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
              actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              title: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.accentYellow.withAlpha(70),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.event_note_rounded,
                      color: AppColors.primaryMaroon,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Add Mirvnuk',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryMaroon,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Step ${currentStep + 1} of 3 - $stepSubtitle',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.primaryMaroon,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: availableHeight),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        stepTitle,
                        style: const TextStyle(
                          color: AppColors.primaryMaroon,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (currentStep == 0) ...[
                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Mirvnuk Name',
                            prefixIcon: Icon(
                              Icons.event,
                              color: AppColors.primaryMaroon,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: dateController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Date',
                            prefixIcon: Icon(
                              Icons.calendar_today,
                              color: AppColors.primaryMaroon,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          onTap: () async {
                            final now = DateTime.now();
                            final selectedDate = await showDatePicker(
                              context: dialogContext,
                              initialDate: now,
                              firstDate: now,
                              lastDate: DateTime(2100),
                            );
                            if (selectedDate != null) {
                              dateController.text =
                                  '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
                              setState(() {});
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: timeFromController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Start Time',
                            prefixIcon: Icon(
                              Icons.access_time,
                              color: AppColors.primaryMaroon,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          onTap: () async {
                            final timeFrom = await showTimePicker(
                              context: dialogContext,
                              initialTime: TimeOfDay.now(),
                            );
                            if (timeFrom != null) {
                              timeFromController.text =
                                  '${timeFrom.hour.toString().padLeft(2, '0')}:${timeFrom.minute.toString().padLeft(2, '0')}';
                              setState(() {});
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: timeToController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'End Time',
                            prefixIcon: Icon(
                              Icons.access_time,
                              color: AppColors.primaryMaroon,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          onTap: () async {
                            final timeTo = await showTimePicker(
                              context: dialogContext,
                              initialTime: TimeOfDay.now(),
                            );
                            if (timeTo != null) {
                              timeToController.text =
                                  '${timeTo.hour.toString().padLeft(2, '0')}:${timeTo.minute.toString().padLeft(2, '0')}';
                              setState(() {});
                            }
                          },
                        ),
                        if (timeToController.text.isNotEmpty &&
                            timeFromController.text.isNotEmpty &&
                            !isEndAfterStart()) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'End time must be after start time.',
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ],
                      ],
                      if (currentStep == 1) ...[
                        TextFormField(
                          controller: locationController,
                          decoration: const InputDecoration(
                            labelText: 'Location',
                            prefixIcon: Icon(
                              Icons.location_on,
                              color: AppColors.primaryMaroon,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: mapLinkController,
                          decoration: const InputDecoration(
                            labelText: 'Map Link',
                            prefixIcon: Icon(
                              Icons.map,
                              color: AppColors.primaryMaroon,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        if (mapLinkController.text.isNotEmpty &&
                            !isValidMapLink(mapLinkController.text)) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Please enter a valid map URL.',
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ],
                      ],
                      if (currentStep == 2) ...[
                        TextFormField(
                          controller: descriptionController,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            prefixIcon: Icon(
                              Icons.description,
                              color: AppColors.primaryMaroon,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          minLines: 3,
                          maxLines: 5,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.accentYellow.withAlpha(35),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Review',
                                style: TextStyle(
                                  color: AppColors.primaryMaroon,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text('Name: ${nameController.text.trim()}'),
                              Text('Date: ${dateController.text.trim()}'),
                              Text(
                                'Time: ${timeFromController.text.trim()} - ${timeToController.text.trim()}',
                              ),
                              Text(
                                'Location: ${locationController.text.trim()}',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: AppColors.primaryMaroon),
                  ),
                ),
                if (currentStep > 0)
                  OutlinedButton(
                    onPressed: isSubmitting
                        ? null
                        : () {
                            setState(() => currentStep = currentStep - 1);
                          },
                    child: const Text('Back'),
                  ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isStepValid(currentStep)
                        ? AppColors.primaryMaroon
                        : Colors.grey,
                    foregroundColor: AppColors.accentYellow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                  onPressed: isStepValid(currentStep) && !isSubmitting
                      ? () async {
                          if (!isStepValid(currentStep)) {
                            return;
                          }

                          if (currentStep < 2) {
                            setState(() => currentStep = currentStep + 1);
                            return;
                          }

                          setState(() => isSubmitting = true);

                          final accessToken = await storage.read(
                            key: ApiEndpoints.accessTokenKey,
                          );
                          if (accessToken == null ||
                              accessToken.trim().isEmpty) {
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Session expired. Please login again.',
                                  ),
                                ),
                              );
                            }
                            setState(() => isSubmitting = false);
                            return;
                          }

                          final body = jsonEncode({
                            'pathak_id': ApiEndpoints.pathakId,
                            'name': nameController.text.trim(),
                            'date': dateController.text.trim(),
                            'time_from': timeFromController.text.trim(),
                            'time_to': timeToController.text.trim(),
                            'location': locationController.text.trim(),
                            'map_link': mapLinkController.text.trim(),
                            'description': descriptionController.text.trim(),
                          });

                          try {
                            Future<http.Response> postCreateEvent(
                              String token,
                            ) {
                              return http.post(
                                Uri.parse(ApiEndpoints.createEvent),
                                headers: ApiEndpoints.authorizedHeaders(token),
                                body: body,
                              );
                            }

                            final response =
                                await AuthorizedApiService.sendWithAutoRefresh(
                                  accessToken,
                                  postCreateEvent,
                                );

                            if (response == null) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Session expired. Please login again.',
                                  ),
                                ),
                              );
                              return;
                            }

                            if (response.statusCode == 200 ||
                                response.statusCode == 201) {
                              Navigator.of(dialogContext).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Mirvnuk added successfully'),
                                ),
                              );
                            } else if (response.statusCode == 401) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Session expired. Please login again.',
                                  ),
                                ),
                              );
                            } else {
                              await BugReportService.reportApiFailure(
                                title: 'Create event API failed',
                                errorMessage: response.body,
                                pageUrl: '/events/create',
                                statusCode: response.statusCode,
                                endpoint: ApiEndpoints.createEvent,
                              );
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    ApiEndpoints.genericApiFailureMessage,
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            await BugReportService.reportApiFailure(
                              title: 'Create event API exception',
                              errorMessage: e.toString(),
                              pageUrl: '/events/create',
                              endpoint: ApiEndpoints.createEvent,
                            );
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  ApiEndpoints.genericApiFailureMessage,
                                ),
                              ),
                            );
                          } finally {
                            if (dialogContext.mounted) {
                              setState(() => isSubmitting = false);
                            }
                          }
                        }
                      : null,
                  icon: isSubmitting
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          currentStep < 2
                              ? Icons.arrow_forward_rounded
                              : Icons.send_rounded,
                          size: 16,
                        ),
                  label: Text(
                    isSubmitting
                        ? 'Submitting...'
                        : currentStep < 2
                        ? 'Next'
                        : 'Submit',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    dateController.dispose();
    timeFromController.dispose();
    timeToController.dispose();
    locationController.dispose();
    mapLinkController.dispose();
    descriptionController.dispose();
  }
}
