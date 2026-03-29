class User {
  final int? id;
  final bool? isActive;
  final String? phoneNumber;
  final String? firstName;
  final String? lastName;
  final String? instrument;
  final String? sex;
  final String? role;
  final String? bloodGroup;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? gatName;
  final String? gatPramukhName;

  User({
    this.id,
    this.isActive,
    this.phoneNumber,
    this.firstName,
    this.lastName,
    this.instrument,
    this.sex,
    this.role,
    this.bloodGroup,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.gatName,
    this.gatPramukhName,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    final dynamic gatRaw =
        json['gat_name'] ??
        json['gat'] ??
        json['gatName'] ??
        json['group'] ??
        json['gat_id'];
    final String? parsedGatName = switch (gatRaw) {
      null => null,
      Map<String, dynamic> map => map['name']?.toString(),
      _ => gatRaw.toString(),
    };

    return User(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id'] ?? ''}'),
      isActive: json['is_active'] is bool
          ? json['is_active'] as bool
          : (json['is_active'] == null
                ? null
                : '${json['is_active']}'.toLowerCase() == 'true'),
      phoneNumber: json['phone_number'],
      firstName: json['first_name'],
      lastName: json['last_name'],
      instrument: json['instrument'],
      sex: json['sex'],
      role: json['role'],
      bloodGroup: json['blood_group'],
      emergencyContactName: json['emergency_contact_name'],
      emergencyContactPhone: json['emergency_contact_phone'],
      gatName: parsedGatName,
      gatPramukhName: json['gat_pramukh_name'],
    );
  }

  User copyWith({
    int? id,
    bool? isActive,
    String? phoneNumber,
    String? firstName,
    String? lastName,
    String? instrument,
    String? sex,
    String? role,
    String? bloodGroup,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? gatName,
    String? gatPramukhName,
  }) {
    return User(
      id: id ?? this.id,
      isActive: isActive ?? this.isActive,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      instrument: instrument ?? this.instrument,
      sex: sex ?? this.sex,
      role: role ?? this.role,
      bloodGroup: bloodGroup ?? this.bloodGroup,
      emergencyContactName: emergencyContactName ?? this.emergencyContactName,
      emergencyContactPhone:
          emergencyContactPhone ?? this.emergencyContactPhone,
      gatName: gatName ?? this.gatName,
      gatPramukhName: gatPramukhName ?? this.gatPramukhName,
    );
  }
}
