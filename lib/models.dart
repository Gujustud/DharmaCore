// models.dart
// Model classes for PocketBase records

import 'dart:convert';

class Tool {
  final String id;
  final String toolName;
  final String category;
  final String? subcategory;
  final String? subSubcategory;
  final String? modelNumber;
  final String? url;  // NEW
  final String? manufacturerBarcode;
  final String? brandId;  // NEW - stores the brand ID
  final String? supplierId;  // NEW - stores the supplier ID
  final bool needsRestock; // Manual buy-list flag
  final int? restockQty; // Qty to buy (manual)
  final String? restockNotes; // Optional notes for purchasing
  final double? diameterIn;
  final double? diameterMm;
  final int? flutes;
  final double? fluteLength;
  final double? cornerRad;
  final double? neck;
  final String? size;
  final String? serialNumber;
  final String? photo;  // NEW
  final String? brand;  // Display name (from expand)
  final String? supplier;  // Display name (from expand)
  final dynamic record;  // NEW - stores the original PocketBase record

  Tool({
    required this.id,
    required this.toolName,
    required this.category,
    this.subcategory,
    this.subSubcategory,
    this.modelNumber,
    this.url,
    this.manufacturerBarcode,
    this.brandId,
    this.supplierId,
    this.needsRestock = false,
    this.restockQty,
    this.restockNotes,
    this.diameterIn,
    this.diameterMm,
    this.flutes,
    this.fluteLength,
    this.cornerRad,
    this.neck,
    this.size,
    this.serialNumber,
    this.photo,
    this.brand,
    this.supplier,
    this.record,
  });

  factory Tool.fromRecord(dynamic record) {
    // RecordModel has .id and .data properties
    final data = record.data;
    
    // Helper function to safely extract expanded relation data
    String? getExpandedName(String fieldName, String nameField) {
      try {
        if (record.expand == null) return null;
        final expandedData = record.expand[fieldName];
        if (expandedData == null) return null;
        
        // Handle both single object and array (Flutter web sometimes returns arrays)
        if (expandedData is List && expandedData.isNotEmpty) {
          return expandedData[0].data?[nameField];
        } else {
          return expandedData.data?[nameField];
        }
      } catch (e) {
        print('Error extracting $fieldName: $e');
        return null;
      }
    }
    
    return Tool(
      id: record.id,
      toolName: data['tool_name'] ?? '',
      category: data['category'] ?? '',
      subcategory: data['subcategory'],
      subSubcategory: data['sub_subcategory'],
      modelNumber: data['model_number'],
      url: data['url'],  // NEW
      manufacturerBarcode: data['manufacturer_barcode'],
      brandId: data['brand'],  // NEW
      supplierId: data['supplier'],  // NEW
      needsRestock: data['needs_restock'] == true,
      restockQty: (data['restock_qty'] != null) ? (data['restock_qty'] as num).toInt() : null,
      restockNotes: data['restock_notes'],
      diameterIn: data['diameter_in']?.toDouble(),
      diameterMm: data['diameter_mm']?.toDouble(),
      flutes: data['flutes']?.toInt(),
      fluteLength: data['flute_length']?.toDouble(),
      cornerRad: data['corner_rad']?.toDouble(),
      neck: data['neck']?.toDouble(),
      size: data['size'],
      serialNumber: data['serial_number'],
      photo: data['photo'],  // NEW
      brand: getExpandedName('brand', 'name'),  // FIXED - handles both array and object
      supplier: getExpandedName('supplier', 'company_name'),  // FIXED - handles both array and object
      record: record,  // NEW - store the original record
    );
  }

  // Helper method to get display specs
  String get displaySpecs {
    final parts = <String>[];
    
    if (diameterIn != null) {
      parts.add('Ø${diameterIn}"');
    }
    if (flutes != null) {
      parts.add('${flutes}FL');
    }
    if (fluteLength != null) {
      parts.add('LOC: $fluteLength"');
    }
    if (cornerRad != null && cornerRad! > 0) {
      parts.add('CR: ${cornerRad}"');
    }
    if (neck != null && neck! > 0) {
      parts.add('Neck: ${neck}"');
    }
    
    // Fallback to model number if no specs
    if (parts.isEmpty && modelNumber != null && modelNumber!.isNotEmpty) {
      return 'Model: $modelNumber';
    }
    
    return parts.join(' • ');
  }
}

