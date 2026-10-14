import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';

import 'add_tool_screen.dart';
import 'drawer_behavior.dart';
import 'list_toolbar_widgets.dart';
import 'models.dart';
import 'pocketbase_service.dart';
import 'ui_breakpoints.dart';
import 'workspace_layout.dart';
import 'workspace_scaffold.dart';

class BuyListScreen extends StatefulWidget {
  const BuyListScreen({super.key});

  @override
  State<BuyListScreen> createState() => _BuyListScreenState();
}

class _BuyListScreenState extends State<BuyListScreen> with AutoOpenDrawerMixin {
  final _pb = PocketBaseService();
  bool _loading = true;
  String? _error;
  List<Tool> _tools = [];
  List<Tool> _filteredTools = [];
  List<ManualBuyItem> _manualItems = [];
  List<ManualBuyItem> _filteredManual = [];
  List<RecordModel> _suppliers = [];
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final _searchController = TextEditingController();

  Tool? _selectedTool;
  ManualBuyItem? _selectedManual;
  bool _creatingManual = false;

  @override
  GlobalKey<ScaffoldState> get scaffoldKey => _scaffoldKey;

  bool get _panelOpen =>
      _creatingManual || _selectedTool != null || _selectedManual != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _syncFilter(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      _filteredTools = List.from(_tools);
      _filteredManual = List.from(_manualItems);
      return;
    }
    _filteredTools = _tools.where((t) {
      final hay = [
        t.toolName,
        t.modelNumber ?? '',
        t.brand ?? '',
        t.supplier ?? '',
        t.restockNotes ?? '',
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
    _filteredManual = _manualItems.where((m) {
      final supplierName = _supplierName(m.supplier);
      final hay =
          '${m.description} $supplierName ${m.notes ?? ''}'.toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  String _supplierName(String? id) {
    if (id == null || id.trim().isEmpty) return '';
    try {
      final sup = _suppliers.firstWhere((s) => s.id == id);
      return (sup.data['company_name'] ?? sup.id).toString();
    } catch (_) {
      return id;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records = await _pb.pb.collection('inventory').getFullList(
            filter: 'needs_restock = true',
            expand: 'brand,supplier',
            sort: 'tool_name',
          );
      final manual = await _pb.getManualBuyItems();
      final supplierRecords = await _pb.pb.collection('suppliers').getFullList(
            sort: 'company_name',
          );
      setState(() {
        _tools = records.map((r) => Tool.fromRecord(r)).toList();
        _manualItems = manual;
        _suppliers = supplierRecords;
        _syncFilter(_searchController.text);
        if (_selectedTool != null) {
          final id = _selectedTool!.id;
          Tool? still;
          for (final t in _tools) {
            if (t.id == id) {
              still = t;
              break;
            }
          }
          _selectedTool = still;
        }
        if (_selectedManual != null) {
          final id = _selectedManual!.id;
          ManualBuyItem? still;
          for (final m in _manualItems) {
            if (m.id == id) {
              still = m;
              break;
            }
          }
          _selectedManual = still;
        }
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error =
            'Could not load Buy List. Make sure the `inventory` collection has fields `needs_restock` (bool) and `restock_qty` (number/int).\n\n$e';
        _loading = false;
      });
    }
  }

  void _closePanel() {
    setState(() {
      _selectedTool = null;
      _selectedManual = null;
      _creatingManual = false;
    });
  }

  Future<void> _openToolEditor(Tool tool) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AddToolScreen(tool: tool)),
    );
    if (result == true) await _load();
  }

  Future<void> _selectTool(Tool tool, {required bool usePanel}) async {
    if (usePanel) {
      setState(() {
        _selectedTool = tool;
        _selectedManual = null;
        _creatingManual = false;
      });
      return;
    }
    await _openToolEditor(tool);
  }

  Future<void> _selectManual(
    ManualBuyItem item, {
    required bool usePanel,
  }) async {
    if (usePanel) {
      setState(() {
        _selectedManual = item;
        _selectedTool = null;
        _creatingManual = false;
      });
      return;
    }
    await _showManualItemDialog(existing: item);
  }

  Future<void> _openAddCustom({required bool usePanel}) async {
    if (usePanel) {
      setState(() {
        _creatingManual = true;
        _selectedTool = null;
        _selectedManual = null;
      });
      return;
    }
    await _showManualItemDialog();
  }

  Future<void> _updateRestock({
    required Tool tool,
    required bool needsRestock,
    required int? qty,
    String? notes,
  }) async {
    try {
      final body = <String, dynamic>{
        'needs_restock': needsRestock,
        'restock_qty': needsRestock ? (qty ?? 1) : null,
      };
      if (notes != null) body['restock_notes'] = notes.isEmpty ? null : notes;
      await _pb.pb.collection('inventory').update(tool.id, body: body);
      if (!mounted) return;
      if (!needsRestock) _closePanel();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating buy list: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showManualItemDialog({ManualBuyItem? existing}) async {
    final descController =
        TextEditingController(text: existing?.description ?? '');
    final qtyController =
        TextEditingController(text: (existing?.qty ?? 1).toString());
    final notesController = TextEditingController(text: existing?.notes ?? '');

    String? selectedSupplierId = existing?.supplier;
    String initialSupplierName = '';
    if (existing?.supplier != null) {
      initialSupplierName = _supplierName(existing!.supplier);
    }
    final supplierTextController =
        TextEditingController(text: initialSupplierName);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add custom item' : 'Edit custom item'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Qty'),
              ),
              const SizedBox(height: 8),
              Autocomplete<RecordModel>(
                optionsBuilder: (textValue) {
                  final query = textValue.text.trim().toLowerCase();
                  if (query.isEmpty) return _suppliers;
                  return _suppliers.where((s) {
                    final name =
                        (s.data['company_name'] ?? s.id).toString().toLowerCase();
                    return name.contains(query);
                  });
                },
                displayStringForOption: (s) =>
                    (s.data['company_name'] ?? s.id).toString(),
                initialValue: initialSupplierName.isNotEmpty
                    ? TextEditingValue(text: initialSupplierName)
                    : null,
                onSelected: (record) {
                  selectedSupplierId = record.id;
                },
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                  controller.text = supplierTextController.text;
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Supplier (optional)',
                    ),
                    onChanged: (value) {
                      supplierTextController.text = value;
                      if (value.trim().isEmpty) {
                        selectedSupplierId = null;
                      }
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesController,
                decoration:
                    const InputDecoration(labelText: 'Notes (optional)'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true) {
      final desc = descController.text.trim();
      final qty = int.tryParse(qtyController.text.trim()) ?? 1;
      final notes = notesController.text.trim().isEmpty
          ? null
          : notesController.text.trim();
      if (desc.isEmpty) return;

      if (existing == null) {
        await _pb.createManualBuyItem(
          description: desc,
          qty: qty,
          supplier: selectedSupplierId,
          notes: notes,
        );
      } else {
        await _pb.updateManualBuyItem(
          id: existing.id,
          description: desc,
          qty: qty,
          supplier: selectedSupplierId,
          notes: notes,
        );
      }
      await _load();
    }
  }

  Widget _qtyChip(BuildContext context, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onPrimaryContainer,
            ),
      ),
    );
  }

