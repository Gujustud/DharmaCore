import 'package:pocketbase/pocketbase.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'app_config.dart';
import 'http_client_factory.dart';
import 'models.dart';

class PocketBaseService {
  static const _authPrefsKey = 'pb_auth';

  static final PocketBaseService _instance = PocketBaseService._internal();
  static Future<void>? _initFuture;

  PocketBase? _pb;

  factory PocketBaseService() {
    return _instance;
  }

  PocketBaseService._internal();

  /// PocketBase client. Call [init] from [main] before first use.
  PocketBase get pb {
    final client = _pb;
    if (client == null) {
      throw StateError('PocketBaseService.init() must be awaited before use');
    }
    return client;
  }

  /// Loads persisted auth (survives hard refresh) then creates the client.
  static Future<void> get init {
    return _initFuture ??= _instance._doInit();
  }

  Future<void> _doInit() async {
    final prefs = await SharedPreferences.getInstance();
    final authStore = AsyncAuthStore(
      save: (String data) async {
        await prefs.setString(_authPrefsKey, data);
      },
      initial: prefs.getString(_authPrefsKey),
      clear: () async {
        await prefs.remove(_authPrefsKey);
      },
    );

    final baseUrl = AppConfig.pocketBaseUrl;
    _pb = PocketBase(
      baseUrl,
      authStore: authStore,
      httpClientFactory: baseUrl.startsWith('https')
          ? () => HttpClientFactory.getHttpClient()
          : null,
      reuseHTTPClient: true,
    );
  }

  // Save a new tool
  Future<void> createTool({
    required String toolName,
    required String category,
    String? subcategory,
    String? subSubcategory,
    String? modelNumber,
    double? diameterIn,
    double? diameterMm,
    int? flutes,
    double? fluteLength,
    double? cornerRad,
    double? neck,
  }) async {
    try {
      final record = await pb.collection('inventory').create(body: {
        'tool_name': toolName,
        'category': category,
        'subcategory': subcategory,
        'sub_subcategory': subSubcategory,
        'model_number': modelNumber,
        'diameter_in': diameterIn,
        'diameter_mm': diameterMm,
        'flutes': flutes,
        'flute_length': fluteLength,
        'corner_rad': cornerRad,
        'neck': neck,
      });
      print('Tool created: ${record.id}');
    } catch (e) {
      print('Error creating tool: $e');
      rethrow;
    }
  }

  // Get all tools
  Future<List<dynamic>> getTools() async {
    try {
      final records = await pb.collection('inventory').getFullList(
        expand: 'brand,supplier',
      );
      return records;
    } catch (e) {
      print('Error getting tools: $e');
      rethrow;
    }
  }

  Future<List<ManualBuyItem>> getManualBuyItems() async {
    try {
      final records = await pb.collection('buy_list_manual').getFullList(
        sort: 'description',
      );
      return records.map((r) => ManualBuyItem.fromRecord(r)).toList();
    } catch (e) {
      print('Error getting manual buy list items: $e');
      rethrow;
    }
  }

  Future<void> createManualBuyItem({
    required String description,
    int qty = 1,
    String? supplier,
    String? notes,
  }) async {
    await pb.collection('buy_list_manual').create(body: {
      'description': description,
      'qty': qty,
      'supplier': supplier,
      'notes': notes,
    });
  }

  Future<void> updateManualBuyItem({
    required String id,
    required String description,
    required int qty,
    String? supplier,
    String? notes,
  }) async {
    await pb.collection('buy_list_manual').update(id, body: {
      'description': description,
      'qty': qty,
      'supplier': supplier,
      'notes': notes,
    });
  }

  Future<void> deleteManualBuyItem(String id) async {
    await pb.collection('buy_list_manual').delete(id);
  }

  // Create a new location
  Future<void> createLocation({
    required String name,
    required String type,
    String? parentId,
  }) async {
    try {
      final record = await pb.collection('locations').create(body: {
        'name': name,
        'type': type,
        'parent': parentId,
      });
      print('Location created: ${record.id}');
    } catch (e) {
      print('Error creating location: $e');
      rethrow;
    }
  }

  // Get all locations
  Future<List<dynamic>> getLocations() async {
    try {
      final records = await pb.collection('locations').getFullList(
        sort: 'name',
      );
      return records;
    } catch (e) {
      print('Error getting locations: $e');
      rethrow;
    }
  }

  // Update a location
  Future<void> updateLocation({
    required String locationId,
    required String name,
    required String type,
    String? parentId,
  }) async {
    try {
      await pb.collection('locations').update(locationId, body: {
        'name': name,
        'type': type,
        if (parentId != null) 'parent': parentId,
      });
      print('Location updated: $locationId');
    } catch (e) {
      print('Error updating location: $e');
      rethrow;
    }
  }

  // Delete a location
  Future<void> deleteLocation(String locationId) async {
    try {
      await pb.collection('locations').delete(locationId);
      print('Location deleted: $locationId');
    } catch (e) {
      print('Error deleting location: $e');
      rethrow;
    }
  }

  // Get tool locations for a specific tool
  Future<List<dynamic>> getToolLocations(String toolId) async {
    try {
      final records = await pb.collection('tool_locations').getFullList(
        filter: 'tool = "$toolId"',
        expand: 'location',
      );
      return records;
    } catch (e) {
      print('Error getting tool locations: $e');
      rethrow;
    }
  }

  /// Get all tool_locations in one request (expanded location).
  Future<List<dynamic>> getAllToolLocations() async {
    try {
      final records = await pb.collection('tool_locations').getFullList(
        expand: 'location',
      );
      return records;
    } catch (e) {
      print('Error getting all tool locations: $e');
      rethrow;
    }
  }

  // Get tool locations at a specific location (includes 0-qty so "home bin" stays visible)
  Future<List<dynamic>> getToolLocationsAtLocation(String locationId) async {
    try {
      final records = await pb.collection('tool_locations').getFullList(
        filter: 'location = "$locationId"',
      );
      return records;
    } catch (e) {
      print('Error getting tool locations: $e');
      rethrow;
    }
  }

  /// Tool locations at [locationId] with tool expanded (includes 0-qty for "home bin").
  Future<List<dynamic>> getToolLocationsAtLocationWithTool(String locationId) async {
    try {
      final records = await pb.collection('tool_locations').getFullList(
        filter: 'location = "$locationId"',
        expand: 'tool',
      );
      return records;
    } catch (e) {
      print('Error getting tool locations at location: $e');
      rethrow;
    }
  }

  /// Removes all tool_location records at [locationId] so the location can be deleted.
  /// History (inventory_history) is unchanged; past moves may show "Unknown location".
  Future<void> deleteToolLocationsAtLocation(String locationId) async {
    try {
      final records = await pb.collection('tool_locations').getFullList(
        filter: 'location = "$locationId"',
      );
      for (final r in records) {
        await pb.collection('tool_locations').delete(r.id);
      }
    } catch (e) {
      print('Error deleting tool locations at location: $e');
      rethrow;
    }
  }

  // Get tool by ID
  Future<dynamic> getToolById(String toolId) async {
    try {
      final record = await pb.collection('inventory').getOne(
        toolId,
        expand: 'brand,supplier',
      );
      return record;
    } catch (e) {
      print('Error getting tool: $e');
      rethrow;
    }
  }

  // Move tool between locations
  Future<void> moveTool({
    required String toolId,
    required String fromLocationId,
    required String toLocationId,
    required int quantity,
  }) async {
    try {
      // Get current tool_location records
      final fromRecords = await pb.collection('tool_locations').getFullList(
        filter: 'tool = "$toolId" && location = "$fromLocationId"',
      );

      if (fromRecords.isEmpty) {
        throw Exception('Tool not found at source location');
      }

      final fromRecord = fromRecords.first;
      final currentQty = fromRecord.data['quantity'] as int;

      if (currentQty < quantity) {
        throw Exception('Not enough quantity at source location');
      }

      // Get destination quantity before transfer
      final destQtyBefore = await getCurrentQuantityAtLocation(
        toolId: toolId,
        locationId: toLocationId,
      );

      // Update source location (reduce quantity; keep record at 0 as "home" bin)
      final newSourceQty = currentQty - quantity;
      await pb.collection('tool_locations').update(
        fromRecord.id,
        body: {'quantity': newSourceQty},
      );

      // Update or create destination location
      final toRecords = await pb.collection('tool_locations').getFullList(
        filter: 'tool = "$toolId" && location = "$toLocationId"',
      );

      if (toRecords.isEmpty) {
        // Create new record
        await pb.collection('tool_locations').create(body: {
          'tool': toolId,
          'location': toLocationId,
          'quantity': quantity,
        });
      } else {
        // Update existing record
        final toRecord = toRecords.first;
        final existingQty = toRecord.data['quantity'] as int;
        await pb.collection('tool_locations').update(
          toRecord.id,
          body: {'quantity': existingQty + quantity},
        );
      }

      // Create OLD movement history record (keep for backwards compatibility)
      await pb.collection('movement_history').create(body: {
        'tool': toolId,
        'from_location': fromLocationId,
        'to_location': toLocationId,
        'quantity': quantity,
      });

      // NEW: Log to inventory_history (transfer_out from source)
      await logInventoryHistory(
        toolId: toolId,
        locationId: fromLocationId,
        action: 'transfer_out',
        quantity: quantity,
        quantityBefore: currentQty,
        quantityAfter: newSourceQty,
        relatedLocationId: toLocationId,
      );

      // NEW: Log to inventory_history (transfer_in at destination)
      await logInventoryHistory(
        toolId: toolId,
        locationId: toLocationId,
        action: 'transfer_in',
        quantity: quantity,
        quantityBefore: destQtyBefore,
        quantityAfter: destQtyBefore + quantity,
        relatedLocationId: fromLocationId,
      );

      print('Tool moved successfully');
    } catch (e) {
      print('Error moving tool: $e');
      rethrow;
    }
  }