class Location {
  final String id;
  final String name;
  final String type; // machine, shelf, toolbox, recycle
  final String? qrCode;
  final String? machine; // For locations linked to machines
  final String? parentId; // For hierarchical locations

  Location({
    required this.id,
    required this.name,
    required this.type,
    this.qrCode,
    this.machine,
    this.parentId,
  });

  factory Location.fromRecord(dynamic record) {
    // RecordModel has .id and .data properties
    final data = record.data;
    return Location(
      id: record.id,
      name: data['name'] ?? '',
      type: data['type'] ?? '',
      qrCode: data['qr_code'],
      machine: data['machine'],
      parentId: data['parent'],
    );
  }

  // Get color based on location type
  LocationColors get colors {
    switch (type.toLowerCase()) {
      case 'machine':
        return LocationColors.machine;
      case 'shelf':
        return LocationColors.shelf;
      case 'toolbox':
        return LocationColors.toolbox;
      case 'recycle':
        return LocationColors.recycle;
      default:
        return LocationColors.unknown;
    }
  }
}

class LocationColors {
  final int fillColor;
  final int borderColor;
  final int textColor;

  const LocationColors({
    required this.fillColor,
    required this.borderColor,
    required this.textColor,
  });

  static const machine = LocationColors(
    fillColor: 0xFFFF9800, // Orange
    borderColor: 0xFFE65100,
    textColor: 0xFFFFFFFF,
  );

  static const shelf = LocationColors(
    fillColor: 0xFF4CAF50, // Green
    borderColor: 0xFF2E7D32,
    textColor: 0xFFFFFFFF,
  );

  static const toolbox = LocationColors(
    fillColor: 0xFF2196F3, // Blue
    borderColor: 0xFF1565C0,
    textColor: 0xFFFFFFFF,
  );

  static const recycle = LocationColors(
    fillColor: 0xFFF44336, // Red
    borderColor: 0xFFC62828,
    textColor: 0xFFFFFFFF,
  );

  static const unknown = LocationColors(
    fillColor: 0xFF9E9E9E, // Grey
    borderColor: 0xFF616161,
    textColor: 0xFFFFFFFF,
  );
}

class ToolLocation {
  final String id;
  final String toolId;
  final String locationId;
  final int quantity;
  final String? qrCode;
  
  // Expanded fields (if expand is used in query)
  final Location? location;

  ToolLocation({
    required this.id,
    required this.toolId,
    required this.locationId,
    required this.quantity,
    this.qrCode,
    this.location,
  });

  factory ToolLocation.fromRecord(dynamic record) {
    // RecordModel has .id and .data properties
    final data = record.data;
    
    // Check if location is expanded
    Location? expandedLocation;
    try {
      if (record.expand != null && record.expand['location'] != null) {
        final locationData = record.expand['location'];
        // The expanded location might be an array or a single object
        if (locationData is List && locationData.isNotEmpty) {
          expandedLocation = Location.fromRecord(locationData[0]);
        } else {
          expandedLocation = Location.fromRecord(locationData);
        }
      }
    } catch (e) {
      print('⚠️ Error expanding location: $e');
    }

    return ToolLocation(
      id: record.id,
      toolId: data['tool'] ?? '',
      locationId: data['location'] ?? '',
      quantity: (data['quantity'] ?? 0).toInt(),
      qrCode: data['qr_code'],
      location: expandedLocation,
    );
  }
}

class ToolWithLocations {
  final Tool tool;
  final List<ToolLocation> locations;

  ToolWithLocations({
    required this.tool,
    required this.locations,
  });

  // Get total quantity across all locations
  int get totalQuantity {
    return locations.fold(0, (sum, loc) => sum + loc.quantity);
  }