  Widget _buildToolbar(bool stacked, {required bool usePanel}) {
    final search = InventoryListSearchField(
      controller: _searchController,
      hintText: 'Search buy list…',
      onChanged: (v) => setState(() => _syncFilter(v)),
      decoration: inventoryListSearchDecoration(
        context,
        hintText: 'Search buy list…',
      ).copyWith(
        suffixIcon: _searchController.text.isNotEmpty
            ? inventoryListSearchClearButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _syncFilter(''));
                },
              )
            : null,
      ),
    );
    final addButton = InventoryListActionButton(
      label: 'Add custom item',
      onPressed: _loading ? null : () => _openAddCustom(usePanel: usePanel),
    );

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          const SizedBox(height: 12),
          addButton,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: search),
        const SizedBox(width: 12),
        addButton,
      ],
    );
  }

  Widget _buildDetailPanel(ColorScheme scheme) {
    if (!_panelOpen) return const SizedBox.shrink();

    if (_creatingManual || _selectedManual != null) {
      return _ManualDetailPanel(
        key: ValueKey(
          _creatingManual
              ? 'manual-new'
              : 'manual-${_selectedManual!.id}',
        ),
        existing: _creatingManual ? null : _selectedManual,
        suppliers: _suppliers,
        onClose: _closePanel,
        onSaved: () async {
          _closePanel();
          await _load();
        },
        onDeleted: () async {
          _closePanel();
          await _load();
        },
      );
    }

    final tool = _selectedTool!;
    return _ToolBuyDetailPanel(
      key: ValueKey('tool-${tool.id}-${tool.restockQty}'),
      tool: tool,
      onClose: _closePanel,
      onOpenTool: () => _openToolEditor(tool),
      onMarkDone: () => _updateRestock(
        tool: tool,
        needsRestock: false,
        qty: null,
      ),
      onSave: ({required int qty, required String notes}) => _updateRestock(
        tool: tool,
        needsRestock: true,
        qty: qty,
        notes: notes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    maybeAutoOpenDrawer();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final muted =
        textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final titleStyle =
        textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
    final sectionStyle =
        textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);
    final width = MediaQuery.sizeOf(context).width;
    final isNarrow = width < 700;
    final usePanel = width >= kWorkspaceWideBreakpointPx;

    final listColumn = workspaceContentFrame(
      Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(
                bottom: BorderSide(color: scheme.outlineVariant),
              ),
            ),
            child: _buildToolbar(
              isNarrow || (usePanel && _panelOpen),
              usePanel: usePanel,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _error!,
                          style: TextStyle(color: scheme.error),
                        ),
                      )
                    : _filteredTools.isEmpty && _filteredManual.isEmpty
                        ? Center(
                            child: Text(
                              _tools.isEmpty && _manualItems.isEmpty
                                  ? 'No items in the Buy List.'
                                  : 'No items match your search.',
                              style: muted,
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.all(8),
                            children: [
                              if (_filteredTools.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                                  child: Text(
                                    'Inventory tools',
                                    style: sectionStyle,
                                  ),
                                ),
                                ..._filteredTools.map((t) {
                                  final qtyToBuy = t.restockQty ?? 1;
                                  final selected = usePanel &&
                                      !_creatingManual &&
                                      _selectedTool?.id == t.id;
                                  final subtitle = [
                                    if (t.modelNumber != null &&
                                        t.modelNumber!.isNotEmpty)
                                      'Model: ${t.modelNumber}',
                                    if (t.brand != null && t.brand!.isNotEmpty)
                                      'Brand: ${t.brand}',
                                    if (t.supplier != null &&
                                        t.supplier!.isNotEmpty)
                                      'Supplier: ${t.supplier}',
                                  ].join(' • ');
                                  return Card(
                                    color: selected
                                        ? scheme.secondaryContainer
                                        : null,
                                    child: ListTile(
                                      title: Text(t.toolName, style: titleStyle),
                                      subtitle: subtitle.isEmpty
                                          ? null
                                          : Text(subtitle, style: muted),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _qtyChip(context, 'Qty: $qtyToBuy'),
                                          Icon(
                                            Icons.chevron_right,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ],
                                      ),
                                      onTap: () =>
                                          _selectTool(t, usePanel: usePanel),
                                    ),
                                  );
                                }),
                              ],
                              if (_filteredManual.isNotEmpty) ...[
                                if (_filteredTools.isNotEmpty)
                                  const SizedBox(height: 12),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                                  child: Text(
                                    'Custom items',
                                    style: sectionStyle,
                                  ),
                                ),
                                ..._filteredManual.map((m) {
                                  final selected = usePanel &&
                                      !_creatingManual &&
                                      _selectedManual?.id == m.id;
                                  final supplierName =
                                      _supplierName(m.supplier);
                                  final subtitle = [
                                    if (supplierName.isNotEmpty)
                                      'Supplier: $supplierName',
                                    if ((m.notes ?? '').trim().isNotEmpty)
                                      'Notes: ${m.notes}',
                                  ].join(' • ');
                                  return Card(
                                    color: selected
                                        ? scheme.secondaryContainer
                                        : null,
                                    child: ListTile(
                                      title: Text(
                                        m.description,
                                        style: titleStyle,
                                      ),
                                      subtitle: subtitle.isEmpty
                                          ? null
                                          : Text(subtitle, style: muted),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _qtyChip(context, 'Qty: ${m.qty}'),
                                          Icon(
                                            Icons.chevron_right,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ],
                                      ),
                                      onTap: () => _selectManual(
                                        m,
                                        usePanel: usePanel,
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
          ),
        ],
      ),
      maxWidth: usePanel && _panelOpen
          ? kWorkspacePanelContentMaxWidth
          : kWorkspaceContentMaxWidth,
    );

    return WorkspaceScaffold(
      scaffoldKey: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Buy List'),
        leading: workspaceMenuLeading(context),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: usePanel && _panelOpen
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: listColumn),
                Expanded(
                  flex: 7,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: scheme.outlineVariant),
                      ),
                    ),
                    child: _buildDetailPanel(scheme),
                  ),
                ),
              ],
            )
          : listColumn,
    );
  }
}

