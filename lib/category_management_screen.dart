// category_management_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pocketbase_service.dart';
import 'workspace_layout.dart';
import 'workspace_scaffold.dart';
import 'settings_screen.dart';
import 'drawer_behavior.dart';
import 'drawer_data_cache.dart';

class CategoryManagementScreen extends StatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  State<CategoryManagementScreen> createState() => _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen> with AutoOpenDrawerMixin {
  final PocketBaseService _pbService = PocketBaseService();
  
  List<dynamic> _categories = [];
  List<dynamic> _allSubcategories = [];
  List<dynamic> _attributeLists = [];
  
  String? _selectedCategoryId;
  Set<String> _expandedSubcategories = {};
  
  bool _isLoading = true;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  GlobalKey<ScaffoldState> get scaffoldKey => _scaffoldKey;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadExpandedState();
  }

  Future<void> _loadExpandedState() async {
    final prefs = await SharedPreferences.getInstance();
    final expanded = prefs.getStringList('expanded_subcategories') ?? [];
    setState(() {
      _expandedSubcategories = expanded.toSet();
    });
  }

  Future<void> _saveExpandedState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('expanded_subcategories', _expandedSubcategories.toList());
  }

  void _toggleExpanded(String subcategoryId) {
    setState(() {
      if (_expandedSubcategories.contains(subcategoryId)) {
        _expandedSubcategories.remove(subcategoryId);
      } else {
        _expandedSubcategories.add(subcategoryId);
      }
    });
    _saveExpandedState();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      await _pbService.ensureMaterialsCategoryId();
      final categories = await _pbService.getCategories();
      final subcategories = await _pbService.getSubcategories();
      final attributeLists = await _pbService.getAttributeLists();
      
      setState(() {
        _categories = categories;
        _allSubcategories = subcategories;
        _attributeLists = attributeLists;
        _isLoading = false;
        
        // Auto-select first category if none selected (use first sorted category)
        if (_selectedCategoryId == null && _categories.isNotEmpty) {
          final sorted = _categories
            ..sort((a, b) => (a.data['sort_order'] ?? 0).compareTo(b.data['sort_order'] ?? 0));
          _selectedCategoryId = sorted.first.id;
        }
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Category CRUD methods
  void _showAddCategoryDialog() {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Category'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Category Name',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                try {
                  // Get max sort_order and add 1
                  final maxOrder = _categories.isEmpty 
                      ? 0 
                      : _categories.map((c) => c.data['sort_order'] ?? 0).reduce((a, b) => a > b ? a : b);
                  
                  await _pbService.createCategory(
                    name: nameController.text,
                    sortOrder: maxOrder + 1,
                  );
                  Navigator.pop(context);
                  _loadData();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Category "${nameController.text}" created!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                    );
                  }
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Category'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Category Name',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                try {
                  await _pbService.updateCategory(
                    categoryId: category.id,
                    name: nameController.text,
                    sortOrder: category.data['sort_order'] ?? 0, // Keep existing order
                  );
                  Navigator.pop(context);
                  _loadData();
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
                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteCategoryDialog(dynamic category) async {
    final count = await _pbService.getCategoryInventoryCount(category.data['name']);
    final subcategoryCount = _allSubcategories.where((s) => s.data['category'] == category.id).length;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete "${category.data['name']}"?'),
            if (subcategoryCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '⚠️ This category has $subcategoryCount subcategories that will also be deleted.',
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
            if (count > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '⚠️ This category has $count inventory items.',
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'This action cannot be undone.',
              style: TextStyle(fontStyle: FontStyle.italic),
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
              try {
                await _pbService.deleteCategory(category.id);
                Navigator.pop(context);
                _loadData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Category "${category.data['name']}" deleted'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Subcategory CRUD methods
  void _showAddSubcategoryDialog({String? parentSubcategoryId}) {
    if (_selectedCategoryId == null) return;

    final nameController = TextEditingController();
    final selfLabelController = TextEditingController();
    final childLabelController = TextEditingController();
    final sortController = TextEditingController(text: '1');
    String? selectedAttrListId;
    String selectedDisplayMode = 'dropdown';
    String selectedFieldType = 'selection';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(parentSubcategoryId != null ? 'Add Child Subcategory' : 'Add Subcategory'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: selfLabelController,
                  decoration: const InputDecoration(
                    labelText: 'Custom Label (optional)',
                    hintText: 'e.g., Tool Type, Style',
                  ),
                ),
                TextField(
                  controller: childLabelController,
                  decoration: const InputDecoration(
                    labelText: 'Custom Label for Children (optional)',
                    hintText: 'e.g., Style, Thread Type',
                  ),
                ),
                TextField(
                  controller: sortController,
                  decoration: const InputDecoration(labelText: 'Sort Order'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedFieldType,
                  decoration: const InputDecoration(labelText: 'Field Type'),
                  items: const [
                    DropdownMenuItem(value: 'selection', child: Text('Selection (from list)')),
                    DropdownMenuItem(value: 'text', child: Text('Text Input')),
                    DropdownMenuItem(value: 'number', child: Text('Number Input')),
                  ],
                  onChanged: (value) => setDialogState(() {
                    selectedFieldType = value ?? 'selection';
                    if (selectedFieldType != 'selection') {
                      selectedAttrListId = null;
                    }
                  }),
                ),
                const SizedBox(height: 16),
                if (selectedFieldType == 'selection') ...[
                  DropdownButtonFormField<String>(
                    value: selectedDisplayMode,
                    decoration: const InputDecoration(labelText: 'Display Mode'),
                    items: const [
                      DropdownMenuItem(value: 'dropdown', child: Text('Dropdown')),
                      DropdownMenuItem(value: 'buttons', child: Text('Buttons')),
                    ],
                    onChanged: (value) => setDialogState(() => selectedDisplayMode = value ?? 'dropdown'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    value: selectedAttrListId,
                    decoration: const InputDecoration(labelText: 'Attribute List (optional)'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('None')),
                      ..._attributeLists.map((list) => DropdownMenuItem<String?>(
                        value: list.id,
                        child: Text(list.data['name']),
                      )).toList(),
                    ],
                    onChanged: (value) => setDialogState(() => selectedAttrListId = value),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  try {
                    await _pbService.createSubcategory(
                      name: nameController.text,
                      categoryId: parentSubcategoryId != null ? null : _selectedCategoryId,
                      parentSubcategoryId: parentSubcategoryId,
                      sortOrder: int.tryParse(sortController.text) ?? 1,
                      label: selfLabelController.text.isEmpty ? null : selfLabelController.text,
                      customLabel: childLabelController.text.isEmpty ? null : childLabelController.text,
                      attributeListId: selectedFieldType == 'selection' ? selectedAttrListId : null,
                      displayMode: selectedFieldType == 'selection' ? selectedDisplayMode : null,
                      fieldType: selectedFieldType,
                    );
                    if (mounted) {
                      Navigator.pop(context);
                      if (parentSubcategoryId != null) {
                        _expandedSubcategories.add(parentSubcategoryId);
                      }
                      _loadData();
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditSubcategoryDialog(dynamic subcategory) {
    final nameController = TextEditingController(text: subcategory.data['name']);
    final selfLabelController = TextEditingController(text: subcategory.data['label'] ?? '');
    final childLabelController = TextEditingController(text: subcategory.data['custom_label'] ?? '');
    final sortController = TextEditingController(text: subcategory.data['sort_order'].toString());
    String? selectedAttrListId = subcategory.data['attribute_list'];
    
    String selectedDisplayMode = 'dropdown';
    final rawDisplayMode = subcategory.data['display_mode'];
    if (rawDisplayMode != null && rawDisplayMode.toString().isNotEmpty) {
      selectedDisplayMode = rawDisplayMode.toString();
    }
    
    String selectedFieldType = 'selection';
    final rawFieldType = subcategory.data['field_type'];
    if (rawFieldType != null && rawFieldType.toString().isNotEmpty) {
      selectedFieldType = rawFieldType.toString();
    }
    
    if (selectedAttrListId != null && selectedAttrListId.toString().isNotEmpty) {
      final exists = _attributeLists.any((list) => list.id == selectedAttrListId);
      if (!exists) {
        selectedAttrListId = null;
      }
    } else {
      selectedAttrListId = null;
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Subcategory'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: selfLabelController,
                  decoration: const InputDecoration(
                    labelText: 'Custom Label (optional)',
                    hintText: 'e.g., Tool Type, Style',
                  ),
                ),
                TextField(
                  controller: childLabelController,
                  decoration: const InputDecoration(
                    labelText: 'Custom Label for Children (optional)',
                    hintText: 'e.g., Style, Thread Type',
                  ),
                ),
                TextField(
                  controller: sortController,
                  decoration: const InputDecoration(labelText: 'Sort Order'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedFieldType,
                  decoration: const InputDecoration(labelText: 'Field Type'),
                  items: const [
                    DropdownMenuItem(value: 'selection', child: Text('Selection (from list)')),
                    DropdownMenuItem(value: 'text', child: Text('Text Input')),
                    DropdownMenuItem(value: 'number', child: Text('Number Input')),
                  ],
                  onChanged: (value) => setDialogState(() {
                    selectedFieldType = value ?? 'selection';
                    if (selectedFieldType != 'selection') {
                      selectedAttrListId = null;
                    }
                  }),
                ),
                const SizedBox(height: 16),
                if (selectedFieldType == 'selection') ...[
                  DropdownButtonFormField<String>(
                    value: selectedDisplayMode,
                    decoration: const InputDecoration(labelText: 'Display Mode'),
                    items: const [
                      DropdownMenuItem(value: 'dropdown', child: Text('Dropdown')),
                      DropdownMenuItem(value: 'buttons', child: Text('Buttons')),
                    ],
                    onChanged: (value) => setDialogState(() => selectedDisplayMode = value ?? 'dropdown'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    value: selectedAttrListId,
                    decoration: const InputDecoration(labelText: 'Attribute List (optional)'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('None')),
                      ..._attributeLists.map((list) => DropdownMenuItem<String?>(
                        value: list.id,
                        child: Text(list.data['name']),
                      )).toList(),
                    ],
                    onChanged: (value) => setDialogState(() => selectedAttrListId = value),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  try {
                    await _pbService.updateSubcategory(
                      subcategoryId: subcategory.id,
                      name: nameController.text,
                      sortOrder: int.tryParse(sortController.text) ?? 1,
                      label: selfLabelController.text.isEmpty ? null : selfLabelController.text,
                      customLabel: childLabelController.text.isEmpty ? null : childLabelController.text,
                      attributeListId: selectedFieldType == 'selection' ? selectedAttrListId : null,
                      displayMode: selectedFieldType == 'selection' ? selectedDisplayMode : null,
                      fieldType: selectedFieldType,
                    );
                    if (mounted) {
                      Navigator.pop(context);
                      _loadData();
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteSubcategoryDialog(dynamic subcategory) async {
    final hasChildren = await _pbService.subcategoryHasChildren(subcategory.id);
    final count = await _pbService.getSubcategoryInventoryCount(subcategory.data['name']);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Subcategory'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete "${subcategory.data['name']}"?'),
            if (hasChildren)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '⚠️ This subcategory has children that will also be deleted.',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
            if (count > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '⚠️ This subcategory has $count inventory items.',
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'This action cannot be undone.',
              style: TextStyle(fontStyle: FontStyle.italic),
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
              try {
                await _pbService.deleteSubcategory(subcategory.id);
                Navigator.pop(context);
                _loadData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Subcategory "${subcategory.data['name']}" deleted'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Get subcategories for selected category
  List<dynamic> _getRootSubcategories() {
    if (_selectedCategoryId == null) return [];
    return _allSubcategories
        .where((s) => 
          s.data['category'] == _selectedCategoryId && 
          (s.data['parent_subcategory'] == null || s.data['parent_subcategory'] == '')
        )
        .toList()
      ..sort((a, b) => (a.data['sort_order'] ?? 0).compareTo(b.data['sort_order'] ?? 0));
  }

  // NEW: Get categories sorted by sort_order
  List<dynamic> get _sortedCategories {
    return _categories
      ..sort((a, b) => (a.data['sort_order'] ?? 0).compareTo(b.data['sort_order'] ?? 0));
  }

  // NEW: Handle category reordering
  Future<void> _onCategoryReorder(int oldIndex, int newIndex) async {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _categories.removeAt(oldIndex);
      _categories.insert(newIndex, item);
      
      // Update sort_order for all categories
      for (int i = 0; i < _categories.length; i++) {
        _categories[i].data['sort_order'] = i + 1;
      }
    });

    // Save new order to database
    try {
      for (final category in _categories) {
        await _pbService.updateCategory(
          categoryId: category.id,
          name: category.data['name'],
          sortOrder: category.data['sort_order'],
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving order: $e'), backgroundColor: Colors.red),
        );
      }
      // Reload data to revert to saved order
      _loadData();
    }
  }

  List<dynamic> _getChildSubcategories(String parentId) {
    return _allSubcategories
        .where((s) => s.data['parent_subcategory'] == parentId)
        .toList()
      ..sort((a, b) => (a.data['sort_order'] ?? 0).compareTo(b.data['sort_order'] ?? 0));
  }

  Future<void> _onRootSubcategoryReorder(int oldIndex, int newIndex) async {
    if (_selectedCategoryId == null) return;
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final rootSubs = _getRootSubcategories();
      final item = rootSubs.removeAt(oldIndex);
      rootSubs.insert(newIndex, item);
      for (int i = 0; i < rootSubs.length; i++) {
        rootSubs[i].data['sort_order'] = i + 1;
      }
    });
    try {
      for (final sub in _getRootSubcategories()) {
        await _pbService.updateSubcategory(
          subcategoryId: sub.id,
          name: sub.data['name'],
          sortOrder: sub.data['sort_order'],
          label: sub.data['label'],
          customLabel: sub.data['custom_label'],
          attributeListId: sub.data['attribute_list'],
          displayMode: sub.data['display_mode'],
          fieldType: sub.data['field_type'],
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving order: $e'), backgroundColor: Colors.red),
        );
      }
      _loadData();
    }
  }

  Future<void> _onChildSubcategoryReorder(String parentId, int oldIndex, int newIndex) async {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final children = _getChildSubcategories(parentId);
      final item = children.removeAt(oldIndex);
      children.insert(newIndex, item);
      for (int i = 0; i < children.length; i++) {
        children[i].data['sort_order'] = i + 1;
      }
    });
    try {
      for (final sub in _getChildSubcategories(parentId)) {
        await _pbService.updateSubcategory(
          subcategoryId: sub.id,
          name: sub.data['name'],
          sortOrder: sub.data['sort_order'],
          label: sub.data['label'],
          customLabel: sub.data['custom_label'],
          attributeListId: sub.data['attribute_list'],
          parentSubcategoryId: parentId,
          displayMode: sub.data['display_mode'],
          fieldType: sub.data['field_type'],
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving order: $e'), backgroundColor: Colors.red),
        );
      }
      _loadData();
    }
  }

  Widget _buildFieldTypeBadge(String fieldType, String displayMode) {
    if (fieldType == 'text') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.blue[100],
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text('Text', style: TextStyle(fontSize: 10, color: Colors.blue)),
      );
    } else if (fieldType == 'number') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.green[100],
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text('Number', style: TextStyle(fontSize: 10, color: Colors.green)),
      );
    } else {
      // selection type
      if (displayMode == 'buttons') {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.orange[100],
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text('Buttons', style: TextStyle(fontSize: 10, color: Colors.orange)),
        );
      } else {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.purple[100],
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text('Dropdown', style: TextStyle(fontSize: 10, color: Colors.purple)),
        );
      }
    }
  }

  Widget _buildSubcategoryTree(dynamic subcategory, int depth, {bool showDragHandle = false, int reorderableIndex = 0}) {
    final children = _getChildSubcategories(subcategory.id);
    final hasChildren = children.isNotEmpty;
    final isExpanded = _expandedSubcategories.contains(subcategory.id);
    
    final fieldType = subcategory.data['field_type'] ?? 'selection';
    final displayMode = subcategory.data['display_mode'] ?? 'dropdown';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          margin: EdgeInsets.only(left: depth * 16.0, top: 4, right: 4, bottom: 4),
          child: ListTile(
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showDragHandle)
                  ReorderableDragStartListener(
                    index: reorderableIndex,
                    child: Icon(Icons.drag_handle, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                if (hasChildren)
                  GestureDetector(
                    onTap: () => _toggleExpanded(subcategory.id),
                    child: Icon(
                      isExpanded ? Icons.expand_more : Icons.chevron_right,
                      size: 24,
                    ),
                  ),
              ],
            ),
            title: Row(
              children: [
                Text(
                  subcategory.data['name'],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                _buildFieldTypeBadge(fieldType, displayMode),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subcategory.data['label'] != null)
                  Text('Label: ${subcategory.data['label']}', style: const TextStyle(fontSize: 12)),
                if (subcategory.data['custom_label'] != null)
                  Text('Child Label: ${subcategory.data['custom_label']}', style: const TextStyle(fontSize: 12)),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.add, color: Colors.blue),
                  onPressed: () => _showAddSubcategoryDialog(parentSubcategoryId: subcategory.id),
                  tooltip: 'Add Child',
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.orange),
                  onPressed: () => _showEditSubcategoryDialog(subcategory),
                  tooltip: 'Edit',
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _showDeleteSubcategoryDialog(subcategory),
                  tooltip: 'Delete',
                ),
              ],
            ),
          ),
        ),
        if (hasChildren && isExpanded)
          ReorderableListView.builder(
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: children.length,
            onReorder: (oldIndex, newIndex) => _onChildSubcategoryReorder(subcategory.id, oldIndex, newIndex),
            itemBuilder: (context, index) {
              final child = _getChildSubcategories(subcategory.id)[index];
              return KeyedSubtree(
                key: Key(child.id),
                child: _buildSubcategoryTree(child, depth + 1, showDragHandle: true, reorderableIndex: index),
              );
            },
          ),
      ],
    );
  }

  // Attribute List Management Methods
  void _showAttributeListsDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Attribute Lists'),
              IconButton(
                icon: const Icon(Icons.add, color: Colors.green),
                onPressed: () {
                  Navigator.pop(context);
                  _showAddAttributeListDialog();
                },
                tooltip: 'Add Attribute List',
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 400,
            child: _attributeLists.isEmpty
                ? const Center(child: Text('No attribute lists yet'))
                : ListView.builder(
                    itemCount: _attributeLists.length,
                    itemBuilder: (context, index) {
                      final attrList = _attributeLists[index];
                      
                      return Card(
                        child: FutureBuilder<List<dynamic>>(
                          future: _pbService.getAttributeValues(attrList.id),
                          builder: (context, snapshot) {
                            final values = snapshot.data?.map((v) => v.data['value'].toString()).join(', ') ?? 'Loading...';
                            
                            return ListTile(
                              title: Text(attrList.data['name']),
                              subtitle: Text(values.isEmpty ? 'No values' : values),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.orange),
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _showEditAttributeListDialog(attrList);
                                    },
                                    tooltip: 'Edit',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _showDeleteAttributeListDialog(attrList);
                                    },
                                    tooltip: 'Delete',
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
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
        ),
      ),
    ).then((_) => _loadData()); // Reload data when dialog closes
  }

  void _showAddAttributeListDialog() {
    final nameController = TextEditingController();
    final valuesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Attribute List'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'List Name',
                  hintText: 'e.g., Filament Types, Tool Materials',
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: valuesController,
                decoration: const InputDecoration(
                  labelText: 'Values (comma-separated)',
                  hintText: 'e.g., PLA, PETG, TPU, ABS',
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty && valuesController.text.isNotEmpty) {
                try {
                  final values = valuesController.text
                      .split(',')
                      .map((v) => v.trim())
                      .where((v) => v.isNotEmpty)
                      .toList();
                  
                  // First create the attribute list
                  await _pbService.createAttributeList(name: nameController.text);
                  
                  // Get the newly created list to get its ID
                  final lists = await _pbService.getAttributeLists();
                  final newList = lists.firstWhere((l) => l.data['name'] == nameController.text);
                  
                  // Then add each value
                  for (int i = 0; i < values.length; i++) {
                    await _pbService.createAttributeValue(
                      listId: newList.id,
                      value: values[i],
                      sortOrder: i + 1,
                    );
                  }
                  
                  Navigator.pop(context);
                  _loadData();
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Attribute list "${nameController.text}" created!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditAttributeListDialog(dynamic attrList) async {
    final nameController = TextEditingController(text: attrList.data['name']);
    
    // Get existing values
    final existingValueRecords = await _pbService.getAttributeValues(attrList.id);
    final existingValues = existingValueRecords.map((v) => v.data['value'].toString()).toList();
    final valuesController = TextEditingController(text: existingValues.join(', '));

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Attribute List'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'List Name',
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: valuesController,
                decoration: const InputDecoration(
                  labelText: 'Values (comma-separated)',
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty && valuesController.text.isNotEmpty) {
                try {
                  final values = valuesController.text
                      .split(',')
                      .map((v) => v.trim())
                      .where((v) => v.isNotEmpty)
                      .toList();
                  
                  // Update the list name
                  await _pbService.updateAttributeList(
                    listId: attrList.id,
                    name: nameController.text,
                  );
                  
                  // Delete all existing values
                  for (final valueRecord in existingValueRecords) {
                    await _pbService.deleteAttributeValue(valueRecord.id);
                  }
                  
                  // Create new values
                  for (int i = 0; i < values.length; i++) {
                    await _pbService.createAttributeValue(
                      listId: attrList.id,
                      value: values[i],
                      sortOrder: i + 1,
                    );
                  }
                  
                  Navigator.pop(context);
                  _loadData();
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Attribute list "${nameController.text}" updated!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAttributeListDialog(dynamic attrList) async {
    // Get values first to show count
    final valueRecords = await _pbService.getAttributeValues(attrList.id);
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Attribute List'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete "${attrList.data['name']}"?'),
            if (valueRecords.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'This will also delete ${valueRecords.length} value(s).',
                  style: const TextStyle(color: Colors.orange),
                ),
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
              try {
                // Delete all values first
                for (final valueRecord in valueRecords) {
                  await _pbService.deleteAttributeValue(valueRecord.id);
                }
                
                // Then delete the list
                await _pbService.deleteAttributeList(attrList.id);
                
                Navigator.pop(context);
                _loadData();
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Attribute list "${attrList.data['name']}" deleted'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dividerColor = theme.dividerColor;

    final bodyContent = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // LEFT PANEL - Categories
              Container(
                  width: 250,
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: dividerColor)),
                    color: colorScheme.surfaceContainerLowest,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: dividerColor)),
                        ),
                        child: Text(
                          'CATEGORIES',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurfaceVariant,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ReorderableListView.builder(
                          itemCount: _sortedCategories.length,
                          buildDefaultDragHandles: false, // Disable default right-side handles
                          onReorder: _onCategoryReorder,
                          itemBuilder: (context, index) {
                            final category = _sortedCategories[index];
                            final isSelected = _selectedCategoryId == category.id;
                            
                            return ListTile(
                              key: Key(category.id), // Required for ReorderableListView
                              selected: isSelected,
                              selectedTileColor: colorScheme.primaryContainer,
                              leading: ReorderableDragStartListener(
                                index: index,
                                child: Icon(Icons.drag_handle, size: 20, color: colorScheme.onSurfaceVariant),
                              ),
                              title: Text(
                                category.data['name'],
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 16),
                                    onPressed: () => _showEditCategoryDialog(category),
                                    tooltip: 'Edit',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    splashRadius: 20,
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                                    onPressed: () => _showDeleteCategoryDialog(category),
                                    tooltip: 'Delete',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    splashRadius: 20,
                                  ),
                                ],
                              ),
                              onTap: () {
                                setState(() {
                                  _selectedCategoryId = category.id;
                                });
                              },
                            );
                          },
                        ),
                      ),
                      // Buttons directly below categories list
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: dividerColor)),
                        ),
                        child: Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _showAddCategoryDialog,
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Add Category'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _showAttributeListsDialog,
                                icon: const Icon(Icons.list_alt, size: 18),
                                label: const Text('Manage Attributes'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
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
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // RIGHT PANEL - Subcategories Tree
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: dividerColor)),
                        ),
                        child: Text(
                          _selectedCategoryId != null
                              ? '${_categories.firstWhere((c) => c.id == _selectedCategoryId).data['name'].toUpperCase()} SUBCATEGORIES'
                              : 'Select a category',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: _selectedCategoryId == null
                            ? const Center(child: Text('Select a category'))
                            : _getRootSubcategories().isEmpty
                                ? Center(
                                    child: Text(
                                      'No subcategories yet.\nClick "Add Subcategory" to create one.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant),
                                    ),
                                  )
                                : ReorderableListView.builder(
                                    padding: const EdgeInsets.all(8),
                                    buildDefaultDragHandles: false,
                                    itemCount: _getRootSubcategories().length,
                                    onReorder: _onRootSubcategoryReorder,
                                    itemBuilder: (context, index) {
                                      final sub = _getRootSubcategories()[index];
                                      return KeyedSubtree(
                                        key: Key(sub.id),
                                        child: _buildSubcategoryTree(sub, 0, showDragHandle: true, reorderableIndex: index),
                                      );
                                    },
                                  ),
                      ),
                      // Add Subcategory button centered below list
                      if (_selectedCategoryId != null)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border(top: BorderSide(color: dividerColor)),
                          ),
                          child: Center(
                            child: ElevatedButton.icon(
                              onPressed: () => _showAddSubcategoryDialog(),
                              icon: const Icon(Icons.add),
                              label: const Text('Add Subcategory'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );

    return WorkspaceScaffold(
      scaffoldKey: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Category Management'),
        backgroundColor: colorScheme.inversePrimary,
        leading: workspaceMenuLeading(context),
      ),
      body: bodyContent,
    );
  }
}