  // Create tool_location record
  Future<void> createToolLocation({
    required String toolId,
    required String locationId,
    required int quantity,
  }) async {
    try {
      final record = await pb.collection('tool_locations').create(body: {
        'tool': toolId,
        'location': locationId,
        'quantity': quantity,
      });
      print('Tool location created: ${record.id}');
    } catch (e) {
      print('Error creating tool location: $e');
      rethrow;
    }
  }

  // Get location path (for display)
  String getLocationPath(String locationId, List<dynamic> allLocations) {
    dynamic location;
    try {
      location = allLocations.firstWhere(
        (loc) => loc.id == locationId,
      );
    } catch (e) {
      return 'Unknown';
    }
    
    final parts = <String>[];
    var current = location;
    
    while (current != null) {
      parts.insert(0, current.data['name']);
      final parentId = current.data['parent'];
      if (parentId == null || parentId == '') break;
      
      try {
        current = allLocations.firstWhere(
          (loc) => loc.id == parentId,
        );
      } catch (e) {
        break;
      }
    }
    
    return parts.join(' - ');
  }

  // Brand management
  Future<List<dynamic>> getBrands({String? categoryId}) async {
    try {
      List<dynamic> records;
      if (categoryId != null) {
        print('DEBUG getBrands: Filtering by categoryId = $categoryId');
        records = await pb.collection('brands').getFullList(sort: 'name');
        print('DEBUG getBrands: Loaded ${records.length} total brands');
        
        // Filter: show brands with no categories OR brands that include this category
        records = records.where((brand) {
          final categories = brand.data['categories'];
          final brandName = brand.data['name'];
          print('DEBUG getBrands: Brand "$brandName" has categories = $categories (type: ${categories?.runtimeType})');
          
          // If no categories assigned, show for all (backward compatible)
          if (categories == null || categories == '' || (categories is List && categories.isEmpty)) {
            print('DEBUG getBrands: Brand "$brandName" has no categories - showing for all');
            return true;
          }
          
          // Check if this category is in the list
          if (categories is List) {
            final matches = categories.any((c) {
              String? catId;
              if (c is String) {
                catId = c;
              } else if (c is Map && c['id'] != null) {
                catId = c['id'];
              } else {
                catId = c.toString();
              }
              return catId == categoryId;
            });
            print('DEBUG getBrands: Brand "$brandName" ${matches ? "MATCHES" : "does NOT match"} category $categoryId');
            return matches;
          }
          
          // Handle single value (shouldn't happen with multiple relation, but just in case)
          if (categories is Map && categories['id'] != null) {
            final matches = categories['id'] == categoryId;
            print('DEBUG getBrands: Brand "$brandName" (single value) ${matches ? "MATCHES" : "does NOT match"}');
            return matches;
          }
          
          final matches = categories.toString() == categoryId;
          print('DEBUG getBrands: Brand "$brandName" (string) ${matches ? "MATCHES" : "does NOT match"}');
          return matches;
        }).toList();
        
        print('DEBUG getBrands: After filtering, ${records.length} brands match category $categoryId');
      } else {
        records = await pb.collection('brands').getFullList(sort: 'name');
      }
      return records;
    } catch (e) {
      print('Error getting brands: $e');
      rethrow;
    }
  }

  Future<void> createBrand(
    String name, {
    List<String>? categoryIds,
    String? urlPattern,
    bool? scraperEnabled,
    String? scraperNotes,
    String? defaultSupplierId,
  }) async {
    try {
      final body = <String, dynamic>{'name': name};
      if (categoryIds != null && categoryIds.isNotEmpty) {
        body['categories'] = categoryIds;
      }
      if (defaultSupplierId != null && defaultSupplierId.isNotEmpty) {
        body['default_supplier'] = defaultSupplierId;
      }
      // Add scraping fields if provided
      if (urlPattern != null && urlPattern.isNotEmpty) {
        body['url_pattern'] = urlPattern;
      }
      if (scraperEnabled != null) {
        body['scraper_enabled'] = scraperEnabled;
      }
      if (scraperNotes != null && scraperNotes.isNotEmpty) {
        body['scraper_notes'] = scraperNotes;
      }
      await pb.collection('brands').create(body: body);
    } catch (e) {
      print('Error creating brand: $e');
      rethrow;
    }
  }

  Future<void> updateBrand(
    String id,
    String name, {
    List<String>? categoryIds,
    String? urlPattern,
    bool? scraperEnabled,
    String? scraperNotes,
    String? defaultSupplierId,
  }) async {
    try {
      final body = <String, dynamic>{'name': name};
      // Always set categories, even if empty (to clear existing ones)
      if (categoryIds != null) {
        body['categories'] = categoryIds;
      } else {
        // If null, set to empty array to clear all categories
        body['categories'] = [];
      }
      // Always set default_supplier (can be null/empty to clear)
      body['default_supplier'] =
          (defaultSupplierId != null && defaultSupplierId.isNotEmpty) ? defaultSupplierId : null;

      // Add scraping fields if provided
      if (urlPattern != null) {
        body['url_pattern'] = urlPattern;
      }
      if (scraperEnabled != null) {
        body['scraper_enabled'] = scraperEnabled;
      }
      if (scraperNotes != null) {
        body['scraper_notes'] = scraperNotes;
      }
      print('DEBUG updateBrand: Updating brand $id with categories: ${body['categories']} (type: ${body['categories'].runtimeType})');
      print('DEBUG updateBrand: Body being sent: $body');
      final result = await pb.collection('brands').update(id, body: body);
      print('DEBUG updateBrand: Successfully updated brand $id');
      print('DEBUG updateBrand: Result categories = ${result.data['categories']} (type: ${result.data['categories']?.runtimeType})');
    } catch (e) {
      print('Error updating brand: $e');
      rethrow;
    }
  }

  Future<void> deleteBrand(String id) async {
    try {
      await pb.collection('brands').delete(id);
    } catch (e) {
      print('Error deleting brand: $e');
      rethrow;
    }
  }

