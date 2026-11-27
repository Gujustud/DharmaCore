// return_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models.dart';
import 'pocketbase_service.dart';

class ReturnDialog extends StatefulWidget {
  const ReturnDialog({super.key});

  @override
  State<ReturnDialog> createState() => _ReturnDialogState();
}

class _ReturnDialogState extends State<ReturnDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _toolsInMachines = [];
  List<Map<String, dynamic>> _filteredTools = [];
  Map<String, dynamic>? _selectedTool;
  int _quantity = 1;
  String? _selectedDestination;
  bool _isLoading = true;
  bool _isSubmitting = false;
  List<Location> _allLocations = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadToolsInMachines();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Build full hierarchical path for a location
  String _buildLocationPath(Location location) {
    final names = <String>[];
    var current = location;

    while (true) {
      names.insert(0, current.name);

      if (current.parentId == null || current.parentId!.isEmpty) break;

      try {
        current = _allLocations.firstWhere((loc) => loc.id == current.parentId);
      } catch (e) {
        break;
      }
    }

    return names.join(' - ');
  }

  Future<void> _loadToolsInMachines() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final pbService = PocketBaseService();

      // Load all locations for destination selection
      final locationRecords = await pbService.getLocations();
      _allLocations = locationRecords.map((r) => Location.fromRecord(r)).toList();

      // Find all machine locations
      final machineLocations = locationRecords.where((loc) => loc.data['type'] == 'machine').toList();

      // Get tools in each machine
      final List<Map<String, dynamic>> toolsInMachines = [];

      for (var machineLoc in machineLocations) {
        final toolLocations = await pbService.getToolLocationsAtLocation(machineLoc.id);

        for (var tl in toolLocations) {
          final toolId = tl.data['tool'];
          final tool = await pbService.getToolById(toolId);
          // Filament lives under machines for stock tracking but is not a
          // shop tool — omit from Return Tool (dashboard / inventory home).
          final category =
              (tool.data['category'] ?? '').toString().trim().toLowerCase();
          if (category == '3d filament') continue;

          toolsInMachines.add({
            'tool': tool,
            'tool_location': tl,
            'machine_location': machineLoc,
            'quantity': tl.data['quantity'],
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
          return tool.data['tool_name'].toString().toLowerCase().contains(query) ||
                 (tool.data['brand']?.toString().toLowerCase().contains(query) ?? false) ||
                 (tool.data['model_number']?.toString().toLowerCase().contains(query) ?? false) ||
                 machineLoc.data['name'].toString().toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  void _selectTool(Map<String, dynamic> toolData) {
    setState(() {
      if (_selectedTool == toolData) {
        // Deselect if already selected
        _selectedTool = null;
        _quantity = 1;
        _selectedDestination = null;
      } else {
        // Select new tool
        _selectedTool = toolData;
        _quantity = 1; // Reset quantity
        _selectedDestination = null; // Reset destination
      }
    });
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

  // Get available destinations grouped by type (recycle first, then shelves, then toolboxes)
  List<Location> get _availableDestinations {
    final locations = _allLocations.where((loc) => loc.type != 'machine').toList();

    // Group by type with specific ordering: recycle, shelf, toolbox
    final grouped = <Location>[];

    // Add recycle locations first
    grouped.addAll(locations.where((loc) => loc.type == 'recycle'));
    // Add shelf locations
    grouped.addAll(locations.where((loc) => loc.type == 'shelf'));
    // Add toolbox locations
    grouped.addAll(locations.where((loc) => loc.type == 'toolbox'));

    return grouped;
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
        toLocationId: _selectedDestination!,
        quantity: _quantity,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tool returned successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Close dialog and refresh parent screen
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Select Tool to Return',
        style: TextStyle(fontSize: 16),
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 600, // Make dialog wider
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search field
              TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search tools in machines...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),

              // Loading state
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else ...[
                // Results list
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
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(
                                '${machineLoc.data['name']} (Qty: $quantity)',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isSelected ? Colors.blue[700] : Colors.grey[600],
                                ),
                              ),
                              selected: isSelected,
                              onTap: () => _selectTool(toolData),
                            );
                          },
                        ),
                ),

                // Selection details
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
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'From: ${_selectedTool!['machine_location'].data['name']}',
                          style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                        ),
                        const SizedBox(height: 8),

                        // Quantity controls
                        Row(
                          children: [
                            const Text('Quantity: '),
                            IconButton(
                              onPressed: _decrementQuantity,
                              icon: const Icon(Icons.remove),
                              iconSize: 16,
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey[400]!),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('$_quantity'),
                            ),
                            IconButton(
                              onPressed: _incrementQuantity,
                              icon: const Icon(Icons.add),
                              iconSize: 16,
                            ),
                            Text(' (max: ${_selectedTool!['quantity']})'),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // Destination dropdown
                        DropdownButtonFormField<String>(
                          value: _selectedDestination,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Return to',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: _availableDestinations.map((location) {
                            return DropdownMenuItem<String>(
                              value: location.id,
                              child: Text(
                                _buildLocationPath(location),
                                style: const TextStyle(fontSize: 14),
                              ),
                            );
                          }).toList(),
                          onChanged: _isSubmitting
                              ? null
                              : (value) {
                                  setState(() {
                                    _selectedDestination = value;
                                  });
                                },
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
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting || _selectedTool == null ? null : _handleReturn,
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