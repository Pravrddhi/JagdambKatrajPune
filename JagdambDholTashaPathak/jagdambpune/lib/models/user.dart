class User {
  final int? id;
  final bool? isActive;
  final bool? isDeleted;
  final int? approvalStatus;
  final String? phoneNumber;
  final String? firstName;
  final String? lastName;
  final String? instrument;
  final String? joiningYear;
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
    this.isDeleted,
    this.approvalStatus,
    this.phoneNumber,
    this.firstName,
    this.lastName,
    this.instrument,
    this.joiningYear,
    this.sex,
    this.role,
    this.bloodGroup,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.gatName,
    this.gatPramukhName,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    final rawDeleted = json['isdelete'] ?? json['is_deleted'];
    final bool? parsedIsDeleted = (() {
      if (rawDeleted == null) return null;
      if (rawDeleted is bool) return rawDeleted;
      if (rawDeleted is num) return rawDeleted != 0;
      final normalized = rawDeleted.toString().trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    })();

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
      approvalStatus: json['approval_status'] is int
          ? json['approval_status'] as int
          : int.tryParse('${json['approval_status'] ?? ''}'),
      isActive: (() {
        if (parsedIsDeleted == true) {
          return false;
        }

        if (json['is_active'] is bool) {
          return json['is_active'] as bool;
        }

        if (json['is_active'] != null) {
          return '${json['is_active']}'.toLowerCase() == 'true';
        }

        final parsedApprovalStatus = json['approval_status'] is int
            ? json['approval_status'] as int
            : int.tryParse('${json['approval_status'] ?? ''}');
        if (parsedApprovalStatus == null) {
          return null;
        }

        return parsedApprovalStatus == 1;
      })(),
      isDeleted: parsedIsDeleted,
      phoneNumber: json['phone_number'],
      firstName: json['first_name'],
      lastName: json['last_name'],
      instrument: json['instrument'],
      joiningYear: json['joining_year']?.toString(),
      sex: json['sex'],
      role: json['role']?.toString() ?? json['group_name']?.toString(),
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
    bool? isDeleted,
    int? approvalStatus,
    String? phoneNumber,
    String? firstName,
    String? lastName,
    String? instrument,
    String? joiningYear,
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
      isDeleted: isDeleted ?? this.isDeleted,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      instrument: instrument ?? this.instrument,
      joiningYear: joiningYear ?? this.joiningYear,
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
