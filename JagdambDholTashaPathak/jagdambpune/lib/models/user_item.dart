class UserItem {
  final int id;
  final int? userId;
  final String? userName;
  final int? pathak;
  final int? catalogItem;
  final String? catalogItemName;
  final String itemName;
  final String itemType;
  final String? itemTypeDisplay;
  final String? size;
  final String? sizeDisplay;
  final int? instrumentId;
  final String? instrumentName;
  final String paymentStatus;
  final String? paymentStatusDisplay;
  final String? paymentAmount;
  final String? paymentDate;
  final String? issuedDate;
  final String? returnDate;
  final bool isReturned;
  final String? notes;
  final String? initiatedBy;
  final String? initiatedByDisplay;
  final String status;
  final String? statusDisplay;
  final String? statusNote;
  final int? approvedBy;
  final String? approvedByName;
  final String? approvedAt;
  final String? userConfirmedAt;
  final int? createdBy;
  final String? createdAt;
  final String? updatedAt;

  const UserItem({
    required this.id,
    this.userId,
    this.userName,
    this.pathak,
    this.catalogItem,
    this.catalogItemName,
    required this.itemName,
    required this.itemType,
    this.itemTypeDisplay,
    this.size,
    this.sizeDisplay,
    this.instrumentId,
    this.instrumentName,
    required this.paymentStatus,
    this.paymentStatusDisplay,
    this.paymentAmount,
    this.paymentDate,
    this.issuedDate,
    this.returnDate,
    this.isReturned = false,
    this.notes,
    this.initiatedBy,
    this.initiatedByDisplay,
    required this.status,
    this.statusDisplay,
    this.statusNote,
    this.approvedBy,
    this.approvedByName,
    this.approvedAt,
    this.userConfirmedAt,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  factory UserItem.fromJson(Map<String, dynamic> json) {
    return UserItem(
      id: _asInt(json['id']) ?? 0,
      userId: _asInt(json['user']),
      userName: json['user_name']?.toString(),
      pathak: _asInt(json['pathak']),
      catalogItem: _asInt(json['catalog_item']),
      catalogItemName: json['catalog_item_name']?.toString(),
      itemName:
          json['item_name']?.toString() ??
          json['catalog_item_name']?.toString() ??
          '',
      itemType: json['item_type']?.toString() ?? '',
      itemTypeDisplay: json['item_type_display']?.toString(),
      size: json['size']?.toString(),
      sizeDisplay: json['size_display']?.toString(),
      instrumentId: _asInt(json['instrument']),
      instrumentName: json['instrument_name']?.toString(),
      paymentStatus: json['payment_status']?.toString() ?? '',
      paymentStatusDisplay: json['payment_status_display']?.toString(),
      paymentAmount: json['payment_amount']?.toString(),
      paymentDate: json['payment_date']?.toString(),
      issuedDate: json['issued_date']?.toString(),
      returnDate: json['return_date']?.toString(),
      isReturned: json['is_returned'] == true,
      notes: json['notes']?.toString(),
      initiatedBy: json['initiated_by']?.toString(),
      initiatedByDisplay: json['initiated_by_display']?.toString(),
      status: json['status']?.toString() ?? '',
      statusDisplay: json['status_display']?.toString(),
      statusNote: json['status_note']?.toString(),
      approvedBy: _asInt(json['approved_by']),
      approvedByName: json['approved_by_name']?.toString(),
      approvedAt: json['approved_at']?.toString(),
      userConfirmedAt: json['user_confirmed_at']?.toString(),
      createdBy: _asInt(json['created_by']),
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
    );
  }

  static List<UserItem> listFromJson(List<dynamic> list) =>
      list.whereType<Map<String, dynamic>>().map(UserItem.fromJson).toList();
}