  // Get locations sorted by type order (Toolboxes -> Shelves -> Machines -> Recycle)
  List<ToolLocation> get sortedLocations {
    final order = {'toolbox': 1, 'shelf': 2, 'machine': 3, 'recycle': 4};
    final sorted = List<ToolLocation>.from(locations);
    sorted.sort((a, b) {
      final aType = a.location?.type.toLowerCase() ?? '';
      final bType = b.location?.type.toLowerCase() ?? '';
      final aOrder = order[aType] ?? 5;
      final bOrder = order[bType] ?? 5;
      
      if (aOrder != bOrder) return aOrder.compareTo(bOrder);
      // If same type, sort by name
      return (a.location?.name ?? '').compareTo(b.location?.name ?? '');
    });
    return sorted;
  }
}

class ManualBuyItem {
  final String id;
  final String description;
  final int qty;
  final String? supplier;
  final String? notes;

  ManualBuyItem({
    required this.id,
    required this.description,
    required this.qty,
    this.supplier,
    this.notes,
  });

  factory ManualBuyItem.fromRecord(dynamic record) {
    final data = record.data;
    return ManualBuyItem(
      id: record.id as String,
      description: (data['description'] ?? '').toString(),
      qty: (data['qty'] ?? 1).toInt(),
      supplier: (data['supplier'] as String?)?.trim(),
      notes: (data['notes'] as String?)?.trim(),
    );
  }
}

// NEW: Inventory History Model
class InventoryHistory {
  final String id;
  final String toolId;
  final String locationId;
  final String action; // 'add', 'remove', 'transfer_in', 'transfer_out', 'edit'
  final int quantity;
  final int quantityBefore;
  final int quantityAfter;
  final String? relatedLocationId; // For transfers (destination or source)
  final String? notes;
  final double? toolLife; // Tool life in hours (optional)
  final DateTime created;
  
  // Expanded fields
  final Location? location;
  final Location? relatedLocation;

  InventoryHistory({
    required this.id,
    required this.toolId,
    required this.locationId,
    required this.action,
    required this.quantity,
    required this.quantityBefore,
    required this.quantityAfter,
    this.relatedLocationId,
    this.notes,
    this.toolLife,
    required this.created,
    this.location,
    this.relatedLocation,
  });

  factory InventoryHistory.fromRecord(dynamic record) {
    final data = record.data;
    
    // Parse location expansions
    Location? expandedLocation;
    Location? expandedRelatedLocation;
    
    try {
      if (record.expand != null) {
        if (record.expand['location'] != null) {
          final locationData = record.expand['location'];
          expandedLocation = locationData is List && locationData.isNotEmpty
              ? Location.fromRecord(locationData[0])
              : Location.fromRecord(locationData);
        }
        
        if (record.expand['related_location'] != null) {
          final relatedData = record.expand['related_location'];
          expandedRelatedLocation = relatedData is List && relatedData.isNotEmpty
              ? Location.fromRecord(relatedData[0])
              : Location.fromRecord(relatedData);
        }
      }
    } catch (e) {
      print('⚠️ Error expanding history locations: $e');
    }
    
    return InventoryHistory(
      id: record.id,
      toolId: data['tool'] ?? '',
      locationId: data['location'] ?? '',
      action: data['action'] ?? '',
      quantity: (data['quantity'] ?? 0).toInt(),
      quantityBefore: (data['quantity_before'] ?? 0).toInt(),
      quantityAfter: (data['quantity_after'] ?? 0).toInt(),
      relatedLocationId: data['related_location'],
      notes: data['notes'],
      toolLife: data['tool_life']?.toDouble(),
      created: DateTime.parse(data['created'] ?? record.created),
      location: expandedLocation,
      relatedLocation: expandedRelatedLocation,
    );
  }
  
