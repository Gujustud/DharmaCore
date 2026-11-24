import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'pocketbase_service.dart';
import 'models.dart';
import 'add_purchase_screen.dart';
import 'supplier_spend_panel.dart';
import 'drawer_behavior.dart';
import 'ui_breakpoints.dart';
import 'workspace_layout.dart';
import 'workspace_scaffold.dart';

class SupplierDetailScreen extends StatefulWidget {
  /// null = new supplier (add mode), non-null = edit mode
  final dynamic supplier;

  /// When true, renders as a side panel (no scaffold / route pop).
  final bool embedded;
  final ValueChanged<bool>? onClosed;

  const SupplierDetailScreen({
    super.key,
    this.supplier,
    this.embedded = false,
    this.onClosed,
  });

  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends State<SupplierDetailScreen> with AutoOpenDrawerMixin {
  // Form controllers
  final _companyNameController = TextEditingController();
  final _contactController     = TextEditingController();
  final _telController         = TextEditingController();
  final _directTelController   = TextEditingController();
  final _emailController       = TextEditingController();
  final _websiteController     = TextEditingController();
  final _notesController       = TextEditingController();
  final _addressController     = TextEditingController();

  List<dynamic> _categories = [];
  final Set<String> _selectedCategoryIds = {};

  List<Purchase> _purchases = [];
  List<PurchaseItem>? _purchaseItems;
  SpendPeriod? _spendPeriod;
  bool _isLoadingPurchases = true;
  bool _isSaving = false;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  GlobalKey<ScaffoldState> get scaffoldKey => _scaffoldKey;

  bool get _isNew => widget.supplier == null;

  @override
  void initState() {
    super.initState();
    if (!_isNew) {
      final d = widget.supplier.data;
      _companyNameController.text = d['company_name'] ?? '';
      _contactController.text     = d['contact']      ?? '';
      _telController.text         = d['tel']           ?? '';
      _directTelController.text   = d['direct_tel']    ?? '';
      _emailController.text       = d['email']         ?? '';
      _websiteController.text     = d['website']       ?? '';
      _notesController.text       = d['notes']         ?? '';
      _addressController.text     = d['address']       ?? '';
      final cats = d['categories'];
      if (cats is List) {
        for (final c in cats) {
          String? id;
          if (c is String) {
            id = c;
          } else if (c is Map && c['id'] != null) {
            id = c['id'] as String;
          } else {
            // Fallback: try common patterns or last-resort string
            try {
              final dynamic dyn = c;
              if (dyn.id is String) {
                id = dyn.id as String;
              }
            } catch (_) {
              // ignore
            }
            id ??= c.toString();
          }
          if (id.isNotEmpty) {
            _selectedCategoryIds.add(id);
          }
        }
      }
    }
    _loadCategories();
    if (!_isNew) _loadPurchases();
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _contactController.dispose();
    _telController.dispose();
    _directTelController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    _notesController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final pb = PocketBaseService();
      // Ensure Materials exists so quote Buy vendors can be tagged here.
      await pb.ensureMaterialsCategoryId();
      final cats = await pb.getCategories();
      if (mounted) setState(() => _categories = cats);
    } catch (_) {}
  }

  Future<void> _loadPurchases() async {
    setState(() => _isLoadingPurchases = true);
    try {
      final records = await PocketBaseService().getPurchases(supplierId: widget.supplier.id);
      setState(() {
        _purchases = records.map((r) => Purchase.fromRecord(r)).toList();
        _isLoadingPurchases = false;
      });
      _loadPurchaseItems();
    } catch (e) {
      setState(() => _isLoadingPurchases = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading purchases: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadPurchaseItems() async {
    try {
      final records = await PocketBaseService()
          .getPurchaseItemsBySupplier(widget.supplier.id);
      if (!mounted) return;
      setState(() {
        _purchaseItems = records.map((r) => PurchaseItem.fromRecord(r)).toList();
      });
    } catch (_) {
      // Breakdown is optional; stats and chart only need purchase totals.
      if (mounted) setState(() => _purchaseItems = const []);
    }
  }

  List<Purchase> get _visiblePurchases => _spendPeriod == null
      ? _purchases
      : _purchases
          .where((p) => _spendPeriod!.contains(p.purchaseDate))
          .toList();

  void _close({required bool saved}) {
    if (widget.embedded) {
      widget.onClosed?.call(saved);
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context, saved);
    }
  }

  String get _title {
    if (_isNew) return 'Add Supplier';
    final name = _companyNameController.text.trim();
    return name.isEmpty ? 'Supplier' : name;
  }

  Future<void> _delete() async {
    final name = _companyNameController.text.trim().isEmpty
        ? (widget.supplier.data['company_name'] ?? 'this supplier')
        : _companyNameController.text.trim();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Supplier'),
        content: Text('Delete "$name"?'),
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
    if (confirm != true || !mounted) return;
    try {
      await PocketBaseService().deleteSupplier(widget.supplier.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Supplier deleted'),
            backgroundColor: Colors.green,
          ),
        );
        _close(saved: true);
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

  Future<void> _save() async {
    if (_companyNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Company name is required')),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final pb = PocketBaseService();
      if (_isNew) {
        await pb.createSupplier(
          companyName: _companyNameController.text.trim(),
          address:     _addressController.text.trim(),
          tel:         _telController.text.trim(),
          website:     _websiteController.text.trim(),
          contact:     _contactController.text.trim(),
          directTel:   _directTelController.text.trim(),
          email:       _emailController.text.trim(),
          notes:       _notesController.text.trim(),
          categoryIds: _selectedCategoryIds.toList(),
        );
      } else {
        await pb.updateSupplier(
          id:          widget.supplier.id,
          companyName: _companyNameController.text.trim(),
          address:     _addressController.text.trim(),
          tel:         _telController.text.trim(),
          website:     _websiteController.text.trim(),
          contact:     _contactController.text.trim(),
          directTel:   _directTelController.text.trim(),
          email:       _emailController.text.trim(),
          notes:       _notesController.text.trim(),
          categoryIds: _selectedCategoryIds.toList(),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isNew ? 'Supplier added' : 'Supplier updated'),
            backgroundColor: Colors.green,
          ),
        );
        _close(saved: true);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildEmbeddedHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  _title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => _close(saved: false),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          floatingLabelBehavior: FloatingLabelBehavior.always,
        ),
      ),
    );
  }

