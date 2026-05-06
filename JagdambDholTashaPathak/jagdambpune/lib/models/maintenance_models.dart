class InventoryItem {
  final int id;
  final int? pathak;
  final String pathakName;
  final String category;
  final String categoryDisplay;
  final String otherCategoryName;
  final String name;
  final int quantityAvailable;
  final String createdAt;
  final String updatedAt;

  const InventoryItem({
    required this.id,
    required this.pathak,
    required this.pathakName,
    required this.category,
    required this.categoryDisplay,
    required this.otherCategoryName,
    required this.name,
    required this.quantityAvailable,
    required this.createdAt,
    required this.updatedAt,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      id: _toInt(json['id']) ?? 0,
      pathak: _toInt(json['pathak']),
      pathakName: json['pathak_name']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      categoryDisplay: json['category_display']?.toString() ?? '',
      otherCategoryName: json['other_category_name']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      quantityAvailable: _toInt(json['quantity_available']) ?? 0,
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }
}

class InventoryRequestItem {
  final int id;
  final int inventoryItem;
  final int? maintenanceEventId;
  final String maintenanceEventTitle;
  final String maintenanceEventDate;
  final String inventoryItemName;
  final String inventoryItemCategory;
  final String inventoryItemCategoryDisplay;
  final String inventoryItemOtherCategoryName;
  final int requestedQuantity;
  final String note;
  final String status;
  final String adminNote;
  final int? requestedBy;
  final String requestedByName;
  final String requestedByPhone;
  final int? approvedBy;
  final String approvedByName;
  final String approvedAt;
  final String createdAt;
  final String updatedAt;

  const InventoryRequestItem({
    required this.id,
    required this.inventoryItem,
    required this.maintenanceEventId,
    required this.maintenanceEventTitle,
    required this.maintenanceEventDate,
    required this.inventoryItemName,
    required this.inventoryItemCategory,
    required this.inventoryItemCategoryDisplay,
    required this.inventoryItemOtherCategoryName,
    required this.requestedQuantity,
    required this.note,
    required this.status,
    required this.adminNote,
    required this.requestedBy,
    required this.requestedByName,
    required this.requestedByPhone,
    required this.approvedBy,
    required this.approvedByName,
    required this.approvedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory InventoryRequestItem.fromJson(Map<String, dynamic> json) {
    return InventoryRequestItem(
      id: _toInt(json['id']) ?? 0,
      inventoryItem: _toInt(json['inventory_item']) ?? 0,
      maintenanceEventId:
          _toInt(json['event']) ??
          _toInt(json['event_id']) ??
          _toInt(json['maintenance_event']) ??
          _toInt(json['maintenance_event_id']),
      maintenanceEventTitle:
          json['event_title']?.toString() ??
          json['maintenance_event_title']?.toString() ??
          '',
      maintenanceEventDate:
          json['event_date']?.toString() ??
          json['maintenance_event_date']?.toString() ??
          '',
      inventoryItemName: json['inventory_item_name']?.toString() ?? '',
      inventoryItemCategory: json['inventory_item_category']?.toString() ?? '',
      inventoryItemCategoryDisplay:
          json['inventory_item_category_display']?.toString() ?? '',
      inventoryItemOtherCategoryName:
          json['inventory_item_other_category_name']?.toString() ?? '',
      requestedQuantity: _toInt(json['requested_quantity']) ?? 0,
      note: json['note']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      adminNote: json['admin_note']?.toString() ?? '',
      requestedBy: _toInt(json['requested_by']),
      requestedByName: json['requested_by_name']?.toString() ?? '',
      requestedByPhone: json['requested_by_phone']?.toString() ?? '',
      approvedBy: _toInt(json['approved_by']),
      approvedByName: json['approved_by_name']?.toString() ?? '',
      approvedAt: json['approved_at']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }

  DateTime? _normalizeDate(String rawValue) {
    final parsed = DateTime.tryParse(rawValue);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  DateTime? get createdDay => _normalizeDate(createdAt);

  DateTime? get approvedDay => _normalizeDate(approvedAt);

  DateTime? get requestDay => approvedDay ?? createdDay;

  DateTime? get linkedEventDay => _normalizeDate(maintenanceEventDate);

  String get normalizedStatus {
    final rawStatus = status.trim().toLowerCase();
    if (rawStatus == 'approved' || rawStatus == 'rejected') {
      return rawStatus;
    }

    // Some responses may keep status as pending even after approval metadata is set.
    if ((approvedBy != null && approvedBy! > 0) ||
        approvedAt.trim().isNotEmpty) {
      return 'approved';
    }

    if (rawStatus.isEmpty) {
      return 'pending';
    }
    return rawStatus;
  }

  bool matchesEventDate(String eventDate) {
    final eventDay = _normalizeDate(eventDate);
    final requestDate = requestDay;
    if (eventDay == null || requestDate == null) {
      return false;
    }
    return eventDay == requestDate;
  }

  bool matchesMaintenanceEvent(MaintenanceEvent event) {
    if (maintenanceEventId != null && maintenanceEventId == event.id) {
      return true;
    }

    final eventDay = event.parsedEventDate;
    final requestEventDay = linkedEventDay;
    if (eventDay != null && requestEventDay != null) {
      return eventDay == requestEventDay;
    }

    return matchesEventDate(event.eventDate);
  }
}

class DholMaintenanceEntry {
  final int id;
  final String dholNumber;
  final String workNotes;
  final String status;
  final int? maintainedBy;
  final String maintainedByName;
  final String maintainedByPhone;
  final int? approvedBy;
  final String approvedByName;
  final String approvedAt;
  final String approverNote;
  final String createdAt;
  final String updatedAt;

  const DholMaintenanceEntry({
    required this.id,
    required this.dholNumber,
    required this.workNotes,
    required this.status,
    required this.maintainedBy,
    required this.maintainedByName,
    required this.maintainedByPhone,
    required this.approvedBy,
    required this.approvedByName,
    required this.approvedAt,
    required this.approverNote,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DholMaintenanceEntry.fromJson(Map<String, dynamic> json) {
    return DholMaintenanceEntry(
      id: _toInt(json['id']) ?? 0,
      dholNumber: json['dhol_number']?.toString() ?? '',
      workNotes: json['work_notes']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      maintainedBy: _toInt(json['maintained_by']),
      maintainedByName: json['maintained_by_name']?.toString() ?? '',
      maintainedByPhone: json['maintained_by_phone']?.toString() ?? '',
      approvedBy: _toInt(json['approved_by']),
      approvedByName: json['approved_by_name']?.toString() ?? '',
      approvedAt: json['approved_at']?.toString() ?? '',
      approverNote: json['approver_note']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }
}

class MaintenanceAnalysisSummary {
  final int totalStockItems;
  final int totalAvailableUnits;
  final int pendingRequests;
  final int approvedRequests;
  final int rejectedRequests;
  final int pendingEntries;
  final int approvedEntries;
  final int rejectedEntries;
  final int lowStockItems;

  const MaintenanceAnalysisSummary({
    required this.totalStockItems,
    required this.totalAvailableUnits,
    required this.pendingRequests,
    required this.approvedRequests,
    required this.rejectedRequests,
    required this.pendingEntries,
    required this.approvedEntries,
    required this.rejectedEntries,
    required this.lowStockItems,
  });

  factory MaintenanceAnalysisSummary.fromJson(Map<String, dynamic> json) {
    return MaintenanceAnalysisSummary(
      totalStockItems: _toInt(json['total_stock_items']) ?? 0,
      totalAvailableUnits: _toInt(json['total_available_units']) ?? 0,
      pendingRequests: _toInt(json['pending_requests']) ?? 0,
      approvedRequests: _toInt(json['approved_requests']) ?? 0,
      rejectedRequests: _toInt(json['rejected_requests']) ?? 0,
      pendingEntries: _toInt(json['pending_entries']) ?? 0,
      approvedEntries: _toInt(json['approved_entries']) ?? 0,
      rejectedEntries: _toInt(json['rejected_entries']) ?? 0,
      lowStockItems: _toInt(json['low_stock_items']) ?? 0,
    );
  }
}

class MaintenanceAnalysisCategory {
  final String category;
  final String categoryDisplay;
  final int stockItems;
  final int availableUnits;
  final int pendingRequests;
  final int approvedRequests;
  final int lowStockItems;

  const MaintenanceAnalysisCategory({
    required this.category,
    required this.categoryDisplay,
    required this.stockItems,
    required this.availableUnits,
    required this.pendingRequests,
    required this.approvedRequests,
    required this.lowStockItems,
  });

  factory MaintenanceAnalysisCategory.fromJson(Map<String, dynamic> json) {
    return MaintenanceAnalysisCategory(
      category: json['category']?.toString() ?? '',
      categoryDisplay: json['category_display']?.toString() ?? '',
      stockItems: _toInt(json['stock_items']) ?? 0,
      availableUnits: _toInt(json['available_units']) ?? 0,
      pendingRequests: _toInt(json['pending_requests']) ?? 0,
      approvedRequests: _toInt(json['approved_requests']) ?? 0,
      lowStockItems: _toInt(json['low_stock_items']) ?? 0,
    );
  }
}

class MaintenanceAnalysisLowStockItem {
  final int inventoryItemId;
  final String name;
  final String category;
  final String categoryDisplay;
  final String otherCategoryName;
  final int quantityAvailable;
  final int threshold;

  const MaintenanceAnalysisLowStockItem({
    required this.inventoryItemId,
    required this.name,
    required this.category,
    required this.categoryDisplay,
    required this.otherCategoryName,
    required this.quantityAvailable,
    required this.threshold,
  });

  factory MaintenanceAnalysisLowStockItem.fromJson(Map<String, dynamic> json) {
    return MaintenanceAnalysisLowStockItem(
      inventoryItemId: _toInt(json['inventory_item_id']) ?? 0,
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      categoryDisplay: json['category_display']?.toString() ?? '',
      otherCategoryName: json['other_category_name']?.toString() ?? '',
      quantityAvailable: _toInt(json['quantity_available']) ?? 0,
      threshold: _toInt(json['threshold']) ?? 0,
    );
  }
}

class MaintenanceAnalysisRequestedItem {
  final int inventoryItemId;
  final String name;
  final String category;
  final int requestedQuantity;
  final int requestCount;

  const MaintenanceAnalysisRequestedItem({
    required this.inventoryItemId,
    required this.name,
    required this.category,
    required this.requestedQuantity,
    required this.requestCount,
  });

  factory MaintenanceAnalysisRequestedItem.fromJson(Map<String, dynamic> json) {
    return MaintenanceAnalysisRequestedItem(
      inventoryItemId: _toInt(json['inventory_item_id']) ?? 0,
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      requestedQuantity: _toInt(json['requested_quantity']) ?? 0,
      requestCount: _toInt(json['request_count']) ?? 0,
    );
  }
}

class MaintenanceAnalysis {
  final MaintenanceAnalysisSummary summary;
  final List<MaintenanceAnalysisCategory> categories;
  final List<MaintenanceAnalysisLowStockItem> lowStockAlerts;
  final List<MaintenanceAnalysisRequestedItem> topRequestedItems;

  const MaintenanceAnalysis({
    required this.summary,
    required this.categories,
    required this.lowStockAlerts,
    required this.topRequestedItems,
  });

  factory MaintenanceAnalysis.fromJson(Map<String, dynamic> json) {
    final categoriesJson = json['categories'];
    final lowStockJson = json['low_stock_alerts'];
    final topRequestedJson = json['top_requested_items'];

    return MaintenanceAnalysis(
      summary: MaintenanceAnalysisSummary.fromJson(
        Map<String, dynamic>.from(json['summary'] as Map? ?? const {}),
      ),
      categories: categoriesJson is List
          ? categoriesJson
                .whereType<Map>()
                .map(
                  (item) => MaintenanceAnalysisCategory.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : <MaintenanceAnalysisCategory>[],
      lowStockAlerts: lowStockJson is List
          ? lowStockJson
                .whereType<Map>()
                .map(
                  (item) => MaintenanceAnalysisLowStockItem.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : <MaintenanceAnalysisLowStockItem>[],
      topRequestedItems: topRequestedJson is List
          ? topRequestedJson
                .whereType<Map>()
                .map(
                  (item) => MaintenanceAnalysisRequestedItem.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : <MaintenanceAnalysisRequestedItem>[],
    );
  }
}

class MaintenanceEvent {
  final int id;
  final String title;
  final String description;
  final String eventDate;
  final String scope;
  final String scopeDisplay;
  final int? assignedGat;
  final String assignedGatName;
  final int? createdBy;
  final String createdByName;
  final String status;
  final String createdAt;
  final String updatedAt;
  final List<CompletionUsedItem> usedItems;

  const MaintenanceEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.eventDate,
    required this.scope,
    required this.scopeDisplay,
    required this.assignedGat,
    required this.assignedGatName,
    required this.createdBy,
    required this.createdByName,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.usedItems,
  });

  factory MaintenanceEvent.fromJson(Map<String, dynamic> json) {
    final usedItemsJson = json['used_items'];

    return MaintenanceEvent(
      id: _toInt(json['id']) ?? 0,
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      eventDate: json['event_date']?.toString() ?? '',
      scope: json['scope']?.toString() ?? '',
      scopeDisplay: json['scope_display']?.toString() ?? '',
      assignedGat: _toInt(json['assigned_gat']),
      assignedGatName: json['assigned_gat_name']?.toString() ?? '',
      createdBy: _toInt(json['created_by']),
      createdByName: json['created_by_name']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
      usedItems: usedItemsJson is List
          ? usedItemsJson
                .whereType<Map>()
                .map(
                  (item) => CompletionUsedItem.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : <CompletionUsedItem>[],
    );
  }

  MaintenanceEvent copyWith({
    int? id,
    String? title,
    String? description,
    String? eventDate,
    String? scope,
    String? scopeDisplay,
    int? assignedGat,
    String? assignedGatName,
    int? createdBy,
    String? createdByName,
    String? status,
    String? createdAt,
    String? updatedAt,
    List<CompletionUsedItem>? usedItems,
  }) {
    return MaintenanceEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      eventDate: eventDate ?? this.eventDate,
      scope: scope ?? this.scope,
      scopeDisplay: scopeDisplay ?? this.scopeDisplay,
      assignedGat: assignedGat ?? this.assignedGat,
      assignedGatName: assignedGatName ?? this.assignedGatName,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      usedItems: usedItems ?? this.usedItems,
    );
  }
}

extension MaintenanceEventDayState on MaintenanceEvent {
  DateTime? get parsedEventDate {
    final parsed = DateTime.tryParse(eventDate);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  bool get isActiveStatus => status.trim().toLowerCase() == 'active';

  bool get isScheduledForToday {
    final eventDay = parsedEventDate;
    if (eventDay == null) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return eventDay == today;
  }

  bool get shouldShowOnHome => isActiveStatus && isScheduledForToday;

  bool get isClosedForUserAction => !shouldShowOnHome;
}

class CompletionUsedItem {
  final int id;
  final int inventoryItem;
  final String inventoryItemName;
  final int quantityUsed;
  final String status;
  final int? quantityBeforeUpdate;
  final int? quantityAfterUpdate;

  const CompletionUsedItem({
    required this.id,
    required this.inventoryItem,
    required this.inventoryItemName,
    required this.quantityUsed,
    required this.status,
    required this.quantityBeforeUpdate,
    required this.quantityAfterUpdate,
  });

  factory CompletionUsedItem.fromJson(Map<String, dynamic> json) {
    return CompletionUsedItem(
      id: _toInt(json['id']) ?? 0,
      inventoryItem: _toInt(json['inventory_item']) ?? 0,
      inventoryItemName: json['inventory_item_name']?.toString() ?? '',
      quantityUsed: _toInt(json['quantity_used']) ?? 0,
      status: json['status']?.toString() ?? '',
      quantityBeforeUpdate: _toInt(json['quantity_before_update']),
      quantityAfterUpdate: _toInt(json['quantity_after_update']),
    );
  }

  String get normalizedDisplayStatus {
    final rawStatus = status.trim().toLowerCase();
    if (rawStatus == 'approved' || rawStatus == 'rejected') {
      return rawStatus;
    }

    // Completion submit uses approved stock requests only.
    // If backend sends pending/empty here, show approved in UI.
    return 'approved';
  }
}

class MaintenanceCompletionRequest {
  final int id;
  final int event;
  final String eventTitle;
  final String eventDate;
  final int? assignedGatId;
  final String? assignedGatName;
  final int? assignedGatPramukhId;
  final String? assignedGatPramukhName;
  final bool isActionableForCurrentUser;
  final int? submittedBy;
  final String submittedByName;
  final String? submitterGatPramukhName;
  final String workNotes;
  final String status;
  final int? approvedBy;
  final String approvedAt;
  final String approverNote;
  final String createdAt;
  final String updatedAt;
  final List<CompletionUsedItem> usedItems;

  const MaintenanceCompletionRequest({
    required this.id,
    required this.event,
    required this.eventTitle,
    required this.eventDate,
    required this.assignedGatId,
    required this.assignedGatName,
    required this.assignedGatPramukhId,
    required this.assignedGatPramukhName,
    required this.isActionableForCurrentUser,
    required this.submittedBy,
    required this.submittedByName,
    required this.submitterGatPramukhName,
    required this.workNotes,
    required this.status,
    required this.approvedBy,
    required this.approvedAt,
    required this.approverNote,
    required this.createdAt,
    required this.updatedAt,
    required this.usedItems,
  });

  factory MaintenanceCompletionRequest.fromJson(Map<String, dynamic> json) {
    final usedItemsJson = json['used_items'];
    return MaintenanceCompletionRequest(
      id: _toInt(json['id']) ?? 0,
      event: _toInt(json['event']) ?? 0,
      eventTitle: json['event_title']?.toString() ?? '',
      eventDate: json['event_date']?.toString() ?? '',
      assignedGatId: _toInt(json['assigned_gat_id']),
      assignedGatName: json['assigned_gat_name']?.toString(),
      assignedGatPramukhId: _toInt(json['assigned_gat_pramukh_id']),
      assignedGatPramukhName: json['assigned_gat_pramukh_name']?.toString(),
      isActionableForCurrentUser:
          json['is_actionable_for_current_user'] == true ||
          json['is_actionable_for_current_user']?.toString().toLowerCase() ==
              'true',
      submittedBy: _toInt(json['submitted_by']),
      submittedByName: json['submitted_by_name']?.toString() ?? '',
      submitterGatPramukhName: json['submitter_gat_pramukh_name']?.toString(),
      workNotes: json['work_notes']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      approvedBy: _toInt(json['approved_by']),
      approvedAt: json['approved_at']?.toString() ?? '',
      approverNote: json['approver_note']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
      usedItems: usedItemsJson is List
          ? usedItemsJson
                .whereType<Map>()
                .map(
                  (item) => CompletionUsedItem.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : <CompletionUsedItem>[],
    );
  }
}

int? _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