  // Get a user-friendly description of the action
  String getActionDescription() {
    switch (action) {
      case 'add':
        return 'Added $quantity';
      case 'remove':
        return 'Removed $quantity';
      case 'transfer_out':
        return 'Transferred $quantity out';
      case 'transfer_in':
        return 'Transferred $quantity in';
      case 'edit':
        final diff = quantityAfter - quantityBefore;
        if (diff > 0) {
          return 'Increased by ${diff.abs()}';
        } else if (diff < 0) {
          return 'Decreased by ${diff.abs()}';
        } else {
          return 'Quantity unchanged';
        }
      default:
        return action;
    }
  }
  
  // Get icon for the action
  String getActionIcon() {
    switch (action) {
      case 'add':
        return '➕';
      case 'remove':
        return '➖';
      case 'transfer_out':
        return '📤';
      case 'transfer_in':
        return '📥';
      case 'edit':
        return '✏️';
      default:
        return '📝';
    }
  }
}

// Purchase tracking
class Purchase {
  final String id;
  final DateTime purchaseDate;
  final String? supplierId;
  final String? orderReference;
  /// Supplier invoice number (optional).
  final String? invoice;
  final String? notes;
  final double? total;
  final String? supplierName;
  /// Invoice currency: `CAD` (default) or `USD`. No FX conversion.
  final String currency;
  final List<String> attachmentNames;

  Purchase({
    required this.id,
    required this.purchaseDate,
    this.supplierId,
    this.orderReference,
    this.invoice,
    this.notes,
    this.total,
    this.supplierName,
    this.currency = 'CAD',
    this.attachmentNames = const [],
  });

  bool get isUsd => currency == 'USD';

  factory Purchase.fromRecord(dynamic record) {
    final data = record.data;
    String? supplierName;
    try {
      if (record.expand != null && record.expand['supplier'] != null) {
        final s = record.expand['supplier'];
        if (s is List && s.isNotEmpty) {
          supplierName = s[0].data?['company_name'];
        } else {
          supplierName = s.data?['company_name'];
        }
      }
    } catch (_) {}
    final rawCurrency = (data['currency'] ?? 'CAD').toString().trim().toUpperCase();
    return Purchase(
      id: record.id,
      purchaseDate: data['purchase_date'] != null
          ? DateTime.parse(data['purchase_date'].toString())
          : DateTime.parse(record.created),
      supplierId: data['supplier'],
      orderReference: data['order_reference'],
      invoice: data['invoice']?.toString(),
      notes: data['notes'],
      total: data['total']?.toDouble(),
      supplierName: supplierName,
      currency: rawCurrency == 'USD' ? 'USD' : 'CAD',
      attachmentNames: _fileNamesFrom(data['attachments']),
    );
  }
}

/// Shop material catalog entry (grade + form + size). Named to avoid Flutter [Material].
class ShopMaterial {
  final String id;
  final String grade;
  final String form;
  final String sizeLabel;
  final String unit;
  final String? notes;

  ShopMaterial({
    required this.id,
    required this.grade,
    required this.form,
    required this.sizeLabel,
    this.unit = 'ea',
    this.notes,
  });

  String get displayLabel {
    final g = grade.trim();
    final f = form.trim();
    final s = sizeLabel.trim();
    return '$g · $f · $s';
  }

  factory ShopMaterial.fromRecord(dynamic record) {
    final data = record.data as Map<String, dynamic>? ?? {};
    return ShopMaterial(
      id: record.id,
      grade: (data['grade'] ?? '').toString(),
      form: (data['form'] ?? 'other').toString(),
      sizeLabel: (data['size_label'] ?? '').toString(),
      unit: (data['unit'] ?? 'ea').toString(),
      notes: data['notes']?.toString(),
    );
  }
}

class PurchaseItem {
  final String id;
  final String purchaseId;
  final String? toolId; // null for tax/shipping/material lines
  final String? materialId;
  final num quantity;
  final double? unitCost;
  final String? toolName;
  final String? materialLabel;
  final String lineType; // 'item' | 'material' | 'misc' | 'tax' | 'shipping'
  final String? description; // e.g. 'GST', 'PST', 'Shipping', misc text
  final String? heatLot;
  /// Mill cert filenames on this line (`purchase_items.mill_certs`).
  final List<String> millCertNames;

