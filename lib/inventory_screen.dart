// inventory_screen.dart
import 'package:flutter/material.dart';
import 'models.dart';
import 'pocketbase_service.dart';
import 'transfer_dialog.dart';
import 'add_tool_screen.dart';
import 'return_dialog.dart';
import 'drawer_behavior.dart';
import 'list_toolbar_widgets.dart';
import 'tool_style_icons.dart';
import 'workspace_layout.dart';
import 'workspace_scaffold.dart';

class InventoryScreen extends StatefulWidget {
  final String? categoryFilter; // Optional category filter
  final String? initialSearchQuery; // Optional: pre-fill search (e.g. from main page)

  const InventoryScreen({
    super.key,
    this.categoryFilter,
    this.initialSearchQuery,
  });

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> with AutoOpenDrawerMixin {
  final _pbService = PocketBaseService();
  List<ToolWithLocations> _toolsWithLocations = [];
  List<ToolWithLocations> _filteredTools = [];
  List<Location> _allLocations = [];
  bool _isLoading = true;
  bool _showToolDetails = true; // NEW: Default to true
  String? _errorMessage;
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Active filter selections
  String? _selectedBrandFilter;
  String? _selectedSubcatFilter;
  String? _selectedSubSubcatFilter;

  // Available filter options (derived from loaded tools)
  List<String> _availableBrands = [];
  List<String> _availableSubcats = [];

  @override
  GlobalKey<ScaffoldState> get scaffoldKey => _scaffoldKey;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    if (widget.initialSearchQuery != null && widget.initialSearchQuery!.trim().isNotEmpty) {
      _searchController.text = widget.initialSearchQuery!.trim();
    }
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() => _applyFilters();

  void _applyFilters() {
    final rawInput = _searchController.text.toLowerCase();
    final rawTokens = rawInput.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    // Special-case: treat "bin <number>" as a phrase match against location paths.
    final requiredBinNumbers = <String>[];
    final exactBinNumbers = <String>{};
    final tokens = <String>[];
    for (var i = 0; i < rawTokens.length; i++) {
      final t = rawTokens[i];
      if (t == 'bin' && i + 1 < rawTokens.length) {
        final next = rawTokens[i + 1];
        if (RegExp(r'^\d+$').hasMatch(next)) {
          requiredBinNumbers.add(next);
          final isLastPair = i + 1 == rawTokens.length - 1;
          if (isLastPair && rawInput.endsWith(' ')) {
            exactBinNumbers.add(next);
          }
          i++;
          continue;
        }
      }
      tokens.add(t);
    }

    setState(() {
      _filteredTools = _toolsWithLocations.where((toolWithLoc) {
        final tool = toolWithLoc.tool;

        // Brand filter
        if (_selectedBrandFilter != null) {
          final toolBrand = (tool.brand ?? '').trim().toLowerCase();
          if (toolBrand != _selectedBrandFilter!.toLowerCase()) return false;
        }

        // Subcategory filter (match on first segment, e.g. "End Mills")
        if (_selectedSubcatFilter != null) {
          final toolSubcat = (tool.subcategory ?? '').trim().toLowerCase();
          if (!toolSubcat.startsWith(_selectedSubcatFilter!.toLowerCase())) return false;
        }

        // Sub-subcategory filter (match on second segment, e.g. "Ball")
        if (_selectedSubSubcatFilter != null) {
          final parts = (tool.subcategory ?? '').split(' > ');
          final second = parts.length > 1 ? parts[1].trim().toLowerCase() : '';
          if (second != _selectedSubSubcatFilter!.toLowerCase()) return false;
        }

        // Text search
        if (rawInput.trim().isNotEmpty) {
          final locationText = toolWithLoc.locations
              .map((tl) => _buildLocationPathFromToolLocation(tl))
              .where((s) => s.isNotEmpty)
              .join(' | ')
              .toLowerCase();

          final binsOk = requiredBinNumbers.every((n) {
            final re = exactBinNumbers.contains(n)
                ? RegExp(r'\bbin\s*' + RegExp.escape(n) + r'\b')
                : RegExp(r'\bbin\s*' + RegExp.escape(n) + r'\d*\b');
            return re.hasMatch(locationText);
          });
          if (!binsOk) return false;

          final fields = <String>[
            tool.toolName,
            tool.brand ?? '',
            tool.modelNumber ?? '',
            tool.category,
            tool.subcategory ?? '',
            locationText,
          ].join(' ').toLowerCase();

          if (!tokens.every(fields.contains)) return false;
        }

        return true;
      }).toList();
    });
  }

  String _buildLocationPathFromToolLocation(ToolLocation tl) {
    final loc = tl.location;
    if (loc == null) return '';
    final names = <String>[];
    Location? current = loc;
    while (current != null) {
      names.insert(0, current.name);
      final parentId = current.parentId;
      if (parentId == null || parentId.isEmpty) break;
      try {
        current = _allLocations.firstWhere((l) => l.id == parentId);
      } catch (_) {
        break;
      }
    }
    return names.join(' ');
  }

  void _navigateToAddTool() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddToolScreen(
          initialCategory: widget.categoryFilter, // Pass the category filter
        ),
      ),
    );
    if (result == true) {
      _loadData();
    }
  }

  void _navigateToEditTool(Tool tool) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddToolScreen(tool: tool),
      ),
    );
    if (result == true) {
      _loadData();
    }
  }

  void _navigateToDuplicateTool(Tool tool) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddToolScreen(tool: tool, isDuplicate: true),
      ),
    );
    if (result == true) {
      _loadData();
    }
  }

  void _navigateToReturnTool() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const ReturnDialog(),
    );
    if (result == true) {
      _loadData();
    }
  }

  Future<void> _deleteTool(Tool tool) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Tool'),
        content: Text('Are you sure you want to delete "${tool.toolName}"?\n\nThis will remove all inventory records for this tool.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Delete all tool_locations first
        final toolLocationRecords = await _pbService.pb
            .collection('tool_locations')
            .getFullList(filter: 'tool = "${tool.id}"');
        
        for (final record in toolLocationRecords) {
          await _pbService.pb.collection('tool_locations').delete(record.id);
        }
        
        // Delete the tool
        await _pbService.pb.collection('inventory').delete(tool.id);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Tool "${tool.toolName}" deleted'),
              backgroundColor: Colors.green,
            ),
          );
        }
        
        _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting tool: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // NEW: Load app settings first
      final settings = await _pbService.getAppSettings();
      final showDetails = settings.data['show_tool_details_in_list'] ?? true;
      
      // Load all locations first
      final locationRecords = await _pbService.getLocations();
      _allLocations = locationRecords.map((r) => Location.fromRecord(r)).toList();

      // Load all tools
      final toolRecords = await _pbService.getTools();
      List<Tool> tools = toolRecords.map((r) => Tool.fromRecord(r)).toList();

      // NEW: Filter by category if specified (case-insensitive, trim)
      if (widget.categoryFilter != null) {
        final filterName = widget.categoryFilter!.trim().toLowerCase();
        tools = tools.where((tool) {
          final toolCategory = (tool.category).trim().toLowerCase();
          return toolCategory == filterName;
        }).toList();
      }

      // Load all tool_locations once (avoid N+1 requests), then group by tool id.
      final allToolLocationRecords = await _pbService.getAllToolLocations();
      final locationsByToolId = <String, List<ToolLocation>>{};
      for (final r in allToolLocationRecords) {
        final toolId = r.data['tool']?.toString();
        if (toolId == null || toolId.isEmpty) continue;
        (locationsByToolId[toolId] ??= []).add(ToolLocation.fromRecord(r));
      }

      final toolsWithLocs = <ToolWithLocations>[];
      for (final tool in tools) {
        toolsWithLocs.add(ToolWithLocations(
          tool: tool,
          locations: locationsByToolId[tool.id] ?? const [],
        ));
      }

      // Sort by diameter (SMALLEST first, tools with no diameter go to end)
      toolsWithLocs.sort((a, b) {
        // Get diameter for sorting (prefer inches, fallback to mm)
        final aDia = a.tool.diameterIn ?? a.tool.diameterMm ?? 0.0;
        final bDia = b.tool.diameterIn ?? b.tool.diameterMm ?? 0.0;

        // Tools with no diameter go to the end
        if (aDia == 0.0 && bDia > 0.0) return 1;  // a goes after b
        if (bDia == 0.0 && aDia > 0.0) return -1; // a goes before b

        // Sort by diameter ASCENDING (smallest first), then by name
        if (aDia != bDia) {
          return aDia.compareTo(bDia);
        }

        return a.tool.toolName.compareTo(b.tool.toolName);
      });

      // Build available filter options from the loaded tools
      final brands = toolsWithLocs
          .map((t) => t.tool.brand ?? '')
          .where((b) => b.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      // Use only the first segment of subcategory (e.g. "End Mills" from "End Mills > Ball")
      final subcats = toolsWithLocs
          .map((t) => (t.tool.subcategory ?? '').split(' > ').first.trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      setState(() {
        _toolsWithLocations = toolsWithLocs;
        _filteredTools = toolsWithLocs;
        _showToolDetails = showDetails;
        _availableBrands = brands;
        _availableSubcats = subcats;
        _isLoading = false;
      });
      // Re-apply search/filter when opening with initialSearchQuery (e.g. from main page)
      _applyFilters();
    } catch (e, stackTrace) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  List<String> _stylesForSelectedType() {
    if (_selectedSubcatFilter == null) return const [];
    final type = _selectedSubcatFilter!.toLowerCase();
    return _toolsWithLocations
        .where((t) {
          final parts = (t.tool.subcategory ?? '').split(' > ');
          return parts.isNotEmpty &&
              parts[0].trim().toLowerCase() == type &&
              parts.length > 1 &&
              parts[1].trim().isNotEmpty;
        })
        .map((t) => (t.tool.subcategory ?? '').split(' > ')[1].trim())
        .toSet()
        .toList()
      ..sort();
  }

  /// Type chips when idle; All + style icons after a type is picked.
  /// Parent provides horizontal scrolling.
  Widget _buildTypeOrStyleFilterStrip() {
    if (_selectedSubcatFilter == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _availableSubcats.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Builder(builder: (_) {
              final type = _availableSubcats[i];
              void select() {
                setState(() {
                  _selectedSubcatFilter = type;
                  _selectedSubSubcatFilter = null;
                });
                _applyFilters();
              }

              if (ToolStyleIcons.hasTypeIcon(type)) {
                return ToolStyleIconButton(
                  label: type,
                  assetPath: ToolStyleIcons.assetForType(type),
                  selected: false,
                  onTap: select,
                );
              }
              return ToolFilterChipButton(
                label: type,
                selected: false,
                onTap: select,
              );
            }),
          ],
        ],
      );
    }

    final styles = _stylesForSelectedType();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Returns to type chips (Endmills / Drills / Threading)
        ToolFilterChipButton(
          label: 'All',
          selected: false,
          onTap: () {
            setState(() {
              _selectedSubcatFilter = null;
              _selectedSubSubcatFilter = null;
            });
            _applyFilters();
          },
        ),
        for (final style in styles) ...[
          const SizedBox(width: 8),
          if (ToolStyleIcons.hasIcon(style))
            ToolStyleIconButton(
              label: style,
              assetPath: ToolStyleIcons.assetForStyle(style),
              selected: _selectedSubSubcatFilter == style,
              onTap: () {
                setState(() {
                  _selectedSubSubcatFilter =
                      _selectedSubSubcatFilter == style ? null : style;
                });
                _applyFilters();
              },
            )
          else
            ToolFilterChipButton(
              label: style,
              selected: _selectedSubSubcatFilter == style,
              onTap: () {
                setState(() {
                  _selectedSubSubcatFilter =
                      _selectedSubSubcatFilter == style ? null : style;
                });
                _applyFilters();
              },
            ),
        ],
      ],
    );
  }

  Future<void> _handleTransfer({
    required Tool tool,
    required ToolLocation sourceLocation,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => TransferDialog(
        tool: tool,
        sourceLocation: sourceLocation,
        allLocations: _allLocations,
      ),
    );

    if (result == true) {
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 600;

    final bodyContent = Column(
      children: [
        // Top action bar with search and buttons (centered)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: isNarrow
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        InventoryListSearchField(
                          controller: _searchController,
                          hintText: 'Search tools...',
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: InventoryListActionButton(
                                label: 'Add Tool',
                                onPressed: _navigateToAddTool,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: InventoryListActionButton(
                                label: 'Return Tool',
                                icon: Icons.keyboard_return,
                                onPressed: _navigateToReturnTool,
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          flex: 3,
                          child: InventoryListSearchField(
                            controller: _searchController,
                            hintText: 'Search tools...',
                          ),
                        ),
                        const SizedBox(width: 12),
                        InventoryListActionButton(
                          label: 'Add Tool',
                          onPressed: _navigateToAddTool,
                        ),
                        const SizedBox(width: 12),
                        InventoryListActionButton(
                          label: 'Return Tool',
                          icon: Icons.keyboard_return,
                          onPressed: _navigateToReturnTool,
                        ),
                      ],
                    ),
            ),
          ),
        ),

        // Filter bar: brand dropdown + type chips / style icons (same row)
        if (!_isLoading && (_availableBrands.isNotEmpty || _availableSubcats.isNotEmpty))
          Container(
            color: Theme.of(context).cardColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                if (_availableBrands.isNotEmpty) ...[
                  SizedBox(
                    width: isNarrow ? 120 : 160,
                    height: 40,
                    child: DropdownButtonFormField<String>(
                      value: _selectedBrandFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('All brands'),
                        ),
                        ..._availableBrands.map(
                          (b) => DropdownMenuItem<String>(
                            value: b,
                            child: Text(b, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        setState(() => _selectedBrandFilter = v);
                        _applyFilters();
                      },
                    ),
                  ),
                  if (_availableSubcats.isNotEmpty) const SizedBox(width: 12),
                ],
                if (_availableSubcats.isNotEmpty)
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _buildTypeOrStyleFilterStrip(),
                    ),
                  ),
                if (_selectedBrandFilter != null ||
                    _selectedSubcatFilter != null ||
                    _selectedSubSubcatFilter != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Clear filters',
                    onPressed: () {
                      setState(() {
                        _selectedBrandFilter = null;
                        _selectedSubcatFilter = null;
                        _selectedSubSubcatFilter = null;
                      });
                      _applyFilters();
                    },
                  ),
                ],
              ],
            ),
          ),

        // Tool list (takes remaining space)
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Error: $_errorMessage',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadData,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : _filteredTools.isEmpty && _searchController.text.isNotEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.search_off,
                                size: 48,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No tools found for "${_searchController.text}"',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : _filteredTools.isEmpty
                          ? Center(
                              child: Text(
                                'No tools found.\nAdd some tools to get started!',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _filteredTools.length,
                              itemBuilder: (context, index) {
                                return ToolCard(
                                  toolWithLocations: _filteredTools[index],
                                  allLocations: _allLocations,
                                  showToolDetails: _showToolDetails, // NEW
                                  onTap: () => _navigateToEditTool(_filteredTools[index].tool),
                                  onEdit: () => _navigateToEditTool(_filteredTools[index].tool),
                                  onDuplicate: () => _navigateToDuplicateTool(_filteredTools[index].tool),
                                  onDelete: () => _deleteTool(_filteredTools[index].tool),
                                  onTransfer: (sourceLocation) {
                                    _handleTransfer(
                                      tool: _filteredTools[index].tool,
                                      sourceLocation: sourceLocation,
                                    );
                                  },
                                );
                              },
                            ),
        ),
      ],
    );

    return WorkspaceScaffold(
      scaffoldKey: _scaffoldKey,
      appBar: AppBar(
        title: Text(widget.categoryFilter ?? 'All Inventory'), // UPDATED: Dynamic title
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: workspaceMenuLeading(context),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: bodyContent,
    );
  }
}

