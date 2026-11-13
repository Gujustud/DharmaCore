import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'pocketbase_service.dart';
import 'models.dart';
import 'add_inventory_dialog.dart';
import 'workspace_layout.dart';
import 'workspace_scaffold.dart';
import 'inventory_screen.dart';
import 'transfer_dialog.dart';
import 'drawer_behavior.dart';
import 'label_print_service.dart';
import 'package:intl/intl.dart'; // For date formatting in history
import 'package:url_launcher/url_launcher.dart';

class AddToolScreen extends StatefulWidget {
  final Tool? tool; // If provided, we're in edit mode
  final bool isDuplicate; // If true, we're duplicating (don't update, create new)
  final String? initialCategory; // If provided, pre-select this category
  
  const AddToolScreen({
    super.key,
    this.tool,
    this.isDuplicate = false,
    this.initialCategory,
  });

  @override
  State<AddToolScreen> createState() => _AddToolScreenState();
}

class _AddToolScreenState extends State<AddToolScreen> with AutoOpenDrawerMixin {
  // Cutting Tools category ID from PocketBase
  static const String CUTTING_TOOLS_CATEGORY_ID = '0ro99ktjwyl14dc';

  // Wire + Letter drill equivalents for Drill Standard naming.
  // Key is the formatted drill diameter string (per our drill-diameter rules in _formatDrillDiameterKey()).
  static const Map<String, String> _LETTER_BY_INCH_DIAMETER = {
    '.234': 'A',
    '.238': 'B',
    '.242': 'C',
    '.246': 'D',
    '.25': 'E',
    '.257': 'F',
    '.261': 'G',
    '.266': 'H',
    '.272': 'I',
    '.277': 'J',
    '.281': 'K',
    '.29': 'L',
    '.295': 'M',
    '.302': 'N',
    '.316': 'O',
    '.323': 'P',
    '.332': 'Q',
    '.339': 'R',
    '.348': 'S',
    '.358': 'T',
    '.368': 'U',
    '.377': 'V',
    '.386': 'W',
    '.397': 'X',
    '.404': 'Y',
    '.413': 'Z',
  };

  // Note: For wire keys >= 0.125", the drill diameter formatter truncates to 3 decimals (no rounding),
  // so the keys below reflect that canonical formatting.
  static const Map<String, String> _WIRE_BY_INCH_DIAMETER = {
    '.0019': '107',
    '.0023': '106',
    '.0027': '105',
    '.0031': '104',
    '.0035': '103',
    '.0039': '102',
    '.0043': '101',
    '.0047': '100',
    '.0051': '99',
    '.0055': '98',
    '.0059': '97',
    '.0063': '96',
    '.0067': '95',
    '.0071': '94',
    '.0075': '93',
    '.0079': '92',
    '.0083': '91',
    '.0087': '90',
    '.0091': '89',
    '.0095': '88',
    '.01': '87',
    '.0105': '86',
    '.011': '85',
    '.0115': '84',
    '.012': '83',
    '.0125': '82',
    '.013': '81',
    '.0135': '80',
    '.0145': '79',
    '.016': '78',
    '.018': '77',
    '.02': '76',
    '.021': '75',
    '.0225': '74',
    '.024': '73',
    '.025': '72',
    '.026': '71',
    '.028': '70',
    '.0292': '69',
    '.031': '68',
    '.032': '67',
    '.033': '66',
    '.035': '65',
    '.036': '64',
    '.037': '63',
    '.038': '62',
    '.039': '61',
    '.04': '60',
    '.041': '59',
    '.042': '58',
    '.043': '57',
    '.0465': '56',
    '.052': '55',
    '.055': '54',
    '.0595': '53',
    '.0635': '52',
    '.067': '51',
    '.07': '50',
    '.073': '49',
    '.076': '48',
    '.0785': '47',
    '.081': '46',
    '.082': '45',
    '.086': '44',
    '.089': '43',
    '.0935': '42',
    '.096': '41',
    '.098': '40',
    '.0995': '39',
    '.1015': '38',
    '.104': '37',
    '.1065': '36',
    '.11': '35',
    '.111': '34',
    '.113': '33',
    '.116': '32',
    '.12': '31',

    // >= 0.125" keys (truncated to 3 decimals by _formatDrillDiameterKey()).
    '.128': '30',
    '.136': '29',
    '.14': '28',
    '.144': '27',
    '.147': '26',
    '.149': '25',
    '.152': '24',
    '.154': '23',
    '.157': '22',
    '.159': '21',
    '.161': '20',
    '.166': '19',
    '.169': '18',
    '.173': '17',
    '.177': '16',
    '.18': '15',
    '.182': '14',
    '.185': '13',
    '.189': '12',
    '.191': '11',
    '.193': '10',
    '.196': '9',
    '.199': '8',
    '.201': '7',
    '.204': '6',
    '.205': '5',
    '.209': '4',
    '.213': '3',
    '.221': '2',
    '.228': '1',
  };
  
  final _formKey = GlobalKey<FormState>();
  
  // Form controllers
  final _toolNameController = TextEditingController();
  final _modelNumberController = TextEditingController();
  final _urlController = TextEditingController();
  final _diameterInController = TextEditingController();
  final _diameterMmController = TextEditingController();
  final _flutesController = TextEditingController();
  final _fluteLengthController = TextEditingController();
  final _cornerRadController = TextEditingController();
  final _neckController = TextEditingController();
  final _drillIncludedAngleController = TextEditingController(); // Drills: Included angle (optional)
  final _tslotRadiusController = TextEditingController();  // NEW: T-slot radius
  final _chamferAngleController = TextEditingController();  // NEW: Chamfer angle
  final _chamferTipDiameterController = TextEditingController();  // NEW: Chamfer tip diameter
  final _notesController = TextEditingController();
  final _restockQtyController = TextEditingController();
  final _restockNotesController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  GlobalKey<ScaffoldState> get scaffoldKey => _scaffoldKey;
  
  // Dropdown values
  String _category = 'Cutting Tools';
  
  // Subcategories
  List<dynamic> _allSubcategories = [];
  List<String?> _selectedSubcategoryIds = []; // Stack of selections for unlimited levels
  String _subcategoryText = ''; // Combined subcategory text for saving
  
  // NEW: Store text/number input values for subcategories
  Map<int, String> _subcategoryTextValues = {}; // level → text value
  Map<int, double?> _subcategoryNumberValues = {}; // level → number value
  
  // Temporary backward compatibility variables (will be replaced with dynamic system)
  String? _subcategory;
  String? _subSubcategory;
  
  // Attribute
  String? _selectedAttributeValue;
  
  // Categories (loaded dynamically)
  List<dynamic> _categories = [];
  String? _selectedCategoryId;
  
  // Location selection
  List<dynamic> _locations = [];
  
  // Inventory to add (for add/duplicate mode)
  Map<String, dynamic>? _inventoryToAdd; // {quantity: int, locationId: String, locationPath: String}
  
  // Brand and Supplier selection
  List<dynamic> _brands = [];
  List<dynamic> _suppliers = [];
  String? _selectedBrandId;
  String? _selectedBrandName;
  String? _selectedSupplierId;
  String? _selectedSupplierName;
  /// FocusNodes from Autocomplete fieldViewBuilder so we can refocus after Enter select.
  FocusNode? _brandFieldFocusNode;
  FocusNode? _supplierFieldFocusNode;
  
  // Auto-generated tool name
  String _toolName = '';
  bool _autoGenerateName = true;
  
  // Display preferences
  bool _useCategoryButtons = false; // Load from settings
  
  // Tool Import feature
  bool _enableToolImport = false; // Load from settings
  bool _isImporting = false; // Track import state
  
  // Photo
  String? _photoUrl;
  Uint8List? _photoBytes;
  bool _photoChanged = false;
  
  // Tool locations (for edit mode)
  List<ToolLocation> _toolLocations = [];
  List<Location> _allLocations = [];
  
  // NEW: History tracking
  List<InventoryHistory> _recentHistory = [];
  bool _loadingHistory = false;
  
  // Purchase history (price over time)
  List<dynamic> _purchaseHistoryRecords = [];
  bool _loadingPurchaseHistory = false;

  // Tool usage (performance stats)
  List<dynamic> _toolUsageRecords = [];
  bool _loadingToolUsage = false;

  static const List<String> _toolUsageMaterials = [
    'Aluminum',
    'Mild Steel',
    'Stainless',
    'Titanium',
    'Plastic',
    'Nylon',
    '17-4PH',
  ];
  
  // Manual buy list (restock)
  bool _needsRestock = false;
  
  // Initialization state
  bool _isInitialized = false;
  
  bool get _isEditMode => widget.tool != null && !widget.isDuplicate;
  
  @override
  void initState() {
    super.initState();
    _initializeScreen();
    
    _diameterInController.addListener(_scheduleToolNameUpdate);
    _flutesController.addListener(_scheduleToolNameUpdate);
    _fluteLengthController.addListener(_scheduleToolNameUpdate);
    _cornerRadController.addListener(_scheduleToolNameUpdate);
    _neckController.addListener(_scheduleToolNameUpdate);
    _drillIncludedAngleController.addListener(_scheduleToolNameUpdate);
    _tslotRadiusController.addListener(_scheduleToolNameUpdate);  // NEW
    _chamferAngleController.addListener(_scheduleToolNameUpdate);  // NEW
    _chamferTipDiameterController.addListener(_scheduleToolNameUpdate);  // NEW
  }
  
  Future<void> _initializeScreen() async {
    // Load in proper sequence to ensure data is available when needed
    await _loadSettings(); // Load display settings first
    _loadLocations(); // Can be async in background
    await _loadCategories(); // Load categories and determine _selectedCategoryId
    await _loadSubcategories(); // FIXED: Await so subcategories are loaded before matching
    
    // If initialCategory is provided, use it (for new tools only)
    if (widget.initialCategory != null && widget.tool == null) {
      _category = widget.initialCategory!;
      // Find the category ID for the initial category
      if (_categories.isNotEmpty) {
        final matchingCategory = _categories.where(
          (c) => c.data['name'] == widget.initialCategory,
        );
        if (matchingCategory.isNotEmpty) {
          _selectedCategoryId = matchingCategory.first.id;
        }
      }
    }
    
    // If editing/duplicating, pre-fill fields FIRST to set the brand/supplier IDs
    if (widget.tool != null) {
      _prefillFields();
      // Now that subcategories are loaded, match them
      if (_allSubcategories.isNotEmpty) {
        _matchSubcategoryNamesToIds();
        // Ensure attribute-value based selectors (button-style) highlight immediately
        // by aligning the saved last subcategory part with _selectedAttributeValue.
        _syncAttributeValueIntoSelectionChain();
      }
    }
    
    // Now load brands/suppliers with the correct category filter
    // This will match the Brand/Supplier objects from the IDs we just set
    await _loadBrandsAndSuppliers(
      categoryId: _selectedCategoryId,
      preserveSelections: widget.tool != null
    );
    
    if (_isEditMode) {
      _loadToolLocations();
      _loadRecentHistory();
      _loadPurchaseHistory();
      _loadToolUsage();
    }
    
    // Mark initialization as complete and trigger UI update
    setState(() {
      _isInitialized = true;
    });
  }

  Future<void> _loadToolUsage() async {
    if (!_isEditMode) return;
    setState(() {
      _loadingToolUsage = true;
    });
    try {
      final pbService = PocketBaseService();
      final records = await pbService.getToolUsage(toolId: widget.tool!.id);
      setState(() {
        _toolUsageRecords = records;
        _loadingToolUsage = false;
      });
    } catch (e) {
      setState(() {
        _loadingToolUsage = false;
      });
    }
  }

  Map<String, dynamic> _computeToolUsageStats() {
    // Defensive: hot reload / JS interop can sometimes surface unexpected shapes.
    final items = _toolUsageRecords;
    if (items.isEmpty) {
      return {
        'avgMinutes': null,
        'count': 0,
        'bestMaterial': null,
        'worstMaterial': null,
      };
    }

    int count = 0;
    int totalMinutes = 0;
    int wornCount = 0;
    int brokenCount = 0;

    // last logged usage (newest) - rely on service sort '-used_at' (fallback to created)
    Map<String, dynamic>? lastUsage;

    for (final r in items) {
      try {
        // PocketBase returns RecordModel; but be defensive if we ever get a raw map.
        final dynamic dataDynamic = (r is Map) ? r : r.data;
        if (dataDynamic == null) continue;
        final Map data = (dataDynamic is Map) ? dataDynamic : <String, dynamic>{};
        final mins = (data['minutes_used'] as num?)?.toInt();
        if (mins == null || mins <= 0) continue;
        final materialRaw = data['material'];
        final material = (materialRaw == null) ? '' : materialRaw.toString().trim();
        final outcomeRaw = data['outcome'];
        final outcome = (outcomeRaw == null) ? '' : outcomeRaw.toString().trim().toLowerCase();

        count += 1;
        totalMinutes += mins;
        if (outcome == 'broken') {
          brokenCount += 1;
        } else if (outcome == 'worn') {
          wornCount += 1;
        }

        // First valid record becomes "last usage" (records are already sorted newest->oldest).
        lastUsage ??= {
          'minutes': mins,
          'material': material,
          'outcome': outcome,
          'usedAt': data['used_at'],
          'notes': data['notes'],
        };
      } catch (_) {
        // ignore malformed record
      }
    }

    if (count == 0) {
      return {
        'avgMinutes': null,
        'count': 0,
        'bestMaterial': null,
        'worstMaterial': null,
      };
    }

    final avgMinutes = totalMinutes / count;

    return {
      'avgMinutes': avgMinutes,
      'count': count,
      'wornCount': wornCount,
      'brokenCount': brokenCount,
      'lastUsage': lastUsage,
    };
  }