  PurchaseItem({
    required this.id,
    required this.purchaseId,
    this.toolId,
    this.materialId,
    required this.quantity,
    this.unitCost,
    this.toolName,
    this.materialLabel,
    this.lineType = 'item',
    this.description,
    this.heatLot,
    this.millCertNames = const [],
  });

  factory PurchaseItem.fromRecord(dynamic record) {
    final data = record.data;
    String? toolName;
    try {
      if (record.expand != null && record.expand['tool'] != null) {
        final t = record.expand['tool'];
        String? name;
        String? model;
        if (t is List && t.isNotEmpty) {
          name = t[0].data?['tool_name']?.toString();
          model = t[0].data?['model_number']?.toString();
        } else {
          name = t.data?['tool_name']?.toString();
          model = t.data?['model_number']?.toString();
        }
        if (name != null && name.isNotEmpty) {
          final hasModel = model != null && model.trim().isNotEmpty;
          toolName = hasModel ? '$name (${model.trim()})' : name;
        }
      }
    } catch (_) {}

    String? materialLabel;
    try {
      if (record.expand != null && record.expand['material'] != null) {
        final m = record.expand['material'];
        final raw = (m is List && m.isNotEmpty) ? m[0] : m;
        materialLabel = ShopMaterial.fromRecord(raw).displayLabel;
      }
    } catch (_) {}

    final qtyRaw = data['quantity'];
    final quantity = qtyRaw is num
        ? qtyRaw
        : num.tryParse('$qtyRaw') ?? 0;

    return PurchaseItem(
      id: record.id,
      purchaseId: data['purchase'] ?? '',
      toolId: _relationIdFromData(data['tool']) ??
          _relationIdFromExpand(record.expand?['tool']),
      materialId: _relationIdFromData(data['material']) ??
          _relationIdFromExpand(record.expand?['material']),
      quantity: quantity,
      unitCost: data['unit_cost']?.toDouble(),
      toolName: toolName,
      materialLabel: materialLabel,
      lineType: data['line_type'] ?? 'item',
      description: data['description'],
      heatLot: data['heat_lot']?.toString(),
      millCertNames: _fileNamesFrom(data['mill_certs']),
    );
  }

  bool get isItem => lineType == 'item';
  bool get isMaterial => lineType == 'material';
  bool get isTax => lineType == 'tax';
  bool get isShipping => lineType == 'shipping';
}

List<String> _fileNamesFrom(dynamic v) {
  if (v is List) {
    return v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }
  if (v == null) return [];
  final s = v.toString();
  return s.isEmpty ? [] : [s];
}

String? _relationIdFromData(dynamic v) {
  if (v == null) return null;
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty || s == 'null') return null;
    return s;
  }
  if (v is Map) {
    final id = v['id']?.toString().trim();
    if (id != null && id.isNotEmpty && id != 'null') return id;
  }
  try {
    final id = (v as dynamic).id?.toString().trim();
    if (id != null && id.isNotEmpty && id != 'null') return id;
  } catch (_) {}
  final s = v.toString().trim();
  if (s.isEmpty || s == 'null' || s.startsWith('Instance of')) return null;
  return s;
}

String? _relationIdFromExpand(dynamic expanded) {
  if (expanded == null) return null;
  final raw = (expanded is List && expanded.isNotEmpty) ? expanded[0] : expanded;
  return _relationIdFromData(raw);
}

/// Pending email-ingest purchase draft (review queue).
class PurchaseDraft {
  final String id;
  final DateTime? purchaseDate;
  final String? supplierId;
  final String? supplierName;
  final String? vendorKey;
  final String? vendorName;
  final String? orderReference;
  final String? invoice;
  final String? notes;
  final String? tracking;
  final double? total;
  final String currency;
  final String status; // pending|approved|rejected
  final String? parseNotes;
  final List<String> attachmentNames;

  PurchaseDraft({
    required this.id,
    this.purchaseDate,
    this.supplierId,
    this.supplierName,
    this.vendorKey,
    this.vendorName,
    this.orderReference,
    this.invoice,
    this.notes,
    this.tracking,
    this.total,
    this.currency = 'USD',
    this.status = 'pending',
    this.parseNotes,
    this.attachmentNames = const [],
  });

