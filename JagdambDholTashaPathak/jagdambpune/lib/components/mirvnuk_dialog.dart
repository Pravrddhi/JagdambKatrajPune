import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_endpoints.dart';
import '../theme/app_colors.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AddMirvnukDialog {
  static Future<void> show(BuildContext context) async {
    await showGeneralDialog(
      context: context,
      barrierLabel: "Add Mirvnuk",
      barrierDismissible: true,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, __, ___) => const _AddMirvnukForm(),
      transitionBuilder: (_, anim, __, child) {
        final curvedAnim =
            CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.3),
              end: Offset.zero,
            ).animate(curvedAnim),
            child: ScaleTransition(scale: curvedAnim, child: child),
          ),
        );
      },
    );
  }
}

class _AddMirvnukForm extends StatefulWidget {
  const _AddMirvnukForm();

  @override
  State<_AddMirvnukForm> createState() => _AddMirvnukFormState();
}

class _AddMirvnukFormState extends State<_AddMirvnukForm> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _dateController = TextEditingController();
  final storage = const FlutterSecureStorage();

  String? name;
  DateTime? date;
  String? location;
  String? mapLink;
  String? description;
  bool _isSubmitting = false;

  final _nameFocus = FocusNode();
  final _dateFocus = FocusNode();
  final _locationFocus = FocusNode();
  final _mapLinkFocus = FocusNode();
  final _descriptionFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(_onFocusChange);
    _dateFocus.addListener(_onFocusChange);
    _locationFocus.addListener(_onFocusChange);
    _mapLinkFocus.addListener(_onFocusChange);
    _descriptionFocus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    setState(() {});
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _dateFocus.dispose();
    _locationFocus.dispose();
    _mapLinkFocus.dispose();
    _descriptionFocus.dispose();
    _dateController.dispose();
    super.dispose();
  }

  bool get _isFormValid {
    return name?.isNotEmpty == true &&
        date != null &&
        !date!.isBefore(DateTime.now()) &&
        location?.isNotEmpty == true &&
        mapLink?.isNotEmpty == true &&
        Uri.tryParse(mapLink!)?.hasAbsolutePath == true &&
        description?.isNotEmpty == true;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _isSubmitting = true);

    String? accessToken = await storage.read(key: 'access_token');
    if (accessToken != null) {
      try {
        final response = await http.post(
          Uri.parse(ApiEndpoints.createEvent),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode({
            "pathak": ApiEndpoints.pathak_id,
            "name": name,
            "date":
                "${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}",
            "location": location,
            "map_link": mapLink,
            "description": description,
          }),
        );

        if (response.statusCode == 201 || response.statusCode == 200) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mirvnuk added successfully')),
          );

        } else {
          final data = jsonDecode(response.body);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'] ?? 'Failed to add event')),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      } finally {
        setState(() => _isSubmitting = false);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Access token not found')));
    }
  }

  InputDecoration _inputDecoration(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon != null ? Icon(icon, color: AppColors.primaryMaroon) : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.primaryMaroon, width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 60.0),
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Color(0xFFFFF8E1), Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              // border: Border.all(
              //   color: AppColors.primaryMaroon,
              //   width: 10,
              // ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                )
              ],
            ),
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header Container
                    Container(
                      width: double.infinity,
                      height: 60,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryMaroon,
                        // borderRadius: BorderRadius.only(
                        //   bottomLeft: Radius.circular(16),
                        //   bottomRight: Radius.circular(16),
                        // ),
                      ),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 60), // space before title
                      child: const Text(
                        'Add Mirvnuk',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.accentYellow,
                        ),
                      ),
                    ),

                    // Space after header
                    const SizedBox(height: 20),

                    // Form container
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: SingleChildScrollView(
                        child: Form(
                          key: _formKey,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Name
                              TextFormField(
                                focusNode: _nameFocus,
                                decoration: _inputDecoration('Mirvnuk Name', icon: Icons.person),
                                validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                                onChanged: (val) {
                                  name = val;
                                  setState(() {});
                                },
                              ),
                              const SizedBox(height: 10),

                              // Date
                              TextFormField(
                                controller: _dateController,
                                focusNode: _dateFocus,
                                readOnly: true,
                                decoration: _inputDecoration('Date', icon: Icons.calendar_today),
                                validator: (_) {
                                  if (date == null) return 'Please select a date';
                                  if (date!.isBefore(DateTime.now())) return 'Date cannot be in the past';
                                  return null;
                                },
                                onTap: () async {
                                  DateTime? picked = await showDatePicker(
                                    context: context,
                                    initialDate: DateTime.now(),
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      date = picked;
                                      _dateController.text =
                                          "${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}";
                                    });
                                  }
                                },
                              ),
                              const SizedBox(height: 10),

                              // Location
                              TextFormField(
                                focusNode: _locationFocus,
                                decoration: _inputDecoration('Location', icon: Icons.location_on),
                                validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                                onChanged: (val) {
                                  location = val;
                                  setState(() {});
                                },
                              ),
                              const SizedBox(height: 10),

                              // Map Link
                              TextFormField(
                                focusNode: _mapLinkFocus,
                                decoration: _inputDecoration('Map Link', icon: Icons.map),
                                validator: (val) {
                                  if (val == null || val.isEmpty) return 'Required';
                                  if (Uri.tryParse(val)?.hasAbsolutePath != true) return 'Invalid URL';
                                  return null;
                                },
                                onChanged: (val) {
                                  mapLink = val;
                                  setState(() {});
                                },
                              ),
                              const SizedBox(height: 10),

                              // Description
                              TextFormField(
                                focusNode: _descriptionFocus,
                                decoration: _inputDecoration('Description', icon: Icons.description),
                                maxLines: 3,
                                validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                                onChanged: (val) {
                                  description = val;
                                  setState(() {});
                                },
                              ),
                              const SizedBox(height: 20),

                              // Submit button
                              FittedBox(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    backgroundColor: _isFormValid ? AppColors.accentYellow : Colors.grey[400],
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 6,
                                  ),
                                  onPressed: _isFormValid && !_isSubmitting ? _submit : null,
                                  icon: const Icon(Icons.add_circle_outline, color: AppColors.primaryMaroon),
                                  label: const Text(
                                    'Add Mirvnuk',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: AppColors.primaryMaroon,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // Close button on right
                Positioned(
                  top: 12,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: AppColors.accentYellow),
                    onPressed: () => Navigator.pop(context),
                    iconSize: 24,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
