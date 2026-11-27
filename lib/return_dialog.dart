// return_dialog.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'models.dart';
import 'pocketbase_service.dart';
import 'tool_location_helpers.dart';

class ReturnDialog extends StatefulWidget {
  const ReturnDialog({super.key});

  @override
  State<ReturnDialog> createState() => _ReturnDialogState();
}

class _ReturnDialogState extends State<ReturnDialog> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _destSearchController = TextEditingController();
  List<Map<String, dynamic>> _toolsInMachines = [];
  List<Map<String, dynamic>> _filteredTools = [];
  Map<String, dynamic>? _selectedTool;
  int _quantity = 1;
  String? _selectedDestination;
  bool _isLoading = true;
  bool _isSubmitting = false;
  List<Location> _allLocations = [];

  /// Home bin for the currently selected tool (toolbox row, qty may be 0).
  Location? _homeBin;
  List<Location>? _destSuggestions;
  Timer? _destSearchDebounce;
  static const int _maxDestSuggestions = 8;
  static const int _minDestSearchLength = 1;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadToolsInMachines();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _destSearchController.dispose();
    _destSearchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadToolsInMachines() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final pbService = PocketBaseService();

      final locationRecords = await pbService.getLocations();
      _allLocations =
          locationRecords.map((r) => Location.fromRecord(r)).toList();

      final machineLocations =
          locationRecords.where((loc) => loc.data['type'] == 'machine').toList();

      final List<Map<String, dynamic>> toolsInMachines = [];

      for (var machineLoc in machineLocations) {
        final toolLocations =
            await pbService.getToolLocationsAtLocation(machineLoc.id);

        for (var tl in toolLocations) {
          final qty = toolLocationQuantity(tl.data['quantity']);
          // Zero-qty machine tags are leftover "was here" rows — not returnable.
          if (qty <= 0) continue;

          final toolId = tl.data['tool'];
          final tool = await pbService.getToolById(toolId);
          final category = (tool.data['category'] ?? '').toString();
          if (isFilamentToolCategory(category)) continue;

          toolsInMachines.add({
            'tool': tool,
            'tool_location': tl,
            'machine_location': machineLoc,
            'quantity': qty,
          });
        }
      }

      setState(() {
        _toolsInMachines = toolsInMachines;
        _filteredTools = toolsInMachines;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading tools: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredTools = _toolsInMachines;
      } else {
        _filteredTools = _toolsInMachines.where((toolData) {
          final tool = toolData['tool'] as dynamic;
          final machineLoc = toolData['machine_location'] as dynamic;
          return tool.data['tool_name']
                  .toString()
                  .toLowerCase()
                  .contains(query) ||
              (tool.data['brand']
                      ?.toString()
                      .toLowerCase()
                      .contains(query) ??
                  false) ||
              (tool.data['model_number']
                      ?.toString()
                      .toLowerCase()
                      .contains(query) ??
                  false) ||
              machineLoc.data['name']
                  .toString()
                  .toLowerCase()
                  .contains(query);
        }).toList();
      }
    });
  }

  Future<void> _selectTool(Map<String, dynamic> toolData) async {
    if (_selectedTool == toolData) {
      setState(() {
        _selectedTool = null;
        _quantity = 1;
        _selectedDestination = null;
        _homeBin = null;
        _destSearchController.clear();
        _destSuggestions = null;
      });
      return;
    }

    setState(() {
      _selectedTool = toolData;
      _quantity = 1;
      _selectedDestination = null;
      _homeBin = null;
      _destSearchController.clear();
      _destSuggestions = null;
    });

    try {
      final tool = toolData['tool'];
      final records = await PocketBaseService().getToolLocations(tool.id);
      final toolLocs =
          records.map((r) => ToolLocation.fromRecord(r)).toList();
      final home = findHomeBinLocation(
        toolLocations: toolLocs,
        allLocations: _allLocations,
        excludeLocationId: toolData['machine_location'].id as String?,
      );
      if (!mounted || _selectedTool != toolData) return;
      setState(() => _homeBin = home);
    } catch (_) {
      // No home bin → quick button stays hidden.
    }
  }

  void _incrementQuantity() {
    if (_selectedTool != null && _quantity < _selectedTool!['quantity']) {
      setState(() {
        _quantity++;
      });
    }
  }

  void _decrementQuantity() {
    if (_quantity > 1) {
      setState(() {
        _quantity--;
      });
    }
  }

  /// Leaf recycle / shelf / toolbox destinations (no filament shelves, no parents).
  List<Location> get _availableDestinations {
    final destinations = _allLocations.where((loc) {
      final type = loc.type.trim().toLowerCase();
      if (type == 'machine') return false;
      if (isFilamentShelfLocation(loc)) return false;
      if (type == 'shelf' || type == 'toolbox' || type == 'recycle') {
        return isLeafLocation(loc, _allLocations);
      }
      return false;
    }).toList();

    destinations.sort((a, b) {
      const order = {'recycle': 0, 'shelf': 1, 'toolbox': 2};
      final ao = order[a.type.toLowerCase()] ?? 9;
      final bo = order[b.type.toLowerCase()] ?? 9;
      if (ao != bo) return ao.compareTo(bo);
      return buildLocationPath(a, _allLocations)
          .compareTo(buildLocationPath(b, _allLocations));
    });
    return destinations;
  }

  void _onDestSearchChanged() {
    final query = _destSearchController.text.trim();
    if (query.length < _minDestSearchLength) {
      setState(() => _destSuggestions = null);
      return;
    }
    _destSearchDebounce?.cancel();
    _destSearchDebounce = Timer(const Duration(milliseconds: 150), () {
      final q = query.toLowerCase();
      final matches = _availableDestinations
          .map((loc) => MapEntry(loc, buildLocationPath(loc, _allLocations)))
          .where((e) => e.value.toLowerCase().contains(q))
          .toList();
      if (mounted) {
        setState(() {
          _destSuggestions =
              matches.take(_maxDestSuggestions).map((e) => e.key).toList();
        });
      }
    });
  }

  void _selectDestination(Location loc) {
    setState(() {
      _selectedDestination = loc.id;
      _destSearchController.clear();
      _destSuggestions = null;
    });
  }

  void _clearDestination() {
    setState(() {
      _selectedDestination = null;
      _destSuggestions = null;
    });
  }

  Future<void> _performReturn({required String toLocationId}) async {
    if (_selectedTool == null) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final pbService = PocketBaseService();
      final tool = _selectedTool!['tool'];
      final sourceLocationId = _selectedTool!['tool_location'].data['location'];

      await pbService.moveTool(
        toolId: tool.id,
        fromLocationId: sourceLocationId,
        toLocationId: toLocationId,
        quantity: _quantity,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tool returned successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _isSubmitting = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error returning tool: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleReturn() async {
    if (_selectedTool == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a tool to return'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedDestination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a destination'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await _performReturn(toLocationId: _selectedDestination!);
  }

  /// One-tap return to home bin (no second Confirm click).
  Future<void> _handleQuickHomeBin() async {
    final home = _homeBin;
    if (home == null || _selectedTool == null || _isSubmitting) return;
    await _performReturn(toLocationId: home.id);
  }

  @override
  Widget build(BuildContext context) {
    final home = _homeBin;
    final homeLabel = home?.name;

    return AlertDialog(
      title: const Text(
        'Select Tool to Return',
        style: TextStyle(fontSize: 16),
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search tools in machines...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else ...[
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _filteredTools.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Text(
                              _searchController.text.isEmpty
                                  ? 'No tools currently in machines'
                                  : 'No tools found matching "${_searchController.text}"',
                              style: TextStyle(color: Colors.grey[600]),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _filteredTools.length,
                          itemBuilder: (context, index) {
                            final toolData = _filteredTools[index];
                            final tool = toolData['tool'];
                            final machineLoc = toolData['machine_location'];
                            final quantity = toolData['quantity'];
                            final isSelected = _selectedTool == toolData;

                            return ListTile(
                              leading: Icon(
                                Icons.build,
                                color: isSelected ? Colors.blue : Colors.grey,
                              ),
                              title: Text(
                                tool.data['tool_name'] ?? 'Unknown Tool',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(
                                '${machineLoc.data['name']} (Qty: $quantity)',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isSelected
                                      ? Colors.blue[700]
                                      : Colors.grey[600],
                                ),
                              ),
                              selected: isSelected,
                              onTap: _isSubmitting
                                  ? null
                                  : () => _selectTool(toolData),
                            );
                          },
                        ),
                ),
                if (_selectedTool != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Selected: ${_selectedTool!['tool'].data['tool_name']}',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'From: ${_selectedTool!['machine_location'].data['name']}',
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey[700]),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('Quantity: '),
                            IconButton(
                              onPressed:
                                  _isSubmitting ? null : _decrementQuantity,
                              icon: const Icon(Icons.remove),
                              iconSize: 16,
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey[400]!),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('$_quantity'),
                            ),
                            IconButton(
                              onPressed:
                                  _isSubmitting ? null : _incrementQuantity,
                              icon: const Icon(Icons.add),
                              iconSize: 16,
                            ),
                            Text(' (max: ${_selectedTool!['quantity']})'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _selectedDestination != null
                                  ? Builder(
                                      builder: (context) {
                                        Location? loc;
                                        try {
                                          loc = _allLocations.firstWhere(
                                              (l) =>
                                                  l.id == _selectedDestination);
                                        } catch (_) {
                                          loc = null;
                                        }
                                        final path = loc != null
                                            ? buildLocationPath(
                                                loc, _allLocations)
                                            : _selectedDestination!;
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 12),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                                color: Colors.grey[400]!),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            color: Colors.grey[50],
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  path,
                                                  style: const TextStyle(
                                                      fontSize: 14),
                                                ),
                                              ),
                                              if (!_isSubmitting)
                                                TextButton(
                                                  onPressed: _clearDestination,
                                                  child: const Text('Change'),
                                                ),
                                            ],
                                          ),
                                        );
                                      },
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        TextField(
                                          controller: _destSearchController,
                                          enabled: !_isSubmitting,
                                          style: const TextStyle(fontSize: 14),
                                          decoration: InputDecoration(
                                            labelText: 'Return to',
                                            hintText: 'Search destination…',
                                            prefixIcon:
                                                const Icon(Icons.search),
                                            border: const OutlineInputBorder(),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8),
                                          ),
                                          onChanged: (_) =>
                                              _onDestSearchChanged(),
                                        ),
                                        if (_destSuggestions != null &&
                                            _destSuggestions!.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Card(
                                            elevation: 2,
                                            child: ListView.separated(
                                              shrinkWrap: true,
                                              padding: EdgeInsets.zero,
                                              itemCount:
                                                  _destSuggestions!.length,
                                              separatorBuilder: (_, __) =>
                                                  const Divider(height: 1),
                                              itemBuilder: (context, i) {
                                                final loc =
                                                    _destSuggestions![i];
                                                final path = buildLocationPath(
                                                    loc, _allLocations);
                                                return ListTile(
                                                  dense: true,
                                                  title: Text(
                                                    path,
                                                    style: const TextStyle(
                                                        fontSize: 13),
                                                  ),
                                                  onTap: () =>
                                                      _selectDestination(loc),
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                            ),
                            if (home != null && homeLabel != null) ...[
                              const SizedBox(width: 8),
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: OutlinedButton.icon(
                                  onPressed: _isSubmitting
                                      ? null
                                      : _handleQuickHomeBin,
                                  icon: const Icon(Icons.inventory_2_outlined,
                                      size: 18),
                                  label: Text(homeLabel),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 14),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ||
                  _selectedTool == null ||
                  _selectedDestination == null
              ? null
              : _handleReturn,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Return Tool'),
        ),
      ],
    );
  }
}