  bool get isPending => status == 'pending';

  String get displayVendor {
    final n = vendorName?.trim();
    if (n != null && n.isNotEmpty) return n;
    final k = vendorKey?.trim();
    if (k == null || k.isEmpty) return 'Email';
    if (k == 'mcmaster') return 'McMaster-Carr';
    if (k == 'dgi_supply') return 'DGI Supply';
    return k;
  }

  factory PurchaseDraft.fromRecord(dynamic record) {
    final data = record.data as Map<String, dynamic>? ?? {};
    String? supplierName;
    String? vendorName;
    try {
      if (record.expand != null) {
        if (record.expand['supplier'] != null) {
          final s = record.expand['supplier'];
          final raw = (s is List && s.isNotEmpty) ? s[0] : s;
          supplierName = raw.data?['company_name']?.toString();
        }
        if (record.expand['email_ingest_vendor'] != null) {
          final v = record.expand['email_ingest_vendor'];
          final raw = (v is List && v.isNotEmpty) ? v[0] : v;
          vendorName = raw.data?['name']?.toString();
        }
      }
    } catch (_) {}
    final rawCurrency = (data['currency'] ?? 'USD').toString().trim().toUpperCase();
    DateTime? purchaseDate;
    final pd = data['purchase_date'];
    if (pd != null) {
      purchaseDate = DateTime.tryParse(pd.toString());
    }
    return PurchaseDraft(
      id: record.id as String,
      purchaseDate: purchaseDate,
      supplierId: data['supplier']?.toString(),
      supplierName: supplierName,
      vendorKey: data['vendor_key']?.toString(),
      vendorName: vendorName,
      orderReference: data['order_reference']?.toString(),
      invoice: data['invoice']?.toString(),
      notes: data['notes']?.toString(),
      tracking: data['tracking']?.toString(),
      total: (data['total'] as num?)?.toDouble(),
      currency: rawCurrency == 'CAD' ? 'CAD' : 'USD',
      status: (data['status'] ?? 'pending').toString(),
      parseNotes: data['parse_notes']?.toString(),
      attachmentNames: _fileNamesFrom(data['attachments']),
    );
  }
}

class PurchaseDraftLine {
  final String id;
  final String draftId;
  final String lineType;
  final String? description;
  final String? partNumber;
  final num quantity;
  final double? unitCost;
  final String? heatLot;
  final String matchStatus;
  final String? matchedMaterialId;
  final String? matchedMaterialLabel;
  final String? matchedToolId;
  final String? matchedToolLabel;
  final String? materialProposalId;
  final Map<String, dynamic>? proposedMaterial;
  final List<String> candidateMaterialIds;
  final int sortOrder;
  /// Mill cert filenames on this draft line (`purchase_draft_lines.mill_certs`).
  final List<String> millCertNames;

  PurchaseDraftLine({
    required this.id,
    required this.draftId,
    required this.lineType,
    this.description,
    this.partNumber,
    required this.quantity,
    this.unitCost,
    this.heatLot,
    this.matchStatus = 'n_a',
    this.matchedMaterialId,
    this.matchedMaterialLabel,
    this.matchedToolId,
    this.matchedToolLabel,
    this.materialProposalId,
    this.proposedMaterial,
    this.candidateMaterialIds = const [],
    this.sortOrder = 0,
    this.millCertNames = const [],
  });

