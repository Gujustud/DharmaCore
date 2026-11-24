import 'package:flutter/material.dart';
import 'pocketbase_service.dart';
import 'workspace_layout.dart';
import 'workspace_scaffold.dart';
import 'settings_screen.dart'; // NEW: For back button navigation
import 'drawer_behavior.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> with AutoOpenDrawerMixin {
  List<dynamic> _categories = [];
  bool _isLoading = true;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  GlobalKey<ScaffoldState> get scaffoldKey => _scaffoldKey;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final pbService = PocketBaseService();
      await pbService.ensureMaterialsCategoryId();
      final categories = await pbService.getCategories();
      setState(() {
        _categories = categories;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading categories: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAddCategoryDialog() {
    final nameController = TextEditingController();
    final sortOrderController = TextEditingController(
      text: (_categories.length + 1).toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Category Name',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: sortOrderController,
              decoration: const InputDecoration(
                labelText: 'Sort Order',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
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
              if (nameController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a category name')),
                );
                return;
              }

              // Check for duplicate name
              final isDuplicate = _categories.any(
                (cat) => cat.data['name'].toLowerCase() == nameController.text.toLowerCase(),
              );
              if (isDuplicate) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Category name already exists')),
                );
                return;
              }

              final sortOrder = int.tryParse(sortOrderController.text) ?? _categories.length + 1;

              try {
                final pbService = PocketBaseService();
                await pbService.createCategory(
                  name: nameController.text,
                  sortOrder: sortOrder,
                );

                Navigator.pop(context);
                _loadCategories();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Category "${nameController.text}" added!'),
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
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditCategoryDialog(dynamic category) {
    final nameController = TextEditingController(text: category.data['name']);
    final sortOrderController = TextEditingController(
      text: category.data['sort_order'].toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Category Name',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: sortOrderController,
              decoration: const InputDecoration(
                labelText: 'Sort Order',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
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
              if (nameController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a category name')),
                );
                return;
              }

              // Check for duplicate name (excluding current category)
              final isDuplicate = _categories.any(
                (cat) => cat.id != category.id && 
                         cat.data['name'].toLowerCase() == nameController.text.toLowerCase(),
              );
              if (isDuplicate) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Category name already exists')),
                );
                return;
              }

              final sortOrder = int.tryParse(sortOrderController.text) ?? 1;

              try {
                final pbService = PocketBaseService();
                await pbService.updateCategory(
                  categoryId: category.id,
                  name: nameController.text,
                  sortOrder: sortOrder,
                );

                Navigator.pop(context);
                _loadCategories();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Category updated to "${nameController.text}"!'),
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCategory(dynamic category) async {
    final pbService = PocketBaseService();
    final categoryName = category.data['name'];
    
    // Check if category has inventory
    final inventoryCount = await pbService.getCategoryInventoryCount(categoryName);
    
    if (inventoryCount > 0) {
      // Show dialog with options
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete "$categoryName"?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('This category has $inventoryCount inventory item(s).'),
              const SizedBox(height: 16),
              const Text('Choose an option:'),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, 'reassign'),
                  child: const Text('Reassign to Another Category'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, 'delete_all'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Delete All Items'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      
      if (result == 'reassign') {
        // Show category picker and reassign
        await _showReassignDialog(category, inventoryCount);
        return;
      } else if (result == 'delete_all') {
        // Show confirmation requiring "DELETE" to be typed
        final confirm = await _showDeleteConfirmation(categoryName, inventoryCount);
        if (confirm) {
          // Delete all inventory items, then delete category
          await _deleteCategoryWithItems(category);
        }
        return;
      } else {
        return; // Cancelled
      }
    } else {
      // No inventory, safe to delete
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete "$categoryName"?'),
          content: const Text('This category has no inventory items.'),
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
          await pbService.deleteCategory(category.id);
          _loadCategories();
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Category "$categoryName" deleted'),
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
      }
    }
  }

  Future<bool> _showDeleteConfirmation(String categoryName, int count) async {
    final controller = TextEditingController();
    bool isDeleteEnabled = false;
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Delete "$categoryName" and $count item(s)?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('This will permanently delete all inventory items in this category.'),
              const SizedBox(height: 16),
              const Text('Type DELETE to confirm:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Type DELETE',
                ),
                onChanged: (value) {
                  setDialogState(() {
                    isDeleteEnabled = value == 'DELETE';
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isDeleteEnabled
                  ? () => Navigator.pop(context, true)
                  : null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    
    controller.dispose();
    return result ?? false;
  }

  Future<void> _deleteCategoryWithItems(dynamic category) async {
    final pbService = PocketBaseService();
    final categoryName = category.data['name'];
    
    try {
      // Get all inventory items in this category
      final items = await pbService.pb.collection('inventory').getFullList(
        filter: 'category = "$categoryName"',
      );
      
      // Delete all inventory items
      for (final item in items) {
        await pbService.pb.collection('inventory').delete(item.id);
      }
      
      // Delete the category
      await pbService.deleteCategory(category.id);
      
      _loadCategories();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Category "$categoryName" and ${items.length} item(s) deleted'),
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
  }

  Future<void> _showReassignDialog(dynamic category, int count) async {
    final pbService = PocketBaseService();
    final categories = await pbService.getCategories();
    final otherCategories = categories.where((c) => c.id != category.id).toList();
    
    if (otherCategories.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No other categories available to reassign to')),
        );
      }
      return;
    }
    
    String? selectedCategoryId;
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Reassign $count item(s)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Select new category for items in "${category.data['name']}":'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedCategoryId,
                decoration: const InputDecoration(
                  labelText: 'New Category',
                  border: OutlineInputBorder(),
                ),
                items: otherCategories.map<DropdownMenuItem<String>>((cat) {
                  return DropdownMenuItem<String>(
                    value: cat.id,
                    child: Text(cat.data['name']),
                  );
                }).toList(),
                onChanged: (value) {
                  setDialogState(() {
                    selectedCategoryId = value;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selectedCategoryId == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Reassign'),
            ),
          ],
        ),
      ),
    );
    
    if (result == true && selectedCategoryId != null) {
      try {
        final newCategory = otherCategories.firstWhere((c) => c.id == selectedCategoryId);
        final newCategoryName = newCategory.data['name'];
        final oldCategoryName = category.data['name'];
        
        // Show final confirmation
        final confirmDelete = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm Deletion'),
            content: Text(
              '$count item(s) will be reassigned to "$newCategoryName".\n\n'
              'Delete "$oldCategoryName" category?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Delete Category'),
              ),
            ],
          ),
        );
        
        if (confirmDelete != true) return;
        
        await _reassignCategoryItems(oldCategoryName, newCategoryName);
        await pbService.deleteCategory(category.id);
        _loadCategories();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$count item(s) reassigned to "$newCategoryName" and "$oldCategoryName" deleted'),
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
    }
  }

  Future<void> _reassignCategoryItems(String oldCategory, String newCategory) async {
    final pbService = PocketBaseService();
    final items = await pbService.pb.collection('inventory').getFullList(
      filter: 'category = "$oldCategory"',
    );
    
    for (final item in items) {
      await pbService.pb.collection('inventory').update(
        item.id,
        body: {'category': newCategory},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    maybeAutoOpenDrawer();

    return WorkspaceScaffold(
      scaffoldKey: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Categories'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: workspaceMenuLeading(context),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _showAddCategoryDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Category'),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.lightbulb_outline, color: Colors.blue.shade700, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Tip: Set sort order to 0 to hide a category from the drawer menu',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.blue.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // NEW: Back to Settings button
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (context) => const SettingsScreen()),
                          );
                        },
                        icon: const Icon(Icons.arrow_back, size: 18),
                        label: const Text('Back to Settings'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _categories.isEmpty
                      ? const Center(
                          child: Text(
                            'No categories yet.\nClick "Add Category" above to get started.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _categories.length,
                          itemBuilder: (context, index) {
                            final category = _categories[index];
                            return Card(
                              child: ListTile(
                                leading: const Icon(Icons.category, color: Colors.blue),
                                title: Text(
                                  category.data['name'],
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text('Sort Order: ${category.data['sort_order']}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.blue),
                                      onPressed: () => _showEditCategoryDialog(category),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deleteCategory(category),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