class _ToolBuyDetailPanel extends StatefulWidget {
  const _ToolBuyDetailPanel({
    super.key,
    required this.tool,
    required this.onClose,
    required this.onOpenTool,
    required this.onMarkDone,
    required this.onSave,
  });

  final Tool tool;
  final VoidCallback onClose;
  final VoidCallback onOpenTool;
  final VoidCallback onMarkDone;
  final Future<void> Function({required int qty, required String notes}) onSave;

  @override
  State<_ToolBuyDetailPanel> createState() => _ToolBuyDetailPanelState();
}

class _ToolBuyDetailPanelState extends State<_ToolBuyDetailPanel> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _notesCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(
      text: (widget.tool.restockQty ?? 1).toString(),
    );
    _notesCtrl = TextEditingController(text: widget.tool.restockNotes ?? '');
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(
        qty: int.tryParse(_qtyCtrl.text.trim()) ?? 1,
        notes: _notesCtrl.text.trim(),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted =
        Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            );
    final t = widget.tool;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t.toolName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (t.modelNumber != null && t.modelNumber!.isNotEmpty)
                Text('Model: ${t.modelNumber}', style: muted),
              if (t.brand != null && t.brand!.isNotEmpty)
                Text('Brand: ${t.brand}', style: muted),
              if (t.supplier != null && t.supplier!.isNotEmpty)
                Text('Supplier: ${t.supplier}', style: muted),
              const SizedBox(height: 16),
              TextField(
                controller: _qtyCtrl,
                keyboardType: TextInputType.number,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Qty to buy',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                enabled: !_saving,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Restock notes',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: const Text('Save'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : widget.onOpenTool,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Open tool'),
                  ),
                  TextButton.icon(
                    onPressed: _saving ? null : widget.onMarkDone,
                    style: TextButton.styleFrom(foregroundColor: scheme.primary),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Mark done'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ManualDetailPanel extends StatefulWidget {
  const _ManualDetailPanel({
    super.key,
    required this.existing,
    required this.suppliers,
    required this.onClose,
    required this.onSaved,
    required this.onDeleted,
  });

  final ManualBuyItem? existing;
  final List<RecordModel> suppliers;
  final VoidCallback onClose;
  final Future<void> Function() onSaved;
  final Future<void> Function() onDeleted;

  @override
  State<_ManualDetailPanel> createState() => _ManualDetailPanelState();
}

class _ManualDetailPanelState extends State<_ManualDetailPanel> {
  late final TextEditingController _descCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _supplierTextCtrl;
  String? _supplierId;
  bool _saving = false;

  final _pb = PocketBaseService();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _qtyCtrl = TextEditingController(text: (e?.qty ?? 1).toString());
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _supplierId = e?.supplier;
    String supplierName = '';
    if (_supplierId != null) {
      try {
        final sup = widget.suppliers.firstWhere((s) => s.id == _supplierId);
        supplierName = (sup.data['company_name'] ?? sup.id).toString();
      } catch (_) {
        supplierName = _supplierId ?? '';
      }
    }
    _supplierTextCtrl = TextEditingController(text: supplierName);
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    _supplierTextCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Description is required')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 1;
      final notes =
          _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();
      if (widget.existing == null) {
        await _pb.createManualBuyItem(
          description: desc,
          qty: qty,
          supplier: _supplierId,
          notes: notes,
        );
      } else {
        await _pb.updateManualBuyItem(
          id: widget.existing!.id,
          description: desc,
          qty: qty,
          supplier: _supplierId,
          notes: notes,
        );
      }
      await widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null) return;
    setState(() => _saving = true);
    try {
      await _pb.deleteManualBuyItem(id);
      await widget.onDeleted();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isNew = widget.existing == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  isNew ? 'Add custom item' : 'Custom item',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _descCtrl,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _qtyCtrl,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Qty',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Autocomplete<RecordModel>(
                optionsBuilder: (textValue) {
                  final query = textValue.text.trim().toLowerCase();
                  if (query.isEmpty) return widget.suppliers;
                  return widget.suppliers.where((s) {
                    final name =
                        (s.data['company_name'] ?? s.id).toString().toLowerCase();
                    return name.contains(query);
                  });
                },
                displayStringForOption: (s) =>
                    (s.data['company_name'] ?? s.id).toString(),
                initialValue: _supplierTextCtrl.text.isNotEmpty
                    ? TextEditingValue(text: _supplierTextCtrl.text)
                    : null,
                onSelected: (record) {
                  _supplierId = record.id;
                  _supplierTextCtrl.text =
                      (record.data['company_name'] ?? record.id).toString();
                },
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Supplier (optional)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      _supplierTextCtrl.text = value;
                      if (value.trim().isEmpty) _supplierId = null;
                    },
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                enabled: !_saving,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(isNew ? 'Add' : 'Save'),
                  ),
                  if (!isNew)
                    TextButton.icon(
                      onPressed: _saving ? null : _delete,
                      style:
                          TextButton.styleFrom(foregroundColor: scheme.error),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Remove'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
