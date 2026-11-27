import 'package:flutter/material.dart';
import 'pocketbase_service.dart';

class ReturnToolScreen extends StatefulWidget {
  const ReturnToolScreen({super.key});

  @override
  State<ReturnToolScreen> createState() => _ReturnToolScreenState();
}

class _ReturnToolScreenState extends State<ReturnToolScreen> {
  List<Map<String, dynamic>> _toolsInMachines = [];
  List<dynamic> _allLocations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadToolsInMachines();
  }

  Future<void> _loadToolsInMachines() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final pbService = PocketBaseService();
      final locations = await pbService.getLocations();
      
      // Find all machine locations
      final machineLocations = locations.where((loc) => loc.data['type'] == 'machine').toList();
      
      // Get tools in each machine
      final List<Map<String, dynamic>> toolsInMachines = [];
      
      for (var machineLoc in machineLocations) {
        final toolLocations = await pbService.getToolLocationsAtLocation(machineLoc.id);
        
        for (var tl in toolLocations) {
          final qty = tl.data['quantity'];
          final quantity = qty is int
              ? qty
              : (qty is num ? qty.toInt() : int.tryParse('$qty') ?? 0);
          if (quantity <= 0) continue;

          final toolId = tl.data['tool'];
          final tool = await pbService.getToolById(toolId);
          final category = (tool.data['category'] ?? '').toString();
          final cat = category.trim().toLowerCase();
          if (cat == '3d filament' ||
              cat == '3dp filament' ||
              cat.contains('filament')) {
            continue;
          }

          toolsInMachines.add({
            'tool': tool,
            'tool_location': tl,
            'machine_location': machineLoc,
            'quantity': quantity,
          });
        }
      }
      
      setState(() {
        _toolsInMachines = toolsInMachines;
        _allLocations = locations;
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

  void _showReturnDialog(Map<String, dynamic> toolData) {
    String? selectedDestination;
    final quantityController = TextEditingController(text: toolData['quantity'].toString());

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Return ${toolData['tool'].data['tool_name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Currently in: ${toolData['machine_location'].data['name']}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: quantityController,
                decoration: const InputDecoration(
                  labelText: 'Quantity to return',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedDestination,
                decoration: const InputDecoration(
                  labelText: 'Return to',
                  border: OutlineInputBorder(),
                ),
                hint: const Text('Select destination'),
                items: [
                  ..._allLocations
                      .where((loc) => loc.data['type'] == 'shelf')
                      .map((loc) {
                        final pbService = PocketBaseService();
                        final path = pbService.getLocationPath(loc.id, _allLocations);
                        return DropdownMenuItem<String>(
                          value: loc.id,
                          child: Text(path),
                        );
                      }),
                  ..._allLocations
                      .where((loc) => loc.data['type'] == 'recycle')
                      .map((loc) => DropdownMenuItem<String>(
                            value: loc.id,
                            child: Text(loc.data['name']),
                          )),
                ],
                onChanged: (value) {
                  setDialogState(() {
                    selectedDestination = value;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedDestination == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select a destination')),
                  );
                  return;
                }

                final qty = int.tryParse(quantityController.text);
                if (qty == null || qty < 1 || qty > toolData['quantity']) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid quantity')),
                  );
                  return;
                }

                try {
                  final pbService = PocketBaseService();
                  
                  // Move the tool
                  await pbService.moveTool(
                    toolId: toolData['tool'].id,
                    fromLocationId: toolData['machine_location'].id,
                    toLocationId: selectedDestination!,
                    quantity: qty,
                  );

                  Navigator.pop(context);
                  _loadToolsInMachines();

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Tool returned successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Return Tool'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Return Tool'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _toolsInMachines.isEmpty
              ? const Center(
                  child: Text(
                    'No tools currently in machines.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _toolsInMachines.length,
                  itemBuilder: (context, index) {
                    final toolData = _toolsInMachines[index];
                    final tool = toolData['tool'];
                    final machineLoc = toolData['machine_location'];
                    final qty = toolData['quantity'];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.build, color: Colors.orange),
                        title: Text(
                          tool.data['tool_name'],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text('Machine: ${machineLoc.data['name']}'),
                            Text('Quantity: $qty'),
                          ],
                        ),
                        trailing: ElevatedButton(
                          onPressed: () => _showReturnDialog(toolData),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Return'),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}