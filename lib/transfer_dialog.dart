// transfer_dialog.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'dmu_machine_icon.dart';
import 'models.dart';
import 'pocketbase_service.dart';
import 'tool_location_helpers.dart';

class TransferDialog extends StatefulWidget {
  final Tool tool;
  final ToolLocation sourceLocation;
  final List<Location> allLocations;

  const TransferDialog({
    Key? key,
    required this.tool,
    required this.sourceLocation,
    required this.allLocations,
  }) : super(key: key);

  @override
  State<TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<TransferDialog> {
  /// Exact [Location.name] values for machine shortcuts (one icon each). Edit to match PocketBase.
  static const List<String> _machineShortcutNames = ['DMU65'];

  /// Exact [Location.name] for the recycle / trash destination shortcut.
  static const String _trashShortcutName = 'Trash';

  int _quantity = 1;
  String? _selectedDestination;
  bool _isSubmitting = false;
  Location? _homeBin;

  final TextEditingController _searchController = TextEditingController();
  List<Location>? _suggestions;
  Timer? _searchDebounce;
  static const int _maxSuggestions = 5;
  static const int _minSearchLength = 2;

  @override
  void initState() {
    super.initState();
    _loadHomeBin();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadHomeBin() async {
    try {
      final records =
          await PocketBaseService().getToolLocations(widget.tool.id);
      final toolLocs =
          records.map((r) => ToolLocation.fromRecord(r)).toList();
      final home = findHomeBinLocation(
        toolLocations: toolLocs,
        allLocations: widget.allLocations,
        excludeLocationId: widget.sourceLocation.locationId,
      );
      if (!mounted) return;
      setState(() => _homeBin = home);
    } catch (_) {
      // Leave _homeBin null — shortcut hidden.
    }
  }

  String _buildLocationPath(Location location) {
    return buildLocationPath(location, widget.allLocations);
  }

  /// Valid destinations (exclude source; hide filament shelves).
  List<Location> get _destinationLocations {
    return widget.allLocations.where((loc) {
      if (loc.id == widget.sourceLocation.locationId) return false;
      if (isFilamentShelfLocation(loc)) return false;
      return true;
    }).toList();
  }

  /// First destination whose leaf [Location.name] equals [exactName], or null.
  Location? _locationForExactName(String exactName) {
    if (exactName.isEmpty) return null;
    try {
      return _destinationLocations.firstWhere((l) => l.name == exactName);
    } catch (_) {
      return null;
    }
  }

  Widget _greyDestinationShortcut({
    required String label,
    required Widget icon,
    required Location? location,
  }) {
    final loc = location;
    final enabled = !_isSubmitting && loc != null;
    final tooltip = loc != null
        ? label
        : 'No destination named "$label" (or same as source)';
    final iconColor = enabled ? Colors.grey[700]! : Colors.grey[400]!;

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: IconButton(
        tooltip: tooltip,
        icon: IconTheme(
          data: IconThemeData(color: iconColor, size: 22),
          child: icon,
        ),
        onPressed: enabled ? () => _selectDestination(loc) : null,
        style: IconButton.styleFrom(
          foregroundColor: iconColor,
          backgroundColor: Colors.grey[200],
          disabledForegroundColor: Colors.grey[400],
          disabledBackgroundColor: Colors.grey[100],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.length < _minSearchLength) {
      setState(() => _suggestions = null);
      return;
    }
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      final q = query.toLowerCase();
      final paths = _destinationLocations
          .map((loc) => MapEntry(loc, _buildLocationPath(loc)))
          .where((e) => e.value.toLowerCase().contains(q))
          .toList();
      paths.sort((a, b) => a.value.compareTo(b.value));
      if (mounted) {
        setState(() {
          _suggestions = paths
              .take(_maxSuggestions)
              .map((e) => e.key)
              .toList();
        });
      }
    });
  }

  void _selectDestination(Location loc) {
    setState(() {
      _selectedDestination = loc.id;
      _searchController.clear();
      _suggestions = null;
    });
  }

  void _clearDestination() {
    setState(() {
      _selectedDestination = null;
      _suggestions = null;
    });
  }

  void _incrementQuantity() {
    if (_quantity < widget.sourceLocation.quantity) {
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

  Future<void> _handleSubmit() async {
    // Validate destination
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
      await pbService.moveTool(
        toolId: widget.tool.id,
        fromLocationId: widget.sourceLocation.locationId,
        toLocationId: _selectedDestination!,
        quantity: _quantity,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tool transferred successfully!'),
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
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleDelete() async {
    final sourceLoc = widget.sourceLocation.location;
    if (sourceLoc == null) return;

    final path = _buildLocationPath(sourceLoc);
    final qty = widget.sourceLocation.quantity;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from Location'),
        content: Text('Remove this tool from $path?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final pbService = PocketBaseService();
      await pbService.logInventoryHistory(
        toolId: widget.sourceLocation.toolId,
        locationId: widget.sourceLocation.locationId,
        action: 'remove',
        quantity: qty,
        quantityBefore: qty,
        quantityAfter: 0,
      );

      await pbService.pb.collection('tool_locations').delete(widget.sourceLocation.id);

      if (!mounted) return;
      Navigator.of(context).pop(true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Removed from location!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sourceLoc = widget.sourceLocation.location;
    final availableQty = widget.sourceLocation.quantity;
    final sourceLocationPath = sourceLoc != null ? _buildLocationPath(sourceLoc) : 'Unknown Location';

    return AlertDialog(
      title: Text(
        'Transfer Tool: ${widget.tool.toolName}',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SizedBox(
        width: 400, // Narrower dialog
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Source location info - just black outline, no background
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'From: ',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            sourceLocationPath,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Available: $availableQty',
                      style: const TextStyle(
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Quantity selector with +/- buttons
              const Text(
                'Quantity',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed: _isSubmitting ? null : _decrementQuantity,
                    icon: const Icon(Icons.remove, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey[200],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '$_quantity',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: _isSubmitting ? null : _incrementQuantity,
                    icon: const Icon(Icons.add, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey[300],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Max: $availableQty',
                    style: const TextStyle(
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Destination: search field with suggestions (or show selected)
              const Text(
                'Destination',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              if (_selectedDestination != null) ...[
                Builder(
                  builder: (context) {
                    Location? loc;
                    try {
                      loc = widget.allLocations.firstWhere(
                          (l) => l.id == _selectedDestination);
                    } catch (_) {
                      loc = null;
                    }
                    final path = loc != null ? _buildLocationPath(loc) : _selectedDestination!;
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[400]!),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey[50],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              path,
                              style: const TextStyle(fontSize: 14),
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
                ),
              ] else ...[
                TextField(
                  controller: _searchController,
                  enabled: !_isSubmitting,
                  decoration: InputDecoration(
                    hintText: 'Search destination',
                    hintStyle: const TextStyle(fontSize: 14),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: (_) => _onSearchChanged(),
                ),
                if (_suggestions != null && _suggestions!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Card(
                    elevation: 2,
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _suggestions!.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final loc = _suggestions![i];
                        final path = _buildLocationPath(loc);
                        return ListTile(
                          dense: true,
                          title: Text(path, style: const TextStyle(fontSize: 13)),
                          onTap: () => _selectDestination(loc),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: Colors.red,
              tooltip: 'Remove from location',
              onPressed: _isSubmitting ? null : _handleDelete,
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    _greyDestinationShortcut(
                      label: _trashShortcutName,
                      icon: const Icon(Icons.recycling, size: 22),
                      location: _locationForExactName(_trashShortcutName),
                    ),
                    for (final name in _machineShortcutNames)
                      _greyDestinationShortcut(
                        label: name,
                        icon: const DmuMachineIcon(size: 22),
                        location: _locationForExactName(name),
                      ),
                    if (_homeBin != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: TextButton(
                          onPressed: _isSubmitting
                              ? null
                              : () => _selectDestination(_homeBin!),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.grey[800],
                            backgroundColor: Colors.grey[200],
                            minimumSize: const Size(0, 40),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            _homeBin!.name,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            TextButton(
              onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _handleSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                  : const Text(
                      'Transfer',
                      style: TextStyle(fontSize: 14),
                    ),
            ),
          ],
        ),
      ],
    );
  }

}