  Future<void> _showToolUsageHistoryDialog() async {
    if (!_isEditMode) return;
    final materials = _toolUsageRecords
        .map((r) {
          dynamic data;
          try {
            data = r.data;
          } catch (_) {
            data = (r is Map) ? r : null;
          }
          return (data?['material'] ?? '').toString().trim();
        })
        .where((m) => m.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    const allMaterialsValue = '__all_materials__';
    String selectedMaterial = allMaterialsValue;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Tool usage history'),
          content: SizedBox(
            width: 600,
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                final filteredUsage = _toolUsageRecords.where((r) {
                  if (selectedMaterial == allMaterialsValue) return true;
                  dynamic data;
                  try {
                    data = r.data;
                  } catch (_) {
                    data = (r is Map) ? r : null;
                  }
                  final material = (data?['material'] ?? '').toString().trim();
                  return material == selectedMaterial;
                }).toList();
                final validMinutes = filteredUsage
                    .map((r) {
                      dynamic data;
                      try {
                        data = r.data;
                      } catch (_) {
                        data = (r is Map) ? r : null;
                      }
                      return (data?['minutes_used'] as num?)?.toDouble();
                    })
                    .whereType<double>()
                    .where((m) => m > 0)
                    .toList();
                final avgMinutes = validMinutes.isEmpty
                    ? null
                    : (validMinutes.reduce((a, b) => a + b) / validMinutes.length);
                final avgHours = avgMinutes == null ? null : (avgMinutes / 60.0);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (materials.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        value: selectedMaterial,
                        decoration: const InputDecoration(
                          labelText: 'Filter by material',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: allMaterialsValue,
                            child: Text('All materials'),
                          ),
                          ...materials.map(
                            (m) => DropdownMenuItem<String>(
                              value: m,
                              child: Text(m),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            selectedMaterial = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (filteredUsage.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          avgHours == null
                              ? 'Average tool life: —'
                              : 'Average tool life: ${avgHours.toStringAsFixed(2)} hr (${avgMinutes!.toStringAsFixed(1)} min)',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_toolUsageRecords.isEmpty)
                      const Text('No usage logged yet.')
                    else if (filteredUsage.isEmpty)
                      const Text('No usage records match this material filter.')
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: filteredUsage.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final r = filteredUsage[index];
                            dynamic data;
                            try {
                              data = r.data;
                            } catch (_) {
                              data = (r is Map) ? r : null;
                            }
                            final mins = (data?['minutes_used'] as num?)?.toInt();
                            final outcome = (data?['outcome'] ?? '').toString();
                            final material = (data?['material'] ?? '').toString();
                            final usedAtRaw = data?['used_at'];
                            String usedAtStr = '';
                            try {
                              if (usedAtRaw != null && usedAtRaw.toString().isNotEmpty) {
                                usedAtStr = DateFormat.yMMMd().add_jm().format(DateTime.parse(usedAtRaw.toString()));
                              }
                            } catch (_) {}

                            final notes = (data?['notes'] ?? '').toString();
                            return ListTile(
                              title: Text('${mins ?? '—'} mins • $material • ${outcome.isEmpty ? '—' : outcome}'),
                              subtitle: (usedAtStr.isNotEmpty || notes.isNotEmpty)
                                  ? Text([usedAtStr, if (notes.isNotEmpty) notes].where((s) => s.isNotEmpty).join(' • '))
                                  : null,
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showLogToolUsageDialog() async {
    if (!_isEditMode) return;

    final minutesController = TextEditingController();
    final notesController = TextEditingController();
    String outcome = 'worn';
    String material = _toolUsageMaterials.first;
    String? machineId;

    final machines = _allLocations.where((l) => l.type.toLowerCase() == 'machine').toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Log tool usage'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: minutesController,
                  decoration: const InputDecoration(
                    labelText: 'Minutes used',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: outcome,
                  decoration: const InputDecoration(
                    labelText: 'Outcome',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'worn', child: Text('Worn')),
                    DropdownMenuItem(value: 'broken', child: Text('Broken')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    outcome = v;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: material,
                  decoration: const InputDecoration(
                    labelText: 'Material',
                    border: OutlineInputBorder(),
                  ),
                  items: _toolUsageMaterials
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    material = v;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: machineId,
                  decoration: const InputDecoration(
                    labelText: 'Machine (optional)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('—'),
                    ),
                    ...machines.map((m) => DropdownMenuItem<String>(
                          value: m.id,
                          child: Text(m.name),
                        )),
                  ],
                  onChanged: (v) {
                    machineId = v;
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final mins = int.tryParse(minutesController.text.trim());
                if (mins == null || mins <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter minutes used')),
                  );
                  return;
                }
                try {
                  final pbService = PocketBaseService();
                  await pbService.createToolUsage(
                    toolId: widget.tool!.id,
                    minutesUsed: mins,
                    outcome: outcome,
                    material: material,
                    usedAt: DateTime.now(),
                    notes: notesController.text,
                    machineLocationId: machineId,
                  );
                  if (context.mounted) Navigator.pop(context, true);
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    minutesController.dispose();
    notesController.dispose();

    if (saved == true) {
      await _loadToolUsage();
    }
  }

  /// Some categories store the deepest selection both as:
  /// - `subcategory` string (e.g. "Threading > Dixi > M1.0x0.25")
  /// - `attribute_value` field (e.g. "M1.0x0.25")
  ///
  /// The UI button selectors use `_selectedSubcategoryIds[level]` to decide which
  /// button is selected. During edit-mode rehydration, `_selectedSubcategoryIds`
  /// may not always include the deepest `attribute_value` yet.
  ///
  /// This sync ensures the last chain element matches `_selectedAttributeValue`
  /// so the correct button is selected immediately when the attribute list loads.
  void _syncAttributeValueIntoSelectionChain() {
    final tool = widget.tool;
    if (tool == null) return;
    if (_selectedAttributeValue == null) return;

    final subcategoryText = tool.record.data['subcategory']?.toString() ?? '';
    if (subcategoryText.trim().isEmpty) return;

    final parts = subcategoryText
        .split(' > ')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (parts.isEmpty) return;

    final attr = _selectedAttributeValue!.trim();
    final lastPart = parts.last.trim();
    if (attr.isEmpty || lastPart != attr) return;

    final targetIndex = parts.length - 1;
    while (_selectedSubcategoryIds.length <= targetIndex) {
      _selectedSubcategoryIds.add(null);
    }

    _selectedSubcategoryIds[targetIndex] = attr;
    _updateSubcategoryText();
  }
  
  Future<void> _loadSettings() async {
    try {
      final pbService = PocketBaseService();
      final settings = await pbService.getAppSettings();
      setState(() {
        _useCategoryButtons = settings.data['use_category_buttons'] ?? false;
        _enableToolImport = settings.data['enable_tool_import'] ?? false; // NEW
      });
    } catch (e) {
      print('Error loading settings: $e');
      // Default to dropdown if can't load
      setState(() {
        _useCategoryButtons = false;
        _enableToolImport = false; // NEW
      });
    }
  }
  
  // ============================================================================
  // TOOL IMPORT METHODS
  // ============================================================================
  
  Future<void> _importToolSpecs() async {
    // Validate that we have the necessary info
    if (_selectedBrandId == null || _selectedBrandId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a brand first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final modelNumber = _modelNumberController.text.trim();
    final url = _urlController.text.trim();

    if (modelNumber.isEmpty && url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a model number or URL first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // If user entered something in URL, ensure it at least looks like a URL.
    if (url.isNotEmpty &&
        !(url.toLowerCase().startsWith('http://') ||
          url.toLowerCase().startsWith('https://'))) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'That does not look like a valid URL.\n'
              'Please enter the full URL (e.g. https://example.com/your-tool).',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    setState(() {
      _isImporting = true;
    });

    try {
      final pbService = PocketBaseService();
      
      // Get brand info including scraping config
      String? brandName;
      String? urlPattern;
      bool scraperEnabled = false;
      
      try {
        final brand = _brands.firstWhere((b) => b.id == _selectedBrandId);
        brandName = brand.data['name'];
        urlPattern = brand.data['url_pattern'];
        scraperEnabled = brand.data['scraper_enabled'] ?? false;
      } catch (e) {
        throw Exception('Could not find selected brand');
      }
      
      // Ensure brandName is not null
      if (brandName == null || brandName.isEmpty) {
        throw Exception('Brand name is empty');
      }
      
      // Check if scraping is enabled for this brand
      if (!scraperEnabled && url.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Auto-import is not configured for $brandName.\n'
                'Please enter a direct URL or configure scraping in Brand settings.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }
      
      // Check if URL pattern exists when using model number
      if (url.isEmpty && (urlPattern == null || urlPattern.isEmpty)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No URL pattern configured for $brandName.\n'
                'Please enter a direct URL.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Call the import service
      final result = await pbService.importToolSpecs(
        brand: brandName,
        urlPattern: urlPattern,
        modelNumber: modelNumber.isNotEmpty ? modelNumber : null,
        url: url.isNotEmpty ? url : null,
      );

      if (!mounted) return;

      if (result?['success'] == true) {
        final data = result!['data'] as Map<String, dynamic>;
        final sourceUrl = result['source_url'] as String?;

        // Show preview dialog
        final confirmed = await _showImportPreviewDialog(data, sourceUrl);

        if (confirmed == true) {
          // Populate fields with imported data
          _applyImportedData(data, sourceUrl);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Tool specs imported successfully!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        final error = result?['error'] ?? 'Unknown error occurred';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Import failed. Please double-check the URL or model number.\n'
                'Details: $error',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Something went wrong while importing. '
              'Please make sure the URL is correct and try again.',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  Future<bool?> _showImportPreviewDialog(
    Map<String, dynamic> data,
    String? sourceUrl,
  ) async {
    // Check if any existing fields would be overwritten
    final hasExistingData = _diameterInController.text.isNotEmpty ||
        _diameterMmController.text.isNotEmpty ||
        _flutesController.text.isNotEmpty ||
        _fluteLengthController.text.isNotEmpty ||
        _cornerRadController.text.isNotEmpty ||
        _neckController.text.isNotEmpty;

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Tool Specifications'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasExistingData) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This will overwrite existing data',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Text(
                'Imported Data:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              _buildPreviewField('Diameter (in)', data['diameter_in']),
              _buildPreviewField('Flutes', data['flutes']),
              _buildPreviewField('Flute Length', data['flute_length']),
              _buildPreviewField('Overall Length', data['overall_length']),
              _buildPreviewField('Corner Radius', data['corner_rad']),
              _buildPreviewField('Shank Diameter', data['shank_diameter']),
              _buildPreviewField('Neck', data['neck']),
              _buildPreviewField('Coating', data['coating']),
              _buildPreviewField('Material', data['material']),
              if (sourceUrl != null) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Source: $sourceUrl',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewField(String label, dynamic value) {
    final displayValue = value?.toString() ?? 'Not found';
    final isEmpty = value == null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              displayValue,
              style: TextStyle(
                color: isEmpty ? Colors.grey : Colors.black,
                fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _applyImportedData(Map<String, dynamic> data, String? sourceUrl) {
    setState(() {
      // Update numeric fields
      if (data['diameter_in'] != null) {
        final diaIn = data['diameter_in'];
        _diameterInController.text = diaIn.toString();
        // Calculate mm from inches (don't trust extracted mm values)
        _diameterMmController.text = (diaIn * 25.4).toStringAsFixed(2);
      }
      if (data['flutes'] != null) {
        _flutesController.text = data['flutes'].toString();
      }
      if (data['flute_length'] != null) {
        _fluteLengthController.text = data['flute_length'].toString();
      }
      if (data['corner_rad'] != null) {
        _cornerRadController.text = data['corner_rad'].toString();
      }
      if (data['neck'] != null) {
        _neckController.text = data['neck'].toString();
      }

      // Update URL if source was provided and URL field is empty
      if (sourceUrl != null && _urlController.text.isEmpty) {
        _urlController.text = sourceUrl;
      }

      // Note: coating and material fields would need to be added to your form
      // or stored in attribute_values if you want to capture them

      // Trigger tool name update
      _updateToolName();
    });
  }
  
  // ============================================================================
  // END TOOL IMPORT METHODS
  // ============================================================================
  
  Widget _buildCategorySelector() {
    if (_useCategoryButtons) {
      return _buildCategoryButtons();
    } else {
      return _buildCategoryDropdown();
    }
  }
  
  static const _selectorLabelStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w500);

  Widget _buildCategoryDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Category', style: _selectorLabelStyle),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedCategoryId,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
          items: _categories.map((category) {
        return DropdownMenuItem<String>(
          value: category.id,
          child: Text(category.data['name']),
        );
      }).toList(),
      onChanged: (value) async {
        if (value != null) {
          final category = _categories.firstWhere((c) => c.id == value);
          print('DEBUG category dropdown: Selected category ${category.data['name']} with id $value');
          setState(() {
            _selectedCategoryId = value;
            _category = category.data['name'];
            // Clear subcategory selections when category changes
            _selectedSubcategoryIds.clear();
            _selectedAttributeValue = null;
            _updateSubcategoryText();
            _updateToolName();
          });
          // Reload brands and suppliers filtered by new category - pass categoryId directly
          _loadBrandsAndSuppliers(categoryId: value);
        }
      },
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please select a category';
        }
        return null;
      },
        ),
      ],
    );
  }
  
  Widget _buildCategoryButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Category', style: _selectorLabelStyle),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _categories.map((category) {
            final isSelected = _selectedCategoryId == category.id;
            return ElevatedButton(
              onPressed: () async {
                print('DEBUG category button: Selected category ${category.data['name']} with id ${category.id}');
                setState(() {
                  _selectedCategoryId = category.id;
                  _category = category.data['name'];
                  // Clear subcategory selections when category changes
                  _selectedSubcategoryIds.clear();
                  _selectedAttributeValue = null;
                  _updateSubcategoryText();
                  _updateToolName();
                });
                // Reload brands and suppliers filtered by new category - pass categoryId directly
                _loadBrandsAndSuppliers(categoryId: category.id);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isSelected ? Colors.blue : Colors.grey[300],
                foregroundColor: isSelected ? Colors.white : Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              child: Text(category.data['name']),
            );
          }).toList(),
        ),
      ],
    );
  }
  
  void _prefillFields() {
    final tool = widget.tool!;
    // Turn off auto name before filling fields so dimension listeners don't overwrite saved name
    _autoGenerateName = false;
    _toolNameController.text = widget.isDuplicate ? '${tool.toolName} (Copy)' : tool.toolName;
    _modelNumberController.text = tool.modelNumber ?? '';
    _urlController.text = tool.url ?? '';
    
    // Ensure category exists (default to Cutting Tools)
    _category = tool.category.isNotEmpty ? tool.category : 'Cutting Tools';
    
    // Load subcategories and try to match existing values
    // This will be handled after subcategories are loaded
    _subcategory = tool.subcategory;
    _subSubcategory = tool.subSubcategory;
    
    // Safely get attribute_value from record
    if (tool.record != null && tool.record.data != null) {
      _selectedAttributeValue = tool.record.data['attribute_value'];
    } else {
      _selectedAttributeValue = null;
    }
    
    // Don't set brand/supplier until they're loaded
    // Will be validated in _loadBrandsAndSuppliers if valid
    print('DEBUG _prefillFields: tool.brandId = ${tool.brandId}, tool.supplierId = ${tool.supplierId}');
    if (tool.brandId != null && tool.brandId!.isNotEmpty) {
      _selectedBrandId = tool.brandId;
      _selectedBrandName = tool.brand;
      print('DEBUG _prefillFields: Set _selectedBrandId = $_selectedBrandId, _selectedBrandName = $_selectedBrandName');
    }
    if (tool.supplierId != null && tool.supplierId!.isNotEmpty) {
      _selectedSupplierId = tool.supplierId;
      _selectedSupplierName = tool.supplier;
      print('DEBUG _prefillFields: Set _selectedSupplierId = $_selectedSupplierId');
    }
    
    if (tool.diameterIn != null) {
      _diameterInController.text = tool.diameterIn.toString();
    }
    if (tool.diameterMm != null) {
      _diameterMmController.text = tool.diameterMm.toString();
    }
    if (tool.flutes != null) {
      _flutesController.text = tool.flutes.toString();
    }
    if (tool.fluteLength != null) {
      _fluteLengthController.text = tool.fluteLength.toString();
    }
    if (tool.cornerRad != null) {
      _cornerRadController.text = tool.cornerRad.toString();
    }
    if (tool.neck != null) {
      _neckController.text = tool.neck.toString();
    }
    // Load T-slot radius, chamfer angle, chamfer tip diameter
    if (tool.record != null && tool.record.data != null) {
      final drillAngle = tool.record.data['drill_included_angle'];
      if (drillAngle != null) {
        _drillIncludedAngleController.text = drillAngle.toString();
      }
      final tslotRadius = tool.record.data['tslot_radius'];
      if (tslotRadius != null) {
        _tslotRadiusController.text = tslotRadius.toString();
      }
      final chamferAngle = tool.record.data['chamfer_angle'];
      if (chamferAngle != null) {
        _chamferAngleController.text = chamferAngle.toString();
      }
      final chamferTip = tool.record.data['chamfer_tip_diameter'];
      if (chamferTip != null) {
        _chamferTipDiameterController.text = chamferTip.toString();
      }
    }
    if (tool.record != null && tool.record.data != null) {
      final n = tool.record.data['notes'];
      _notesController.text = n != null ? n.toString() : '';

      _needsRestock = tool.record.data['needs_restock'] == true;
      final rq = tool.record.data['restock_qty'];
      _restockQtyController.text = (rq == null) ? '' : rq.toString();
      final rn = tool.record.data['restock_notes'];
      _restockNotesController.text = rn == null ? '' : rn.toString();
    }
    
    // Load photo if exists
    if (tool.photo != null && tool.photo!.isNotEmpty) {
      final pbService = PocketBaseService();
      _photoUrl = pbService.pb.files.getUrl(
        tool.record,
        tool.photo!,
      ).toString();
    }
  }
  
  Future<void> _loadToolLocations() async {
    try {
      final pbService = PocketBaseService();
      final locationRecords = await pbService.getLocations();
      _allLocations = locationRecords.map((r) => Location.fromRecord(r)).toList();
      
      final toolLocationRecords = await pbService.pb
          .collection('tool_locations')
          .getFullList(
            filter: 'tool = "${widget.tool!.id}"',
            expand: 'location',
          );
      
      setState(() {
        _toolLocations = toolLocationRecords
            .map((r) => ToolLocation.fromRecord(r))
            .toList();
      });
    } catch (e) {
      print('Error loading tool locations: $e');
    }
  }
  
  // NEW: Load recent history for the tool
  Future<void> _loadRecentHistory() async {
    if (!_isEditMode) return;
    
    setState(() {
      _loadingHistory = true;
    });
    
    try {
      final pbService = PocketBaseService();
      final historyRecords = await pbService.getInventoryHistory(
        toolId: widget.tool!.id,
        limit: 5,
      );
      
      setState(() {
        _recentHistory = historyRecords
            .map((r) => InventoryHistory.fromRecord(r))
            .toList();
        _loadingHistory = false;
      });
    } catch (e) {
      print('Error loading history: $e');
      setState(() {
        _loadingHistory = false;
      });
    }
  }

  Future<void> _loadPurchaseHistory() async {
    if (!_isEditMode) return;

    setState(() {
      _loadingPurchaseHistory = true;
    });

    try {
      final pbService = PocketBaseService();
      final records = await pbService.getPurchaseItemsByTool(widget.tool!.id);
      setState(() {
        _purchaseHistoryRecords = records;
        _loadingPurchaseHistory = false;
      });
    } catch (e) {
      print('Error loading purchase history: $e');
      setState(() {
        _loadingPurchaseHistory = false;
      });
    }
  }
  
  Future<void> _loadLocations() async {
    try {
      final pbService = PocketBaseService();
      final locations = await pbService.getLocations();
      setState(() {
        _locations = locations;
      });
    } catch (e) {
      print('Error loading locations: $e');
    }
  }
  
  Future<void> _loadSubcategories() async {
    try {
      final pbService = PocketBaseService();
      final subcategories = await pbService.getSubcategories();
      setState(() {
        _allSubcategories = subcategories;
        // Note: _matchSubcategoryNamesToIds() is now called explicitly in _initializeScreen()
      });
    } catch (e) {
      print('Error loading subcategories: $e');
    }
  }

  void _matchSubcategoryNamesToIds() {
    // Try to find subcategories by name and build the selection chain
    _selectedSubcategoryIds.clear();
    _subcategoryTextValues.clear();
    _subcategoryNumberValues.clear();
    
    if (_selectedCategoryId == null) return;
    
    // Parse the full subcategory text (e.g., "PLA > Black" for independent attributes)
    final subcategoryText = widget.tool?.record?.data['subcategory'] ?? '';
    if (subcategoryText.isEmpty) return;
    
    print('DEBUG _matchSubcategoryNamesToIds: Parsing subcategoryText = "$subcategoryText"');
    final parts = subcategoryText.split(' > ');
    print('DEBUG _matchSubcategoryNamesToIds: Split into ${parts.length} parts: $parts');
    
    // Get top-level subcategories
    final topLevel = _allSubcategories.where((s) =>
      s.data['category'] == _selectedCategoryId &&
      (s.data['parent_subcategory'] == null || s.data['parent_subcategory'] == '')
    ).toList();
    
    if (topLevel.isEmpty) return;
    
    // Sort by sort_order to ensure consistent ordering
    topLevel.sort((a, b) => (a.data['sort_order'] ?? 0).compareTo(b.data['sort_order'] ?? 0));
    
    // Check if we have multiple independent subcategories (all with attribute lists)
    final allHaveAttributeLists = topLevel.every((sub) {
      final attrList = sub.data['attribute_list'];
      return attrList != null && attrList.toString().isNotEmpty;
    });

    // Special-case: drills are selected as:
    //   Drills (type) > Carbide/HSS (style) > Fractional/Metric/Wire/Letter (standard as attribute value)
    //
    // The "multiple independent subcategories" logic below incorrectly treats the last part
    // ("Fractional", etc.) as if it were a *subcategory id*, which breaks edit-mode
    // rehydration of the Standard selector.
    final normalized0 = parts.isNotEmpty ? parts[0].trim().toLowerCase() : '';
    final normalized1 = parts.length > 1 ? parts[1].trim().toLowerCase() : '';
    if (normalized0 == 'drills' &&
        (normalized1 == 'carbide' || normalized1 == 'hss') &&
        parts.length >= 3) {
      dynamic firstLevelSub;
      for (final s in topLevel) {
        final n = (s.data['name'] ?? '').toString().trim().toLowerCase();
        if (n == normalized0) {
          firstLevelSub = s;
          break;
        }
      }

      if (firstLevelSub != null) {
        dynamic secondLevelSub;
        for (final s in _allSubcategories) {
          final parentOk = s.data['parent_subcategory'] == firstLevelSub.id;
          final n = (s.data['name'] ?? '').toString().trim().toLowerCase();
          if (parentOk && n == normalized1) {
            secondLevelSub = s;
            break;
          }
        }

        if (secondLevelSub != null) {
          _selectedSubcategoryIds.add(firstLevelSub.id);
          _selectedSubcategoryIds.add(secondLevelSub.id);
          _selectedAttributeValue = parts[2]; // Fractional/Metric/Wire/Letter
          // Attribute-value selectors (Wire/Letter/Fractional/Metric) render "isSelected"
          // by comparing _selectedSubcategoryIds[level] to the attribute value.
          // If we don't also place the attribute value into the selector stack,
          // the Standard buttons won't appear selected on edit—even though it will
          // still save correctly via _selectedAttributeValue/_subcategoryText.
          _selectedSubcategoryIds.add(parts[2]);
          _updateSubcategoryText();
          return;
        }
      }
    }
    
    if (allHaveAttributeLists && topLevel.length > 1 && parts.length >= topLevel.length) {
      // Multiple independent subcategories - map each part to corresponding subcategory
      print('DEBUG _matchSubcategoryNamesToIds: Multiple independent subcategories detected');
      for (int i = 0; i < topLevel.length; i++) {
        if (i < parts.length) {
          // Store the attribute value at this level
          _selectedSubcategoryIds.add(parts[i]);
          _selectedAttributeValue = parts[i]; // Store last value
          print('DEBUG _matchSubcategoryNamesToIds: Set attribute value at level $i: "${parts[i]}"');
        }
      }
    } else {
      // Single or hierarchical subcategories - use original logic
      _matchSubcategoryHierarchical(topLevel, parts);
    }
    
    _updateSubcategoryText();
  }
  
  void _matchSubcategoryHierarchical(List<dynamic> topLevel, List<String> parts) {
    // Original hierarchical matching logic
    // Find first level subcategory using parts[0]
    final firstLevel = topLevel.where((s) => s.data['name'] == parts[0]).toList();
    
    if (firstLevel.isNotEmpty) {
      final firstLevelSub = firstLevel.first;
      final hasChildren = _allSubcategories.any((s) => s.data['parent_subcategory'] == firstLevelSub.id);
      final hasAttributeList = firstLevelSub.data['attribute_list'] != null && 
                               firstLevelSub.data['attribute_list'].toString().isNotEmpty;
      
      print('DEBUG _matchSubcategoryNamesToIds: Found first level subcategory "${firstLevelSub.data['name']}" with ID ${firstLevelSub.id}');
      print('DEBUG _matchSubcategoryNamesToIds: hasChildren = $hasChildren, hasAttributeList = $hasAttributeList, parts.length = ${parts.length}');

      // Special-case: parent has multiple leaf children where each leaf has an
      // attribute_list. In this case, saved `subcategory` may look like:
      //   "PLA > <childAttrValue1> > <childAttrValue2>"
      // so we map parts[1..] directly into `_selectedSubcategoryIds`
      // slots (attribute values), rather than trying to match subcategory names.
      if (hasChildren) {
        final childCandidates = _allSubcategories
            .where((s) => s.data['parent_subcategory'] == firstLevelSub.id)
            .toList()
          ..sort((a, b) => (a.data['sort_order'] ?? 0).compareTo(b.data['sort_order'] ?? 0));

        final leafChildren = childCandidates.where((child) {
          final hasKids = _allSubcategories.any((s) => s.data['parent_subcategory'] == child.id);
          return !hasKids;
        }).toList()
          ..sort((a, b) => (a.data['sort_order'] ?? 0).compareTo(b.data['sort_order'] ?? 0));

        final allLeafChildrenHaveAttributeLists = leafChildren.isNotEmpty &&
            leafChildren.every((child) {
              final attrListId = child.data['attribute_list'];
              return attrListId != null && attrListId.toString().isNotEmpty;
            });

        if (leafChildren.length > 1 &&
            allLeafChildrenHaveAttributeLists &&
            parts.length == 1 + leafChildren.length) {
          _selectedSubcategoryIds.add(firstLevelSub.id);
          for (int j = 0; j < leafChildren.length; j++) {
            final attrValue = parts[j + 1];
            _selectedSubcategoryIds.add(attrValue);
            _selectedAttributeValue = attrValue; // keep last selected
          }
          return;
        }
      }
      
      // Leaf subcategory with attribute_list (e.g. Drills > SC): keep subcategory ID + attribute
      if (hasAttributeList && !hasChildren && parts.length > 1) {
        _selectedSubcategoryIds.add(firstLevelSub.id);
        _selectedAttributeValue = parts[1];
        print(
            'DEBUG _matchSubcategoryNamesToIds: Leaf+attr level 0: id=${firstLevelSub.id}, attr="${parts[1]}"');
      } else if (hasAttributeList && !hasChildren && parts.length == 1) {
        _selectedSubcategoryIds.add(firstLevelSub.id);
        print(
            'DEBUG _matchSubcategoryNamesToIds: Leaf+attr, subcategory only (attribute from record)');
      } else if (!hasChildren && !hasAttributeList && parts.length > 1) {
        // This is a dynamic text value (like "Black" in "Color > Black" when Color has no attribute list)
        _selectedSubcategoryIds.add(firstLevelSub.id);
        _subcategoryTextValues[1] = parts[1];
        print('DEBUG _matchSubcategoryNamesToIds: Set dynamic text value at level 1: "${parts[1]}"');
      } else {
        // Regular subcategory selection (has children or no value specified)
        _selectedSubcategoryIds.add(firstLevelSub.id);
        print('DEBUG _matchSubcategoryNamesToIds: Set subcategory ID at level 0: ${firstLevelSub.id}');
        
        // If there's a second part, process child subcategories
        if (parts.length > 1) {
          final secondLevel = _allSubcategories.where((s) =>
            s.data['parent_subcategory'] == firstLevelSub.id &&
            s.data['name'] == parts[1]
          ).toList();
          
          if (secondLevel.isNotEmpty) {
            final secondLevelSub = secondLevel.first;
            final hasChildren2 = _allSubcategories.any((s) => s.data['parent_subcategory'] == secondLevelSub.id);
            final hasAttributeList2 = secondLevelSub.data['attribute_list'] != null && 
                                     secondLevelSub.data['attribute_list'].toString().isNotEmpty;
            
            print('DEBUG _matchSubcategoryNamesToIds: Found second level subcategory "${secondLevelSub.data['name']}" with ID ${secondLevelSub.id}');
            
            // If child has attribute_list and there's a value, store the VALUE
            if (hasAttributeList2 && parts.length > 2) {
              // The attribute value (e.g., "Fractional") should be stored in _selectedAttributeValue,
              // while the deepest selected subcategory at this level should remain the subcategory ID.
              // Otherwise, edit-mode rehydration breaks attribute selectors (deepestValue isn't a subcategory ID).
              _selectedSubcategoryIds.add(secondLevelSub.id);
              _selectedAttributeValue = parts[2];
              print('DEBUG _matchSubcategoryNamesToIds: Set attribute value at level 1: "${parts[2]}" (subcategory id: ${secondLevelSub.id})');
            } else if (hasAttributeList2 && parts.length == 2) {
              // Child has attribute_list but no value saved (old data format)
              _selectedSubcategoryIds.add(null);
              print('DEBUG _matchSubcategoryNamesToIds: Child subcategory has attribute_list but no value saved - adding null placeholder');
            } else if (!hasChildren2 && !hasAttributeList2 && parts.length > 2) {
              // Dynamic text value at level 2
              _selectedSubcategoryIds.add(secondLevelSub.id);
              _subcategoryTextValues[2] = parts[2];
              print('DEBUG _matchSubcategoryNamesToIds: Set dynamic text value at level 2: "${parts[2]}"');
            } else {
              // Regular child subcategory
              _selectedSubcategoryIds.add(secondLevelSub.id);
              print('DEBUG _matchSubcategoryNamesToIds: Set subcategory ID at level 1: ${secondLevelSub.id}');
            }
          }
        }
      }
    } else {
      print('DEBUG _matchSubcategoryNamesToIds: Could not find first level subcategory "${parts[0]}"');
    }
  }

  Future<void> _loadBrandsAndSuppliers({String? categoryId, bool preserveSelections = false}) async {
    try {
      final pbService = PocketBaseService();
      // Use provided categoryId or fall back to _selectedCategoryId
      final filterCategoryId = categoryId ?? _selectedCategoryId;
      print('DEBUG _loadBrandsAndSuppliers: filterCategoryId = $filterCategoryId, _selectedCategoryId = $_selectedCategoryId, preserveSelections = $preserveSelections');
      
      // Store current selections if preserving
      final preservedBrandId = preserveSelections ? _selectedBrandId : null;
      final preservedSupplierId = preserveSelections ? _selectedSupplierId : null;
      
      // Filter brands and suppliers by selected category
      final brands = await pbService.getBrands(categoryId: filterCategoryId);
      final suppliers = await pbService.getSuppliers(categoryId: filterCategoryId);
      print('DEBUG _loadBrandsAndSuppliers: Loaded ${brands.length} brands, ${suppliers.length} suppliers');
      
      setState(() {
        _brands = brands;
        _suppliers = suppliers;
        
        // Validate that selected IDs exist in the filtered lists
        if (_selectedBrandId != null && _selectedBrandId!.isNotEmpty) {
          final brandExists = brands.any((b) => b.id == _selectedBrandId);
          if (brandExists) {
            final brand = brands.firstWhere((b) => b.id == _selectedBrandId);
            print('DEBUG _loadBrandsAndSuppliers: Found brand ${brand.data['name']} for ID $_selectedBrandId');
          } else {
            print('DEBUG _loadBrandsAndSuppliers: Brand with ID $_selectedBrandId not found in filtered list');
            // If not preserving selections, clear the ID
            if (!preserveSelections || preservedBrandId == null) {
              _selectedBrandId = null;
            }
          }
        }
        
        if (_selectedSupplierId != null && _selectedSupplierId!.isNotEmpty) {
          final supplierExists = suppliers.any((s) => s.id == _selectedSupplierId);
          if (supplierExists) {
            final supplier = suppliers.firstWhere((s) => s.id == _selectedSupplierId);
            _selectedSupplierName = supplier.data['company_name'] as String?;
            print('DEBUG _loadBrandsAndSuppliers: Found supplier ${_selectedSupplierName} for ID $_selectedSupplierId');
          } else {
            print('DEBUG _loadBrandsAndSuppliers: Supplier with ID $_selectedSupplierId not found in filtered list');
            // If not preserving selections, clear the ID
            if (!preserveSelections || preservedSupplierId == null) {
              _selectedSupplierId = null;
              _selectedSupplierName = null;
            }
          }
        }
      });
    } catch (e) {
      print('Error loading brands/suppliers: $e');
    }
  }
  
  Future<void> _loadCategories() async {
    try {
      final pbService = PocketBaseService();
      final categories = await pbService.getCategories();
      setState(() {
        _categories = categories;
        
        // If editing/duplicating, find the category by name
        if (widget.tool != null && categories.isNotEmpty) {
          final toolCategory = widget.tool!.category;
          final matchingCategory = categories.where(
            (c) => c.data['name'] == toolCategory,
          );
          
          if (matchingCategory.isNotEmpty) {
            _selectedCategoryId = matchingCategory.first.id;
            _category = matchingCategory.first.data['name'];
          } else {
            // Category doesn't exist, default to Cutting Tools or first
            final cuttingTools = categories.where(
              (c) => c.data['name'] == 'Cutting Tools',
            );
            if (cuttingTools.isNotEmpty) {
              _selectedCategoryId = cuttingTools.first.id;
              _category = cuttingTools.first.data['name'];
            } else {
              _selectedCategoryId = categories.first.id;
              _category = categories.first.data['name'];
            }
          }
          
          // After setting category, try to match subcategories if they're loaded
          if (_allSubcategories.isNotEmpty) {
            _matchSubcategoryNamesToIds();
          }
        } else if (_selectedCategoryId == null && categories.isNotEmpty) {
          // New tool - check for initialCategory first, otherwise default to "Cutting Tools"
          if (widget.initialCategory != null) {
            // Find the initialCategory in the list
            final matchingCategory = categories.where(
              (c) => c.data['name'] == widget.initialCategory,
            );
            if (matchingCategory.isNotEmpty) {
              _selectedCategoryId = matchingCategory.first.id;
              _category = matchingCategory.first.data['name'];
            } else {
              // initialCategory not found, fallback to Cutting Tools or first
              final cuttingTools = categories.where(
                (c) => c.data['name'] == 'Cutting Tools',
              );
              if (cuttingTools.isNotEmpty) {
                _selectedCategoryId = cuttingTools.first.id;
                _category = cuttingTools.first.data['name'];
              } else {
                _selectedCategoryId = categories.first.id;
                _category = categories.first.data['name'];
              }
            }
          } else {
            // No initialCategory - default to "Cutting Tools" if it exists
            final cuttingTools = categories.where(
              (c) => c.data['name'] == 'Cutting Tools',
            );
            if (cuttingTools.isNotEmpty) {
              _selectedCategoryId = cuttingTools.first.id;
              _category = cuttingTools.first.data['name'];
            } else {
              _selectedCategoryId = categories.first.id;
              _category = categories.first.data['name'];
            }
          }
        }
      });
      
      // After categories are loaded and _selectedCategoryId is set, reload brands/suppliers with the category filter
      if (_selectedCategoryId != null) {
        print('DEBUG _loadCategories: Category loaded, reloading brands/suppliers with categoryId = $_selectedCategoryId');
        // When editing, preserve existing brand/supplier selections
        _loadBrandsAndSuppliers(categoryId: _selectedCategoryId, preserveSelections: widget.tool != null);
      }
    } catch (e) {
      print('Error loading categories: $e');
    }
  }
  
  void _scheduleToolNameUpdate() {
    if (!_autoGenerateName) return;
    
    final newName = _generateToolName();
    if (newName != _toolName) {
      setState(() {
        _toolName = newName;
      });
      // Only overwrite controller when we have a generated name (Cutting Tools).
      // For other categories _generateToolName() returns ''; don't clear user input.
      if (newName.isNotEmpty) {
        _toolNameController.text = newName;
      }
    }
  }
  
  void _updateToolName() {
    if (!_autoGenerateName) return;
    
    final newName = _generateToolName();
    setState(() {
      _toolName = newName;
    });
    // Only overwrite controller when we have a generated name (Cutting Tools).
    // For other categories _generateToolName() returns ''; don't clear user input.
    if (newName.isNotEmpty) {
      _toolNameController.text = newName;
    }
  }

  String _formatThreeDecimal(double value) {
    // Truncate to 3 decimals (no rounding)
    double truncated = (value * 1000).floorToDouble() / 1000;
    String s = truncated.toStringAsFixed(3); // e.g. "0.010", "0.140", "0.105"

    // If there are more than 2 decimal places and the last digit is 0,
    // drop the last digit so we show 2 decimals instead of 3.
    final dotIndex = s.indexOf('.');
    if (dotIndex != -1) {
      final decimals = s.length - dotIndex - 1;
      if (decimals > 2 && s.endsWith('0')) {
        s = s.substring(0, s.length - 1); // "0.010" -> "0.01"
      }
    }

    // Remove leading zero for values < 1: "0.01" -> ".01"
    if (s.startsWith('0.')) {
      s = s.substring(1);
    }

    return s;
  }

  /// Canonical diameter key used for Drill Standard lookup + naming.
  /// Rules (no rounding):
  /// - < 0.125"  => truncate to 4 decimals
  /// - >= 0.125" => truncate to 3 decimals
  /// Then: trim trailing zeros and strip leading `0` for values < 1.
  String _formatDrillDiameterKey(double valueInInches) {
    // Small epsilon to reduce cases where binary floating error makes values
    // like 0.0100 turn into 0.009999... during multiplication+floor.
    const double epsilon = 1e-9;
    final bool under125 = valueInInches < 0.125;
    final double factor = under125 ? 10000.0 : 1000.0;
    final int decimals = under125 ? 4 : 3;

    final double truncated =
        ((valueInInches * factor) + epsilon).floorToDouble() / factor;

    String s = truncated.toStringAsFixed(decimals); // includes leading 0 for < 1
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      if (s.endsWith('.')) {
        s = s.substring(0, s.length - 1);
      }
    }
    if (s.startsWith('0.')) {
      s = s.substring(1);
    }
    // If it became an integer (e.g. "1"), keep one decimal place for naming consistency.
    if (!s.contains('.')) {
      s = '${s}.0';
    }
    return s;
  }

  /// Flute length formatting for drills.
  /// - truncate (no rounding) to max 2 decimals
  /// - trim trailing zeros
  /// - keep at least one decimal digit (so 1.00 => 1.0)
  /// - strip leading `0` for values < 1
  String _formatDrillFluteLength(double valueInInches) {
    const double epsilon = 1e-9;
    final double truncated = ((valueInInches * 100.0) + epsilon).floorToDouble() / 100.0;

    String s = truncated.toStringAsFixed(2); // always has 2 decimals first
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      if (s.endsWith('.')) {
        s = s.substring(0, s.length - 1);
      }
    }

    // Ensure we still show a decimal point for whole numbers (1.0FL requirement).
    if (!s.contains('.')) {
      s = '${s}.0';
    }

    if (s.startsWith('0.')) {
      s = s.substring(1);
    }
    return s;
  }

  /// Metric token (in->mm) for Drill Standard naming.
  /// - round to 2 decimals
  /// - trim trailing zeros
  /// - append `MM`
  String _formatDrillMetricToken(double diameterInInches) {
    final mm = diameterInInches * 25.4;
    final rounded = (mm * 100.0).roundToDouble() / 100.0;
    String mmStr = rounded.toStringAsFixed(2);

    if (mmStr.contains('.')) {
      mmStr = mmStr.replaceFirst(RegExp(r'0+$'), '');
      if (mmStr.endsWith('.')) {
        mmStr = mmStr.substring(0, mmStr.length - 1);
      }
    }

    return '${mmStr}MM';
  }

  /// Extract selected Drill Standard type from the built subcategory chain.
  /// Expected values: Fractional, Metric, Wire, Letter.
  String? _getSelectedDrillStandardType() {
    if (_subcategoryText.isEmpty) return null;

    final parts = _subcategoryText
        .split(' > ')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);

    for (final part in parts) {
      final p = part.toLowerCase();
      if (p == 'fractional') return 'Fractional';
      if (p == 'metric') return 'Metric';
      if (p == 'wire') return 'Wire';
      if (p == 'letter') return 'Letter';
    }
    return null;
  }

  /// Extract selected Drill Style token from the built subcategory chain.
  /// UI shows "Carbide" or "HSS".
  /// Naming token expects "SC" for solid carbide, otherwise "HSS".
  String? _getSelectedDrillStyleToken() {
    if (_subcategoryText.isEmpty) return null;

    final parts = _subcategoryText
        .split(' > ')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);

    for (final part in parts) {
      final p = part.toLowerCase();
      if (p == 'carbide') return 'SC';
      if (p == 'hss') return 'HSS';
    }
    return null;
  }

  /// Top-level Cutting Tools type is "Drills" (leaf + SC/HSS attribute).
  bool _isDrillsToolType() {
    if (_category != 'Cutting Tools' || _selectedSubcategoryIds.isEmpty) {
      return false;
    }
    final first = _selectedSubcategoryIds[0];
    if (first == null || first.isEmpty) return false;
    try {
      final sub = _allSubcategories.firstWhere((s) => s.id == first);
      return sub.data['name'] == 'Drills';
    } catch (_) {
      return false;
    }
  }

  String _generateToolName() {
    // Only auto-generate names for Cutting Tools category
    if (_category != 'Cutting Tools') {
      return '';
    }

    final diaIn = double.tryParse(_diameterInController.text);
    final fluteLen = double.tryParse(_fluteLengthController.text);

    // Drills: DIA_FLUTELENGTHFL_MATERIAL e.g. .125_.75FL_SC
    if (_isDrillsToolType()) {
      final style = _getSelectedDrillStyleToken() ?? '';
      if (diaIn == null || fluteLen == null || style.isEmpty) {
        return '';
      }

      final String diaStr = _formatDrillDiameterKey(diaIn);
      final String flStr = _formatDrillFluteLength(fluteLen);

      final standardType = _getSelectedDrillStandardType();
      if (standardType == null) return '';

      // Build: {dia}_{optionalStandard}_{fluteLen}FL_{style}
      if (standardType == 'Fractional') {
        return '${diaStr}_${flStr}FL_$style';
      }

      late final String standardToken;
      switch (standardType) {
        case 'Metric':
          standardToken = _formatDrillMetricToken(diaIn);
          break;
        case 'Wire':
          standardToken = _WIRE_BY_INCH_DIAMETER[diaStr] ?? '';
          break;
        case 'Letter':
          standardToken = _LETTER_BY_INCH_DIAMETER[diaStr] ?? '';
          break;
        case 'Fractional':
          // handled above
          standardToken = '';
          break;
        default:
          standardToken = '';
          break;
      }

      if (standardToken.isEmpty) return '';
      return '${diaStr}_${standardToken}_${flStr}FL_$style';
    }

    final flutes = int.tryParse(_flutesController.text);
    final cornerRad = double.tryParse(_cornerRadController.text);
    final neck = double.tryParse(_neckController.text);

    if (diaIn == null || flutes == null || fluteLen == null) {
      return '';
    }
    
    final String diaStr = _formatDrillDiameterKey(diaIn);
    
    // Format flute length: up to 3 decimals, but drop trailing zero
    // so 1.00 => 1.0, .030 => .03
    final String flStr = _formatDrillFluteLength(fluteLen);
    
    String name = '${diaStr}_${flutes}F_${flStr}FL';
    
    // Corner radius in name: required semantics for CR; optional for Special
    if (cornerRad != null &&
        cornerRad > 0 &&
        (_subSubcategory == 'CR' || _subSubcategory == 'Special')) {
      final String crStr = _formatDrillDiameterKey(cornerRad);
      name += '_${crStr}CR';
    }
    
    // Only include neck radius if there's a value (independent of type)
    if (neck != null && neck > 0) {
      final String neckStr = _formatDrillDiameterKey(neck);
      name += '_${neckStr}NR';
    }
    
    // T-slot radius (optional - only if filled)
    if (_subSubcategory == 'Tslot') {
      final tslotRadius = double.tryParse(_tslotRadiusController.text);
      if (tslotRadius != null && tslotRadius > 0) {
        final String tsrStr = _formatDrillDiameterKey(tslotRadius);
        // Use CR suffix for the T-slot radius to match naming semantics.
        name += '_${tsrStr}CR';
      }
    }
    
    // Chamfer angle and tip diameter
    if (_subSubcategory == 'Chamfer') {
      final chamferAngle = double.tryParse(_chamferAngleController.text);
      final chamferTip = double.tryParse(_chamferTipDiameterController.text);
      
      if (chamferAngle != null) {
        // Angle as integer (e.g., 45, 60, 90)
        name += '_${chamferAngle.toInt()}DEG';
      }
      
      if (chamferTip != null && chamferTip > 0) {
        final String tipStr = _formatDrillDiameterKey(chamferTip);
        name += '_${tipStr}TIP';
      }
    }
    
    // Add type suffix for Ball, Tslot, Chamfer, Special
    if (_subSubcategory == 'Ball') {
      name += '_BALL';
    } else if (_subSubcategory == 'Tslot') {
      // Use shortened T-slot suffix.
      name += '_TS';
    } else if (_subSubcategory == 'Chamfer') {
      name += '_CHAMFER';
    } else if (_subSubcategory == 'Special') {
      name += '_SPECIAL';
    }
    
    return name;
  }
  
  void _onDiameterInChanged(String value) {
    final diaIn = double.tryParse(value);
    if (diaIn != null) {
      _diameterMmController.text = (diaIn * 25.4).toStringAsFixed(2);
    }
  }
  
  void _onDiameterMmChanged(String value) {
    final diaMm = double.tryParse(value);
    if (diaMm != null) {
      // Metric-to-inch conversion is used for drill naming too.
      // We want "no rounding" and more precision than 3 decimals.
      // Example: 2mm => 0.0787... (not 0.079).
      final diaIn = diaMm / 25.4;
      const epsilon = 1e-9;
      final truncated = ((diaIn * 10000.0) + epsilon).floorToDouble() / 10000.0;
      _diameterInController.text = truncated.toStringAsFixed(4);
    }
  }
  
  Future<void> _pickPhoto() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.first;
      final bytes = picked.bytes ?? await picked.readAsBytes();
      if (!mounted || bytes.isEmpty) return;

      setState(() {
        _photoBytes = bytes;
        _photoChanged = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking photo: $e')),
      );
    }
  }
  
  Future<void> _extractFromUrl() async {
    final pageUrl = _urlController.text.trim();
    if (pageUrl.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a product URL in the URL field first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final lower = pageUrl.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL must start with http:// or https://'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Loading images from page…'),
                  const SizedBox(height: 16),
                  const CircularProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final pb = PocketBaseService();
    late final Map<String, dynamic> result;
    try {
      result = await pb.extractPageImages(pageUrl);
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (!mounted) return;
    if (result['success'] != true) {
      final err = result['error']?.toString() ?? 'Could not load images.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: Colors.red),
      );
      return;
    }

    final raw = result['images'];
    if (raw is! List || raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No images found on this page.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final imageUrls = raw.map((e) => e.toString()).toList();

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => _PageImagePickerDialog(imageUrls: imageUrls),
    );

    if (!mounted || selected == null) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Downloading image…'),
                  const SizedBox(height: 16),
                  const CircularProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Uint8List? bytes;
    try {
      bytes = await pb.fetchImageBytesViaMcp(selected);
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not download that image. Try another.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _photoBytes = bytes;
      _photoChanged = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Image selected. Save the tool to keep it.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _openCurrentUrl() async {
    final raw = _urlController.text.trim();
    if (raw.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a URL first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final uri = Uri.tryParse(raw);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL must start with http:// or https://'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open URL.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  Future<void> _showAddInventoryDialog() async {
    print('DEBUG: _showAddInventoryDialog called');
    print('DEBUG: _isEditMode = $_isEditMode');
    print('DEBUG: widget.tool = ${widget.tool?.toolName}');
    print('DEBUG: widget.isDuplicate = ${widget.isDuplicate}');
    
    final pbService = PocketBaseService();
    
    // For edit mode, get existing locations
    List<ToolLocation>? existingLocations;
    List<String>? historicalLocationIds;
    
    if (_isEditMode) {
      existingLocations = _toolLocations;
      print('DEBUG: _toolLocations count: ${_toolLocations.length}');
      for (var tl in _toolLocations) {
        print('DEBUG: Location ${tl.location?.name ?? "null"}, qty: ${tl.quantity}');
      }
      
      // NEW: Get historical add locations
      historicalLocationIds = await pbService.getHistoricalAddLocations(
        toolId: widget.tool!.id,
        limit: 3,
      );
      print('DEBUG: Historical location IDs: $historicalLocationIds');
    } else {
      print('DEBUG: NOT in edit mode - no existing locations');
    }
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AddInventoryDialog(
        allLocations: _locations,
        existingLocations: existingLocations,
        historicalLocationIds: historicalLocationIds, // NEW
      ),
    );
    
    if (result != null) {
      if (_isEditMode) {
        // Edit mode: Add inventory immediately WITH HISTORY LOGGING
        try {
          final pbService = PocketBaseService();
          
          // Get current quantity before adding
          final quantityBefore = await pbService.getCurrentQuantityAtLocation(
            toolId: widget.tool!.id,
            locationId: result['locationId'],
          );
          
          // Check if tool_location already exists at this location
          final existingRecords = await pbService.pb
              .collection('tool_locations')
              .getFullList(
                filter: 'tool = "${widget.tool!.id}" && location = "${result['locationId']}"',
              );
          
          if (existingRecords.isNotEmpty) {
            // Update existing record
            final existingRecord = existingRecords.first;
            final newQuantity = quantityBefore + (result['quantity'] as int);
            await pbService.pb.collection('tool_locations').update(
              existingRecord.id,
              body: {'quantity': newQuantity},
            );
          } else {
            // Create new record
            await pbService.createToolLocation(
              toolId: widget.tool!.id,
              locationId: result['locationId'],
              quantity: result['quantity'] as int,
            );
          }
          
          // Log history
          await pbService.logInventoryHistory(
            toolId: widget.tool!.id,
            locationId: result['locationId'],
            action: 'add',
            quantity: result['quantity'] as int,
            quantityBefore: quantityBefore,
            quantityAfter: quantityBefore + (result['quantity'] as int),
          );
          
          await _loadToolLocations();
          await _loadRecentHistory(); // Refresh history
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Inventory added!'),
              backgroundColor: Colors.green,
            ),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        // Add/duplicate mode: Store for later when tool is saved
        setState(() {
          _inventoryToAdd = {
            'quantity': result['quantity'],
            'locationId': result['locationId'],
            'locationPath': _buildLocationPath(result['locationId']),
          };
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Inventory of ${result['quantity']} will be added when tool is saved'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    }
  }
  
  String _buildLocationPath(String locationId) {
    final names = <String>[];
    var currentId = locationId;
    
    while (currentId.isNotEmpty) {
      try {
        final loc = _locations.firstWhere((l) => l.id == currentId);
        names.insert(0, loc.data['name']);
        currentId = loc.data['parent'] ?? '';
      } catch (e) {
        break;
      }
    }
    
    return names.join(' → ');
  }

  /// Returns subcategory selector widgets plus a trailing gap before Tool Name only when there are any.
  List<Widget> _subcategorySelectorWidgets() {
    final list = _buildSubcategorySelectors();
    if (list.isEmpty) return list;
    return [...list, const SizedBox(height: 16)];
  }

  // Build dynamic cascading subcategory selectors
  List<Widget> _buildSubcategorySelectors() {
    if (_selectedCategoryId == null) return [];

    final widgets = <Widget>[];

    // Get top-level subcategories for selected category
    final topLevel = _allSubcategories.where((s) =>
      s.data['category'] == _selectedCategoryId &&
      (s.data['parent_subcategory'] == null || s.data['parent_subcategory'] == '')
    ).toList();
    
    // Sort by sort_order to ensure consistent ordering
    topLevel.sort((a, b) => (a.data['sort_order'] ?? 0).compareTo(b.data['sort_order'] ?? 0));

    if (topLevel.isEmpty) return widgets;

    // Check if we have multiple independent subcategories (all with attribute lists, no hierarchy)
    final allHaveAttributeLists = topLevel.every((sub) {
      final attrList = sub.data['attribute_list'];
      return attrList != null && attrList.toString().isNotEmpty;
    });
    
    if (allHaveAttributeLists && topLevel.length > 1) {
      // Multiple independent subcategories with attribute lists
      // Build a separate selector for each one (e.g., Filament Type + Filament Color)
      for (int i = 0; i < topLevel.length; i++) {
        if (i > 0) widgets.add(const SizedBox(height: 16));
        // Each gets its own level in _selectedSubcategoryIds
        widgets.add(_buildSubcategorySelector([topLevel[i]], i));
      }
    } else {
      // Single subcategory OR hierarchical subcategories (choose one from multiple)
      // Build selector for level 0
      widgets.add(_buildSubcategorySelector(topLevel, 0));
    }

    // Build selectors for nested levels (children of hierarchical subcategories)
    // Skip levels used by independent top-level subcategories
    final startLevel = (allHaveAttributeLists && topLevel.length > 1) ? topLevel.length : 0;
    
    for (int i = 0; i < _selectedSubcategoryIds.length; i++) {
      if (_selectedSubcategoryIds[i] == null) break;
      
      // Skip if this is an independent top-level subcategory
      if (i < startLevel) continue;

      final children = _allSubcategories.where((s) =>
        s.data['parent_subcategory'] == _selectedSubcategoryIds[i]
      ).toList();

      if (children.isNotEmpty) {
        // If multiple child subcategories under this parent each have their own
        // attribute_list and are leaf nodes, render an attribute selector for
        // each child. (Existing logic only used `options.first`.)
        final allChildrenHaveAttributeLists = children.every((sub) {
          final attrListId = sub.data['attribute_list'];
          return attrListId != null && attrListId.toString().isNotEmpty;
        });

        final allChildrenAreLeafNodes = children.every((sub) {
          final hasChildren = _allSubcategories.any((s) => s.data['parent_subcategory'] == sub.id);
          return !hasChildren;
        });

        if (children.length > 1 && allChildrenHaveAttributeLists && allChildrenAreLeafNodes) {
          for (int childIndex = 0; childIndex < children.length; childIndex++) {
            if (childIndex > 0) widgets.add(const SizedBox(height: 16));
            widgets.add(_buildSubcategorySelector([children[childIndex]], i + 1 + childIndex));
          }
        } else {
          widgets.add(const SizedBox(height: 16));
          widgets.add(_buildSubcategorySelector(children, i + 1));
        }
      }
    }

    // Check if deepest selected subcategory has attribute list OR needs dynamic dropdown
    // Note: At this point, if a subcategory had an attribute_list, we already showed those values
    // and the "selected ID" might actually be an attribute value string, not a subcategory ID
    if (_selectedSubcategoryIds.isNotEmpty) {
      final deepestValue = _selectedSubcategoryIds.last;
      if (deepestValue != null) {
        // Try to find if this is a subcategory ID
        try {
          final deepest = _allSubcategories.firstWhere((s) => s.id == deepestValue);
          final attrListId = deepest.data['attribute_list'];
          final hasChildren = _allSubcategories.any((s) => s.data['parent_subcategory'] == deepestValue);
          
          // Only show additional attribute selector if:
          // 1. The subcategory has an attribute_list AND no children (leaf node)
          if (attrListId != null && attrListId.toString().isNotEmpty && !hasChildren) {
            // Has attribute list and no children - show attribute selector
            widgets.add(const SizedBox(height: 16));
            widgets.add(_buildAttributeSelector(attrListId));
          } else if (!hasChildren && attrListId == null) {
            // No attribute list and no children - show dynamic dropdown for VALUES
            final label = deepest.data['custom_label'] ?? deepest.data['label'] ?? 'Value';
            widgets.add(const SizedBox(height: 16));
            widgets.add(_buildDynamicDropdownSelector([], _selectedSubcategoryIds.length, label));
          }
          // If it has an attribute_list but no children, we already showed those values in the selector
        } catch (e) {
          // deepestValue is not a subcategory ID - it's probably an attribute value string
          // This means we already showed the attribute values in the selector, so don't add another one
          print('DEBUG: Selected value "$deepestValue" is not a subcategory ID (this is expected when attribute values are shown)');
        }
      }
    }

    return widgets;
  }

  Widget _buildSubcategorySelector(List<dynamic> options, int level) {
    // Get label, display_mode, and field_type from parent or first option
    String label = 'Subcategory';
    String displayMode = 'dropdown'; // Default
    String fieldType = 'selection'; // Default
    
    // For independent subcategories (single option in array), always use the subcategory's own settings
    if (options.length == 1) {
      final sub = options.first;
      label = sub.data['label'] ?? 'Subcategory';
      displayMode = sub.data['display_mode'] ?? 'dropdown';
      fieldType = sub.data['field_type'] ?? 'selection';
      print('DEBUG _buildSubcategorySelector: level=$level, using own settings: displayMode=$displayMode');
    } else if (level > 0 && _selectedSubcategoryIds.length >= level) {
      final parentId = _selectedSubcategoryIds[level - 1];
      if (parentId != null) {
        try {
          final parent = _allSubcategories.firstWhere((s) => s.id == parentId);
          // For children, use parent's custom_label (label for children)
          label = parent.data['custom_label'] ?? 'Type';
          // Read display_mode and field_type from parent
          displayMode = parent.data['display_mode'] ?? 'dropdown';
          fieldType = parent.data['field_type'] ?? 'selection';
        } catch (e) {
          // Parent not found, use default label
        }
      }
    } else if (level == 0 && _selectedCategoryId != null) {
      // For first level, use the subcategory's own label field
      if (options.isNotEmpty) {
        final firstSub = options.first;
        // Use 'label' field for this subcategory's own label
        label = firstSub.data['label'] ?? 'Subcategory';
        displayMode = firstSub.data['display_mode'] ?? 'dropdown';
        fieldType = firstSub.data['field_type'] ?? 'selection';
      }
    }

    // Check field type FIRST
    if (fieldType == 'text') {
      return _buildTextInputSelector(level, label);
    } else if (fieldType == 'number') {
      return _buildNumberInputSelector(level, label);
    }
    
    // For 'selection' type, use display mode
    if (displayMode == 'buttons') {
      return _buildButtonSelector(options, level, label);
    } else {
      return _buildDropdownSelector(options, level, label);
    }
  }

  Widget _buildDropdownSelector(List<dynamic> options, int level, String label) {
    // Ensure _selectedSubcategoryIds has enough slots
    while (_selectedSubcategoryIds.length <= level) {
      _selectedSubcategoryIds.add(null);
    }
    
    // Check if ANY of the options have an attribute_list
    // If so, we should show attribute values, not subcategory names
    // BUT ONLY if the subcategory has no children
    String? attributeListId;
    if (options.isNotEmpty) {
      final firstOption = options.first;
      attributeListId = firstOption.data['attribute_list'];
      
      // Check if this subcategory has children
      final hasChildren = _allSubcategories.any((s) => s.data['parent_subcategory'] == firstOption.id);
      
      // If this subcategory level has an attribute list AND no children, show attribute values
      if (attributeListId != null && attributeListId.toString().isNotEmpty && !hasChildren) {
        return FutureBuilder<Map<String, dynamic>>(
          future: _loadAttributeListAndValues(attributeListId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return _wrapSelectorWithLabel(label, DropdownButtonFormField<String>(
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: const [],
                onChanged: null,
              ));
            }
            
            final attrData = snapshot.data!;
            final values = attrData['values'] as List<dynamic>;
            final displayMode = attrData['display_mode'] as String;
            
            // If display mode is buttons, use button selector instead
            if (displayMode == 'buttons') {
              return _buildButtonSelectorForAttributeValues(values, level, label);
            }
            
            return _wrapSelectorWithLabel(label, DropdownButtonFormField<String>(
              value: _selectedSubcategoryIds[level],
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: values.map<DropdownMenuItem<String>>((valueRecord) {
                return DropdownMenuItem<String>(
                  value: valueRecord.data['value'],
                  child: Text(valueRecord.data['value']),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedSubcategoryIds[level] = value;
                  _selectedAttributeValue = value;
                  if (level < _selectedSubcategoryIds.length - 1) {
                    _selectedSubcategoryIds.removeRange(level + 1, _selectedSubcategoryIds.length);
                  }
                  _updateSubcategoryText();
                  _updateToolName();
                });
              },
            ));
          },
        );
      }
    }

    // Original behavior: show subcategory options
    return _wrapSelectorWithLabel(label, DropdownButtonFormField<String>(
      value: _selectedSubcategoryIds[level],
      decoration: const InputDecoration(border: OutlineInputBorder()),
      items: options.map<DropdownMenuItem<String>>((sub) {
        return DropdownMenuItem<String>(
          value: sub.id,
          child: Text(sub.data['name']),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          _selectedSubcategoryIds[level] = value;
          _selectedSubcategoryIds = _selectedSubcategoryIds.sublist(0, level + 1);
          _selectedAttributeValue = null;
          _updateSubcategoryText();
          _updateToolName();
        });
      },
    ));
  }

  Widget _wrapSelectorWithLabel(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: _selectorLabelStyle),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildButtonSelector(List<dynamic> options, int level, String label) {
    // Ensure _selectedSubcategoryIds has enough slots
    while (_selectedSubcategoryIds.length <= level) {
      _selectedSubcategoryIds.add(null);
    }
    
    // Check if ANY of the options have an attribute_list
    // If so, we should show attribute values, not subcategory names
    // BUT ONLY if the subcategory has no children
    String? attributeListId;
    if (options.isNotEmpty) {
      final firstOption = options.first;
      attributeListId = firstOption.data['attribute_list'];
      
      // Check if this subcategory has children
      final hasChildren = _allSubcategories.any((s) => s.data['parent_subcategory'] == firstOption.id);
      
      // If this subcategory level has an attribute list AND no children, show attribute values as buttons
      if (attributeListId != null && attributeListId.toString().isNotEmpty && !hasChildren) {
        return FutureBuilder<Map<String, dynamic>>(
          future: _loadAttributeListAndValues(attributeListId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: _selectorLabelStyle),
                  const SizedBox(height: 8),
                  const CircularProgressIndicator(),
                ],
              );
            }
            
            final attrData = snapshot.data!;
            final values = attrData['values'] as List<dynamic>;
            
            return _buildButtonSelectorForAttributeValues(values, level, label);
          },
        );
      }
    }

    // Original behavior: show subcategory options as buttons
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: _selectorLabelStyle),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((sub) {
            final isSelected = _selectedSubcategoryIds[level] == sub.id;
            return ElevatedButton(
              onPressed: () {
                setState(() {
                  _selectedSubcategoryIds[level] = sub.id;
                  // Clear selections beyond this level
                  _selectedSubcategoryIds = _selectedSubcategoryIds.sublist(0, level + 1);
                  _selectedAttributeValue = null;
                  _updateSubcategoryText();
                  _updateToolName();
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isSelected ? Colors.blue : Colors.grey[300],
                foregroundColor: isSelected ? Colors.white : Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              child: Text(sub.data['name']),
            );
          }).toList(),
        ),
      ],
    );
  }

  // NEW: Build button selector for attribute values (when subcategory has attribute_list)
  Widget _buildButtonSelectorForAttributeValues(List<dynamic> values, int level, String label) {
    // Ensure _selectedSubcategoryIds has enough slots
    while (_selectedSubcategoryIds.length <= level) {
      _selectedSubcategoryIds.add(null);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: _selectorLabelStyle),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values.map((valueRecord) {
            final value = valueRecord.data['value'];
            final isSelected = _selectedSubcategoryIds[level] == value;
            return ElevatedButton(
              onPressed: () {
                setState(() {
                  _selectedSubcategoryIds[level] = value;
                  // When a value is selected, store it (it's the actual value, not an ID)
                  _selectedAttributeValue = value;
                  
                  // Clear selections beyond this level
                  if (level < _selectedSubcategoryIds.length - 1) {
                    _selectedSubcategoryIds.removeRange(level + 1, _selectedSubcategoryIds.length);
                  }
                  
                  _updateSubcategoryText();
                  _updateToolName();
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isSelected ? Colors.blue : Colors.grey[300],
                foregroundColor: isSelected ? Colors.white : Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              child: Text(value),
            );
          }).toList(),
        ),
      ],
    );
  }

  // NEW: Build text input selector for text field type
  Widget _buildTextInputSelector(int level, String label) {
    return _wrapSelectorWithLabel(label, TextFormField(
      initialValue: _subcategoryTextValues[level] ?? '',
      decoration: const InputDecoration(border: OutlineInputBorder()),
      onChanged: (value) {
        setState(() {
          _subcategoryTextValues[level] = value;
          // Text inputs don't have children, so clear beyond this level
          _selectedSubcategoryIds = _selectedSubcategoryIds.sublist(0, level);
          _selectedAttributeValue = null;
          _updateSubcategoryText();
        });
      },
    ));
  }

  // NEW: Get previously used values for dynamic dropdown (subcategories without attribute lists)
  Future<List<String>> _getUsedValuesForSubcategory(String subcategoryName) async {
    try {
      final pbService = PocketBaseService();
      final tools = await pbService.getTools();
      
      // Extract unique values from subcategory field, filtering by category
      final values = <String>{};
      for (final tool in tools) {
        // Only look at tools from the same category
        if (tool.data['category'] != _category) continue;
        
        final subcatText = tool.data['subcategory']?.toString() ?? '';
        // Parse the subcategory text (e.g., "Colors > Red")
        final parts = subcatText.split(' > ').map((s) => s.trim()).toList();
        
        // Find values that come after our current subcategory level
        // For example, if we're at "Colors" level and it's "Colors > Red", we want "Red"
        if (parts.length >= _selectedSubcategoryIds.length + 1) {
          // Get the value at the position we're looking for
          final value = parts[_selectedSubcategoryIds.length];
          if (value.isNotEmpty) {
            values.add(value);
          }
        }
      }
      
      return values.toList()..sort();
    } catch (e) {
      print('Error getting used values: $e');
      return [];
    }
  }

  // NEW: Build autocomplete with previously used values for subcategories without attribute lists
  Widget _buildDynamicDropdownSelector(List<dynamic> options, int level, String label) {
    final currentValue = _subcategoryTextValues[level] ?? '';
    
    return _wrapSelectorWithLabel(label, FutureBuilder<List<String>>(
      future: _getUsedValuesForSubcategory(label),
      builder: (context, snapshot) {
        final usedValues = snapshot.data ?? [];
        
        return Autocomplete<String>(
          initialValue: currentValue.isNotEmpty
              ? TextEditingValue(text: currentValue)
              : const TextEditingValue(),
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty) return usedValues;
            return usedValues
                .where((value) => value
                    .toLowerCase()
                    .contains(textEditingValue.text.toLowerCase()))
                .toList();
          },
          onSelected: (String selectedValue) {
            setState(() {
              _subcategoryTextValues[level] = selectedValue;
              _selectedSubcategoryIds = _selectedSubcategoryIds.sublist(0, level);
              _selectedAttributeValue = null;
              _updateSubcategoryText();
              _updateToolName();
            });
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            if (currentValue.isNotEmpty && controller.text.isEmpty) {
              controller.text = currentValue;
            }
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: 'Type or select',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    controller.clear();
                    setState(() {
                      _subcategoryTextValues[level] = '';
                      _updateSubcategoryText();
                      _updateToolName();
                    });
                  },
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _subcategoryTextValues[level] = value;
                  _selectedSubcategoryIds = _selectedSubcategoryIds.sublist(0, level);
                  _selectedAttributeValue = null;
                  _updateSubcategoryText();
                  _updateToolName();
                });
              },
            );
          },
        );
      },
    ));
  }

  // NEW: Build number input selector for number field type
  Widget _buildNumberInputSelector(int level, String label) {
    return _wrapSelectorWithLabel(label, TextFormField(
      initialValue: _subcategoryNumberValues[level]?.toString() ?? '',
      decoration: const InputDecoration(border: OutlineInputBorder()),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (value) {
        setState(() {
          _subcategoryNumberValues[level] = double.tryParse(value);
          _selectedSubcategoryIds = _selectedSubcategoryIds.sublist(0, level);
          _selectedAttributeValue = null;
          _updateSubcategoryText();
        });
      },
    ));
  }

  Widget _buildAttributeSelector(String attrListId) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadAttributeListAndValues(attrListId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data!;
        final values = data['values'] as List<dynamic>;
        final displayMode = data['display_mode'] as String;
        
        if (values.isEmpty) return const SizedBox.shrink();

        // Use a generic label (could be enhanced to use attribute list name)
        const String label = 'Attribute';

        if (displayMode == 'buttons') {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: _selectorLabelStyle),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: values.map((value) {
                  final isSelected = _selectedAttributeValue == value.data['value'];
                  return ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _selectedAttributeValue = value.data['value'];
                        _updateSubcategoryText();
                        _updateToolName();
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSelected ? Colors.blue : Colors.grey[300],
                      foregroundColor: isSelected ? Colors.white : Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    child: Text(value.data['value']),
                  );
                }).toList(),
              ),
            ],
          );
        } else {
          return _wrapSelectorWithLabel(label, DropdownButtonFormField<String>(
            value: _selectedAttributeValue,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: values.map<DropdownMenuItem<String>>((val) {
              return DropdownMenuItem<String>(
                value: val.data['value'],
                child: Text(val.data['value']),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedAttributeValue = value;
                _updateSubcategoryText();
                _updateToolName();
              });
            },
          ));
        }
      },
    );
  }
  
  // Helper method to load both attribute list and its values
  Future<Map<String, dynamic>> _loadAttributeListAndValues(String attrListId) async {
    final pbService = PocketBaseService();
    final attributeLists = await pbService.getAttributeLists();
    final values = await pbService.getAttributeValues(attrListId);
    
    // Find the attribute list to get its display_mode
    dynamic attributeList;
    try {
      attributeList = attributeLists.firstWhere((al) => al.id == attrListId);
    } catch (e) {
      // If not found, use default
      return {
        'values': values,
        'display_mode': 'dropdown',
      };
    }
    
    return {
      'values': values,
      'display_mode': attributeList.data['display_mode'] ?? 'dropdown',
    };
  }

  void _updateSubcategoryText() {
    // Build subcategory text from selected IDs and text/number inputs
    final subcategoryNames = <String>[];
    
    for (int i = 0; i < _selectedSubcategoryIds.length; i++) {
      final idOrValue = _selectedSubcategoryIds[i];
      if (idOrValue != null) {
        try {
          // Try to find it as a subcategory ID
          final sub = _allSubcategories.firstWhere((s) => s.id == idOrValue);
          subcategoryNames.add(sub.data['name']);
        } catch (e) {
          // Not a subcategory ID - it's an attribute value (like "PLA" or "Black")
          // Just add it directly as a string
          subcategoryNames.add(idOrValue);
          print('DEBUG _updateSubcategoryText: "$idOrValue" is an attribute value, not a subcategory ID');
        }
      }
    }
    
    // Add text/number values
    _subcategoryTextValues.forEach((level, value) {
      if (value.isNotEmpty) {
        subcategoryNames.add(value);
      }
    });
    
    _subcategoryNumberValues.forEach((level, value) {
      if (value != null) {
        subcategoryNames.add(value.toString());
      }
    });

    // Drills: include selected Drill Standard (Fractional/Metric/Wire/Letter)
    // chosen from the attribute selector so it persists in the saved subcategory chain.
    if (_isDrillsToolType()) {
      final std = (_selectedAttributeValue ?? '').trim();
      final isStandard = std == 'Fractional' || std == 'Metric' || std == 'Wire' || std == 'Letter';
      if (isStandard && !subcategoryNames.contains(std)) {
        subcategoryNames.add(std);
      }
    }

    // Update backward compatibility variables
    _subcategory = subcategoryNames.isNotEmpty ? subcategoryNames[0] : null;
    _subSubcategory = subcategoryNames.length > 1 ? subcategoryNames[1] : null;
    _subcategoryText = subcategoryNames.join(' > ');
    
    print('DEBUG _updateSubcategoryText: Built subcategoryText = "$_subcategoryText"');
    
    // Clear corner radius when leaving CR and Special (both can use the field)
    if (_subSubcategory != 'CR' &&
        _subSubcategory != 'Special' &&
        _cornerRadController.text.isNotEmpty) {
      _cornerRadController.clear();
    }

    // Clear drill included angle if not Drills type
    if (!_isDrillsToolType() && _drillIncludedAngleController.text.isNotEmpty) {
      _drillIncludedAngleController.clear();
    }
    
    // Clear T-slot radius if not Tslot type
    if (_subSubcategory != 'Tslot' && _tslotRadiusController.text.isNotEmpty) {
      _tslotRadiusController.clear();
    }
    
    // Clear chamfer fields if not Chamfer type
    if (_subSubcategory != 'Chamfer') {
      if (_chamferAngleController.text.isNotEmpty) {
        _chamferAngleController.clear();
      }
      if (_chamferTipDiameterController.text.isNotEmpty) {
        _chamferTipDiameterController.clear();
      }
    }
    
    // Update tool name to reflect subcategory changes (fixes Ball/CR suffix sticking)
    if (_autoGenerateName) {
      _updateToolName();
    }
  }

  void _saveTool() async {
    // Ensure dynamic subcategory text vars are up to date before validation checks.
    _updateSubcategoryText();

    // Cutting Tools: require Tool Type; End mills need Style; Drills need material (SC/HSS).
    if (_category == 'Cutting Tools') {
      if (_subcategory == null || _subcategory!.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select a Tool Type')),
          );
        }
        return;
      }
      if (_isDrillsToolType()) {
        final style = _getSelectedDrillStyleToken();
        final standard = _getSelectedDrillStandardType();
        if (style == null || style.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Please select drill style (Carbide or HSS)')),
            );
          }
          return;
        }
        if (standard == null || standard.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please select drill standard')),
            );
          }
          return;
        }
      } else if (_subSubcategory == null || _subSubcategory!.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select a Style')),
          );
        }
        return;
      }
    }

    // Basic URL validation: if provided, it should look like a real URL.
    final rawUrl = _urlController.text.trim();
    if (rawUrl.isNotEmpty &&
        !(rawUrl.toLowerCase().startsWith('http://') ||
          rawUrl.toLowerCase().startsWith('https://'))) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'That does not look like a valid URL.\n'
              'Please enter the full URL (e.g. https://example.com/your-tool).',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    if (_formKey.currentState!.validate()) {
      try {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );

        final pbService = PocketBaseService();
        
        // Use the subcategory text that was already built by _updateSubcategoryText()
        // This handles both hierarchical subcategories and independent subcategories with attribute lists
        String subcategoryStr = _subcategoryText;
        String subSubcategoryStr = '';
        
        // For backward compatibility with hierarchical subcategories, set subSubcategoryStr
        if (_subSubcategory != null && _subSubcategory!.isNotEmpty) {
          subSubcategoryStr = _subSubcategory!;
        }
        
        print('DEBUG _saveTool: subcategoryStr = "$subcategoryStr"');
        print('DEBUG _saveTool: subSubcategoryStr = "$subSubcategoryStr"');
        
        final body = {
          'tool_name': _toolNameController.text,
          'category': _category,
          'subcategory': subcategoryStr,
          'sub_subcategory': subSubcategoryStr,
          'attribute_value': _selectedAttributeValue,
          'model_number': _modelNumberController.text.isEmpty 
              ? null 
              : _modelNumberController.text,
          'url': rawUrl.isEmpty ? null : rawUrl,
          'brand': _selectedBrandId,
          'supplier': _selectedSupplierId,
          'diameter_in': double.tryParse(_diameterInController.text),
          'diameter_mm': double.tryParse(_diameterMmController.text),
          'flutes': int.tryParse(_flutesController.text),
          'flute_length': double.tryParse(_fluteLengthController.text),
          'corner_rad': double.tryParse(_cornerRadController.text),
          'neck': double.tryParse(_neckController.text),
          'drill_included_angle': double.tryParse(_drillIncludedAngleController.text),
          'tslot_radius': double.tryParse(_tslotRadiusController.text),  // NEW
          'chamfer_angle': double.tryParse(_chamferAngleController.text),  // NEW
          'chamfer_tip_diameter': double.tryParse(_chamferTipDiameterController.text),  // NEW
          'notes': _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          'needs_restock': _needsRestock,
          'restock_qty': _needsRestock
              ? (int.tryParse(_restockQtyController.text.trim()) ?? 1)
              : null,
          'restock_notes': _needsRestock && _restockNotesController.text.trim().isNotEmpty
              ? _restockNotesController.text.trim()
              : null,
        };
        
        print('DEBUG _saveTool: Saving with brand = $_selectedBrandId, supplier = $_selectedSupplierId');
        print('DEBUG _saveTool: Body = $body');
        
        dynamic toolRecord;
        
        if (_isEditMode) {
          // Update existing tool
          if (_photoChanged && _photoBytes != null) {
            toolRecord = await pbService.pb.collection('inventory').update(
              widget.tool!.id,
              body: body,
              files: [
                http.MultipartFile.fromBytes(
                  'photo',
                  _photoBytes!,
                  filename: 'tool_photo.jpg',
                ),
              ],
            );
          } else {
            print('DEBUG _saveTool: Updating tool ${widget.tool!.id}');
            toolRecord = await pbService.pb.collection('inventory').update(
              widget.tool!.id,
              body: body,
            );
            print('DEBUG _saveTool: Update result - brand = ${toolRecord.data['brand']}, supplier = ${toolRecord.data['supplier']}');
          }
        } else {
          // Create new tool
          if (_photoBytes != null) {
            toolRecord = await pbService.pb.collection('inventory').create(
              body: body,
              files: [
                http.MultipartFile.fromBytes(
                  'photo',
                  _photoBytes!,
                  filename: 'tool_photo.jpg',
                ),
              ],
            );
          } else {
            toolRecord = await pbService.pb.collection('inventory').create(body: body);
          }
          
          // Create tool_location record if inventory was added
          if (_inventoryToAdd != null) {
        await pbService.createToolLocation(
          toolId: toolRecord.id,
              locationId: _inventoryToAdd!['locationId'],
              quantity: _inventoryToAdd!['quantity'] as int,
            );
            
            // Log initial inventory add
            await pbService.logInventoryHistory(
              toolId: toolRecord.id,
              locationId: _inventoryToAdd!['locationId'],
              action: 'add',
              quantity: _inventoryToAdd!['quantity'] as int,
              quantityBefore: 0,
              quantityAfter: _inventoryToAdd!['quantity'] as int,
            );
          }
        }

        if (context.mounted) Navigator.pop(context);
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_isEditMode 
                  ? 'Tool updated successfully!' 
                  : 'Tool "${_toolNameController.text}" saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          
          // Navigate back to inventory screen with the selected category filter
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => InventoryScreen(
                categoryFilter: _category,
              ),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) Navigator.pop(context);
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving tool: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    // Show loading indicator while initializing
    if (!_isInitialized) {
      return WorkspaceScaffold(
        scaffoldKey: _scaffoldKey,
        appBar: AppBar(
          title: Text(_isEditMode ? 'Edit Tool' : widget.isDuplicate ? 'Duplicate Tool' : 'Add Tool'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          leading: workspaceMenuLeading(context),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final isNarrow = MediaQuery.of(context).size.width < 800;

    return WorkspaceScaffold(
      scaffoldKey: _scaffoldKey,
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit Tool' : widget.isDuplicate ? 'Duplicate Tool' : 'Add Tool'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: workspaceMenuLeading(context),
      ),
      body: Form(
        key: _formKey,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // LEFT COLUMN - Tool Details
            Expanded(
              flex: 3,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // CATEGORY - Dynamic (Dropdown or Buttons based on setting)
            _buildCategorySelector(),
            const SizedBox(height: 16),
            // Dynamic Cascading Subcategories (spacing before Tool Name only when we have subcategory widgets)
            ..._subcategorySelectorWidgets(),
            // Tool Name
              TextFormField(
                controller: _toolNameController,
                    decoration: InputDecoration(
                  labelText: 'Tool Name',
                      border: const OutlineInputBorder(),
                      suffixIcon: _selectedCategoryId == CUTTING_TOOLS_CATEGORY_ID
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Checkbox(
                                  value: _autoGenerateName,
                                  onChanged: (value) {
                                    print('DEBUG: Checkbox clicked, current: $_autoGenerateName, new value: $value');
                                    setState(() {
                                      _autoGenerateName = value == true;
                                      print('DEBUG: After setState, _autoGenerateName = $_autoGenerateName');
                                      if (_autoGenerateName) {
                                        _toolName = _generateToolName();
                                        _toolNameController.text = _toolName;
                                      }
                                    });
                                  },
                                ),
                                GestureDetector(
                                  onTap: () {
                                    print('DEBUG: Text clicked, toggling from $_autoGenerateName');
                                    setState(() {
                                      _autoGenerateName = !_autoGenerateName;
                                      print('DEBUG: After text click, _autoGenerateName = $_autoGenerateName');
                                      if (_autoGenerateName) {
                                        _toolName = _generateToolName();
                                        _toolNameController.text = _toolName;
                                      }
                                    });
                                  },
                                  child: const Text('Auto'),
                                ),
                                const SizedBox(width: 8),
                              ],
                            )
                          : null,
                    ),
                    readOnly: _selectedCategoryId == CUTTING_TOOLS_CATEGORY_ID
                        ? _autoGenerateName
                        : false,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Tool name is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
            
            // Model Number with Import button
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _modelNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Model Number',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                if (_enableToolImport) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isImporting ? null : _importToolSpecs,
                    icon: _isImporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_download, size: 18),
                    label: const Text('Import'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            
            // Brand and Supplier row (explicit Tab order: Brand → Supplier)
            FocusTraversalGroup(
              child: Row(
                children: [
                  // BRAND - Searchable Autocomplete
                  FocusTraversalOrder(
                    order: const NumericFocusOrder(1),
                    child: Expanded(
                      child: Autocomplete<String>(
                    initialValue: const TextEditingValue(),
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.isEmpty) {
                        return _brands.map((brand) => brand.data['name'] as String);
                      }
                      return _brands
                          .where((brand) => (brand.data['name'] as String)
                              .toLowerCase()
                              .contains(textEditingValue.text.toLowerCase()))
                          .map((brand) => brand.data['name'] as String);
                    },
                    onSelected: (String selectedName) {
                      final brand = _brands.firstWhere((b) => b.data['name'] == selectedName);
                      setState(() {
                        _selectedBrandId = brand.id;
                        _selectedBrandName = brand.data['name'] as String?;

                        // If brand has a default supplier, always auto-select it
                        // (changing brand should update supplier to match).
                        final defaultSupplierId = brand.data['default_supplier'] as String?;
                        if (defaultSupplierId != null &&
                            defaultSupplierId.isNotEmpty) {
                          dynamic matchingSupplier;
                          try {
                            matchingSupplier = _suppliers.firstWhere(
                              (s) => s.id == defaultSupplierId,
                            );
                          } catch (_) {
                            matchingSupplier = null;
                          }
                          if (matchingSupplier != null) {
                            _selectedSupplierId = matchingSupplier.id as String;
                            _selectedSupplierName =
                                matchingSupplier.data['company_name'] as String?;
                            print('DEBUG brand onSelected: auto-selected supplier $_selectedSupplierId / $_selectedSupplierName');
                          } else {
                            print('DEBUG brand onSelected: default supplier $defaultSupplierId not found in _suppliers');
                          }
                        }
                      });
                      // Keep focus in Brand field so Tab moves to Supplier
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _brandFieldFocusNode?.requestFocus();
                      });
                    },
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      _brandFieldFocusNode = focusNode;
                      // Keep text in sync with our selected brand name
                      final desiredText = _selectedBrandName ?? '';
                      if (controller.text != desiredText) {
                        controller.text = desiredText;
                        controller.selection = TextSelection.fromPosition(
                          TextPosition(offset: controller.text.length),
                        );
                      }
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        onFieldSubmitted: (_) => onFieldSubmitted(),
                        decoration: InputDecoration(
                          labelText: 'Brand',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              controller.clear();
                              setState(() {
                                _selectedBrandId = null;
                                _selectedBrandName = null;
                              });
                              // Keep focus so user can immediately type a new brand
                              _brandFieldFocusNode?.requestFocus();
                            },
                          ),
                        ),
                        onChanged: (value) {
                          _selectedBrandName = value;
                          // Clear selection if text doesn't match any brand
                          if (!_brands.any((b) => b.data['name'] == value)) {
                            setState(() {
                              _selectedBrandId = null;
                            });
                          }
                        },
                      );
                    },
                  ),
                    ),
                  ),
                const SizedBox(width: 16),
                // SUPPLIER - Searchable Autocomplete
                FocusTraversalOrder(
                  order: const NumericFocusOrder(2),
                  child: Expanded(
                  child: Autocomplete<String>(
                    initialValue: const TextEditingValue(),
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.isEmpty) {
                        return _suppliers.map((supplier) => supplier.data['company_name'] as String);
                      }
                      return _suppliers
                          .where((supplier) => (supplier.data['company_name'] as String)
                              .toLowerCase()
                              .contains(textEditingValue.text.toLowerCase()))
                          .map((supplier) => supplier.data['company_name'] as String);
                    },
                    onSelected: (String selectedName) {
                      final supplier = _suppliers.firstWhere((s) => s.data['company_name'] == selectedName);
                      setState(() {
                        _selectedSupplierId = supplier.id;
                        _selectedSupplierName = supplier.data['company_name'] as String?;
                      });
                      // Keep focus in Supplier field so Tab moves to next field (e.g. URL)
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _supplierFieldFocusNode?.requestFocus();
                      });
                    },
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      _supplierFieldFocusNode = focusNode;
                      // Keep text in sync with our selected supplier name
                      final desiredText = _selectedSupplierName ?? '';
                      if (controller.text != desiredText) {
                        controller.text = desiredText;
                        controller.selection = TextSelection.fromPosition(
                          TextPosition(offset: controller.text.length),
                        );
                      }
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        onFieldSubmitted: (_) => onFieldSubmitted(),
                        decoration: InputDecoration(
                          labelText: 'Supplier',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              controller.clear();
                              setState(() {
                              _selectedSupplierId = null;
                              _selectedSupplierName = null;
                              });
                            },
                          ),
                        ),
                        onChanged: (value) {
                          _selectedSupplierName = value;
                          // Clear selection if text doesn't match any supplier
                          if (!_suppliers.any((s) => s.data['company_name'] == value)) {
                            setState(() {
                              _selectedSupplierId = null;
                            });
                          }
                        },
                      );
                    },
                  ),
                  ),
                ),
              ],
            ),
            ),
                  const SizedBox(height: 16),

                  // URL
                  TextFormField(
                    controller: _urlController,
                    decoration: InputDecoration(
                      labelText: 'URL',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      border: OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'Open URL',
                        onPressed: _openCurrentUrl,
                        icon: const Icon(Icons.open_in_new),
                      ),
                    ),
                  ),
            const SizedBox(height: 16),
            
            // Hardcoded Fields - Only show for Cutting Tools category
            if (_selectedCategoryId == CUTTING_TOOLS_CATEGORY_ID) ...[
              // Diameter row
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _diameterInController,
                    decoration: const InputDecoration(
                      labelText: 'Diameter (in)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: _onDiameterInChanged,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Required';
                      }
                      if (double.tryParse(value) == null) {
                        return 'Invalid number';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _diameterMmController,
                    decoration: const InputDecoration(
                      labelText: 'Diameter (mm)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: _onDiameterMmChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Flutes, Flute Length, Neck, and Corner Radius (CR or Special)
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _flutesController,
                    decoration: InputDecoration(
                      labelText: _isDrillsToolType()
                          ? 'Flutes (optional)'
                          : 'Number of Flutes',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (_isDrillsToolType()) {
                        if (value == null || value.isEmpty) {
                          return null;
                        }
                        if (int.tryParse(value) == null) {
                          return 'Must be a whole number';
                        }
                        return null;
                      }
                      if (value == null || value.isEmpty) {
                        return 'Required';
                      }
                      if (int.tryParse(value) == null) {
                        return 'Must be a whole number';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _fluteLengthController,
                    decoration: InputDecoration(
                      labelText: _isDrillsToolType()
                          ? 'Flute length (in)'
                          : 'Flute Length',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Required';
                      }
                      if (double.tryParse(value) == null) {
                        return 'Invalid number';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _neckController,
                    decoration: const InputDecoration(
                      labelText: 'Neck',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                if (_isDrillsToolType()) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _drillIncludedAngleController,
                      decoration: const InputDecoration(
                        labelText: 'Included Angle (°)',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (!_isDrillsToolType()) return null;
                        if (value == null || value.trim().isEmpty) return null;
                        if (double.tryParse(value) == null) {
                          return 'Invalid number';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
                if (_subSubcategory == 'CR' ||
                    _subSubcategory == 'Special') ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _cornerRadController,
                      decoration: InputDecoration(
                        labelText: _subSubcategory == 'Special'
                            ? 'Corner Radius (optional)'
                            : 'Corner Radius',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (_subSubcategory != 'CR' &&
                            _subSubcategory != 'Special') {
                          return null;
                        }
                        if (_subSubcategory == 'CR') {
                          if (value == null || value.trim().isEmpty) {
                            return 'Required';
                          }
                          if (double.tryParse(value) == null) {
                            return 'Invalid number';
                          }
                          return null;
                        }
                        // Special: optional; if filled must be valid
                        if (value == null || value.trim().isEmpty) {
                          return null;
                        }
                        if (double.tryParse(value) == null) {
                          return 'Invalid number';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
                // T-slot radius (optional)
                if (_subSubcategory == 'Tslot') ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _tslotRadiusController,
                      decoration: const InputDecoration(
                        labelText: 'T-Slot Radius',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
                // Chamfer angle and tip diameter
                if (_subSubcategory == 'Chamfer') ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _chamferAngleController,
                      decoration: const InputDecoration(
                        labelText: 'Chamfer Angle',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (_subSubcategory != 'Chamfer') return null;
                        if (value == null || value.trim().isEmpty) {
                          return 'Required';
                        }
                        if (double.tryParse(value) == null) {
                          return 'Invalid number';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _chamferTipDiameterController,
                      decoration: const InputDecoration(
                        labelText: 'Tip Diameter',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (_subSubcategory != 'Chamfer') return null;
                        if (value == null || value.trim().isEmpty) {
                          return 'Required';
                        }
                        if (double.tryParse(value) == null) {
                          return 'Invalid number';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            ], // End of hardcoded Cutting Tools fields

            // Notes (left column, below category-specific fields, above Save)
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 4,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes',
                floatingLabelBehavior: FloatingLabelBehavior.always,
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
                  
            const SizedBox(height: 24),
                  
            // Save button
            SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveTool,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      child: Text(
                        _isEditMode ? 'UPDATE TOOL' : 'SAVE TOOL',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            if (isNarrow) ...[
              const Divider(),
              const SizedBox(height: 16),
              _buildMobileSidePanel(context),
            ],
                ],
              ),
            ),
            
            // RIGHT COLUMN - Photo & Inventory
            if (!isNarrow)
              Expanded(
                flex: 2,
                child: Container(
                  color: Theme.of(context).colorScheme.surface,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                    // Photo
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        border: Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _photoBytes != null
                          ? Image.memory(_photoBytes!, fit: BoxFit.contain)
                          : _photoUrl != null
                              ? Image.network(_photoUrl!, fit: BoxFit.contain)
                              : const Center(
                                  child: Icon(Icons.image_outlined, size: 64, color: Colors.grey),
                                ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Upload Photo button
                    ElevatedButton.icon(
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.upload),
                      label: const Text('Upload Photo'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // Extract from URL — uses URL field; lists images via MCP server
                    ElevatedButton.icon(
                      onPressed: () => _extractFromUrl(),
                      icon: const Icon(Icons.link),
                      label: const Text('Extract from URL'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ..._buildInventoryAndHistorySection(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Mobile: inventory and history in one panel below the form.
  Widget _buildMobileSidePanel(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _buildInventoryAndHistorySection(context),
    );
  }

  /// Shared inventory, performance stats, price history, then movement history.
  List<Widget> _buildInventoryAndHistorySection(BuildContext context) {
    return [
      const SizedBox(height: 16),
      const Text(
        'Inventory',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Checkbox(
            value: _needsRestock,
            onChanged: (v) {
              setState(() {
                _needsRestock = v == true;
                if (_needsRestock &&
                    _restockQtyController.text.trim().isEmpty) {
                  _restockQtyController.text = '1';
                }
              });
            },
          ),
          const Text('Buy'),
          const SizedBox(width: 8),
          if (_needsRestock) ...[
            SizedBox(
              width: 80,
              child: TextFormField(
                controller: _restockQtyController,
                decoration: const InputDecoration(
                  labelText: 'Qty',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (!_needsRestock) return null;
                  final v = int.tryParse((value ?? '').trim());
                  if (v == null || v < 1) return '!';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _restockNotesController,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 1,
              ),
            ),
          ] else
            const Spacer(),
          IconButton(
            onPressed: _showAddInventoryDialog,
            icon: const Icon(Icons.add_circle),
            color: Colors.blue,
            tooltip: 'Add Inventory',
          ),
          if (_isEditMode && (kIsWeb || (!kIsWeb && Platform.isAndroid)))
            IconButton(
              onPressed: _showPrintLabelDialog,
              icon: const Icon(Icons.print),
              tooltip: _getBinToolLocations().isEmpty
                  ? 'Print bin label (assign tool to a bin first)'
                  : (kIsWeb
                      ? 'Print bin label (system print → PT-P910BT)'
                      : 'Print bin label'),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (!_isEditMode && _inventoryToAdd != null)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            border: Border.all(color: Colors.blue[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Qty: ${_inventoryToAdd!['quantity']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _inventoryToAdd!['locationPath'],
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  setState(() => _inventoryToAdd = null);
                },
              ),
            ],
          ),
        ),
      if (_isEditMode) ...[
        if (_toolLocations.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'No inventory',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ..._getSortedToolLocations().map((toolLocation) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InventoryLocationTag(
                tool: widget.tool!,
                toolLocation: toolLocation,
                allLocations: _allLocations,
                onChanged: () {
                  _loadToolLocations();
                  _loadRecentHistory();
                },
              ),
            );
          }),
      ],
      if (_category.toLowerCase() == 'cutting tools') ...[
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Performance Stats',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (_isEditMode)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    onPressed: _showLogToolUsageDialog,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Log usage'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _showToolUsageHistoryDialog,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('History'),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        Builder(
          builder: (context) {
            final stats = _computeToolUsageStats();
            final last = stats['lastUsage'] as Map<String, dynamic>?;
            String lastUsageText = '—';
            if (last != null) {
              final mins = last['minutes'];
              if (mins != null) lastUsageText = '${mins}m';
            }
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_loadingToolUsage)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(
                        icon: Icons.access_time,
                        label: 'Avg Tool Life',
                        value: (stats['avgMinutes'] == null)
                            ? '—'
                            : '${(stats['avgMinutes'] as double).round()} mins',
                        color: Colors.blue,
                      ),
                      _buildStatItem(
                        icon: Icons.history_toggle_off,
                        label: 'Last usage',
                        value: lastUsageText,
                        color: Colors.orange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(
                        icon: Icons.check_circle_outline,
                        label: 'Worn / Broken',
                        value: '${stats['wornCount'] ?? 0} / ${stats['brokenCount'] ?? 0}',
                        color: Colors.green,
                      ),
                      _buildStatItem(
                        icon: Icons.inventory_2,
                        label: 'Tools Used',
                        value: '${stats['count'] ?? 0}',
                        color: Colors.red,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
      if (_isEditMode) ...[
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),
        const Text(
          'Price History',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_loadingPurchaseHistory)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_purchaseHistoryRecords.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'No purchase history',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Theme.of(context).colorScheme.surfaceContainerHighest),
              columns: const [
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Supplier')),
                DataColumn(label: Text('Unit cost'), numeric: true),
                DataColumn(label: Text('Qty'), numeric: true),
              ],
              rows: _purchaseHistoryRecords.map((r) {
                String dateStr = '';
                String supplierName = '';
                try {
                  final purchase = r.expand?['purchase'];
                  if (purchase != null) {
                    final p = purchase is List ? purchase.isNotEmpty ? purchase[0] : null : purchase;
                    if (p != null) {
                      final d = p.data?['purchase_date'];
                      if (d != null) dateStr = DateFormat.yMMMd().format(DateTime.parse(d.toString()));
                      final sup = p.expand?['supplier'];
                      if (sup != null) {
                        final s = sup is List ? sup.isNotEmpty ? sup[0] : null : sup;
                        if (s != null) supplierName = s.data?['company_name'] ?? '';
                      }
                    }
                  }
                } catch (_) {}
                final data = r.data;
                final unitCost = data['unit_cost']?.toDouble();
                final qty = (data['quantity'] ?? 0).toInt();
                return DataRow(
                  cells: [
                    DataCell(Text(dateStr)),
                    DataCell(Text(supplierName)),
                    DataCell(Text(unitCost != null ? '\$${unitCost.toStringAsFixed(2)}' : '—')),
                    DataCell(Text('$qty')),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
      if (_isEditMode) ...[
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'History',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (_recentHistory.isNotEmpty)
              ElevatedButton(
                onPressed: _showAllHistory,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('View All'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loadingHistory)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_recentHistory.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'No history yet',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          )
        else
          ..._buildHistoryItems(_recentHistory),
      ],
    ];
  }
  
  // NEW: Get sorted tool locations by type order (matches location types order)
  List<ToolLocation> _getSortedToolLocations() {
    final typeOrder = {
      'toolbox': 1,
      'machine': 2,
      'shelf': 3,
      'recycle': 4,
      'bin': 5,      // fallback
      'worn': 6,     // fallback
      'broken': 7,   // fallback
    };
    
    final sorted = List<ToolLocation>.from(_toolLocations);
    sorted.sort((a, b) {
      final typeA = a.location?.type.toLowerCase() ?? 'unknown';
      final typeB = b.location?.type.toLowerCase() ?? 'unknown';
      
      final orderA = typeOrder[typeA] ?? 99;
      final orderB = typeOrder[typeB] ?? 99;
      
      // First sort by type
      if (orderA != orderB) {
        return orderA.compareTo(orderB);
      }
      
      // Then sort by location name within same type
      final nameA = a.location?.name ?? '';
      final nameB = b.location?.name ?? '';
      return nameA.compareTo(nameB);
    });
    
    return sorted;
  }

  /// Tool locations that are bins: type is 'bin', or name/path contains "bin" (e.g. "bin 250", "row 1, bin 250").
  List<ToolLocation> _getBinToolLocations() {
    return _toolLocations.where((tl) {
      final loc = tl.location;
      if (loc == null) return false;
      final type = (loc.type ?? '').toLowerCase();
      final name = (loc.name ?? '').toLowerCase();
      if (type == 'bin' || name.contains('bin')) return true;
      final pathNames = LabelPrintService.getPathNames(loc, _allLocations);
      final pathLower = pathNames.join(' ').toLowerCase();
      return pathLower.contains('bin');
    }).toList();
  }

  Future<void> _printLabelForBin(ToolLocation toolLocation) async {
    final location = toolLocation.location;
    if (location == null || widget.tool == null) return;
    final binCode = LabelPrintService.getBinCodeForLocation(location, _allLocations);

    if (!kIsWeb && mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Expanded(child: Text('Sending label to Brother printer…')),
              ],
            ),
          ),
        ),
      );
    }

    try {
      await LabelPrintService.printLabel(toolName: widget.tool!.toolName, binCode: binCode);
      if (mounted) {
        if (!kIsWeb) Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kIsWeb
                  ? 'Opened system print — PT-P910BT, 18mm, Length ${LabelPrintService.targetLabelLengthMm.round()} mm'
                  : 'Label sent to Brother printer',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on PlatformException catch (e) {
      if (mounted) {
        if (!kIsWeb) Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print failed (${e.code}): ${e.message ?? e.code}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        if (!kIsWeb) Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  Future<void> _showPrintLabelDialog() async {
    if (widget.tool == null) return;
    final bins = _getBinToolLocations();
    if (bins.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Assign this tool to a bin location to print a label.'),
          ),
        );
      }
      return;
    }
    if (bins.length == 1) {
      await _printLabelForBin(bins.first);
      return;
    }
    final chosen = await showDialog<ToolLocation>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Print label for which bin?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: bins.map((tl) {
              final loc = tl.location!;
              final binCode = LabelPrintService.getBinCodeForLocation(loc, _allLocations);
              return ListTile(
                title: Text('BIN: $binCode'),
                onTap: () => Navigator.pop(context, tl),
              );
            }).toList(),
          ),
        ),
      ),
    );
    if (chosen != null) await _printLabelForBin(chosen);
  }
  
  // NEW: Build history items with smart transfer pairing
  List<Widget> _buildHistoryItems(List<InventoryHistory> historyList) {
    final widgets = <Widget>[];
    final processedIndices = <int>{};
    
    for (int i = 0; i < historyList.length; i++) {
      if (processedIndices.contains(i)) continue;
      
      final current = historyList[i];
      
      // Check if this is a transfer_out with a matching transfer_in
      if (current.action == 'transfer_out' && i + 1 < historyList.length) {
        final next = historyList[i + 1];
        
        // Check if next entry is the matching transfer_in
        // (same time within 1 second, related locations match)
        if (next.action == 'transfer_in' &&
            current.created.difference(next.created).inSeconds.abs() <= 1 &&
            current.relatedLocationId == next.locationId &&
            next.relatedLocationId == current.locationId) {
          
          // Found a pair! Create combined widget
          widgets.add(_buildCombinedTransferItem(current, next));
          processedIndices.add(i);
          processedIndices.add(i + 1);
          continue;
        }
      }
      
      // Check if this is a transfer_in with a matching transfer_out before it
      if (current.action == 'transfer_in' && i > 0) {
        final prev = historyList[i - 1];
        
        if (prev.action == 'transfer_out' &&
            prev.created.difference(current.created).inSeconds.abs() <= 1 &&
            prev.relatedLocationId == current.locationId &&
            current.relatedLocationId == prev.locationId) {
          
          // Already handled by the previous iteration
          if (!processedIndices.contains(i - 1)) {
            widgets.add(_buildCombinedTransferItem(prev, current));
            processedIndices.add(i - 1);
            processedIndices.add(i);
          }
          continue;
        }
      }
      
      // Not part of a pair, show as individual entry
      widgets.add(_buildHistoryItem(current));
    }
    
    return widgets;
  }
  
  // NEW: Build combined transfer widget (single box for both transfer_out and transfer_in)
  Widget _buildCombinedTransferItem(InventoryHistory transferOut, InventoryHistory transferIn) {
    final dateFormat = DateFormat('MMM d, h:mm a');
    
    // Get location names
    String sourceLocationName = 'Unknown';
    if (transferOut.location != null) {
      sourceLocationName = transferOut.location!.name;
    } else {
      try {
        final loc = _allLocations.firstWhere((l) => l.id == transferOut.locationId);
        sourceLocationName = loc.name;
      } catch (e) {}
    }
    
    String destLocationName = 'Unknown';
    if (transferIn.location != null) {
      destLocationName = transferIn.location!.name;
    } else {
      try {
        final loc = _allLocations.firstWhere((l) => l.id == transferIn.locationId);
        destLocationName = loc.name;
      } catch (e) {}
    }
    
    final locationDisplay = '$sourceLocationName → $destLocationName';
    final colorScheme = Theme.of(context).colorScheme;
    final dividerColor = Theme.of(context).dividerColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border.all(color: dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Action description
                Text(
                  'Transferred ${transferOut.quantity}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                
                // Location with arrow
                Text(
                  locationDisplay,
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          
          // Date and quantity change on right
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                dateFormat.format(transferOut.created),
                style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(
                '${transferOut.quantityBefore} → ${transferOut.quantityAfter}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  // NEW: Build history item widget
  Widget _buildHistoryItem(InventoryHistory history) {
    final dateFormat = DateFormat('MMM d, h:mm a');
    
    // Try to get location name, with fallback
    String locationName = 'Unknown Location';
    if (history.location != null) {
      locationName = history.location!.name;
    } else {
      // Fallback: try to find location in _allLocations
      try {
        final loc = _allLocations.firstWhere((l) => l.id == history.locationId);
        locationName = loc.name;
      } catch (e) {
        // Keep 'Unknown Location'
      }
    }
    
    // Get related location name
    String? relatedLocationName;
    if (history.relatedLocation != null) {
      relatedLocationName = history.relatedLocation!.name;
    } else if (history.relatedLocationId != null) {
      // Fallback: try to find in _allLocations
      try {
        final loc = _allLocations.firstWhere((l) => l.id == history.relatedLocationId);
        relatedLocationName = loc.name;
      } catch (e) {
        relatedLocationName = 'Unknown';
      }
    }
    
    // Build location display with arrow for transfers
    String locationDisplay;
    if (relatedLocationName != null) {
      if (history.action == 'transfer_out') {
        locationDisplay = '$locationName → $relatedLocationName';
      } else if (history.action == 'transfer_in') {
        locationDisplay = '$relatedLocationName → $locationName';
      } else {
        locationDisplay = locationName;
      }
    } else {
      locationDisplay = locationName;
    }
    
    final colorScheme = Theme.of(context).colorScheme;
    final dividerColor = Theme.of(context).dividerColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border.all(color: dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Action description
                Text(
                  history.getActionDescription(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                
                // Location with arrow
                Text(
                  locationDisplay,
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          
          // Date and quantity change on right
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                dateFormat.format(history.created),
                style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(
                '${history.quantityBefore} → ${history.quantityAfter}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  // NEW: Build stat item widget for performance stats
  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey[400],
          ),
        ),
      ],
    );
  }
  
  // NEW: Show all history dialog
  Future<void> _showAllHistory() async {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Complete History',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 16),
              Expanded(
                child: FutureBuilder<List<dynamic>>(
                  future: PocketBaseService().getAllInventoryHistory(
                    toolId: widget.tool!.id,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    
                    if (snapshot.hasError) {
                      return Center(
                        child: Text('Error loading history: ${snapshot.error}'),
                      );
                    }
                    
                    final allHistory = snapshot.data
                        ?.map((r) => InventoryHistory.fromRecord(r))
                        .toList() ?? [];
                    
                    if (allHistory.isEmpty) {
                      return const Center(
                        child: Text('No history found'),
                      );
                    }
                    
                    // Use smart pairing for all history too
                    final historyWidgets = _buildHistoryItems(allHistory);
                    
                    return ListView.builder(
                      itemCount: historyWidgets.length,
                      itemBuilder: (context, index) {
                        return historyWidgets[index];
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _toolNameController.dispose();
    _modelNumberController.dispose();
    _urlController.dispose();
    _diameterInController.dispose();
    _diameterMmController.dispose();
    _flutesController.dispose();
    _fluteLengthController.dispose();
    _cornerRadController.dispose();
    _neckController.dispose();
    _drillIncludedAngleController.dispose();
    _tslotRadiusController.dispose();  // NEW
    _chamferAngleController.dispose();  // NEW
    _chamferTipDiameterController.dispose();  // NEW
    _notesController.dispose();
    _restockQtyController.dispose();
    _restockNotesController.dispose();
    super.dispose();
  }
}

// Keep the InventoryLocationTag widget exactly as it was (from previous version)
class InventoryLocationTag extends StatelessWidget {
  final Tool tool;
  final ToolLocation toolLocation;
  final List<Location> allLocations;
  final VoidCallback onChanged;

  const InventoryLocationTag({
    Key? key,
    required this.tool,
    required this.toolLocation,
    required this.allLocations,
    required this.onChanged,
  }) : super(key: key);

  String _buildLocationPath(Location location) {
    final names = <String>[];
    var current = location;
    
    while (true) {
      names.insert(0, current.name);
      
      if (current.parentId == null || current.parentId!.isEmpty) break;
      
      try {
        current = allLocations.firstWhere((loc) => loc.id == current.parentId);
      } catch (e) {
        break;
      }
    }
    
    return names.join('-');
  }

  @override
  Widget build(BuildContext context) {
    final location = toolLocation.location;
    final quantity = toolLocation.quantity;
    
    if (location == null) {
      return const SizedBox.shrink();
    }

    final locationPath = _buildLocationPath(location);
    final type = location.type.toLowerCase();
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color backgroundColor;
    Color borderColor;
    Color textColor;
    Color iconColor;
    if (isDark) {
      switch (type) {
        case 'toolbox':
          backgroundColor = colorScheme.errorContainer;
          borderColor = colorScheme.error;
          textColor = colorScheme.onErrorContainer;
          iconColor = colorScheme.onErrorContainer;
          break;
        case 'shelf':
          backgroundColor = colorScheme.tertiaryContainer;
          borderColor = colorScheme.tertiary;
          textColor = colorScheme.onTertiaryContainer;
          iconColor = colorScheme.onTertiaryContainer;
          break;
        case 'machine':
          backgroundColor = colorScheme.primaryContainer;
          borderColor = colorScheme.primary;
          textColor = colorScheme.onPrimaryContainer;
          iconColor = colorScheme.onPrimaryContainer;
          break;
        case 'recycle':
          backgroundColor = colorScheme.surfaceContainerHigh;
          borderColor = colorScheme.outline;
          textColor = colorScheme.onSurfaceVariant;
          iconColor = colorScheme.onSurfaceVariant;
          break;
        default:
          backgroundColor = colorScheme.surfaceContainerHigh;
          borderColor = colorScheme.outline;
          textColor = colorScheme.onSurfaceVariant;
          iconColor = colorScheme.onSurfaceVariant;
      }
    } else {
      switch (type) {
        case 'toolbox':
          backgroundColor = Colors.red[50]!;
          borderColor = Colors.red[300]!;
          textColor = Colors.red[900]!;
          iconColor = Colors.orange[700]!;
          break;
        case 'shelf':
          backgroundColor = Colors.orange[50]!;
          borderColor = Colors.orange[300]!;
          textColor = Colors.orange[900]!;
          iconColor = Colors.orange[700]!;
          break;
        case 'machine':
          backgroundColor = Colors.blue[50]!;
          borderColor = Colors.blue[300]!;
          textColor = Colors.blue[900]!;
          iconColor = Colors.orange[700]!;
          break;
        case 'recycle':
          backgroundColor = Colors.grey[200]!;
          borderColor = Colors.grey[400]!;
          textColor = Colors.grey[800]!;
          iconColor = Colors.orange[700]!;
          break;
        default:
          backgroundColor = Colors.grey[50]!;
          borderColor = Colors.grey[300]!;
          textColor = Colors.grey[900]!;
          iconColor = Colors.orange[700]!;
      }
    }

    return InkWell(
      onTap: () => _showTransferDialog(context),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Qty: $quantity • $locationPath',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Delete confirmation and execution
  Future<void> _confirmDelete(BuildContext context) async {
    final location = toolLocation.location;
    if (location == null) return;
    
    final locationPath = _buildLocationPath(location);
    final quantity = toolLocation.quantity;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from Location'),
        content: Text('Remove this tool from $locationPath?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      try {
        final pbService = PocketBaseService();
        
        // Log before deleting
        await pbService.logInventoryHistory(
          toolId: toolLocation.toolId,
          locationId: toolLocation.locationId,
          action: 'remove',
          quantity: quantity,
          quantityBefore: quantity,
          quantityAfter: 0,
        );
        
        await pbService.pb.collection('tool_locations').delete(toolLocation.id);
        onChanged();
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Removed from location!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
  
  Future<void> _showTransferDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => TransferDialog(
        tool: tool,
        sourceLocation: toolLocation,
        allLocations: allLocations,
      ),
    );
    if (result == true) {
      onChanged();
    }
  }
}

/// Dialog: scrollable grid of image URLs from a product page; user picks one for the tool photo.
class _PageImagePickerDialog extends StatefulWidget {
  final List<String> imageUrls;

  const _PageImagePickerDialog({required this.imageUrls});

  @override
  State<_PageImagePickerDialog> createState() => _PageImagePickerDialogState();
}

class _PageImagePickerDialogState extends State<_PageImagePickerDialog> {
  String? _selectedUrl;
  final PocketBaseService _pb = PocketBaseService();
  final Map<String, Future<Uint8List?>> _thumbFutures = {};

  Future<Uint8List?> _thumbFor(String url) {
    return _thumbFutures.putIfAbsent(url, () => _pb.fetchImageBytesViaMcp(url));
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = (MediaQuery.of(context).size.width * 0.82).clamp(
      720.0,
      1100.0,
    );
    return AlertDialog(
      title: const Text('Choose image from page'),
      content: SizedBox(
        width: dialogWidth,
        height: 360,
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: widget.imageUrls.length,
          itemBuilder: (context, index) {
            final u = widget.imageUrls[index];
            final sel = _selectedUrl == u;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _selectedUrl = u),
                borderRadius: BorderRadius.circular(8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: sel
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).dividerColor,
                      width: sel ? 3 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: ColoredBox(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.65),
                      child: SizedBox.expand(
                        child: FutureBuilder<Uint8List?>(
                          future: _thumbFor(u),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              );
                            }
                            final bytes = snapshot.data;
                            if (bytes == null || bytes.isEmpty) {
                              return const Center(
                                child: Icon(Icons.broken_image_outlined),
                              );
                            }
                            return Image.memory(
                              bytes,
                              fit: BoxFit.contain,
                              alignment: Alignment.center,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedUrl == null
              ? null
              : () => Navigator.pop(context, _selectedUrl),
          child: const Text('Use this image'),
        ),
      ],
    );
  }
}
