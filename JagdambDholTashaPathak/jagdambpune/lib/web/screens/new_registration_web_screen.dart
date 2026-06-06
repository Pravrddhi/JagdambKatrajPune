import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../../services/new_registration_service.dart';
import '../../theme/app_colors.dart';

class NewRegistrationWebScreen extends StatefulWidget {
  const NewRegistrationWebScreen({super.key});

  @override
  State<NewRegistrationWebScreen> createState() =>
      _NewRegistrationWebScreenState();
}

class _NewRegistrationWebScreenState extends State<NewRegistrationWebScreen> {
  static const String _maleWhatsAppGroupLink =
      'https://chat.whatsapp.com/REPLACE_WITH_MALE_GROUP_LINK';
  static const String _femaleWhatsAppGroupLink =
      'https://chat.whatsapp.com/REPLACE_WITH_FEMALE_GROUP_LINK';

  String get _seasonLabel {
    final now = DateTime.now();
    return '${now.year}-${now.year + 1}';
  }

  String get _seasonApiLabel {
    final now = DateTime.now();
    return '${now.year}-${(now.year + 1) % 100}';
  }

  String _toMarathiDigits(String value) {
    const western = '0123456789';
    const marathi = '०१२३४५६७८९';
    return value.split('').map((char) {
      final index = western.indexOf(char);
      return index == -1 ? char : marathi[index];
    }).join();
  }

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _whatsAppController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  DateTime? _selectedDob;
  String? _dobErrorMessage;
  String? _selectedGender;
  String? _selectedInstrument;
  bool _isSubmitting = false;
  Map<String, String> _serverFieldErrors = <String, String>{};

  final List<_OptionItem> _genderOptions = const [
    _OptionItem(value: 'male', labelEn: 'Male', labelMr: 'पुरुष'),
    _OptionItem(value: 'female', labelEn: 'Female', labelMr: 'स्त्री'),
  ];

  final List<_OptionItem> _instrumentOptions = const [
    _OptionItem(value: 'dhol', labelEn: 'Dhol', labelMr: 'ढोल'),
    _OptionItem(value: 'tasha', labelEn: 'Tasha', labelMr: 'ताशा'),
    _OptionItem(value: 'dhwaj', labelEn: 'Dhwaj', labelMr: 'ध्वज'),
  ];

  final List<TextInputFormatter> _nameInputFormatters = [
    FilteringTextInputFormatter.allow(
      RegExp(r"[A-Za-zÀ-ÖØ-öø-ÿ\u0900-\u097F\s.'\-]", unicode: true),
    ),
  ];

  final List<TextInputFormatter> _phoneInputFormatters = [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(10),
  ];

  bool get _canSubmit {
    final fullName = _fullNameController.text.trim();
    final whatsapp = _whatsAppController.text.trim();
    final address = _addressController.text.trim();

    return !_isSubmitting &&
        fullName.isNotEmpty &&
        whatsapp.isNotEmpty &&
        address.isNotEmpty &&
        _selectedDob != null &&
        _isAtLeast18(_selectedDob!) &&
        _selectedGender != null &&
        _selectedInstrument != null &&
        _dobErrorMessage == null;
  }

  @override
  void initState() {
    super.initState();
    _fullNameController.addListener(_handleFormChanged);
    _whatsAppController.addListener(_handleFormChanged);
    _addressController.addListener(_handleFormChanged);
  }

