class UserAnalysisProfile {
  final int id;
  final String firstName;
  final String lastName;
  final String phoneNumber;
  final String role;
  final List<String> groups;
  final String? instrument;
  final String? joiningYear;
  final String? sex;
  final String? bloodGroup;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? profilePhotoUrl;
  final bool isActive;

  const UserAnalysisProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    required this.role,
    required this.groups,
    this.instrument,
    this.joiningYear,
    this.sex,
    this.bloodGroup,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.profilePhotoUrl,
    required this.isActive,
  });

  String get fullName => '$firstName $lastName'.trim();

  factory UserAnalysisProfile.fromJson(Map<String, dynamic> j) {
    final rawGroups = j['groups'];
    final groups = rawGroups is List
        ? rawGroups.map((e) => e.toString()).toList()
        : <String>[];
    return UserAnalysisProfile(
      id: j['id'] as int,
      firstName: j['first_name']?.toString() ?? '',
      lastName: j['last_name']?.toString() ?? '',
      phoneNumber: j['phone_number']?.toString() ?? '',
      role: j['role']?.toString() ?? '',
      groups: groups,
      instrument: j['instrument']?.toString(),
      joiningYear: j['joining_year']?.toString(),
      sex: j['sex']?.toString(),
      bloodGroup: j['blood_group']?.toString(),
      emergencyContactName: j['emergency_contact_name']?.toString(),
      emergencyContactPhone: j['emergency_contact_phone']?.toString(),
      profilePhotoUrl: j['profile_photo_url']?.toString(),
      isActive: j['is_active'] == true,
    );
  }
}

class UserAnalysisGat {
  final int? gatId;
  final String gatName;
  final String gatPramukhName;
  final String? gatPramukhPhone;
  final String? memberSince;
  final String position;
  final int totalGatMembers;

  const UserAnalysisGat({
    this.gatId,
    required this.gatName,
    required this.gatPramukhName,
    this.gatPramukhPhone,
    this.memberSince,
    required this.position,
    required this.totalGatMembers,
  });

  factory UserAnalysisGat.fromJson(Map<String, dynamic> j) {
    return UserAnalysisGat(
      gatId: j['gat_id'] as int?,
      gatName: j['gat_name']?.toString() ?? '',
      gatPramukhName: j['gat_pramukh_name']?.toString() ?? '',
      gatPramukhPhone: j['gat_pramukh_phone']?.toString(),
      memberSince: j['member_since']?.toString(),
      position: j['position']?.toString() ?? 'member',
      totalGatMembers: (j['total_gat_members'] as num?)?.toInt() ?? 0,
    );
  }
}

class AttendanceMonth {
  final String month;
  final String monthDisplay;
  final int totalDays;
  final int present;
  final int absent;
  final int late;

  const AttendanceMonth({
    required this.month,
    required this.monthDisplay,
    required this.totalDays,
    required this.present,
    required this.absent,
    required this.late,
  });

  factory AttendanceMonth.fromJson(Map<String, dynamic> j) {
    return AttendanceMonth(
      month: j['month']?.toString() ?? '',
      monthDisplay: j['month_display']?.toString() ?? '',
      totalDays: (j['total_days'] as num?)?.toInt() ?? 0,
      present: (j['present'] as num?)?.toInt() ?? 0,
      absent: (j['absent'] as num?)?.toInt() ?? 0,
      late: (j['late'] as num?)?.toInt() ?? 0,
    );
  }
}

class UserAnalysisAttendance {
  final int totalDays;
  final int totalPresent;
  final int totalAbsent;
  final int totalLate;
  final double attendancePercentage;
  final List<AttendanceMonth> monthly;

  const UserAnalysisAttendance({
    required this.totalDays,
    required this.totalPresent,
    required this.totalAbsent,
    required this.totalLate,
    required this.attendancePercentage,
    required this.monthly,
  });