  Widget _categoriesWidget() {
    if (_categories.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Used in Categories', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 2),
        Text('Leave unchecked to show for all', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 6),
        ..._categories.map((cat) {
          final selected = _selectedCategoryIds.contains(cat.id);
          return CheckboxListTile(
            title: Text(cat.data['name']),
            value: selected,
            onChanged: (v) => setState(() {
              if (v == true) {
                _selectedCategoryIds.add(cat.id);
              } else {
                _selectedCategoryIds.remove(cat.id);
              }
            }),
            contentPadding: EdgeInsets.zero,
          );
        }),
      ],
    );
  }

  Widget _fieldsWidget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(controller: _companyNameController, label: 'Company Name *'),
        _field(controller: _contactController,     label: 'Contact Person'),
        Row(
          children: [
            Expanded(child: _field(controller: _telController,       label: 'Telephone',  keyboardType: TextInputType.phone)),
            const SizedBox(width: 12),
            Expanded(child: _field(controller: _directTelController, label: 'Direct Tel', keyboardType: TextInputType.phone)),
          ],
        ),
        _field(controller: _addressController, label: 'Address', maxLines: 2),
        Row(
          children: [
            Expanded(child: _field(controller: _emailController,   label: 'Email',   keyboardType: TextInputType.emailAddress)),
            const SizedBox(width: 12),
            Expanded(child: _field(controller: _websiteController, label: 'Website', keyboardType: TextInputType.url)),
          ],
        ),
        _field(controller: _notesController,   label: 'Notes',   maxLines: 3),
      ],
    );
  }

  Widget _buildFormBody() {
    final visiblePurchases = _visiblePurchases;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: widget.embedded ? kWorkspaceContentMaxWidth : 1000,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 600;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isWide)
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: _fieldsWidget()),
                          const SizedBox(width: 24),
                          Expanded(flex: 2, child: _categoriesWidget()),
                        ],
                      ),
                    )
                  else ...[
                    _fieldsWidget(),
                    if (_categories.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _categoriesWidget(),
                    ],
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton(
                        onPressed: _isSaving ? null : _save,
                        child: _isSaving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(_isNew ? 'Save supplier' : 'Save changes'),
                      ),
                      if (!_isNew) ...[
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _isSaving ? null : _delete,
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.error,
                            foregroundColor:
                                Theme.of(context).colorScheme.onError,
                          ),
                          child: const Text('Delete'),
                        ),
                      ],
                    ],
                  ),
                  if (!_isNew) ...[
                    if (!_isLoadingPurchases && _purchases.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      SupplierSpendPanel(
                        purchases: _purchases,
                        items: _purchaseItems,
                        selectedPeriod: _spendPeriod,
                        onPeriodSelected: (p) =>
                            setState(() => _spendPeriod = p),
                      ),
                    ],
                    const SizedBox(height: 28),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        const Text(
                          'Purchase History',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (!_isLoadingPurchases)
                          Text(
                            _spendPeriod == null
                                ? '(${_purchases.length})'
                                : '(${visiblePurchases.length} of ${_purchases.length})',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        if (_spendPeriod != null)
                          InputChip(
                            label: Text(_spendPeriod!.label),
                            avatar: const Icon(Icons.filter_alt, size: 16),
                            visualDensity: VisualDensity.compact,
                            onDeleted: () =>
                                setState(() => _spendPeriod = null),
                          ),
                      ],
                    ),
                    const Divider(height: 16),
                    if (_isLoadingPurchases)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_purchases.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.receipt_long_outlined,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No purchases from this supplier yet.',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: visiblePurchases.length,
                        itemBuilder: (context, index) {
                          final p = visiblePurchases[index];
                          return Card(
                            child: ListTile(
                              leading: const Icon(
                                Icons.receipt_outlined,
                                color: Colors.blueGrey,
                              ),
                              title: Text(
                                DateFormat.yMMMd().format(p.purchaseDate),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (p.orderReference != null &&
                                      p.orderReference!.isNotEmpty)
                                    Text('Ref: ${p.orderReference}'),
                                  if (p.invoice != null &&
                                      p.invoice!.trim().isNotEmpty)
                                    Text('Invoice: ${p.invoice}'),
                                  if (p.total != null)
                                    Text(
                                      '${NumberFormat.currency(symbol: '\$').format(p.total)} ${p.currency}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.green,
                                      ),
                                    ),
                                ],
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        AddPurchaseScreen(purchase: p),
                                  ),
                                );
                                _loadPurchases();
                              },
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 16),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final form = _buildFormBody();

    if (widget.embedded) {
      final scheme = Theme.of(context).colorScheme;
      return Material(
        color: scheme.surface,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildEmbeddedHeader(context),
              Expanded(child: form),
            ],
          ),
        ),
      );
    }

    return WorkspaceScaffold(
      scaffoldKey: _scaffoldKey,
      appBar: AppBar(
        title: Text(_title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: workspaceMenuLeading(context),
      ),
      body: form,
    );
  }
}
