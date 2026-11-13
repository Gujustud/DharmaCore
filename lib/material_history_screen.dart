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
  /// Materials with at least one on-shelf piece (length > 0).
  Set<String> _onShelfMaterialIds = {};
  bool _onShelfIdsUnavailable = false;
  bool _inStockOnly = false;
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
      final materialsFuture = pb.getMaterials();
      final lotsFuture = pb.getMaterialHeatLotsByMaterialId();
      Set<String> onShelfIds = {};
      var onShelfUnavailable = false;
      try {
        onShelfIds = await pb.getOnShelfMaterialIds();
      } catch (_) {
        // material_pieces may not exist on this host yet.
        onShelfUnavailable = true;
      }
      final records = await materialsFuture;
      final lots = await lotsFuture;
      final list = records.map(ShopMaterial.fromRecord).toList();
      setState(() {
        _materials = list;
        _lotsByMaterialId = lots;
        _onShelfMaterialIds = onShelfIds;
        _onShelfIdsUnavailable = onShelfUnavailable;
        if (onShelfUnavailable) _inStockOnly = false;
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

  Future<void> _refreshOnShelfIds() async {
    if (_onShelfIdsUnavailable) return;
    try {
      final ids = await PocketBaseService().getOnShelfMaterialIds();
      if (!mounted) return;
      setState(() {
        _onShelfMaterialIds = ids;
        _syncFilter(_searchController.text);
      });
    } catch (_) {
      // Keep previous snapshot; detail pane still refreshes from pieces.
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
    Iterable<ShopMaterial> source = _materials;
    if (_inStockOnly && !_onShelfIdsUnavailable) {
      source = source.where((m) => _onShelfMaterialIds.contains(m.id));
    }
    if (q.isEmpty) {
      _filtered = source.toList();
      _highlightHeatLot = null;
      return;
    }
    _filtered = source.where((m) {
      if (m.grade.toLowerCase().contains(q) ||
          m.form.toLowerCase().contains(q) ||
          materialFormLabel(m.form).toLowerCase().contains(q) ||
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

  void _toggleInStockOnly() {
    if (_onShelfIdsUnavailable) return;
    setState(() {
      _inStockOnly = !_inStockOnly;
      _syncFilter(_searchController.text);
    });
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
    if (onShelf.isEmpty) return 'Empty';
    final total = onShelf.fold<double>(0, (sum, p) => sum + p.lengthIn);
    final pcs = onShelf.length;
    final totalLabel = '${formatInchesValue(total)} in';
    if (pcs == 1) return '$totalLabel in 1 piece';
    return '$totalLabel across $pcs pieces';
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
      final inStockChip = _onShelfIdsUnavailable
          ? null
          : SizedBox(
              height: kListToolbarControlHeight,
              child: OutlinedButton(
                onPressed: _toggleInStockOnly,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  minimumSize: const Size(0, kListToolbarControlHeight),
                  maximumSize:
                      const Size(double.infinity, kListToolbarControlHeight),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor:
                      _inStockOnly ? scheme.primary : Colors.transparent,
                  foregroundColor:
                      _inStockOnly ? scheme.onPrimary : scheme.onSurface,
                  side: BorderSide(
                    color: _inStockOnly
                        ? scheme.primary
                        : scheme.outlineVariant,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'In stock',
                  style: TextStyle(fontSize: 14, height: 1.2),
                ),
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
            Row(
              children: [
                if (inStockChip != null) ...[
                  inStockChip,
                  const SizedBox(width: 12),
                ],
                Expanded(child: addButton),
              ],
            ),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: search),
          if (inStockChip != null) ...[
            const SizedBox(width: 12),
            inStockChip,
          ],
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
                              : _inStockOnly &&
                                      _searchController.text.trim().isEmpty
                                  ? 'Nothing in stock.\nTurn off In stock to see the full catalog.'
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
                          return Card(
                            color:
                                selected ? scheme.secondaryContainer : null,
                            child: ListTile(
                              title: _buildListIdentityTitle(
                                m,
                                scheme,
                                titleStyle,
                              ),
                              subtitle: matchedLot != null
                                  ? Text('Lot $matchedLot', style: muted)
                                  : null,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  PopupMenuButton<String>(
                                    onSelected: (value) {
                                      if (value == 'history') {
                                        showMaterialHistoryDialog(
                                          context,
                                          material: m,
                                        );
                                      } else if (value == 'edit') {
                                        _editMaterial(m);
                                      } else if (value == 'delete') {
                                        _deleteMaterial(m);
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: 'history',
                                        child: Text('History'),
                                      ),
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
                      dense: true,
                      leading: const Icon(Icons.arrow_back),
                      title: const Text('All materials'),
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

  /// List row: bold grade, muted form, size on second line.
  Widget _buildListIdentityTitle(
    ShopMaterial m,
    ColorScheme scheme,
    TextStyle? base,
  ) {
    final grade = m.grade.trim();
    final form = materialFormLabel(m.form);
    final size = formatMaterialSizeForLabel(m.sizeLabel);
    final muted = base?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w400,
        ) ??
        TextStyle(color: scheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            style: base,
            children: [
              if (grade.isNotEmpty)
                TextSpan(
                  text: grade,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              if (grade.isNotEmpty && form.isNotEmpty)
                TextSpan(text: '  ', style: muted),
              if (form.isNotEmpty) TextSpan(text: form, style: muted),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (size.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            size,
            style: muted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  /// Detail header: grade hero, form secondary, size on its own line.
  Widget _buildDetailIdentityTitle(
    ShopMaterial m,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    final grade = m.grade.trim();
    final form = materialFormLabel(m.form);
    final size = formatMaterialSizeForLabel(m.sizeLabel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              if (grade.isNotEmpty)
                TextSpan(
                  text: grade,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              if (grade.isNotEmpty && form.isNotEmpty)
                TextSpan(
                  text: '  ·  ',
                  style: textTheme.titleMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                  ),
                ),
              if (form.isNotEmpty)
                TextSpan(
                  text: form,
                  style: textTheme.titleMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
            ],
          ),
        ),
        if (size.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            size,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.2,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ],
    );
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
    final textTheme = Theme.of(context).textTheme;
    final notes = (selected.notes ?? '').trim();
    final mcmasterUrl = mcmasterProductUrl(selected.notes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailIdentityTitle(selected, scheme, textTheme),
                    const SizedBox(height: 6),
                    _buildHeaderFacts(scheme, selected, mcmasterUrl),
                    if (notes.isNotEmpty && mcmasterUrl == null) ...[
                      const SizedBox(height: 6),
                      Text(
                        notes,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => showMaterialHistoryDialog(
                  context,
                  material: selected,
                ),
                icon: const Icon(Icons.history, size: 18),
                label: const Text('History'),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'edit') {
                    _editMaterial(selected);
                  } else if (value == 'delete') {
                    _deleteMaterial(selected);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit material'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline, color: scheme.error),
                      title: Text(
                        'Delete material',
                        style: TextStyle(color: scheme.error),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              if (!_piecesUnavailable) ...[
                _sectionHeader(
                  scheme,
                  title: 'On shelf',
                  detail: _onHandSummary(),
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
                      'Nothing on the shelf. Add stock to log a piece and print its sticker.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                else
                  _listFrame(
                    scheme,
                    [
                      for (final piece in _onShelfPieces)
                        _buildPieceRow(scheme, selected, piece),
                    ],
                  ),
                const SizedBox(height: 28),
              ],
              _sectionHeader(
                scheme,
                title: 'Purchases',
                detail: _historyRecords.isEmpty
                    ? null
                    : '${_historyRecords.length} '
                        'line${_historyRecords.length == 1 ? '' : 's'}',
              ),
              const SizedBox(height: 8),
              if (_historyRecords.isEmpty)
                Text(
                  'No purchases linked to this material yet. Link it from a '
                  'purchase line, or edit or delete it from the ⋮ menu.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                )
              else
                _listFrame(
                  scheme,
                  [
                    for (final record in _historyRecords)
                      _buildPurchaseRow(scheme, record),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// One quiet line of price facts + McMaster link under the material title.
  Widget _buildHeaderFacts(
    ColorScheme scheme,
    ShopMaterial m,
    String? mcmasterUrl,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final labelStyle =
        textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final valueStyle = textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    );
    final prices = _priceSummary(m);

    Widget fact(String label, String value) {
      return Text.rich(
        TextSpan(
          style: labelStyle,
          children: [
            TextSpan(text: '$label '),
            TextSpan(text: value, style: valueStyle),
          ],
        ),
      );
    }

    final facts = <Widget>[
      if (prices?.perInch != null)
        Text.rich(
          TextSpan(
            style: labelStyle,
            children: [
              TextSpan(text: _money.format(prices!.perInch!), style: valueStyle),
              const TextSpan(text: ' per inch'),
            ],
          ),
        ),
      if (prices != null)
        fact('Last paid', '${_money.format(prices.last)}${prices.unitSuffix}'),
      if (prices?.avg != null)
        fact('Avg', '${_money.format(prices!.avg!)}${prices.unitSuffix}'),
      if (mcmasterUrl != null)
        InkWell(
          onTap: () => launchUrl(
            Uri.parse(mcmasterUrl),
            mode: LaunchMode.externalApplication,
          ),
          child: Text(
            'McMaster ${mcmasterPartNumberFromText(m.notes) ?? ''}'.trim(),
            style: labelStyle?.copyWith(
              color: scheme.primary,
              decoration: TextDecoration.underline,
              decorationColor: scheme.primary,
            ),
          ),
        ),
    ];
    if (facts.isEmpty) {
      return Text('No purchase price yet', style: labelStyle);
    }
    return Wrap(spacing: 20, runSpacing: 4, children: facts);
  }

  Widget _sectionHeader(
    ColorScheme scheme, {
    required String title,
    String? detail,
    Widget? action,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: detail == null
              ? const SizedBox.shrink()
              : Text(
                  detail,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
        ),
        ?action,
      ],
    );
  }

  /// Rows inside one outlined frame, separated by hairlines (not a card per row).
  Widget _listFrame(ColorScheme scheme, List<Widget> rows) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _addStock(ShopMaterial material) async {
    final piece = await showAddMaterialStockDialog(
      context,
      material: material,
    );
    if (piece == null || _selected == null) return;
    await _selectMaterial(_selected!);
    await _refreshOnShelfIds();
  }

  Future<void> _cutPiece(ShopMaterial material, MaterialPiece piece) async {
    final updated = await showCutMaterialPieceDialog(
      context,
      material: material,
      piece: piece,
    );
    if (updated == null || _selected == null) return;
    await _selectMaterial(_selected!);
    await _refreshOnShelfIds();
  }

  Future<void> _editPiece(ShopMaterial material, MaterialPiece piece) async {
    final updated = await showEditMaterialPieceDialog(
      context,
      material: material,
      piece: piece,
    );
    if (updated == null || _selected == null) return;
    await _selectMaterial(_selected!);
    await _refreshOnShelfIds();
  }

  Future<void> _scrapPiece(ShopMaterial material, MaterialPiece piece) async {
    final ok = await showScrapMaterialPieceDialog(
      context,
      material: material,
      piece: piece,
    );
    if (!ok || _selected == null) return;
    await _selectMaterial(_selected!);
    await _refreshOnShelfIds();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Scrapped ${piece.labelCode}'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildPieceRow(
    ColorScheme scheme,
    ShopMaterial material,
    MaterialPiece piece,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final loc = (piece.locationNote ?? '').trim();
    final heat = (piece.heatLot ?? '').trim();
    final meta = [
      if (heat.isNotEmpty) 'Lot $heat',
      if (loc.isNotEmpty) loc,
    ].join('   ');
    final lengthText = Text(
      piece.lengthLabel,
      textAlign: TextAlign.right,
      style: textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    final code = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Sticker code (${piece.labelCode})',
          child: Text(
            materialLabelCodeForSticker(piece.labelCode),
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              letterSpacing: 0.4,
            ),
          ),
        ),
        if (meta.isNotEmpty)
          Text(
            meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton(
          onPressed: () => _cutPiece(material, piece),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: const Text('Cut'),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Print sticker',
          onPressed: () => printOrPreviewMaterialLabel(
            context,
            material: material,
            piece: piece,
          ),
          icon: const Icon(Icons.print_outlined, size: 20),
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert, size: 20),
          onSelected: (value) {
            if (value == 'edit') {
              _editPiece(material, piece);
            } else if (value == 'scrap') {
              _scrapPiece(material, piece);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Edit piece'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'scrap',
              child: ListTile(
                leading: Icon(Icons.delete_sweep_outlined, color: scheme.error),
                title: Text(
                  'Scrap piece',
                  style: TextStyle(color: scheme.error),
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
      child: Row(
        children: [
          SizedBox(width: 84, child: lengthText),
          const SizedBox(width: 20),
          Expanded(child: code),
          const SizedBox(width: 12),
          actions,
        ],
      ),
    );
  }

  Widget _buildPurchaseRow(ColorScheme scheme, dynamic record) {
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
    final textTheme = Theme.of(context).textTheme;
    final detailStyle =
        textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final detailBold = detailStyle?.copyWith(
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    );

    final dateText = Text(
      date != null ? DateFormat.yMMMd().format(date) : 'No date',
      style: textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          supplier.isNotEmpty ? supplier : 'Unknown supplier',
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            style: detailStyle,
            children: [
              TextSpan(text: 'Qty $qty'),
              if (unit != null) ...[
                const TextSpan(text: ' at '),
                TextSpan(
                  text: _money.format(unit),
                  style: detailBold,
                ),
              ],
              if (lineTotal != null && qty != 1) ...[
                const TextSpan(text: ', '),
                TextSpan(text: _money.format(lineTotal), style: detailBold),
                const TextSpan(text: ' total'),
              ],
              if (heat.isNotEmpty) ...[
                const TextSpan(text: '     Lot '),
                TextSpan(text: heat, style: detailBold),
              ],
            ],
          ),
        ),
      ],
    );

    final certChips = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < certs.length; i++)
          Tooltip(
            message: certs[i],
            child: ActionChip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: Text(
                certs.length == 1 ? 'Mill cert' : 'Mill cert ${i + 1}',
              ),
              onPressed: () => _openMillCert(record, certs[i]),
            ),
          ),
      ],
    );

    return Material(
      color: highlight
          ? scheme.secondaryContainer.withValues(alpha: 0.55)
          : Colors.transparent,
      child: InkWell(
        onTap: () => _openPurchase(item.purchaseId),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              dateText,
                              const SizedBox(height: 4),
                              details,
                              if (certs.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                certChips,
                              ],
                            ],
                          )
                        : Row(
                            children: [
                              SizedBox(width: 110, child: dateText),
                              Expanded(child: details),
                              if (certs.isNotEmpty) ...[
                                const SizedBox(width: 12),
                                certChips,
                              ],
                            ],
                          ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
            );
          },
        ),
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