  factory UserAnalysisAttendance.fromJson(Map<String, dynamic> j) {
    final rawMonthly = j['monthly'];
    final monthly = rawMonthly is List
        ? rawMonthly
              .whereType<Map<String, dynamic>>()
              .map(AttendanceMonth.fromJson)
              .toList()
        : <AttendanceMonth>[];
    return UserAnalysisAttendance(
      totalDays: (j['total_days'] as num?)?.toInt() ?? 0,
      totalPresent: (j['total_present'] as num?)?.toInt() ?? 0,
      totalAbsent: (j['total_absent'] as num?)?.toInt() ?? 0,
      totalLate: (j['total_late'] as num?)?.toInt() ?? 0,
      attendancePercentage:
          (j['attendance_percentage'] as num?)?.toDouble() ?? 0.0,
      monthly: monthly,
    );
  }
}

class MaintenanceRecord {
  final int eventId;
  final String eventTitle;
  final String eventDate;
  final String? instrumentName;
  final String workType;
  final String status;
  final String? notes;
  final String? completedAt;
  final String? approvedBy;
  final String? approvedAt;

  const MaintenanceRecord({
    required this.eventId,
    required this.eventTitle,
    required this.eventDate,
    this.instrumentName,
    required this.workType,
    required this.status,
    this.notes,
    this.completedAt,
    this.approvedBy,
    this.approvedAt,
  });

  factory MaintenanceRecord.fromJson(Map<String, dynamic> j) {
    return MaintenanceRecord(
      eventId: (j['event_id'] as num?)?.toInt() ?? 0,
      eventTitle: j['event_title']?.toString() ?? '',
      eventDate: j['event_date']?.toString() ?? '',
      instrumentName: j['instrument_name']?.toString(),
      workType: j['work_type']?.toString() ?? '',
      status: j['status']?.toString() ?? '',
      notes: j['notes']?.toString(),
      completedAt: j['completed_at']?.toString(),
      approvedBy: j['approved_by']?.toString(),
      approvedAt: j['approved_at']?.toString(),
    );
  }
}

class UserAnalysisMaintenance {
  final int totalAssigned;
  final int totalCompleted;
  final int totalPending;
  final List<MaintenanceRecord> records;

  const UserAnalysisMaintenance({
    required this.totalAssigned,
    required this.totalCompleted,
    required this.totalPending,
    required this.records,
  });

  factory UserAnalysisMaintenance.fromJson(Map<String, dynamic> j) {
    final rawRecords = j['records'];
    final records = rawRecords is List
        ? rawRecords
              .whereType<Map<String, dynamic>>()
              .map(MaintenanceRecord.fromJson)
              .toList()
        : <MaintenanceRecord>[];
    return UserAnalysisMaintenance(
      totalAssigned: (j['total_assigned'] as num?)?.toInt() ?? 0,
      totalCompleted: (j['total_completed'] as num?)?.toInt() ?? 0,
      totalPending: (j['total_pending'] as num?)?.toInt() ?? 0,
      records: records,
    );
  }
}

class DocumentItem {
  final int itemId;
  final String type;
  final String typeDisplay;
  final String status;
  final String? assignedAt;
  final String? returnedAt;
  final String? photoUrl;
  final String? notes;

  const DocumentItem({
    required this.itemId,
    required this.type,
    required this.typeDisplay,
    required this.status,
    this.assignedAt,
    this.returnedAt,
    this.photoUrl,
    this.notes,
  });

  factory DocumentItem.fromJson(Map<String, dynamic> j) {
    return DocumentItem(
      itemId: (j['item_id'] as num?)?.toInt() ?? 0,
      type: j['type']?.toString() ?? '',
      typeDisplay: j['type_display']?.toString() ?? '',
      status: j['status']?.toString() ?? '',
      assignedAt: j['assigned_at']?.toString(),
      returnedAt: j['returned_at']?.toString(),
      photoUrl: j['photo_url']?.toString(),
      notes: j['notes']?.toString(),
    );
  }
}

class UserAnalysisDocuments {
  final List<DocumentItem> items;

  const UserAnalysisDocuments({required this.items});

  factory UserAnalysisDocuments.fromJson(Map<String, dynamic> j) {
    final rawItems = j['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(DocumentItem.fromJson)
              .toList()
        : <DocumentItem>[];
    return UserAnalysisDocuments(items: items);
  }
}

class StockUsageHistory {
  final int eventId;
  final String eventTitle;
  final String eventDate;
  final int quantityUsed;