  // Supplier management
  Future<List<dynamic>> getSuppliers({String? categoryId}) async {
    try {
      List<dynamic> records;
      if (categoryId != null) {
        print('DEBUG getSuppliers: Filtering by categoryId = $categoryId');
        records = await pb.collection('suppliers').getFullList(sort: 'company_name');
        print('DEBUG getSuppliers: Loaded ${records.length} total suppliers');
        
        // Filter: show suppliers with no categories OR suppliers that include this category
        records = records.where((supplier) {
          final categories = supplier.data['categories'];
          final supplierName = supplier.data['company_name'];
          print('DEBUG getSuppliers: Supplier "$supplierName" has categories = $categories (type: ${categories?.runtimeType})');
          
          // If no categories assigned, show for all (backward compatible)
          if (categories == null || categories == '' || (categories is List && categories.isEmpty)) {
            print('DEBUG getSuppliers: Supplier "$supplierName" has no categories - showing for all');
            return true;
          }
          
          // Check if this category is in the list
          if (categories is List) {
            final matches = categories.any((c) {
              String? catId;
              if (c is String) {
                catId = c;
              } else if (c is Map && c['id'] != null) {
                catId = c['id'];
              } else {
                catId = c.toString();
              }
              return catId == categoryId;
            });
            print('DEBUG getSuppliers: Supplier "$supplierName" ${matches ? "MATCHES" : "does NOT match"} category $categoryId');
            return matches;
          }
          
          // Handle single value (shouldn't happen with multiple relation, but just in case)
          if (categories is Map && categories['id'] != null) {
            final matches = categories['id'] == categoryId;
            print('DEBUG getSuppliers: Supplier "$supplierName" (single value) ${matches ? "MATCHES" : "does NOT match"}');
            return matches;
          }
          
          final matches = categories.toString() == categoryId;
          print('DEBUG getSuppliers: Supplier "$supplierName" (string) ${matches ? "MATCHES" : "does NOT match"}');
          return matches;
        }).toList();
        
        print('DEBUG getSuppliers: After filtering, ${records.length} suppliers match category $categoryId');
      } else {
        records = await pb.collection('suppliers').getFullList(sort: 'company_name');
      }
      return records;
    } catch (e) {
      print('Error getting suppliers: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> getCustomers() async {
    try {
      return await pb.collection('customers').getFullList(sort: 'company');
    } catch (e) {
      print('Error getting customers: $e');
      rethrow;
    }
  }

  Future<dynamic> getCustomer(String id) async {
    try {
      return await pb.collection('customers').getOne(id);
    } catch (e) {
      print('Error getting customer: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> getJobsForCustomer(String customerId) async {
    try {
      return await pb.collection('jobs').getFullList(
        filter: 'customer = "$customerId"',
        sort: '-updated',
      );
    } catch (e) {
      print('Error getting jobs for customer: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> getQuotesForCustomer(String customerId) async {
    try {
      return await pb.collection('quotes').getFullList(
        filter: 'customer = "$customerId"',
        sort: '-updated',
      );
    } catch (e) {
      print('Error getting quotes for customer: $e');
      rethrow;
    }
  }

  Future<void> createCustomer({
    required String company,
    String? name,
    String? address,
    String? email,
    String? phone,
    String? notes,
  }) async {
    try {
      await pb.collection('customers').create(body: {
        'company': company,
        'name': name,
        'address': address,
        'email': email,
        'phone': phone,
        'notes': notes,
      });
    } catch (e) {
      print('Error creating customer: $e');
      rethrow;
    }
  }

  Future<void> updateCustomer({
    required String id,
    required String company,
    String? name,
    String? address,
    String? email,
    String? phone,
    String? notes,
  }) async {
    try {
      await pb.collection('customers').update(id, body: {
        'company': company,
        'name': name,
        'address': address,
        'email': email,
        'phone': phone,
        'notes': notes,
      });
    } catch (e) {
      print('Error updating customer: $e');
      rethrow;
    }
  }

  Future<void> deleteCustomer(String id) async {
    try {
      await pb.collection('customers').delete(id);
    } catch (e) {
      print('Error deleting customer: $e');
      rethrow;
    }
  }

  static const String _jobExpand =
      'quote,customer,material_source_vendor,'
      'material_purchase_item,material_purchase_item.material,'
      'material_purchase_item.purchase,material_purchase_item.purchase.supplier';

  Future<List<dynamic>> getJobs() async {
    try {
      return await pb.collection('jobs').getFullList(
        sort: '-updated',
        expand: _jobExpand,
      );
    } catch (e) {
      print('Error getting jobs: $e');
      rethrow;
    }
  }

  /// Single job for detail view (same expands as list).
  Future<dynamic> getJob(String id) async {
    try {
      return await pb.collection('jobs').getOne(
        id,
        expand: _jobExpand,
      );
    } catch (e) {
      print('Error getting job: $e');
      rethrow;
    }
  }

  Future<dynamic> createJob(Map<String, dynamic> body) async {
    try {
      return await pb.collection('jobs').create(body: body);
    } catch (e) {
      print('Error creating job: $e');
      rethrow;
    }
  }

  Future<void> updateJob(String id, Map<String, dynamic> body) async {
    try {
      await pb.collection('jobs').update(id, body: body);
    } catch (e) {
      print('Error updating job: $e');
      rethrow;
    }
  }

  Future<void> deleteJob(String id) async {
    try {
      await pb.collection('jobs').delete(id);
    } catch (e) {
      print('Error deleting job: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> getQuotes() async {
    try {
      return await pb.collection('quotes').getFullList(
        sort: '-updated',
        expand: 'customer',
      );
    } catch (e) {
      print('Error getting quotes: $e');
      rethrow;
    }
  }

  Future<dynamic> getQuote(String id) async {
    try {
      return await pb.collection('quotes').getOne(
        id,
        expand: 'customer',
      );
    } catch (e) {
      print('Error getting quote: $e');
      rethrow;
    }
  }

  /// Lightweight rows for quotes list search by part number.
  Future<List<dynamic>> getAllQuoteLineItemsForSearch() async {
    try {
      return await pb.collection('quote_line_items').getFullList(
        fields: 'quote,part_number',
      );
    } catch (e) {
      print('Error getting quote line items for search: $e');
      return [];
    }
  }

  Future<List<dynamic>> getQuoteLineItems(String quoteId) async {
    try {
      return await pb.collection('quote_line_items').getFullList(
        filter: 'quote = "$quoteId"',
        sort: 'line_number',
        expand: 'material_vendor,subcontractor_1,subcontractor_2',
      );
    } catch (e) {
      print('Error getting quote line items: $e');
      rethrow;
    }
  }

  Future<dynamic?> getJobByQuoteId(String quoteId) async {
    try {
      final list = await pb.collection('jobs').getFullList(
        filter: 'quote = "$quoteId"',
      );
      return list.isEmpty ? null : list.first;
    } catch (e) {
      print('Error getting job by quote: $e');
      return null;
    }
  }

  Future<dynamic> createQuote(Map<String, dynamic> body) async {
    try {
      return await pb.collection('quotes').create(body: body);
    } catch (e) {
      print('Error creating quote: $e');
      rethrow;
    }
  }

  Future<void> updateQuote(String id, Map<String, dynamic> body) async {
    try {
      await pb.collection('quotes').update(id, body: body);
    } catch (e) {
      print('Error updating quote: $e');
      rethrow;
    }
  }

  Future<void> deleteQuote(String id) async {
    try {
      await pb.collection('quotes').delete(id);
    } catch (e) {
      print('Error deleting quote: $e');
      rethrow;
    }
  }

  Future<dynamic> createQuoteLineItemRaw(Map<String, dynamic> body) async {
    try {
      return await pb.collection('quote_line_items').create(body: body);
    } catch (e) {
      print('Error creating quote line item: $e');
      rethrow;
    }
  }

  Future<void> updateQuoteLineItemRaw(String id, Map<String, dynamic> body) async {
    try {
      await pb.collection('quote_line_items').update(id, body: body);
    } catch (e) {
      print('Error updating quote line item: $e');
      rethrow;
    }
  }

  Future<void> createQuoteLineItem({
    required String quoteId,
    required String lineNumber,
    required double partQuantity,
    String? description,
    double? unitPrice,
    double? lineTotal,
  }) async {
    try {
      final unit = unitPrice ?? 0;
      final total = lineTotal ?? (partQuantity * unit);
      final body = <String, dynamic>{
        'quote': quoteId,
        'line_number': int.tryParse(lineNumber) ?? double.tryParse(lineNumber) ?? lineNumber,
        'part_quantity': partQuantity,
        'unit_price': unit,
        'line_total': total,
      };
      if (description != null && description.isNotEmpty) {
        body['description'] = description;
      }
      await pb.collection('quote_line_items').create(body: body);
    } catch (e) {
      print('Error creating quote line item: $e');
      rethrow;
    }
  }

  Future<void> updateQuoteLineItem({
    required String id,
    required String lineNumber,
    required double partQuantity,
    String? description,
    double? unitPrice,
    double? lineTotal,
  }) async {
    try {
      final unit = unitPrice ?? 0;
      final total = lineTotal ?? (partQuantity * unit);
      final body = <String, dynamic>{
        'line_number': int.tryParse(lineNumber) ?? double.tryParse(lineNumber) ?? lineNumber,
        'part_quantity': partQuantity,
        'unit_price': unit,
        'line_total': total,
        'description': description,
      };
      await pb.collection('quote_line_items').update(id, body: body);
    } catch (e) {
      print('Error updating quote line item: $e');
      rethrow;
    }
  }

  Future<void> deleteQuoteLineItem(String id) async {
    try {
      await pb.collection('quote_line_items').delete(id);
    } catch (e) {
      print('Error deleting quote line item: $e');
      rethrow;
    }
  }

  Future<void> createSupplier({
    required String companyName,
    String? address,
    String? tel,
    String? website,
    String? contact,
    String? directTel,
    String? email,
    String? notes,
    List<String>? categoryIds,
  }) async {
    try {
      final body = <String, dynamic>{
        'company_name': companyName,
        'address': address,
        'tel': tel,
        'website': website,
        'contact': contact,
        'direct_tel': directTel,
        'email': email,
        'notes': notes,
      };
      if (categoryIds != null && categoryIds.isNotEmpty) {
        body['categories'] = categoryIds;
      }
      await pb.collection('suppliers').create(body: body);
    } catch (e) {
      print('Error creating supplier: $e');
      rethrow;
    }
  }

  Future<void> updateSupplier({
    required String id,
    required String companyName,
    String? address,
    String? tel,
    String? website,
    String? contact,
    String? directTel,
    String? email,
    String? notes,
    List<String>? categoryIds,
  }) async {
    try {
      final body = <String, dynamic>{
        'company_name': companyName,
        'address': address,
        'tel': tel,
        'website': website,
        'contact': contact,
        'direct_tel': directTel,
        'email': email,
        'notes': notes,
      };
      // Always set categories, even if empty (to clear existing ones)
      if (categoryIds != null) {
        body['categories'] = categoryIds;
      } else {
        // If null, set to empty array to clear all categories
        body['categories'] = [];
      }
      print('DEBUG updateSupplier: Updating supplier $id with categories: ${body['categories']}');
      await pb.collection('suppliers').update(id, body: body);
      print('DEBUG updateSupplier: Successfully updated supplier $id');
    } catch (e) {
      print('Error updating supplier: $e');
      rethrow;
    }
  }

  Future<void> deleteSupplier(String id) async {
    try {
      await pb.collection('suppliers').delete(id);
    } catch (e) {
      print('Error deleting supplier: $e');
      rethrow;
    }
  }

  // ============================================================================
  // CATEGORY MANAGEMENT
  // ============================================================================

  // Get all categories (sorted by sort_order)
  Future<List<dynamic>> getCategories() async {
    try {
      final records = await pb.collection('categories').getFullList(
        sort: 'sort_order,name',
      );
      return records;
    } catch (e) {
      print('Error getting categories: $e');
      rethrow;
    }
  }

  // Create a new category
  Future<void> createCategory({
    required String name,
    required int sortOrder,
  }) async {
    try {
      await pb.collection('categories').create(body: {
        'name': name,
        'sort_order': sortOrder,
      });
      print('Category created: $name');
    } catch (e) {
      print('Error creating category: $e');
      rethrow;
    }
  }

  // Update a category
  Future<void> updateCategory({
    required String categoryId,
    required String name,
    required int sortOrder,
  }) async {
    try {
      await pb.collection('categories').update(categoryId, body: {
        'name': name,
        'sort_order': sortOrder,
      });
      print('Category updated: $categoryId');
    } catch (e) {
      print('Error updating category: $e');
      rethrow;
    }
  }

  // Delete a category
  Future<void> deleteCategory(String categoryId) async {
    try {
      await pb.collection('categories').delete(categoryId);
      print('Category deleted: $categoryId');
    } catch (e) {
      print('Error deleting category: $e');
      rethrow;
    }
  }

  // Check if category has inventory items
  Future<int> getCategoryInventoryCount(String categoryName) async {
    try {
      final records = await pb.collection('inventory').getFullList(
        filter: 'category = "$categoryName"',
      );
      return records.length;
    } catch (e) {
      print('Error checking category inventory: $e');
      return 0;
    }
  }

  // ============================================================================
  // APP SETTINGS MANAGEMENT
  // ============================================================================

  // Get app settings (creates default if doesn't exist)
  Future<dynamic> getAppSettings() async {
    try {
      // Try to get the first settings record
      try {
        final settings = await pb.collection('app_settings').getFirstListItem('');
        return settings;
      } catch (e) {
        // No settings found, create default
        final defaultSettings = await pb.collection('app_settings').create(body: {
          'show_all_inventory_in_menu': true,
          'keep_drawer_open': false,
        });
        return defaultSettings;
      }
    } catch (e) {
      print('Error getting app settings: $e');
      rethrow;
    }
  }

  // Update app settings
  Future<void> updateAppSettings({
    required String settingsId,
    required bool showAllInventoryInMenu,
    String? subcategoryDisplayMode,
    bool? showToolDetailsInList, // NEW
    bool? useCategoryButtons, // NEW
    bool? enableToolImport, // NEW - for tool import feature
    bool? keepDrawerOpen, // NEW - keep side menu open on desktop
  }) async {
    try {
      final Map<String, dynamic> body = {
        'show_all_inventory_in_menu': showAllInventoryInMenu,
      };

      if (subcategoryDisplayMode != null) {
        body['subcategory_display_mode'] = subcategoryDisplayMode;
      }
      
      if (showToolDetailsInList != null) {
        body['show_tool_details_in_list'] = showToolDetailsInList;
      }
      
      if (useCategoryButtons != null) {
        body['use_category_buttons'] = useCategoryButtons;
      }
      
      // NEW: Add tool import setting
      if (enableToolImport != null) {
        body['enable_tool_import'] = enableToolImport;
      }

      // NEW: Keep drawer open on desktop
      if (keepDrawerOpen != null) {
        body['keep_drawer_open'] = keepDrawerOpen;
      }

      await pb.collection('app_settings').update(settingsId, body: body);
      print('App settings updated');
    } catch (e) {
      print('Error updating app settings: $e');
      rethrow;
    }
  }

  // ============================================================================
  // SHOP ERP SETTINGS (`settings` collection — quote defaults)
  // ============================================================================

  Future<dynamic> getShopSettings() async {
    try {
      try {
        return await pb.collection('settings').getFirstListItem('');
      } catch (_) {
        return await pb.collection('settings').create(
          body: _defaultShopSettingsBodyForCreate(),
        );
      }
    } catch (e) {
      print('Error getting shop settings: $e');
      rethrow;
    }
  }

  Map<String, dynamic> _defaultShopSettingsBodyForCreate() => {
        'default_shipping_markup_percent': 30,
        'default_final_markup_percent': 0,
        'default_hourly_rate_programming': 350,
        'default_hourly_rate_setup': 350,
        'default_hourly_rate_first_run': 350,
        'default_hourly_rate_production': 269,
        'exchange_rate_usd_to_cad': 1.3,
        'exchange_rate_auto_update': false,
        'auto_logout_minutes': 0,
      };

  Future<void> updateShopSettings(String id, Map<String, dynamic> body) async {
    try {
      await pb.collection('settings').update(id, body: body);
    } catch (e) {
      print('Error updating shop settings: $e');
      rethrow;
    }
  }

  // ============================================================================
  // INVENTORY HISTORY LOGGING
  // ============================================================================

  /// Log an inventory history entry
  /// 
  /// [toolId] - ID of the tool
  /// [locationId] - Primary location ID for this action
  /// [action] - Type of action: 'add', 'remove', 'transfer_in', 'transfer_out', 'edit'
  /// [quantity] - Quantity involved in the action
  /// [quantityBefore] - Quantity at location before the action
  /// [quantityAfter] - Quantity at location after the action
  /// [relatedLocationId] - For transfers: the other location involved
  /// [notes] - Optional notes about the action
  /// [toolLife] - Optional tool life in hours
  Future<void> logInventoryHistory({
    required String toolId,
    required String locationId,
    required String action,
    required int quantity,
    required int quantityBefore,
    required int quantityAfter,
    String? relatedLocationId,
    String? notes,
    double? toolLife,
  }) async {
    try {
      final body = {
        'tool': toolId,
        'location': locationId,
        'action': action,
        'quantity': quantity,
        'quantity_before': quantityBefore,
        'quantity_after': quantityAfter,
      };
      
      // Add optional fields only if provided
      if (relatedLocationId != null && relatedLocationId.isNotEmpty) {
        body['related_location'] = relatedLocationId;
      }
      if (notes != null && notes.isNotEmpty) {
        body['notes'] = notes;
      }
      if (toolLife != null) {
        body['tool_life'] = toolLife;
      }
      
      print('📝 Attempting to log history:');
      print('   Action: $action');
      print('   Tool: $toolId');
      print('   Location: $locationId');
      print('   Related Location: $relatedLocationId');
      print('   Quantity: $quantity (type: ${quantity.runtimeType})');
      print('   Quantity Before: $quantityBefore (type: ${quantityBefore.runtimeType})');
      print('   Quantity After: $quantityAfter (type: ${quantityAfter.runtimeType})');
      print('   Body being sent: $body');
      
      await pb.collection('inventory_history').create(body: body);
      print('✅ History logged successfully: $action');
    } catch (e) {
      print('❌ ERROR logging inventory history:');
      print('   Action: $action');
      print('   Tool: $toolId');
      print('   Location: $locationId');
      print('   Related Location: $relatedLocationId');
      print('   Quantities: $quantityBefore → $quantityAfter');
      print('   Full error: $e');
      // Don't rethrow - we don't want history logging to break the main operation
      // But we do want to see the error clearly in console
    }
  }

  /// Get inventory history for a specific tool
  /// [limit] - Maximum number of records to return (default: 5)
  /// [sort] - Sort order (default: '-created' for newest first)
  Future<List<dynamic>> getInventoryHistory({
    required String toolId,
    int limit = 5,
    String sort = '-created',
  }) async {
    try {
      final records = await pb.collection('inventory_history').getList(
        page: 1,
        perPage: limit,
        filter: 'tool = "$toolId"',
        sort: sort,
        expand: 'location,related_location',
      );
      return records.items;
    } catch (e) {
      print('Error getting inventory history: $e');
      return [];
    }
  }

  // ============================================================================
  // TOOL USAGE (performance stats)
  // ============================================================================

  /// Get all tool_usage records for a tool (newest first).
  Future<List<dynamic>> getToolUsage({
    required String toolId,
    String sort = '-used_at',
  }) async {
    try {
      final records = await pb.collection('tool_usage').getFullList(
        filter: 'tool = "$toolId"',
        sort: sort,
        expand: 'machine',
      );
      return records;
    } catch (e) {
      print('Error getting tool usage: $e');
      return [];
    }
  }

  Future<void> createToolUsage({
    required String toolId,
    required int minutesUsed,
    required String outcome, // worn | broken
    required String material,
    DateTime? usedAt,
    String? notes,
    String? machineLocationId,
  }) async {
    try {
      await pb.collection('tool_usage').create(
        body: {
          'tool': toolId,
          'minutes_used': minutesUsed,
          'outcome': outcome,
          'material': material,
          if (usedAt != null) 'used_at': usedAt.toIso8601String(),
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
          if (machineLocationId != null && machineLocationId.trim().isNotEmpty)
            'machine': machineLocationId.trim(),
        },
      );
    } catch (e) {
      print('Error creating tool usage: $e');
      rethrow;
    }
  }

  /// Get all inventory history for a tool (for "View All" functionality)
  Future<List<dynamic>> getAllInventoryHistory({
    required String toolId,
    String sort = '-created',
  }) async {
    try {
      final records = await pb.collection('inventory_history').getFullList(
        filter: 'tool = "$toolId"',
        sort: sort,
        expand: 'location,related_location',
      );
      return records;
    } catch (e) {
      print('Error getting all inventory history: $e');
      return [];
    }
  }

  /// Helper method to get current quantity at a location before making changes
  Future<int> getCurrentQuantityAtLocation({
    required String toolId,
    required String locationId,
  }) async {
    try {
      final records = await pb.collection('tool_locations').getFullList(
        filter: 'tool = "$toolId" && location = "$locationId"',
      );
      
      if (records.isEmpty) {
        return 0;
      }
      
      return (records.first.data['quantity'] ?? 0) as int;
    } catch (e) {
      print('Error getting current quantity: $e');
      return 0;
    }
  }

  /// Get historical locations where this tool was added (for quick-add suggestions)
  /// Returns last 3 unique locations where action = 'add' from bins/shelves/toolboxes only
  Future<List<String>> getHistoricalAddLocations({
    required String toolId,
    int limit = 3,
  }) async {
    try {
      // Get history records where tool was added
      final records = await pb.collection('inventory_history').getFullList(
        filter: 'tool = "$toolId" && action = "add"',
        sort: '-created',
        expand: 'location',
      );

      final historicalLocationIds = <String>{};

      for (final record in records) {
        if (historicalLocationIds.length >= limit) break;

        final locationId = record.data['location'];
        if (locationId == null) continue;

        // Check if location is expanded
        final expandedData = record.expand?['location'];
        if (expandedData == null) continue;

        // Handle if expandedData is a List or single object
        dynamic locationRecord;
        if (expandedData is List && expandedData.isNotEmpty) {
          locationRecord = expandedData[0];
        } else {
          locationRecord = expandedData;
        }

        // Get location type
        final locationType = locationRecord.data['type']?.toString().toLowerCase() ?? '';

        // Only include bins, shelves, toolboxes
        if (locationType == 'toolbox' ||
            locationType == 'shelf' ||
            locationType == 'bin') {
          historicalLocationIds.add(locationId);
        }
      }

      return historicalLocationIds.toList();
    } catch (e) {
      print('Error getting historical add locations: $e');
      return [];
    }
  }

  // ============================================================================
  // SUBCATEGORY MANAGEMENT
  // ============================================================================

  // Get all subcategories (sorted by sort_order)
  Future<List<dynamic>> getSubcategories() async {
    try {
      final records = await pb.collection('subcategories').getFullList(
        sort: 'sort_order,name',
      );
      return records;
    } catch (e) {
      print('Error getting subcategories: $e');
      rethrow;
    }
  }

  // Get top-level subcategories for a category
  Future<List<dynamic>> getTopLevelSubcategories(String categoryId) async {
    try {
      final records = await pb.collection('subcategories').getFullList(
        filter: 'category = "$categoryId"',
        sort: 'sort_order,name',
      );
      return records;
    } catch (e) {
      print('Error getting top-level subcategories: $e');
      rethrow;
    }
  }

  // Get child subcategories of a parent
  Future<List<dynamic>> getChildSubcategories(String parentId) async {
    try {
      final records = await pb.collection('subcategories').getFullList(
        filter: 'parent_subcategory = "$parentId"',
        sort: 'sort_order,name',
      );
      return records;
    } catch (e) {
      print('Error getting child subcategories: $e');
      rethrow;
    }
  }

  // Create subcategory
  Future<void> createSubcategory({
    required String name,
    String? categoryId,
    String? parentSubcategoryId,
    required int sortOrder,
    String? label, // NEW: Label for this subcategory itself
    String? customLabel,
    String? attributeListId,
    String? displayMode, // dropdown or buttons
    String? fieldType, // NEW: selection, text, number
  }) async {
    try {
      final body = <String, dynamic>{
        'name': name,
        'sort_order': sortOrder,
      };
      
      // For child subcategories, only set parent_subcategory
      // For top-level subcategories, only set category
      if (parentSubcategoryId != null) {
        body['parent_subcategory'] = parentSubcategoryId;
        print('DEBUG createSubcategory: Setting parent_subcategory=$parentSubcategoryId for "$name"');
        // Don't set category for child subcategories
      } else if (categoryId != null) {
        body['category'] = categoryId;
        print('DEBUG createSubcategory: Setting category=$categoryId for "$name"');
      }
      
      if (label != null && label.isNotEmpty) {
        body['label'] = label;
      }
      
      if (customLabel != null && customLabel.isNotEmpty) {
        body['custom_label'] = customLabel;
      }
      
      if (attributeListId != null) {
        body['attribute_list'] = attributeListId;
      }
      
      if (displayMode != null) {
        body['display_mode'] = displayMode;
      }
      
      if (fieldType != null) {
        body['field_type'] = fieldType;
      }
      
      print('DEBUG createSubcategory: Creating "$name" with body: $body');
      await pb.collection('subcategories').create(body: body);
      print('Subcategory created: $name');
    } catch (e) {
      print('Error creating subcategory: $e');
      rethrow;
    }
  }

  // Update subcategory
  Future<void> updateSubcategory({
    required String subcategoryId,
    required String name,
    required int sortOrder,
    String? label, // NEW: Label for this subcategory itself
    String? customLabel,
    String? attributeListId,
    String? parentSubcategoryId,
    String? displayMode, // dropdown or buttons
    String? fieldType, // NEW: selection, text, number
  }) async {
    try {
      final body = <String, dynamic>{
        'name': name,
        'sort_order': sortOrder,
      };
      
      // Always set label and custom_label (can be null to clear)
      body['label'] = label;
      body['custom_label'] = customLabel;
      
      // Always set attribute_list (can be null to clear)
      body['attribute_list'] = attributeListId;
      
      // If setting parent_subcategory, clear category
      if (parentSubcategoryId != null) {
        body['parent_subcategory'] = parentSubcategoryId;
        body['category'] = null; // Explicitly clear category for child subcategories
      }
      
      if (displayMode != null) {
        body['display_mode'] = displayMode;
      }
      
      if (fieldType != null) {
        body['field_type'] = fieldType;
      }
      
      await pb.collection('subcategories').update(subcategoryId, body: body);
      print('Subcategory updated: $subcategoryId');
    } catch (e) {
      print('Error updating subcategory: $e');
      rethrow;
    }
  }

  // Delete subcategory
  Future<void> deleteSubcategory(String subcategoryId) async {
    try {
      await pb.collection('subcategories').delete(subcategoryId);
      print('Subcategory deleted: $subcategoryId');
    } catch (e) {
      print('Error deleting subcategory: $e');
      rethrow;
    }
  }

  // Check if subcategory has children
  Future<bool> subcategoryHasChildren(String subcategoryId) async {
    try {
      final records = await pb.collection('subcategories').getFullList(
        filter: 'parent_subcategory = "$subcategoryId"',
      );
      return records.isNotEmpty;
    } catch (e) {
      print('Error checking subcategory children: $e');
      return false;
    }
  }

  // Check if subcategory is used in inventory
  Future<int> getSubcategoryInventoryCount(String subcategoryName) async {
    try {
      final records = await pb.collection('inventory').getFullList(
        filter: 'subcategory = "$subcategoryName"',
      );
      return records.length;
    } catch (e) {
      print('Error checking subcategory inventory: $e');
      return 0;
    }
  }

  // ============================================================================
  // ATTRIBUTE LISTS MANAGEMENT
  // ============================================================================

  // Get all attribute lists
  Future<List<dynamic>> getAttributeLists() async {
    try {
      final records = await pb.collection('attribute_lists').getFullList(
        sort: 'name',
      );
      return records;
    } catch (e) {
      print('Error getting attribute lists: $e');
      rethrow;
    }
  }

  // Create attribute list
  Future<void> createAttributeList({
    required String name,
    String? displayMode, // NEW: dropdown or buttons
  }) async {
    try {
      final body = <String, dynamic>{'name': name};
      if (displayMode != null) {
        body['display_mode'] = displayMode;
      }
      await pb.collection('attribute_lists').create(body: body);
      print('Attribute list created: $name');
    } catch (e) {
      print('Error creating attribute list: $e');
      rethrow;
    }
  }

  // Update attribute list
  Future<void> updateAttributeList({
    required String listId,
    required String name,
    String? displayMode, // NEW: dropdown or buttons
  }) async {
    try {
      final body = <String, dynamic>{'name': name};
      if (displayMode != null) {
        body['display_mode'] = displayMode;
      }
      await pb.collection('attribute_lists').update(listId, body: body);
      print('Attribute list updated: $listId');
    } catch (e) {
      print('Error updating attribute list: $e');
      rethrow;
    }
  }

  // Delete attribute list
  Future<void> deleteAttributeList(String listId) async {
    try {
      await pb.collection('attribute_lists').delete(listId);
      print('Attribute list deleted: $listId');
    } catch (e) {
      print('Error deleting attribute list: $e');
      rethrow;
    }
  }

  // Get attribute values for a list
  Future<List<dynamic>> getAttributeValues(String listId) async {
    try {
      final records = await pb.collection('attribute_values').getFullList(
        filter: 'attribute_list = "$listId"',
        sort: 'sort_order,value',
      );
      return records;
    } catch (e) {
      print('Error getting attribute values: $e');
      rethrow;
    }
  }

  // Create attribute value
  Future<void> createAttributeValue({
    required String listId,
    required String value,
    required int sortOrder,
  }) async {
    try {
      await pb.collection('attribute_values').create(body: {
        'attribute_list': listId,
        'value': value,
        'sort_order': sortOrder,
      });
      print('Attribute value created: $value');
    } catch (e) {
      print('Error creating attribute value: $e');
      rethrow;
    }
  }

  // Update attribute value
  Future<void> updateAttributeValue({
    required String valueId,
    required String value,
    required int sortOrder,
  }) async {
    try {
      await pb.collection('attribute_values').update(valueId, body: {
        'value': value,
        'sort_order': sortOrder,
      });
      print('Attribute value updated: $valueId');
    } catch (e) {
      print('Error updating attribute value: $e');
      rethrow;
    }
  }

  // Delete attribute value
  Future<void> deleteAttributeValue(String valueId) async {
    try {
      await pb.collection('attribute_values').delete(valueId);
      print('Attribute value deleted: $valueId');
    } catch (e) {
      print('Error deleting attribute value: $e');
      rethrow;
    }
  }

  // ============================================================================
  // TOOL IMPORT FROM WEB (MCP Server Integration)
  // ============================================================================

  /// Import tool specifications from vendor website using MCP server
  /// 
  /// This calls the MCP server which uses Ollama/Qwen2.5 to extract tool specs
  /// from vendor websites intelligently.
  /// 
  /// Parameters:
  /// - [brand]: Brand name (for logging/display)
  /// - [urlPattern]: URL pattern with {model} placeholder (e.g., "https://example.com/{model}")
  /// - [modelNumber]: Tool model number (required if urlPattern is provided)
  /// - [url]: Direct URL to tool page (optional, overrides urlPattern)
  /// 
  /// Returns a Map with:
  /// - 'success': bool - whether the import succeeded
  /// - 'data': Map - extracted tool specs if successful
  /// - 'source_url': String - the URL that was scraped
  /// - 'error': String - error message if failed
  Future<Map<String, dynamic>?> importToolSpecs({
    required String brand,
    String? urlPattern,
    String? modelNumber,
    String? url,
  }) async {
    try {
      // MCP Server URL - change this to match your setup
      // For production, this could be loaded from app_settings
      const mcpServerUrl = AppConfig.mcpUrl;
      
      // Build URL from pattern if provided
      String? finalUrl = url;
      if (finalUrl == null && urlPattern != null && modelNumber != null) {
        finalUrl = urlPattern.replaceAll('{model}', modelNumber);
      }
      
      if (finalUrl == null) {
        return {
          'success': false,
          'error': 'No URL or URL pattern provided for import',
        };
      }
      
      final requestBody = {
        'brand': brand,
        'url': finalUrl,
      };
      
      print('🔍 Importing tool specs from MCP server...');
      print('   Brand: $brand');
      print('   URL: $finalUrl');
      
      final response = await http.post(
        Uri.parse('$mcpServerUrl/api/extract-tool-specs'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      ).timeout(const Duration(seconds: 180)); // LLM extraction can take time
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        
        if (data['success'] == true) {
          print('✅ Tool specs imported successfully');
          print('   Source: ${data['source_url']}');
          return {
            'success': true,
            'data': data['data'],
            'source_url': data['source_url'],
          };
        } else {
          print('❌ Import failed: ${data['error']}');
          return {
            'success': false,
            'error': data['error'] ?? 'Unknown error',
          };
        }
      } else {
        print('❌ MCP Server returned status ${response.statusCode}');
        return {
          'success': false,
          'error': 'Server returned status ${response.statusCode}',
        };
      }
    } on http.ClientException catch (e) {
      print('❌ Network error connecting to MCP server: $e');
      return {
        'success': false,
        'error': 'Cannot connect to import server. Make sure it is running.',
      };
    } on TimeoutException catch (e) {
      print('❌ Import timed out: $e');
      return {
        'success': false,
        'error': 'Import timed out. This can happen on first run while the model loads. Try again.',
      };
    } catch (e) {
      print('❌ Unexpected error during import: $e');
      return {
        'success': false,
        'error': 'Unexpected error: $e',
      };
    }
  }

  /// Lists image URLs found on a product page (via MCP server HTML parse).
  Future<Map<String, dynamic>> extractPageImages(String pageUrl) async {
    const mcpServerUrl = AppConfig.mcpUrl;
    try {
      final response = await http
          .post(
            Uri.parse('$mcpServerUrl/api/extract-page-images'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'url': pageUrl}),
          )
          .timeout(const Duration(seconds: 45));

      final data = json.decode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        return {
          'success': false,
          'error': data['error']?.toString() ??
              'Server returned status ${response.statusCode}',
        };
      }
      if (data['success'] == true) {
        return {
          'success': true,
          'images': data['images'],
          'source_url': data['source_url'],
        };
      }
      return {
        'success': false,
        'error': data['error']?.toString() ?? 'Unknown error',
        'source_url': data['source_url'],
      };
    } on TimeoutException {
      return {'success': false, 'error': 'Timed out while loading page images.'};
    } on http.ClientException catch (e) {
      return {
        'success': false,
        'error': 'Cannot connect to import server. Make sure it is running. ($e)',
      };
    } catch (e) {
      return {'success': false, 'error': 'Unexpected error: $e'};
    }
  }

  /// Downloads image bytes via MCP (avoids CORS when running on web).
  Future<Uint8List?> fetchImageBytesViaMcp(String imageUrl) async {
    const mcpServerUrl = AppConfig.mcpUrl;
    try {
      final response = await http
          .post(
            Uri.parse('$mcpServerUrl/api/fetch-image'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'url': imageUrl}),
          )
          .timeout(const Duration(seconds: 60));

      final data = json.decode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || data['success'] != true) {
        print(
          '❌ fetch-image failed: ${data['error'] ?? response.statusCode}',
        );
        return null;
      }
      final b64 = data['content_base64'] as String?;
      if (b64 == null || b64.isEmpty) return null;
      return base64Decode(b64);
    } catch (e) {
      print('❌ fetchImageBytesViaMcp: $e');
      return null;
    }
  }

  // ============================================================================
  // PURCHASE TRACKING
  // ============================================================================

  Future<List<dynamic>> getPurchases({String? supplierId}) async {
    try {
      if (supplierId != null && supplierId.isNotEmpty) {
        return await pb.collection('purchases').getFullList(
          filter: 'supplier = "$supplierId"',
          sort: '-purchase_date',
          expand: 'supplier',
        );
      }
      return await pb.collection('purchases').getFullList(
        sort: '-purchase_date',
        expand: 'supplier',
      );
    } catch (e) {
      print('Error getting purchases: $e');
      rethrow;
    }
  }

  Future<dynamic> createPurchase({
    required DateTime purchaseDate,
    String? supplierId,
    String? orderReference,
    String? invoice,
    String? notes,
    double? total,
    String currency = 'CAD',
  }) async {
    try {
      final body = <String, dynamic>{
        'purchase_date': purchaseDate.toIso8601String().split('T').first,
        'currency': currency == 'USD' ? 'USD' : 'CAD',
      };
      if (supplierId != null && supplierId.isNotEmpty) body['supplier'] = supplierId;
      if (orderReference != null && orderReference.isNotEmpty) {
        body['order_reference'] = orderReference;
      }
      if (invoice != null && invoice.isNotEmpty) body['invoice'] = invoice;
      if (notes != null && notes.isNotEmpty) body['notes'] = notes;
      if (total != null) body['total'] = total;
      final record = await pb.collection('purchases').create(body: body);
      return record;
    } catch (e) {
      print('Error creating purchase: $e');
      rethrow;
    }
  }

  Future<void> updatePurchase(String id, {
    DateTime? purchaseDate,
    String? supplierId,
    String? orderReference,
    String? invoice,
    String? notes,
    double? total,
    String? currency,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (purchaseDate != null) body['purchase_date'] = purchaseDate.toIso8601String().split('T').first;
      if (supplierId != null) body['supplier'] = supplierId.isEmpty ? null : supplierId;
      if (orderReference != null) body['order_reference'] = orderReference;
      if (invoice != null) body['invoice'] = invoice;
      if (notes != null) body['notes'] = notes;
      if (total != null) body['total'] = total;
      if (currency != null) {
        body['currency'] = currency == 'USD' ? 'USD' : 'CAD';
      }
      if (body.isEmpty) return;
      await pb.collection('purchases').update(id, body: body);
    } catch (e) {
      print('Error updating purchase: $e');
      rethrow;
    }
  }

  Future<void> deletePurchase(String id) async {
    try {
      final items = await pb.collection('purchase_items').getFullList(filter: 'purchase = "$id"');
      for (final item in items) {
        await pb.collection('purchase_items').delete(item.id);
      }
      await pb.collection('purchases').delete(id);
    } catch (e) {
      print('Error deleting purchase: $e');
      rethrow;
    }
  }

  Future<dynamic> getPurchase(String id) async {
    try {
      return await pb.collection('purchases').getOne(id, expand: 'supplier');
    } catch (e) {
      print('Error getting purchase: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> getPurchaseItems(String purchaseId) async {
    try {
      return await pb.collection('purchase_items').getFullList(
        filter: 'purchase = "$purchaseId"',
        expand: 'tool,material',
      );
    } catch (e) {
      print('Error getting purchase items: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> getPurchaseItemsByTool(String toolId) async {
    try {
      return await pb.collection('purchase_items').getFullList(
        filter: 'tool = "$toolId"',
        expand: 'purchase,purchase.supplier,tool',
        sort: '-purchase.purchase_date',
      );
    } catch (e) {
      print('Error getting purchase items by tool: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> getPurchaseItemsByMaterial(String materialId) async {
    try {
      return await pb.collection('purchase_items').getFullList(
        filter: 'material = "$materialId" && line_type = "material"',
        expand: 'purchase,purchase.supplier,material',
        sort: '-purchase.purchase_date',
      );
    } catch (e) {
      print('Error getting purchase items by material: $e');
      rethrow;
    }
  }

  /// Heat/lot strings keyed by material id (for Material list search).
  Future<Map<String, List<String>>> getMaterialHeatLotsByMaterialId() async {
    try {
      final records = await pb.collection('purchase_items').getFullList(
        filter: 'line_type = "material" && heat_lot != ""',
      );
      final map = <String, List<String>>{};
      for (final r in records) {
        final mid = r.data['material']?.toString() ?? '';
        final lot = (r.data['heat_lot'] ?? '').toString().trim();
        if (mid.isEmpty || lot.isEmpty) continue;
        final list = map.putIfAbsent(mid, () => <String>[]);
        final exists = list.any((x) => x.toLowerCase() == lot.toLowerCase());
        if (!exists) list.add(lot);
      }
      return map;
    } catch (e) {
      print('Error getting material heat lots: $e');
      rethrow;
    }
  }

  /// Material purchase lines that have a heat/lot (for job lot picker).
  Future<List<dynamic>> getMaterialLotsForPicker() async {
    try {
      return await pb.collection('purchase_items').getFullList(
        filter: 'line_type = "material" && heat_lot != ""',
        expand: 'material,purchase,purchase.supplier',
        sort: '-purchase.purchase_date',
      );
    } catch (e) {
      print('Error getting material lots for picker: $e');
      rethrow;
    }
  }

  Future<dynamic> getPurchaseItem(String id) async {
    try {
      return await pb.collection('purchase_items').getOne(
        id,
        expand: 'material,purchase,purchase.supplier',
      );
    } catch (e) {
      print('Error getting purchase item: $e');
      rethrow;
    }
  }

  Future<dynamic> createPurchaseItem({
    required String purchaseId,
    String? toolId,
    String? materialId,
    required num quantity,
    double? unitCost,
    String lineType = 'item',
    String? description,
    String? heatLot,
    List<http.MultipartFile>? millCertFiles,
  }) async {
    try {
      final body = <String, dynamic>{
        'purchase': purchaseId,
        'quantity': quantity,
        'line_type': lineType,
      };
      if (toolId != null && toolId.isNotEmpty) body['tool'] = toolId;
      if (materialId != null && materialId.isNotEmpty) {
        body['material'] = materialId;
      }
      if (unitCost != null) body['unit_cost'] = unitCost;
      if (description != null && description.isNotEmpty) {
        body['description'] = description;
      }
      if (heatLot != null && heatLot.isNotEmpty) body['heat_lot'] = heatLot;
      if (millCertFiles != null && millCertFiles.isNotEmpty) {
        return await pb.collection('purchase_items').create(
          body: body,
          files: millCertFiles,
        );
      }
      return await pb.collection('purchase_items').create(body: body);
    } catch (e) {
      print('Error creating purchase item: $e');
      rethrow;
    }
  }

  /// Download a file field from a record (used when re-saving purchase lines).
  Future<List<int>> downloadRecordFile(dynamic record, String filename) async {
    final url = pb.files.getUrl(record, filename);
    final headers = <String, String>{};
    final token = pb.authStore.token;
    if (token.isNotEmpty) {
      headers['Authorization'] = token;
    }
    final response = await http.get(url, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to download $filename (${response.statusCode})',
      );
    }
    return response.bodyBytes;
  }

  Future<void> deletePurchaseItem(String id) async {
    try {
      await pb.collection('purchase_items').delete(id);
    } catch (e) {
      print('Error deleting purchase item: $e');
      rethrow;
    }
  }

  // ============================================================================
  // MATERIALS CATALOG
  // ============================================================================

  Future<List<dynamic>> getMaterials() async {
    try {
      return await pb.collection('materials').getFullList(
        sort: 'grade,form,size_label',
      );
    } catch (e) {
      print('Error getting materials: $e');
      rethrow;
    }
  }

  Future<dynamic> createMaterial({
    required String grade,
    required String form,
    required String sizeLabel,
    String unit = 'ea',
    String? notes,
  }) async {
    try {
      final body = <String, dynamic>{
        'grade': grade.trim(),
        'form': form.trim(),
        'size_label': sizeLabel.trim(),
        'unit': unit.trim().isEmpty ? 'ea' : unit.trim(),
      };
      if (notes != null && notes.trim().isNotEmpty) {
        body['notes'] = notes.trim();
      }
      return await pb.collection('materials').create(body: body);
    } catch (e) {
      print('Error creating material: $e');
      rethrow;
    }
  }

  Future<dynamic> updateMaterial(
    String id, {
    required String grade,
    required String form,
    required String sizeLabel,
    String unit = 'ea',
    String? notes,
  }) async {
    try {
      final body = <String, dynamic>{
        'grade': grade.trim(),
        'form': form.trim(),
        'size_label': sizeLabel.trim(),
        'unit': unit.trim().isEmpty ? 'ea' : unit.trim(),
        'notes': (notes == null || notes.trim().isEmpty) ? '' : notes.trim(),
      };
      return await pb.collection('materials').update(id, body: body);
    } catch (e) {
      print('Error updating material: $e');
      rethrow;
    }
  }

  Future<void> deleteMaterial(String id) async {
    try {
      await pb.collection('materials').delete(id);
    } catch (e) {
      print('Error deleting material: $e');
      rethrow;
    }
  }

  Future<dynamic> uploadPurchaseAttachments(
    String purchaseId,
    List<http.MultipartFile> files,
  ) async {
    try {
      return await pb.collection('purchases').update(purchaseId, files: files);
    } catch (e) {
      print('Error uploading purchase attachments: $e');
      rethrow;
    }
  }

  Future<dynamic> removePurchaseAttachment(
    String purchaseId,
    String filename,
  ) async {
    try {
      return await pb.collection('purchases').update(
        purchaseId,
        body: {
          'attachments-': [filename],
        },
      );
    } catch (e) {
      print('Error removing purchase attachment: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> getMaintenanceMachines() async {
    try {
      return await pb.collection('maintenance_machines').getFullList(
        sort: 'sort_order,name',
      );
    } catch (e) {
      print('Error getting maintenance machines: $e');
      rethrow;
    }
  }

  Future<dynamic> createMaintenanceMachine({
    required String name,
    int? sortOrder,
  }) async {
    try {
      return await pb.collection('maintenance_machines').create(body: {
        'name': name.trim(),
        if (sortOrder != null) 'sort_order': sortOrder,
      });
    } catch (e) {
      print('Error creating maintenance machine: $e');
      rethrow;
    }
  }

  Future<void> updateMaintenanceMachine({
    required String id,
    required String name,
    int? sortOrder,
  }) async {
    try {
      await pb.collection('maintenance_machines').update(id, body: {
        'name': name.trim(),
        if (sortOrder != null) 'sort_order': sortOrder,
      });
    } catch (e) {
      print('Error updating maintenance machine: $e');
      rethrow;
    }
  }

  Future<void> deleteMaintenanceMachine(String id) async {
    try {
      await pb.collection('maintenance_machines').delete(id);
    } catch (e) {
      print('Error deleting maintenance machine: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> getMaintenanceRecords() async {
    try {
      // Sort by completed_date only — multi-field sorts including -created
      // returned 400 on the live shop PB build.
      return await pb.collection('maintenance_records').getFullList(
        sort: '-completed_date',
        expand: 'machine',
      );
    } catch (e) {
      print('Error getting maintenance records: $e');
      rethrow;
    }
  }

  Future<dynamic> createMaintenanceRecord({
    required String name,
    required String machineId,
    String? completedDate,
    String? note,
    String? updatedByEmail,
    String? scheduleId,
    List<http.MultipartFile>? photoFiles,
  }) async {
    try {
      final body = <String, dynamic>{
        'name': name.trim(),
        'machine': machineId,
        if (completedDate != null && completedDate.isNotEmpty)
          'completed_date': completedDate,
        if (note != null) 'note': note,
        if (updatedByEmail != null && updatedByEmail.isNotEmpty)
          'updated_by_email': updatedByEmail,
        if (scheduleId != null && scheduleId.isNotEmpty) 'schedule': scheduleId,
      };
      if (photoFiles != null && photoFiles.isNotEmpty) {
        return await pb.collection('maintenance_records').create(
          body: body,
          files: photoFiles,
        );
      }
      return await pb.collection('maintenance_records').create(body: body);
    } catch (e) {
      print('Error creating maintenance record: $e');
      rethrow;
    }
  }

  Future<void> updateMaintenanceRecord({
    required String id,
    required String name,
    required String machineId,
    String? completedDate,
    String? note,
    String? updatedByEmail,
  }) async {
    try {
      await pb.collection('maintenance_records').update(id, body: {
        'name': name.trim(),
        'machine': machineId,
        'completed_date':
            (completedDate != null && completedDate.isNotEmpty) ? completedDate : null,
        'note': note ?? '',
        if (updatedByEmail != null && updatedByEmail.isNotEmpty)
          'updated_by_email': updatedByEmail,
      });
    } catch (e) {
      print('Error updating maintenance record: $e');
      rethrow;
    }
  }

  Future<void> deleteMaintenanceRecord(String id) async {
    try {
      await pb.collection('maintenance_records').delete(id);
    } catch (e) {
      print('Error deleting maintenance record: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> getMaintenanceSchedules() async {
    try {
      return await pb.collection('maintenance_schedules').getFullList(
        sort: 'next_due_date',
        expand: 'machine',
      );
    } catch (e) {
      print('Error getting maintenance schedules: $e');
      rethrow;
    }
  }

  Future<dynamic> createMaintenanceSchedule({
    required String name,
    required String machineId,
    required int frequencyValue,
    required String frequencyUnit,
    required String nextDueDate,
    String? note,
    int leadDays = 7,
    bool active = true,
    String? updatedByEmail,
  }) async {
    try {
      return await pb.collection('maintenance_schedules').create(body: {
        'name': name.trim(),
        'machine': machineId,
        'frequency_value': frequencyValue < 1 ? 1 : frequencyValue,
        'frequency_unit': frequencyUnit,
        'next_due_date': nextDueDate,
        'lead_days': leadDays,
        'active': active,
        if (note != null) 'note': note,
        if (updatedByEmail != null && updatedByEmail.isNotEmpty)
          'updated_by_email': updatedByEmail,
      });
    } catch (e) {
      print('Error creating maintenance schedule: $e');
      rethrow;
    }
  }

  Future<void> updateMaintenanceSchedule({
    required String id,
    required String name,
    required String machineId,
    required int frequencyValue,
    required String frequencyUnit,
    required String nextDueDate,
    String? lastCompletedDate,
    String? note,
    int leadDays = 7,
    bool active = true,
    String? updatedByEmail,
  }) async {
    try {
      await pb.collection('maintenance_schedules').update(id, body: {
        'name': name.trim(),
        'machine': machineId,
        'frequency_value': frequencyValue < 1 ? 1 : frequencyValue,
        'frequency_unit': frequencyUnit,
        'next_due_date': nextDueDate,
        'last_completed_date':
            (lastCompletedDate != null && lastCompletedDate.isNotEmpty)
                ? lastCompletedDate
                : null,
        'lead_days': leadDays,
        'active': active,
        'note': note ?? '',
        if (updatedByEmail != null && updatedByEmail.isNotEmpty)
          'updated_by_email': updatedByEmail,
      });
    } catch (e) {
      print('Error updating maintenance schedule: $e');
      rethrow;
    }
  }

  Future<void> deleteMaintenanceSchedule(String id) async {
    try {
      await pb.collection('maintenance_schedules').delete(id);
    } catch (e) {
      print('Error deleting maintenance schedule: $e');
      rethrow;
    }
  }

  /// Log a completion and advance [next_due_date] from the completed date.
  Future<void> completeMaintenanceSchedule({
    required String scheduleId,
    required String name,
    required String machineId,
    required int frequencyValue,
    required String frequencyUnit,
    required String completedDate,
    String? note,
    int leadDays = 7,
    bool active = true,
    String? updatedByEmail,
    List<http.MultipartFile>? photoFiles,
  }) async {
    try {
      await createMaintenanceRecord(
        name: name,
        machineId: machineId,
        completedDate: completedDate,
        note: note,
        updatedByEmail: updatedByEmail,
        scheduleId: scheduleId,
        photoFiles: photoFiles,
      );

      final completed = DateTime.parse(completedDate);
      final from = DateTime(completed.year, completed.month, completed.day);
      final next = _advanceMaintenanceDue(
        from: from,
        frequencyValue: frequencyValue,
        frequencyUnit: frequencyUnit,
      );
      final nextStr =
          '${next.year.toString().padLeft(4, '0')}-${next.month.toString().padLeft(2, '0')}-${next.day.toString().padLeft(2, '0')}';

      await pb.collection('maintenance_schedules').update(scheduleId, body: {
        'last_completed_date': completedDate,
        'next_due_date': nextStr,
        'lead_days': leadDays,
        'active': active,
        if (updatedByEmail != null && updatedByEmail.isNotEmpty)
          'updated_by_email': updatedByEmail,
      });
    } catch (e) {
      print('Error completing maintenance schedule: $e');
      rethrow;
    }
  }

  // --- Wiki tables (reusable grids embedded via {{table:id}}) ---

  Future<List<RecordModel>> getWikiTablesForPage(String pageId) async {
    return await pb.collection('wiki_tables').getFullList(
      filter: 'page = "$pageId"',
      sort: 'sort_order,title',
    );
  }

  Future<RecordModel> getWikiTable(String id) async {
    return await pb.collection('wiki_tables').getOne(id);
  }

  Future<RecordModel> createWikiTable({
    required String title,
    required String columnsJson,
    String? pageId,
    int sortOrder = 0,
    String? updatedByEmail,
    String? updatedByName,
  }) async {
    return await pb.collection('wiki_tables').create(body: {
      'title': title,
      'columns_json': columnsJson,
      'sort_order': sortOrder,
      if (pageId != null && pageId.isNotEmpty) 'page': pageId,
      if (updatedByEmail != null) 'updated_by_email': updatedByEmail,
      if (updatedByName != null) 'updated_by_name': updatedByName,
    });
  }

  Future<RecordModel> updateWikiTable(
    String id,
    Map<String, dynamic> body,
  ) async {
    return await pb.collection('wiki_tables').update(id, body: body);
  }

  Future<void> deleteWikiTable(String id) async {
    final rows = await pb.collection('wiki_table_rows').getFullList(
      filter: 'wiki_table = "$id"',
    );
    for (final r in rows) {
      await pb.collection('wiki_table_rows').delete(r.id);
    }
    await pb.collection('wiki_tables').delete(id);
  }

  Future<List<RecordModel>> getWikiTableRows(String tableId) async {
    return await pb.collection('wiki_table_rows').getFullList(
      filter: 'wiki_table = "$tableId"',
      sort: 'sort_order',
    );
  }

  Future<RecordModel> createWikiTableRow({
    required String tableId,
    required String valuesJson,
    int sortOrder = 0,
  }) async {
    return await pb.collection('wiki_table_rows').create(body: {
      'wiki_table': tableId,
      'values_json': valuesJson,
      'sort_order': sortOrder,
    });
  }

  Future<RecordModel> updateWikiTableRow(
    String id,
    Map<String, dynamic> body,
  ) async {
    return await pb.collection('wiki_table_rows').update(id, body: body);
  }

  Future<void> deleteWikiTableRow(String id) async {
    await pb.collection('wiki_table_rows').delete(id);
  }

  DateTime _advanceMaintenanceDue({
    required DateTime from,
    required int frequencyValue,
    required String frequencyUnit,
  }) {
    final n = frequencyValue < 1 ? 1 : frequencyValue;
    switch (frequencyUnit) {
      case 'weeks':
        return from.add(Duration(days: 7 * n));
      case 'months':
        final month = from.month - 1 + n;
        final year = from.year + month ~/ 12;
        final monthNorm = month % 12 + 1;
        final dim = DateTime(year, monthNorm + 1, 0).day;
        final day = from.day > dim ? dim : from.day;
        return DateTime(year, monthNorm, day);
      case 'days':
      default:
        return from.add(Duration(days: n));
    }
  }
  }