class ToolCard extends StatelessWidget {
  final ToolWithLocations toolWithLocations;
  final List<Location> allLocations;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final Function(ToolLocation) onTransfer;
  final bool showToolDetails; // NEW

  const ToolCard({
    Key? key,
    required this.toolWithLocations,
    required this.allLocations,
    required this.onTap,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onTransfer,
    required this.showToolDetails, // NEW
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tool = toolWithLocations.tool;
    final locations = toolWithLocations.sortedLocations;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final titleStyle =
        textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
    final muted =
        textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    final visibleLocations = locations
        .where((loc) => loc.location?.type.toLowerCase() != 'recycle')
        .toList();

    return GestureDetector(
      onTap: onTap,
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: tool details
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tool.toolName, style: titleStyle),
                    const SizedBox(height: 4),
                    if (tool.subcategory != null &&
                        tool.subcategory!.isNotEmpty) ...[
                      Text(
                        tool.subcategory!,
                        style: muted?.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ],
                    if (tool.modelNumber != null &&
                        tool.modelNumber!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('Model: ${tool.modelNumber}', style: muted),
                    ],
                    if (showToolDetails && tool.displaySpecs.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(tool.displaySpecs, style: muted),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Right: actions + location tags (wider so tags stay side by side)
              Expanded(
                flex: 3,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Allow ~2 tags per row before wrapping on typical desktop widths.
                    final maxTagWidth =
                        (constraints.maxWidth * 0.48).clamp(120.0, 280.0);
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              onPressed: onEdit,
                              tooltip: 'Edit',
                              color: Colors.grey[700],
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              onPressed: onDuplicate,
                              tooltip: 'Duplicate',
                              color: Colors.grey[700],
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 18),
                              onPressed: onDelete,
                              tooltip: 'Delete',
                              color: Colors.grey[700],
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                        if (visibleLocations.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            alignment: WrapAlignment.end,
                            children: [
                              for (final toolLocation in visibleLocations)
                                ConstrainedBox(
                                  constraints:
                                      BoxConstraints(maxWidth: maxTagWidth),
                                  child: LocationTag(
                                    toolLocation: toolLocation,
                                    allLocations: allLocations,
                                    onTap: () => onTransfer(toolLocation),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
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
}

class LocationTag extends StatelessWidget {
  final ToolLocation toolLocation;
  final List<Location> allLocations;
  final VoidCallback onTap;

  const LocationTag({
    Key? key,
    required this.toolLocation,
    required this.allLocations,
    required this.onTap,
  }) : super(key: key);

  // Build hierarchical path showing only names separated by dashes
  String _buildLocationPath(Location location) {
    final names = <String>[];
    var current = location;
    
    // Walk up the parent chain
    while (true) {
      names.insert(0, current.name);
      
      if (current.parentId == null || current.parentId!.isEmpty) break;
      
      // Find parent
      try {
        current = allLocations.firstWhere((loc) => loc.id == current.parentId);
      } catch (e) {
        break; // Parent not found
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
    final isEmpty = quantity <= 0; // Show 0-qty as "home" location with muted style

    // Theme-aware colors: use container colors in dark mode so tags aren't overly bright
    // Empty (0-qty) uses muted outline so "home bin" stays visible
    Color backgroundColor;
    Color borderColor;
    Color textColor;
    if (isEmpty) {
      backgroundColor = colorScheme.surfaceContainerHighest;
      borderColor = colorScheme.outline;
      textColor = colorScheme.onSurfaceVariant;
    } else if (isDark) {
      switch (type) {
        case 'toolbox':
          backgroundColor = colorScheme.errorContainer;
          borderColor = colorScheme.error;
          textColor = colorScheme.onErrorContainer;
          break;
        case 'shelf':
          backgroundColor = colorScheme.tertiaryContainer;
          borderColor = colorScheme.tertiary;
          textColor = colorScheme.onTertiaryContainer;
          break;
        case 'machine':
          backgroundColor = colorScheme.primaryContainer;
          borderColor = colorScheme.primary;
          textColor = colorScheme.onPrimaryContainer;
          break;
        default:
          backgroundColor = colorScheme.surfaceContainerHigh;
          borderColor = colorScheme.outline;
          textColor = colorScheme.onSurfaceVariant;
      }
    } else {
      switch (type) {
        case 'toolbox':
          backgroundColor = Colors.red[50]!;
          borderColor = Colors.red[300]!;
          textColor = Colors.red[900]!;
          break;
        case 'shelf':
          backgroundColor = Colors.orange[50]!;
          borderColor = Colors.orange[300]!;
          textColor = Colors.orange[900]!;
          break;
        case 'machine':
          backgroundColor = Colors.blue[50]!;
          borderColor = Colors.blue[300]!;
          textColor = Colors.blue[900]!;
          break;
        default:
          backgroundColor = Colors.grey[50]!;
          borderColor = Colors.grey[300]!;
          textColor = Colors.grey[900]!;
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Text(
          'Qty: $quantity • $locationPath',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
      ),
    );
  }
}
