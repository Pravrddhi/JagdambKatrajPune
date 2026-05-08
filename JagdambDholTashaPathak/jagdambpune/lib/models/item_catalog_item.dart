class ItemCatalogItem {
  final int id;
  final String name;
  final String itemType;
  final String? itemTypeDisplay;
  final String? description;
  final String? catalogCost;
  final bool canUserRequest;
  final bool requiresSize;
  final bool isActive;

  const ItemCatalogItem({
    required this.id,
    required this.name,
    required this.itemType,
    this.itemTypeDisplay,
    this.description,
    this.catalogCost,
    this.canUserRequest = false,
    this.requiresSize = false,
    this.isActive = true,
  });

  factory ItemCatalogItem.fromJson(Map<String, dynamic> json) {
    return ItemCatalogItem(
      id: json['id'] as int,
      name: json['name']?.toString() ?? '',
      itemType: json['item_type']?.toString() ?? '',
      itemTypeDisplay: json['item_type_display']?.toString(),
      description: json['description']?.toString(),
      catalogCost: json['catalog_cost']?.toString(),
      canUserRequest: json['can_user_request'] == true,
      requiresSize: json['requires_size'] == true,
      isActive: json['is_active'] != false,
    );
  }

  static List<ItemCatalogItem> listFromJson(List<dynamic> list) {
    return list
        .whereType<Map<String, dynamic>>()
        .map(ItemCatalogItem.fromJson)
        .toList();
  }
}