  void _handleFormChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _fullNameController.removeListener(_handleFormChanged);
    _whatsAppController.removeListener(_handleFormChanged);
    _addressController.removeListener(_handleFormChanged);
    _fullNameController.dispose();
    _whatsAppController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initialDate =
        _selectedDob ?? DateTime(now.year - 19, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1960),
      lastDate: now,
      helpText: 'Select Date of Birth / जन्म तारीख निवडा',
    );

    if (picked != null) {
      setState(() {
        _selectedDob = picked;
        _dobErrorMessage = _isAtLeast18(picked)
            ? null
            : 'You are below 18 years. Please ask your parents to register on behalf of you.\n\n'
                  'तुमचे वय १८ वर्षांपेक्षा कमी आहे. कृपया तुमच्या पालकांना तुमच्या वतीने नोंदणी करण्यास सांगा.';
      });
    }
  }

  bool _isAtLeast18(DateTime dob) {
    final today = DateTime.now();
    var age = today.year - dob.year;
    if (today.month < dob.month ||
        (today.month == dob.month && today.day < dob.day)) {
      age -= 1;
    }
    return age >= 18;
  }

  String _formatDob(DateTime value) {
    final dd = value.day.toString().padLeft(2, '0');
    final mm = value.month.toString().padLeft(2, '0');
    return '$dd/$mm/${value.year}';
  }

  String? _validateWhatsApp(String? raw) {
    final value = (raw ?? '').replaceAll(RegExp(r'\D'), '');
    if (value.isEmpty) {
      return 'WhatsApp number is required / व्हॉट्सॲप नंबर आवश्यक आहे';
    }
    if (value.length != 10) {
      return 'Enter a valid 10-digit mobile number / १० अंकी नंबर टाका';
    }
    return null;
  }

  String? _validateName(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) {
      return 'Full name is required / पूर्ण नाव आवश्यक आहे';
    }
    if (RegExp(r'\d').hasMatch(value)) {
      return 'Numbers are not allowed in name / नावात अंक मान्य नाहीत';
    }
    return null;
  }

  String? _groupLinkForGender(String? gender) {
    switch (gender) {
      case 'male':
        return _maleWhatsAppGroupLink;
      case 'female':
        return _femaleWhatsAppGroupLink;
      default:
        return null;
    }
  }

  Future<void> _openWhatsAppGroupLink(String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _showSuccessDialog({required String gender}) async {
    final groupLink = _groupLinkForGender(gender);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Registration Successful / नोंदणी यशस्वी'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Please join this group for next updates.'),
            SizedBox(height: 10),
            Text('पुढील अपडेटसाठी कृपया या ग्रुपमध्ये सामील व्हा.'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: groupLink == null
                ? null
                : () async {
                    await _openWhatsAppGroupLink(groupLink);
                    if (mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
            child: const Text('Join WhatsApp Group'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _serverFieldErrors = <String, String>{};
    });

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    if (_selectedDob == null || !_isAtLeast18(_selectedDob!)) {
      setState(() {
        _dobErrorMessage =
            'You are below 18 years. Please ask your parents to register on behalf of you.\n\n'
            'तुमचे वय १८ वर्षांपेक्षा कमी आहे. कृपया तुमच्या पालकांना तुमच्या वतीने नोंदणी करण्यास सांगा.';
      });
      return;
    }

    if (_selectedGender == null || _selectedInstrument == null) {
      _showSnack(
        'Please select gender and instrument. / कृपया लिंग आणि वाद्य निवडा.',
        isError: true,
      );
      return;
    }

    final seasonError = NewRegistrationService.validateSeasonFormat(
      _seasonApiLabel,
    );
    if (seasonError != null) {
      _showSnack(seasonError, isError: true);
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final payload = NewRegistrationPayload(
      fullName: _fullNameController.text.trim(),
      gender: _selectedGender!,
      whatsappNumber: _whatsAppController.text.replaceAll(RegExp(r'\D'), ''),
      dateOfBirth: _selectedDob!,
      instrument: _selectedInstrument!,
      fullAddress: _addressController.text.trim(),
      season: _seasonApiLabel,
    );

    final result = await NewRegistrationService.submit(payload);

    if (!mounted) {
      return;
    }

    setState(() {
      _isSubmitting = false;
      _serverFieldErrors = result.fieldErrors;
    });

    if (!result.success && result.fieldErrors.isNotEmpty) {
      _formKey.currentState?.validate();
    }

    if (result.success) {
      final currentGender = _selectedGender ?? '';
      _formKey.currentState?.reset();
      setState(() {
        _selectedDob = null;
        _dobErrorMessage = null;
        _selectedGender = null;
        _selectedInstrument = null;
      });
      _fullNameController.clear();
      _whatsAppController.clear();
      _addressController.clear();

      await _showSuccessDialog(gender: currentGender);
      return;
    }

    _showSnack(result.message, isError: !result.success);
  }

  void _showSnack(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F1E8),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: AppColors.primaryMaroon,
          foregroundColor: Colors.white,
          centerTitle: true,
          title: const Text('New Registration / नवीन नोंदणी'),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF8F2E9), Color(0xFFFFFBF5), Color(0xFFF3E9D9)],
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: Colors.white.withAlpha(245),
                    border: Border.all(color: const Color(0xFFEED7B2)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1F4F2A22),
                        blurRadius: 28,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPremiumHeader(context),
                          const SizedBox(height: 18),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF8E1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFF9A825),
                              ),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '⚠️ Important: Only individuals aged 18 years and above are eligible to fill this form.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF5D4037),
                                  ),
                                ),
                                SizedBox(height: 10),
                                Text(
                                  '⚠️ महत्त्वाची सूचना: हा फॉर्म भरण्यासाठी वय १८ वर्षे पूर्ण असणे अनिवार्य आहे. (१८ वर्षांखालील व्यक्तींचे अर्ज स्वीकारले जाणार नाहीत).',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF5D4037),
                                  ),
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'Help / मदत: Pratik Shinde - 9767704126',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF5D4037),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          _buildTextField(
                            controller: _fullNameController,
                            label: 'Full Name',
                            marathi: 'पूर्ण नाव (नाव - वडिलांचे नाव - आडनाव)',
                            apiFieldKey: 'full_name',
                            icon: Icons.person_rounded,
                            inputFormatters: _nameInputFormatters,
                            validator: (value) {
                              return _validateName(value);
                            },
                          ),
                          const SizedBox(height: 14),
                          _buildDropdown(
                            label: 'Gender',
                            marathi: 'लिंग (पुरुष / स्त्री / इतर)',
                            apiFieldKey: 'gender',
                            icon: Icons.wc_rounded,
                            value: _selectedGender,
                            items: _genderOptions,
                            onChanged: (value) {
                              setState(() {
                                _selectedGender = value;
                              });
                            },
                          ),
                          const SizedBox(height: 14),
                          _buildTextField(
                            controller: _whatsAppController,
                            label: 'WhatsApp Mobile Number',
                            marathi: 'व्हॉट्सॲप मोबाईल नंबर',
                            apiFieldKey: 'whatsapp_mobile_number',
                            icon: Icons.phone_android_rounded,
                            keyboardType: TextInputType.phone,
                            inputFormatters: _phoneInputFormatters,
                            validator: _validateWhatsApp,
                          ),
                          const SizedBox(height: 14),
                          _buildDobField(),
                          const SizedBox(height: 14),
                          _buildDropdown(
                            label:
                                'Instrument Selection (Dhol / Tasha / Dhwaj)',
                            marathi: 'वाद्य निवड (ढोल / ताशा / ध्वज)',
                            apiFieldKey: 'instrument',
                            icon: Icons.music_note_rounded,
                            value: _selectedInstrument,
                            items: _instrumentOptions,
                            onChanged: (value) {
                              setState(() {
                                _selectedInstrument = value;
                              });
                            },
                          ),
                          const SizedBox(height: 14),
                          _buildTextField(
                            controller: _addressController,
                            label: 'Full Address',
                            marathi: 'पूर्ण पत्ता (सध्या राहता पत्ता)',
                            apiFieldKey: 'full_address',
                            icon: Icons.home_rounded,
                            maxLines: 3,
                            validator: (value) {
                              if ((value ?? '').trim().isEmpty) {
                                return 'Address is required / पत्ता आवश्यक आहे';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _canSubmit ? _submit : null,
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                backgroundColor: AppColors.primaryMaroon,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _isSubmitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Submit Registration / नोंदणी सबमिट करा',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String marathi,
    required String apiFieldKey,
    required IconData icon,
    required String? Function(String?) validator,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label  |  $marathi',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.primaryMaroon,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          maxLines: maxLines,
          validator: (value) {
            final localError = validator(value);
            if (localError != null) {
              return localError;
            }
            return _serverFieldErrors[apiFieldKey];
          },
          decoration: _formInputDecoration(prefixIcon: icon),
        ),
      ],
    );
  }

  Widget _buildPremiumHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFFFDF3D6), Color(0xFFFFF9EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFFEBC67D)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 640;

          Widget logo = Container(
            width: isCompact ? 132 : 156,
            height: isCompact ? 88 : 96,
            decoration: BoxDecoration(
              color: AppColors.primaryMaroon,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE0B861), width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  AppConfig.logoAsset,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.music_note_rounded,
                    size: 36,
                    color: AppColors.primaryMaroon,
                  ),
                ),
              ),
            ),
          );

          Widget titles = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Jagdamb Dhol Tasha Pathak Katraj, Pune\nNew Vadak Registration Form (Season $_seasonLabel)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isCompact ? 19 : 22,
                  height: 1.4,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryMaroon,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'जगदंब ढोल ताशा पथक कात्रज, पुणे\nनवीन वादक नोंदणी अर्ज (हंगाम ${_toMarathiDigits(_seasonLabel)})',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isCompact ? 15 : 17,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryMaroon,
                ),
              ),
            ],
          );

          if (isCompact) {
            return Column(children: [logo, const SizedBox(height: 12), titles]);
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              logo,
              const SizedBox(width: 18),
              Expanded(child: titles),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String marathi,
    required String apiFieldKey,
    required IconData icon,
    required String? value,
    required List<_OptionItem> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label  |  $marathi',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.primaryMaroon,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: value,
          decoration: _formInputDecoration(prefixIcon: icon),
          items: items
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item.value,
                  child: Text('${item.labelEn} / ${item.labelMr}'),
                ),
              )
              .toList(),
          onChanged: onChanged,
          validator: (selected) {
            if (selected == null || selected.isEmpty) {
              return 'Required field / आवश्यक माहिती';
            }
            return _serverFieldErrors[apiFieldKey];
          },
        ),
      ],
    );
  }

  Widget _buildDobField() {
    final displayText = _selectedDob == null
        ? 'Select DOB / जन्म तारीख निवडा'
        : _formatDob(_selectedDob!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Date of Birth (DOB)  |  जन्म तारीख',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.primaryMaroon,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: _pickDob,
          borderRadius: BorderRadius.circular(14),
          child: InputDecorator(
            decoration: _formInputDecoration(prefixIcon: Icons.cake_rounded),
            child: Row(
              children: [
                Expanded(child: Text(displayText)),
                const Icon(Icons.calendar_month),
              ],
            ),
          ),
        ),
        if (_serverFieldErrors['date_of_birth'] != null) ...[
          const SizedBox(height: 6),
          Text(
            _serverFieldErrors['date_of_birth']!,
            style: TextStyle(color: Colors.red.shade700, fontSize: 12),
          ),
        ] else if (_dobErrorMessage != null) ...[
          const SizedBox(height: 6),
          Text(
            _dobErrorMessage!,
            style: TextStyle(color: Colors.red.shade700, fontSize: 12),
          ),
        ],
      ],
    );
  }

  InputDecoration _formInputDecoration({required IconData prefixIcon}) {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFFFFCF8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      prefixIcon: Icon(prefixIcon, size: 20, color: const Color(0xFFA66D2B)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE6D0AD)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFC68A42), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD35D5D)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD35D5D), width: 1.4),
      ),
    );
  }
}

class _OptionItem {
  const _OptionItem({
    required this.value,
    required this.labelEn,
    required this.labelMr,
  });

  final String value;
  final String labelEn;
  final String labelMr;
}