  const StockUsageHistory({
    required this.eventId,
    required this.eventTitle,
    required this.eventDate,
    required this.quantityUsed,
  });

  factory StockUsageHistory.fromJson(Map<String, dynamic> j) {
    return StockUsageHistory(
      eventId: (j['event_id'] as num?)?.toInt() ?? 0,
      eventTitle: j['event_title']?.toString() ?? '',
      eventDate: j['event_date']?.toString() ?? '',
      quantityUsed: (j['quantity_used'] as num?)?.toInt() ?? 0,
    );
  }
}

class StockUsageItem {
  final int inventoryItemId;
  final String itemName;
  final String category;
  final int totalQuantityUsed;
  final int eventsCount;
  final List<StockUsageHistory> usageHistory;

  const StockUsageItem({
    required this.inventoryItemId,
    required this.itemName,
    required this.category,
    required this.totalQuantityUsed,
    required this.eventsCount,
    required this.usageHistory,
  });

  factory StockUsageItem.fromJson(Map<String, dynamic> j) {
    final rawHistory = j['usage_history'];
    final usageHistory = rawHistory is List
        ? rawHistory
              .whereType<Map<String, dynamic>>()
              .map(StockUsageHistory.fromJson)
              .toList()
        : <StockUsageHistory>[];
    return StockUsageItem(
      inventoryItemId: (j['inventory_item_id'] as num?)?.toInt() ?? 0,
      itemName: j['item_name']?.toString() ?? '',
      category: j['category']?.toString() ?? '',
      totalQuantityUsed: (j['total_quantity_used'] as num?)?.toInt() ?? 0,
      eventsCount: (j['events_count'] as num?)?.toInt() ?? 0,
      usageHistory: usageHistory,
    );
  }
}

class UserAnalysisStockUsage {
  final int totalEventsWithUsage;
  final int totalQuantityUsed;
  final List<StockUsageItem> items;

  const UserAnalysisStockUsage({
    required this.totalEventsWithUsage,
    required this.totalQuantityUsed,
    required this.items,
  });

  static const UserAnalysisStockUsage empty = UserAnalysisStockUsage(
    totalEventsWithUsage: 0,
    totalQuantityUsed: 0,
    items: [],
  );

  factory UserAnalysisStockUsage.fromJson(Map<String, dynamic> j) {
    final rawItems = j['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(StockUsageItem.fromJson)
              .toList()
        : <StockUsageItem>[];
    return UserAnalysisStockUsage(
      totalEventsWithUsage:
          (j['total_events_with_usage'] as num?)?.toInt() ?? 0,
      totalQuantityUsed: (j['total_quantity_used'] as num?)?.toInt() ?? 0,
      items: items,
    );
  }
}

class UserAnalysis {
  final UserAnalysisProfile profile;
  final UserAnalysisGat? gat;
  final UserAnalysisAttendance attendance;
  final UserAnalysisMaintenance maintenance;
  final UserAnalysisDocuments documents;
  final UserAnalysisStockUsage? stockUsage;

  const UserAnalysis({
    required this.profile,
    this.gat,
    required this.attendance,
    required this.maintenance,
    required this.documents,
    this.stockUsage,
  });

  factory UserAnalysis.fromJson(Map<String, dynamic> j) {
    final rawGat = j['gat'];
    final rawStock = j['stock_usage'];
    return UserAnalysis(
      profile: UserAnalysisProfile.fromJson(
        j['profile'] as Map<String, dynamic>,
      ),
      gat: rawGat is Map<String, dynamic>
          ? UserAnalysisGat.fromJson(rawGat)
          : null,
      attendance: UserAnalysisAttendance.fromJson(
        j['attendance'] as Map<String, dynamic>,
      ),
      maintenance: UserAnalysisMaintenance.fromJson(
        j['maintenance'] as Map<String, dynamic>,
      ),
      documents: UserAnalysisDocuments.fromJson(
        j['documents'] as Map<String, dynamic>,
      ),
      stockUsage: rawStock is Map<String, dynamic>
          ? UserAnalysisStockUsage.fromJson(rawStock)
          : const UserAnalysisStockUsage(
              totalEventsWithUsage: 0,
              totalQuantityUsed: 0,
              items: [],
            ),
    );
  }
}