  factory PurchaseDraftLine.fromRecord(dynamic record) {
    final data = record.data as Map<String, dynamic>? ?? {};
    String? materialLabel;
    String? toolLabel;
    try {
      if (record.expand != null && record.expand['matched_material'] != null) {
        final m = record.expand['matched_material'];
        final raw = (m is List && m.isNotEmpty) ? m[0] : m;
        materialLabel = ShopMaterial.fromRecord(raw).displayLabel;
      }
    } catch (_) {}
    try {
      if (record.expand != null && record.expand['matched_tool'] != null) {
        final t = record.expand['matched_tool'];
        final raw = (t is List && t.isNotEmpty) ? t[0] : t;
        final tool = Tool.fromRecord(raw);
        final model = (tool.modelNumber ?? '').trim();
        toolLabel = model.isEmpty
            ? tool.toolName
            : '${tool.toolName} ($model)';
      }
    } catch (_) {}

    Map<String, dynamic>? proposed;
    final rawProp = data['proposed_material_json']?.toString();
    if (rawProp != null && rawProp.isNotEmpty) {
      try {
        // PocketBase stores JSON as text; decode lazily via dart:convert in callers if needed.
        proposed = _tryDecodeJsonMap(rawProp);
      } catch (_) {}
    }

    final candidates = <String>[];
    final rawCand = data['candidate_material_ids']?.toString() ?? '';
    if (rawCand.isNotEmpty) {
      candidates.addAll(
        rawCand.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty),
      );
    }

    final qtyRaw = data['quantity'];
    final quantity = qtyRaw is num ? qtyRaw : num.tryParse('$qtyRaw') ?? 0;

    return PurchaseDraftLine(
      id: record.id as String,
      draftId: data['draft']?.toString() ?? '',
      lineType: (data['line_type'] ?? 'misc').toString(),
      description: data['description']?.toString(),
      partNumber: data['part_number']?.toString(),
      quantity: quantity,
      unitCost: (data['unit_cost'] as num?)?.toDouble(),
      heatLot: data['heat_lot']?.toString(),
      matchStatus: (data['match_status'] ?? 'n_a').toString(),
      matchedMaterialId: _relationIdFromData(data['matched_material']),
      matchedMaterialLabel: materialLabel,
      matchedToolId: _relationIdFromData(data['matched_tool']) ??
          _relationIdFromExpand(record.expand?['matched_tool']),
      matchedToolLabel: toolLabel,
      materialProposalId: data['material_proposal']?.toString(),
      proposedMaterial: proposed,
      candidateMaterialIds: candidates,
      sortOrder: (data['sort_order'] as num?)?.toInt() ?? 0,
      millCertNames: _fileNamesFrom(data['mill_certs']),
    );
  }
}

class EmailIngestVendor {
  final String id;
  final String name;
  final String vendorKey;
  final String? supplierId;
  final String? supplierName;
  final String fromDomains;
  final String defaultCurrency;
  final String defaultLineKind;
  final bool enabled;
  final String adapterStatus;
  final String? notes;

  EmailIngestVendor({
    required this.id,
    required this.name,
    required this.vendorKey,
    this.supplierId,
    this.supplierName,
    required this.fromDomains,
    this.defaultCurrency = 'USD',
    this.defaultLineKind = 'auto',
    this.enabled = false,
    this.adapterStatus = 'stub',
    this.notes,
  });

  factory EmailIngestVendor.fromRecord(dynamic record) {
    final data = record.data as Map<String, dynamic>? ?? {};
    String? supplierName;
    try {
      if (record.expand != null && record.expand['supplier'] != null) {
        final s = record.expand['supplier'];
        final raw = (s is List && s.isNotEmpty) ? s[0] : s;
        supplierName = raw.data?['company_name']?.toString();
      }
    } catch (_) {}
    return EmailIngestVendor(
      id: record.id as String,
      name: (data['name'] ?? '').toString(),
      vendorKey: (data['vendor_key'] ?? '').toString(),
      supplierId: data['supplier']?.toString(),
      supplierName: supplierName,
      fromDomains: (data['from_domains'] ?? '').toString(),
      defaultCurrency: (data['default_currency'] ?? 'USD').toString(),
      defaultLineKind: (data['default_line_kind'] ?? 'auto').toString(),
      enabled: data['enabled'] == true,
      adapterStatus: (data['adapter_status'] ?? 'stub').toString(),
      notes: data['notes']?.toString(),
    );
  }
}

Map<String, dynamic>? _tryDecodeJsonMap(String raw) {
  try {
    final dynamic decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
  } catch (_) {}
  return null;
}
