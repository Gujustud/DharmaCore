import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'add_purchase_screen.dart';
import 'drawer_behavior.dart';
import 'list_toolbar_widgets.dart';
import 'material_form_icons.dart';
import 'material_stock_dialogs.dart';
import 'models.dart';
import 'pocketbase_service.dart';
import 'shop_material_editor.dart';
import 'ui_breakpoints.dart';
import 'vendor_part_links.dart';
import 'workspace_layout.dart';
import 'workspace_scaffold.dart';

/// Material catalog and purchase history by grade / form / size.
class MaterialHistoryScreen extends StatefulWidget {
  const MaterialHistoryScreen({super.key});

  @override
  State<MaterialHistoryScreen> createState() => _MaterialHistoryScreenState();
}

class _MaterialHistoryScreenState extends State<MaterialHistoryScreen>
    with AutoOpenDrawerMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final _searchController = TextEditingController();

  List<ShopMaterial> _materials = [];
  List<ShopMaterial> _filtered = [];
  /// materialId → distinct heat/lot values from purchase lines.
  Map<String, List<String>> _lotsByMaterialId = {};
  ShopMaterial? _selected;
  List<dynamic> _historyRecords = [];
  List<MaterialPiece> _pieces = [];
  bool _piecesUnavailable = false;
  /// When search matched a lot, highlight that heat/lot in the history panel.
  String? _highlightHeatLot;
  bool _loading = true;
  bool _loadingHistory = false;

  @override
  GlobalKey<ScaffoldState> get scaffoldKey => _scaffoldKey;

  @override
  void initState() {
    super.initState();
    _loadMaterials();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMaterials() async {
    setState(() => _loading = true);
    try {
      final pb = PocketBaseService();
      final results = await Future.wait([
        pb.getMaterials(),
        pb.getMaterialHeatLotsByMaterialId(),
      ]);
      final records = results[0] as List<dynamic>;
      final lots = results[1] as Map<String, List<String>>;
      final list = records.map(ShopMaterial.fromRecord).toList();
      setState(() {
        _materials = list;
        _lotsByMaterialId = lots;
        _syncFilter(_searchController.text);
        // Refresh selected if it still exists.
        if (_selected != null) {
          final id = _selected!.id;
          ShopMaterial? still;
          for (final m in list) {
            if (m.id == id) {
              still = m;
              break;
            }
          }
          _selected = still;
        }
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading materials: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<String> _lotsFor(ShopMaterial m) =>
      _lotsByMaterialId[m.id] ?? const <String>[];

  String? _firstMatchingLot(ShopMaterial m, String queryLower) {
    if (queryLower.isEmpty) return null;
    for (final lot in _lotsFor(m)) {
      if (lot.toLowerCase().contains(queryLower)) return lot;
    }
    return null;
  }

  void _syncFilter(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      _filtered = List.from(_materials);
      _highlightHeatLot = null;
      return;
    }
    _filtered = _materials.where((m) {
      if (m.grade.toLowerCase().contains(q) ||
          m.form.toLowerCase().contains(q) ||
          m.sizeLabel.toLowerCase().contains(q) ||
          m.displayLabel.toLowerCase().contains(q)) {
        return true;
      }
      return _lotsFor(m).any((lot) => lot.toLowerCase().contains(q));
    }).toList();
    String? highlight;
    for (final m in _filtered) {
      highlight = _firstMatchingLot(m, q);
      if (highlight != null) break;
    }
    _highlightHeatLot = highlight;
  }

  void _applyFilter(String query) {
    setState(() => _syncFilter(query));
  }

  Future<void> _selectMaterial(ShopMaterial m) async {
    final q = _searchController.text.trim().toLowerCase();
    final matchedLot = _firstMatchingLot(m, q);
    setState(() {
      _selected = m;
      _highlightHeatLot = matchedLot;
      _loadingHistory = true;
      _historyRecords = [];
      _pieces = [];
      _piecesUnavailable = false;
    });
    try {
      final pb = PocketBaseService();
      final historyFuture = pb.getPurchaseItemsByMaterial(m.id);
      List<MaterialPiece> pieces = [];
      var piecesUnavailable = false;
      try {
        final pieceRecords =
            await pb.getMaterialPiecesForMaterial(m.id, onShelfOnly: false);
        pieces = pieceRecords.map(MaterialPiece.fromRecord).toList();
      } catch (_) {
        // Migration may not be applied on this host yet.
        piecesUnavailable = true;
      }
      final records = await historyFuture;
      if (!mounted) return;
      setState(() {
        _historyRecords = records;
        _pieces = pieces;
        _piecesUnavailable = piecesUnavailable;
        _loadingHistory = false;
      });
    } catch (e) {
      setState(() => _loadingHistory = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading history: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<MaterialPiece> get _onShelfPieces =>
      _pieces.where((p) => p.isOnShelf && p.lengthIn > 0).toList();

  String _onHandSummary() {
    final onShelf = _onShelfPieces;
    if (onShelf.isEmpty) return 'No stock on shelf';
    final total = onShelf.fold<double>(0, (sum, p) => sum + p.lengthIn);
    final pcs = onShelf.length;
    final totalLabel = total == total.roundToDouble()
        ? '${total.round()} in'
        : '${total.toStringAsFixed(1)} in';
    return 'On shelf  $pcs pc${pcs == 1 ? '' : 's'} · $totalLabel';
  }

  Map<String, dynamic>? _expandFirst(dynamic expand, String key) {
    if (expand == null) return null;
    try {
      final v = expand[key];
      if (v is List && v.isNotEmpty) {
        return v.first.data as Map<String, dynamic>?;
      }
      if (v != null && v.data != null) {
        return v.data as Map<String, dynamic>?;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _openPurchase(String purchaseId) async {
    try {
      final record = await PocketBaseService().getPurchase(purchaseId);
      final purchase = Purchase.fromRecord(record);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AddPurchaseScreen(purchase: purchase),
        ),
      );
      if (_selected != null) await _selectMaterial(_selected!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open purchase: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _editMaterial(ShopMaterial material) async {
    final updated = await showShopMaterialEditor(
      context,
      existing: material,
    );
    if (updated == null) return;
    await _loadMaterials();
    if (!mounted) return;
    await _selectMaterial(updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Material updated'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _deleteMaterial(ShopMaterial material) async {
    // Refresh link count so we don't delete something in use.
    List<dynamic> linked = [];
    try {
      linked =
          await PocketBaseService().getPurchaseItemsByMaterial(material.id);
    } catch (_) {}

    var pieceCount = 0;
    try {
      final pieces = await PocketBaseService()
          .getMaterialPiecesForMaterial(material.id);
      pieceCount = pieces.length;
    } catch (_) {}

    if (linked.isNotEmpty || pieceCount > 0) {
      if (!mounted) return;
      final reasons = <String>[];
      if (linked.isNotEmpty) {
        reasons.add(
          '${linked.length} purchase line${linked.length == 1 ? '' : 's'}',
        );
      }
      if (pieceCount > 0) {
        reasons.add(
          '$pieceCount stock piece${pieceCount == 1 ? '' : 's'}',
        );
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cannot delete'),
          content: Text(
            '“${material.displayLabel}” is used by ${reasons.join(' and ')}. '
            'Remove those first, or edit this material instead.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete material?'),
        content: Text(
          'Delete “${material.displayLabel}” from the catalog?\n\n'
          'This only removes the catalog entry. It is not linked to any purchase or stock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await PocketBaseService().deleteMaterial(material.id);
      if (!mounted) return;
      setState(() {
        if (_selected?.id == material.id) {
          _selected = null;
          _historyRecords = [];
          _pieces = [];
          _piecesUnavailable = false;
        }
      });
      await _loadMaterials();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Material deleted'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting material: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _createMaterial() async {
    final created = await showShopMaterialEditor(context);
    if (created == null) return;
    await _loadMaterials();
    if (!mounted) return;
    await _selectMaterial(created);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Material created'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final titleStyle =
        textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
    final muted =
        textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final width = MediaQuery.sizeOf(context).width;
    final isNarrow = width < 700;
    // Same as Purchases: split only when wide AND a detail selection is open.
    final usePanel = width >= kWorkspaceWideBreakpointPx;
    final panelOpen = _selected != null;

    Widget buildToolbar({required bool stacked}) {
      final search = InventoryListSearchField(
        controller: _searchController,
        hintText: 'Search grade, size, or heat/lot…',
        onChanged: _applyFilter,
        decoration: inventoryListSearchDecoration(
          context,
          hintText: 'Search grade, size, or heat/lot…',
        ).copyWith(
          suffixIcon: _searchController.text.isNotEmpty
              ? inventoryListSearchClearButton(
                  onPressed: () {
                    _searchController.clear();
                    _applyFilter('');
                  },
                )
              : null,
        ),
      );
      final addButton = InventoryListActionButton(
        label: 'Add material',
        onPressed: _createMaterial,
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
            child: buildToolbar(
              stacked: isNarrow || (usePanel && panelOpen),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Text(
                          _materials.isEmpty
                              ? 'No materials yet.\nAdd one here, or from a purchase line.'
                              : 'No materials match your search.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          final m = _filtered[index];
                          final selected = _selected?.id == m.id;
                          final q = _searchController.text.trim().toLowerCase();
                          final matchedLot = _firstMatchingLot(m, q);
                          final subtitle = matchedLot != null
                              ? '${materialFormLabel(m.form)} · ${m.sizeLabel} · lot $matchedLot'
                              : '${materialFormLabel(m.form)} · ${m.sizeLabel}';
                          return Card(
                            color:
                                selected ? scheme.secondaryContainer : null,
                            child: ListTile(
                              title: Text(m.grade, style: titleStyle),
                              subtitle: Text(
                                subtitle,
                                style: muted,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  PopupMenuButton<String>(
                                    onSelected: (value) {
                                      if (value == 'edit') {
                                        _editMaterial(m);
                                      } else if (value == 'delete') {
                                        _deleteMaterial(m);
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Edit'),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Delete'),
                                      ),
                                    ],
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ],
                              ),
                              onTap: () => _selectMaterial(m),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      maxWidth: usePanel && panelOpen
          ? kWorkspacePanelContentMaxWidth
          : kWorkspaceContentMaxWidth,
    );

    final historyPane = _buildHistoryPane(scheme);

    return WorkspaceScaffold(
      scaffoldKey: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Material'),
        leading: workspaceMenuLeading(context),
      ),
      body: usePanel && panelOpen
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
                    child: historyPane,
                  ),
                ),
              ],
            )
          : !usePanel && panelOpen
              ? Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.arrow_back),
                      title: Text(_selected!.displayLabel),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          final m = _selected!;
                          if (value == 'edit') {
                            _editMaterial(m);
                          } else if (value == 'delete') {
                            _deleteMaterial(m);
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(
                              value: 'delete', child: Text('Delete')),
                        ],
                      ),
                      onTap: () => setState(() {
                        _selected = null;
                        _historyRecords = [];
                        _pieces = [];
                        _piecesUnavailable = false;
                      }),
                    ),
                    const Divider(height: 1),
                    Expanded(child: historyPane),
                  ],
                )
              : listColumn,
    );
  }

  static final _money = NumberFormat.currency(symbol: '\$');

  /// Parse numbers from a free-text size like `7×72`, `1.5" OD x 12"`, `0.5 x 4 x 12`.
  List<double> _parseSizeNumbers(String sizeLabel) {
    final cleaned = sizeLabel
        .replaceAll(RegExp(r'[""″]'), '')
        .replaceAll(RegExp(r'\b(od|id|in|inch|inches|mm)\b', caseSensitive: false), ' ');
    final matches = RegExp(r'(\d+(?:\.\d+)?)').allMatches(cleaned);
    return [
      for (final m in matches) double.tryParse(m.group(1)!) ?? double.nan,
    ].where((n) => n.isFinite && n > 0).toList();
  }

  /// Best-effort length in inches from size (last dimension for multi-part sizes).
  double? _lengthInchesFromSize(String sizeLabel) {
    final nums = _parseSizeNumbers(sizeLabel);
    if (nums.isEmpty) return null;
    return nums.last;
  }

  double? _costPerInch({
    required ShopMaterial m,
    required double unitCost,
  }) {
    final unit = m.unit.trim().toLowerCase();
    if (unit == 'in') return unitCost;
    if (unit == 'ft') return unitCost / 12;
    final len = _lengthInchesFromSize(m.sizeLabel);
    if (len != null && len > 0 && (unit == 'ea' || unit.isEmpty)) {
      return unitCost / len;
    }
    return null;
  }

  /// Price unit suffix for display. Empty for each (default) so we don't say
  /// both "each" and "/ea".
  String _priceUnitSuffix(String unit) {
    switch (unit.trim().toLowerCase()) {
      case '':
      case 'ea':
        return '';
      case 'ft':
        return '/ft';
      case 'in':
        return '/in';
      case 'lb':
        return '/lb';
      case 'kg':
        return '/kg';
      default:
        return '/${unit.trim()}';
    }
  }

  String _identityTitle(ShopMaterial m) {
    final grade = m.grade.trim();
    final form = materialFormLabel(m.form);
    final size = m.sizeLabel.trim();
    final parts = <String>[
      if (grade.isNotEmpty) grade,
      form,
      if (size.isNotEmpty) size,
    ];
    return parts.join(' · ');
  }

  /// Last / avg / $/in for the detail header price column. Null when no costs.
  _MaterialPriceSummary? _priceSummary(ShopMaterial m) {
    final costs = <double>[];
    for (final record in _historyRecords) {
      final item = PurchaseItem.fromRecord(record);
      if (item.unitCost != null && item.unitCost! > 0) {
        costs.add(item.unitCost!);
      }
    }
    if (costs.isEmpty) return null;

    final last = costs.first; // history sorted newest-first
    double? avg;
    if (costs.length > 1) {
      final computed = costs.reduce((a, b) => a + b) / costs.length;
      if ((computed - last).abs() / last > 0.02) {
        avg = computed;
      }
    }
    final unit = m.unit.trim().toLowerCase();
    // Avoid "Last $4.00/in" plus a duplicate "$4.00/in" line.
    final perInch =
        unit == 'in' ? null : _costPerInch(m: m, unitCost: last);
    return _MaterialPriceSummary(
      last: last,
      avg: avg,
      perInch: perInch,
      unitSuffix: _priceUnitSuffix(m.unit),
    );
  }

  Widget _buildHistoryPane(ColorScheme scheme) {
    if (_selected == null) {
      return Center(
        child: Text(
          'Select a material to see purchase history.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    if (_loadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }

    final selected = _selected!;
    final prices = _priceSummary(selected);
    final notes = (selected.notes ?? '').trim();
    final muted = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        );
    final priceValueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _identityTitle(selected),
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        if (!_piecesUnavailable) ...[
                          const SizedBox(height: 6),
                          Text(
                            _onHandSummary(),
                            style: muted,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (prices != null)
                    _buildPriceColumn(
                      prices,
                      labelStyle: muted,
                      valueStyle: priceValueStyle,
                    ),
                  TextButton.icon(
                    onPressed: () => _editMaterial(selected),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: () => _deleteMaterial(selected),
                    style: TextButton.styleFrom(foregroundColor: scheme.error),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete'),
                  ),
                ],
              ),
              if (mcmasterProductUrl(selected.notes) != null) ...[
                const SizedBox(height: 4),
                InkWell(
                  onTap: () {
                    final url = mcmasterProductUrl(selected.notes);
                    if (url != null) {
                      launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  child: Text(
                    'Order on McMaster: ${mcmasterPartNumberFromText(selected.notes)}',
                    style: TextStyle(
                      color: scheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  notes,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (!_piecesUnavailable) ...[
                _sectionHeader(
                  scheme,
                  title: 'On shelf',
                  action: TextButton.icon(
                    onPressed: () => _addStock(selected),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add stock'),
                  ),
                ),
                const SizedBox(height: 8),
                if (_onShelfPieces.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'No pieces on the shelf yet. Add stock to print a sticker.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                else
                  for (final piece in _onShelfPieces) ...[
                    _buildPieceCard(scheme, selected, piece),
                    const SizedBox(height: 8),
                  ],
                const SizedBox(height: 12),
              ],
              _sectionHeader(scheme, title: 'Purchases'),
              const SizedBox(height: 8),
              if (_historyRecords.isEmpty)
                Text(
                  'No purchases linked to this material yet.\n'
                  'It may have been created from a purchase form and never saved on a line — '
                  'you can edit or delete it here.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                )
              else
                for (var i = 0; i < _historyRecords.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _buildPurchaseCard(scheme, _historyRecords[i]),
                ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(
    ColorScheme scheme, {
    required String title,
    Widget? action,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ),
        if (action != null) action,
      ],
    );
  }

  Future<void> _addStock(ShopMaterial material) async {
    final piece = await showAddMaterialStockDialog(
      context,
      material: material,
    );
    if (piece == null || _selected == null) return;
    await _selectMaterial(_selected!);
  }

  Future<void> _cutPiece(ShopMaterial material, MaterialPiece piece) async {
    final updated = await showCutMaterialPieceDialog(
      context,
      material: material,
      piece: piece,
    );
    if (updated == null || _selected == null) return;
    await _selectMaterial(_selected!);
  }

  Widget _buildPieceCard(
    ColorScheme scheme,
    ShopMaterial material,
    MaterialPiece piece,
  ) {
    final loc = (piece.locationNote ?? '').trim();
    final heat = (piece.heatLot ?? '').trim();
    final subtitle = [
      piece.lengthLabel,
      if (loc.isNotEmpty) loc,
      if (heat.isNotEmpty) 'lot $heat',
    ].join(' · ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    piece.labelCode,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _cutPiece(material, piece),
              child: const Text('Cut'),
            ),
            TextButton(
              onPressed: () => printOrPreviewMaterialLabel(
                context,
                material: material,
                piece: piece,
              ),
              child: const Text('Print'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPurchaseCard(ColorScheme scheme, dynamic record) {
    final item = PurchaseItem.fromRecord(record);
    final purchaseData = _expandFirst(record.expand, 'purchase');
    final supplierData = () {
      try {
        final p = record.expand?['purchase'];
        final purchaseRec = (p is List && p.isNotEmpty) ? p.first : p;
        return _expandFirst(purchaseRec?.expand, 'supplier');
      } catch (_) {
        return null;
      }
    }();

    DateTime? date;
    final rawDate = purchaseData?['purchase_date'];
    if (rawDate != null) {
      date = DateTime.tryParse(rawDate.toString());
    }
    final supplier = (supplierData?['company_name'] ?? '').toString().trim();
    final heat = (item.heatLot ?? '').trim();
    final qty = item.quantity;
    final unit = item.unitCost;
    final lineTotal = unit != null ? qty * unit : null;
    final certs = item.millCertNames;
    final highlight = _highlightHeatLot != null &&
        heat.isNotEmpty &&
        heat.toLowerCase().contains(_highlightHeatLot!.toLowerCase());
    final detailStyle = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(color: scheme.onSurfaceVariant);
    final detailBold = detailStyle?.copyWith(
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    );

    return Card(
      color: highlight
          ? scheme.secondaryContainer.withValues(alpha: 0.55)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openPurchase(item.purchaseId),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        if (date != null) DateFormat.yMMMd().format(date),
                        if (supplier.isNotEmpty) supplier,
                      ].join(' · '),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (heat.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text.rich(
                        TextSpan(
                          style: detailStyle,
                          children: [
                            const TextSpan(text: 'Heat/lot '),
                            TextSpan(text: heat, style: detailBold),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        style: detailStyle,
                        children: [
                          TextSpan(text: 'Qty $qty'),
                          if (unit != null) ...[
                            const TextSpan(text: ' · '),
                            TextSpan(
                              text: '\$${unit.toStringAsFixed(2)}/unit',
                              style: detailBold,
                            ),
                          ],
                          if (lineTotal != null) ...[
                            const TextSpan(text: ' · total '),
                            TextSpan(
                              text: '\$${lineTotal.toStringAsFixed(2)}',
                              style: detailBold,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (certs.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final name in certs)
                            ActionChip(
                              avatar: const Icon(
                                Icons.picture_as_pdf,
                                size: 16,
                              ),
                              label: Text(
                                name,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onPressed: () => _openMillCert(record, name),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriceColumn(
    _MaterialPriceSummary prices, {
    required TextStyle? labelStyle,
    required TextStyle? valueStyle,
  }) {
    Widget row(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              child: Text(label, style: labelStyle),
            ),
            Text(value, style: valueStyle),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row('Last', '${_money.format(prices.last)}${prices.unitSuffix}'),
          if (prices.avg != null)
            row('Avg', '${_money.format(prices.avg!)}${prices.unitSuffix}'),
          if (prices.perInch != null)
            row('\$/in', _money.format(prices.perInch!)),
        ],
      ),
    );
  }

  Future<void> _openMillCert(dynamic record, String filename) async {
    final url = PocketBaseService().pb.files.getUrl(record, filename);
    final uri = Uri.parse(url.toString());
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $filename')),
      );
    }
  }
}

class _MaterialPriceSummary {
  const _MaterialPriceSummary({
    required this.last,
    required this.avg,
    required this.perInch,
    required this.unitSuffix,
  });

  final double last;
  final double? avg;
  final double? perInch;
  final String unitSuffix;
}
