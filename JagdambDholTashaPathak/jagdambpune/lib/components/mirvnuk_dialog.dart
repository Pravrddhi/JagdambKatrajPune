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
    final formKey = GlobalKey<FormState>();

    final TextEditingController nameController = TextEditingController();
    final TextEditingController dateController = TextEditingController();
    final TextEditingController timeFromController = TextEditingController();
    final TextEditingController timeToController = TextEditingController();
    final TextEditingController locationController = TextEditingController();
    final TextEditingController mapLinkController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();

    const storage = FlutterSecureStorage();

    DateTime? selectedDate;
    TimeOfDay? timeFrom;
    TimeOfDay? timeTo;

    bool isSubmitting = false;

    await showDialog(
      context: context,
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        final screenHeight = mediaQuery.size.height;
        final bottomInset = mediaQuery.viewInsets.bottom;
        const verticalInset = 10.0;
        final availableHeight =
            (screenHeight - bottomInset - (verticalInset * 2)).clamp(
              240.0,
              screenHeight,
            );

        return StatefulBuilder(
          builder: (context, setState) {
            bool isFormValid() {
              return nameController.text.isNotEmpty &&
                  dateController.text.isNotEmpty &&
                  timeFromController.text.isNotEmpty &&
                  timeToController.text.isNotEmpty &&
                  locationController.text.isNotEmpty &&
                  mapLinkController.text.isNotEmpty &&
                  Uri.tryParse(mapLinkController.text)?.hasAbsolutePath ==
                      true &&
                  descriptionController.text.isNotEmpty;
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
                  const Expanded(
                    child: Text(
                      "Add Mirvnuk",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryMaroon,
                      ),
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: availableHeight),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Fill all details to publish the Mirvnuk event.',
                          style: TextStyle(
                            color: AppColors.primaryMaroon,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: "Mirvnuk Name",
                            prefixIcon: Icon(
                              Icons.event,
                              color: AppColors.primaryMaroon,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) =>
                              val == null || val.isEmpty ? 'Required' : null,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: dateController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: "Date",
                            prefixIcon: Icon(
                              Icons.calendar_today,
                              color: AppColors.primaryMaroon,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) =>
                              val == null || val.isEmpty ? 'Required' : null,
                          onTap: () async {
                            DateTime now = DateTime.now();
                            selectedDate = await showDatePicker(
                              context: context,
                              initialDate: now,
                              firstDate: now,
                              lastDate: DateTime(2100),
                            );
                            if (selectedDate != null) {
                              dateController.text =
                                  "${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}";
                              setState(() {});
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: timeFromController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: "Start Time",
                            prefixIcon: Icon(
                              Icons.access_time,
                              color: AppColors.primaryMaroon,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) =>
                              val == null || val.isEmpty ? 'Required' : null,
                          onTap: () async {
                            timeFrom = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.now(),
                            );
                            if (timeFrom != null) {
                              timeFromController.text =
                                  "${timeFrom!.hour.toString().padLeft(2, '0')}:${timeFrom!.minute.toString().padLeft(2, '0')}";
                              setState(() {});
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: timeToController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: "End Time",
                            prefixIcon: Icon(
                              Icons.access_time,
                              color: AppColors.primaryMaroon,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) {
                            if (val == null || val.isEmpty) return 'Required';
                            if (timeFromController.text.isNotEmpty) {
                              final startParts = timeFromController.text.split(
                                ":",
                              );
                              final endParts = val.split(":");
                              final startMinutes =
                                  int.parse(startParts[0]) * 60 +
                                  int.parse(startParts[1]);
                              final endMinutes =
                                  int.parse(endParts[0]) * 60 +
                                  int.parse(endParts[1]);
                              if (endMinutes <= startMinutes) {
                                return 'End must be after start';
                              }
                            }
                            return null;
                          },
                          onTap: () async {
                            timeTo = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.now(),
                            );
                            if (timeTo != null) {
                              timeToController.text =
                                  "${timeTo!.hour.toString().padLeft(2, '0')}:${timeTo!.minute.toString().padLeft(2, '0')}";
                              setState(() {});
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: locationController,
                          decoration: const InputDecoration(
                            labelText: "Location",
                            prefixIcon: Icon(
                              Icons.location_on,
                              color: AppColors.primaryMaroon,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) =>
                              val == null || val.isEmpty ? 'Required' : null,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: mapLinkController,
                          decoration: const InputDecoration(
                            labelText: "Map Link",
                            prefixIcon: Icon(
                              Icons.map,
                              color: AppColors.primaryMaroon,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) {
                            if (val == null || val.isEmpty) return 'Required';
                            if (Uri.tryParse(val)?.hasAbsolutePath != true) {
                              return 'Invalid URL';
                            }
                            return null;
                          },
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: descriptionController,
                          decoration: const InputDecoration(
                            labelText: "Description",
                            prefixIcon: Icon(
                              Icons.description,
                              color: AppColors.primaryMaroon,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 3,
                          validator: (val) =>
                              val == null || val.isEmpty ? 'Required' : null,
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: AppColors.primaryMaroon),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isFormValid()
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
                  onPressed: isFormValid() && !isSubmitting
                      ? () async {
                          if (!formKey.currentState!.validate()) {
                            return;
                          }
                          setState(() => isSubmitting = true);

                          String? accessToken = await storage.read(
                            key: ApiEndpoints.accessTokenKey,
                          );
                          if (accessToken == null ||
                              accessToken.trim().isEmpty) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
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
                            "pathak_id": ApiEndpoints.pathakId,
                            "name": nameController.text,
                            "date": dateController.text,
                            "time_from": timeFromController.text,
                            "time_to": timeToController.text,
                            "location": locationController.text,
                            "map_link": mapLinkController.text,
                            "description": descriptionController.text,
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
                              ScaffoldMessenger.of(context).showSnackBar(
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
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Mirvnuk added successfully'),
                                ),
                              );
                            } else if (response.statusCode == 401) {
                              ScaffoldMessenger.of(context).showSnackBar(
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
                              ScaffoldMessenger.of(context).showSnackBar(
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
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  ApiEndpoints.genericApiFailureMessage,
                                ),
                              ),
                            );
                          } finally {
                            setState(() => isSubmitting = false);
                          }
                        }
                      : null,
                  icon: isSubmitting
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, size: 16),
                  label: Text(isSubmitting ? 'Submitting...' : 'Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
