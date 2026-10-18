import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'pocketbase_service.dart';
import 'models.dart';
import 'add_purchase_screen.dart';
import 'purchase_draft_review_screen.dart';
import 'drawer_behavior.dart';
import 'list_toolbar_widgets.dart';
import 'ui_breakpoints.dart';
import 'workspace_layout.dart';
import 'workspace_scaffold.dart';

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> with AutoOpenDrawerMixin {
  List<Purchase> _purchases = [];
  List<Purchase> _filteredPurchases = [];
  List<PurchaseDraft> _drafts = [];
  final TextEditingController _purchaseSearchController = TextEditingController();
  String _purchaseSearchQuery = '';
  bool _isLoading = true;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Wide layout: selected purchase shown in the right panel (null when closed / new).
  Purchase? _selectedPurchase;

  /// Wide layout: right panel is creating a new purchase.
  bool _creatingNew = false;

  /// Wide layout: reviewing an email draft in the right panel.
  PurchaseDraft? _selectedDraft;

  @override
  GlobalKey<ScaffoldState> get scaffoldKey => _scaffoldKey;

  bool get _panelOpen =>
      _creatingNew || _selectedPurchase != null || _selectedDraft != null;

  @override
  void initState() {
    super.initState();
    _loadPurchases();
  }

  @override
  void dispose() {
    _purchaseSearchController.dispose();
    super.dispose();
  }

  List<Purchase> _applyPurchaseSearchFilter(List<Purchase> source) {
    final q = _purchaseSearchQuery.trim().toLowerCase();
    if (q.isEmpty) return source;

    return source.where((p) {
      final supplier = (p.supplierName ?? '').toLowerCase();
      final ref = (p.orderReference ?? '').toLowerCase();
      final invoice = (p.invoice ?? '').toLowerCase();
      return supplier.contains(q) || ref.contains(q) || invoice.contains(q);
    }).toList();
  }

  Future<void> _loadPurchases() async {
    setState(() => _isLoading = true);
    try {
      final pbService = PocketBaseService();
      final records = await pbService.getPurchases();
      List<dynamic> draftRecords = [];
      Object? draftLoadError;
      try {
        draftRecords = await pbService.getPendingPurchaseDrafts();
      } catch (e) {
        draftLoadError = e;
        draftRecords = [];
      }
      setState(() {
        _purchases = records.map((r) => Purchase.fromRecord(r)).toList();
        _filteredPurchases = _applyPurchaseSearchFilter(_purchases);
        _drafts = draftRecords.map((r) => PurchaseDraft.fromRecord(r)).toList();
        // Keep selection if the purchase still exists after reload.
        if (_selectedPurchase != null) {
          final id = _selectedPurchase!.id;
          Purchase? stillThere;
          for (final p in _purchases) {
            if (p.id == id) {
              stillThere = p;
              break;
            }
          }
          _selectedPurchase = stillThere;
          if (_selectedPurchase == null) _creatingNew = false;
        }
        if (_selectedDraft != null) {
          final id = _selectedDraft!.id;
          PurchaseDraft? still;
          for (final d in _drafts) {
            if (d.id == id) {
              still = d;
              break;
            }
          }
          _selectedDraft = still;
        }
        _isLoading = false;
      });
      if (draftLoadError != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load email drafts: $draftLoadError'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading purchases: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _closePanel() {
    setState(() {
      _selectedPurchase = null;
      _selectedDraft = null;
      _creatingNew = false;
    });
  }

  void _onPanelClosed(bool saved) {
    _closePanel();
    if (saved) _loadPurchases();
  }

  Future<void> _openPurchase(Purchase purchase, {required bool usePanel}) async {
    if (usePanel) {
      setState(() {
        _selectedPurchase = purchase;
        _selectedDraft = null;
        _creatingNew = false;
      });
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddPurchaseScreen(purchase: purchase),
      ),
    );
    _loadPurchases();
  }

  Future<void> _openDraft(PurchaseDraft draft, {required bool usePanel}) async {
    if (usePanel) {
      setState(() {
        _selectedDraft = draft;
        _selectedPurchase = null;
        _creatingNew = false;
      });
      return;
    }
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => PurchaseDraftReviewScreen(draft: draft),
      ),
    );
    if (saved == true) _loadPurchases();
  }

  Future<void> _openAddPurchase({required bool usePanel}) async {
    if (usePanel) {
      setState(() {
        _selectedPurchase = null;
        _selectedDraft = null;
        _creatingNew = true;
      });
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddPurchaseScreen(),
      ),
    );
    _loadPurchases();
  }

  Widget _buildToolbar(bool isNarrow, {required bool usePanel}) {
    final search = InventoryListSearchField(
      controller: _purchaseSearchController,
      hintText: 'Search supplier or invoice #...',
      onChanged: (v) {
        setState(() {
          _purchaseSearchQuery = v;
          _filteredPurchases = _applyPurchaseSearchFilter(_purchases);
        });
      },
      decoration: inventoryListSearchDecoration(
        context,
        hintText: 'Search supplier or invoice #...',
      ).copyWith(
        suffixIcon: _purchaseSearchController.text.isNotEmpty
            ? inventoryListSearchClearButton(
                onPressed: () {
                  _purchaseSearchController.clear();
                  setState(() {
                    _purchaseSearchQuery = '';
                    _filteredPurchases = _purchases;
                  });
                },
              )
            : null,
      ),
    );
    final addButton = InventoryListActionButton(
      label: 'Add Purchase',
      onPressed: () => _openAddPurchase(usePanel: usePanel),
    );

    if (isNarrow) {
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

  Widget _buildPurchaseList({
    required bool usePanel,
    required TextStyle? titleStyle,
    required TextStyle? muted,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final showDrafts =
        _drafts.isNotEmpty && _purchaseSearchQuery.trim().isEmpty;

    if (_filteredPurchases.isEmpty && !showDrafts) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              _purchaseSearchQuery.trim().isNotEmpty
                  ? 'No purchases match your search.'
                  : 'No purchases yet.\nClick "Add Purchase" above to get started.',
              textAlign: TextAlign.center,
              style: muted,
            ),
          ],
        ),
      );
    }

    // When the detail panel is open, keep the master list compact (supplier + ref);
    // date/total move to a hover tooltip so the form gets more width.
    final compactMaster = usePanel && _panelOpen;

    final draftHeader = showDrafts ? 1 : 0;
    final draftCount = showDrafts ? _drafts.length : 0;
    final purchaseHeader =
        showDrafts && _filteredPurchases.isNotEmpty ? 1 : 0;
    final itemCount =
        draftHeader + draftCount + purchaseHeader + _filteredPurchases.length;

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (showDrafts && index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              children: [
                Icon(Icons.mark_email_unread_outlined,
                    size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Needs review (${_drafts.length})',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          );
        }
        if (showDrafts && index <= draftCount) {
          final d = _drafts[index - 1];
          return _buildDraftCard(
            d,
            usePanel: usePanel,
            titleStyle: titleStyle,
            muted: muted,
            selected: usePanel && _selectedDraft?.id == d.id,
          );
        }
        final afterDrafts = draftHeader + draftCount;
        if (purchaseHeader == 1 && index == afterDrafts) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: Text(
              'Purchases',
              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          );
        }
        final purchaseIndex = index - afterDrafts - purchaseHeader;
        final p = _filteredPurchases[purchaseIndex];
        final supplier = p.supplierName ?? 'No supplier';
        final dateText = DateFormat.yMMMd().format(p.purchaseDate);
        final refRaw = p.orderReference?.trim();
        final refText =
            (refRaw != null && refRaw.isNotEmpty) ? 'Ref: $refRaw' : null;
        final cur = p.currency == 'USD' ? 'USD' : 'CAD';
        final totalText = p.total != null
            ? 'Total: \$${p.total!.toStringAsFixed(2)} $cur'
            : (cur == 'USD' ? 'USD' : null);
        final selected = usePanel &&
            !_creatingNew &&
            _selectedPurchase?.id == p.id;

        final hoverBits = <String>[
          dateText,
          if (refText != null) refText,
          if (totalText != null) totalText,
        ];
        final hoverMessage = hoverBits.join('\n');

        Widget cardBody({required bool isWideCard}) {
          if (compactMaster) {
            return Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        supplier,
                        style: titleStyle,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (refText != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          refText,
                          style: muted,
                          overflow: TextOverflow.ellipsis,
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
            );
          }
          if (isWideCard) {
            return Row(
              children: [
                Expanded(
                  child: Text(
                    supplier,
                    style: titleStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 16),
                Text(dateText, style: muted),
                if (refText != null) ...[
                  const SizedBox(width: 20),
                  Text(refText, style: muted),
                ],
                if (totalText != null) ...[
                  const SizedBox(width: 20),
                  Text(totalText, style: titleStyle),
                ],
                const SizedBox(width: 10),
                Icon(
                  Icons.chevron_right,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(supplier, style: titleStyle),
                    const SizedBox(height: 4),
                    Text(dateText, style: muted),
                    if (refText != null) Text(refText, style: muted),
                    if (totalText != null) Text(totalText, style: titleStyle),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: scheme.onSurfaceVariant,
              ),
            ],
          );
        }

        return Card(
          color: selected ? scheme.secondaryContainer : null,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWideCard = constraints.maxWidth >= 560;
              final tile = InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _openPurchase(p, usePanel: usePanel),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: cardBody(isWideCard: isWideCard),
                ),
              );
              if (!compactMaster) return tile;
              return Tooltip(
                message: hoverMessage,
                waitDuration: const Duration(milliseconds: 400),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: scheme.outlineVariant),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                textStyle: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface,
                ),
                child: tile,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDraftCard(
    PurchaseDraft d, {
    required bool usePanel,
    required TextStyle? titleStyle,
    required TextStyle? muted,
    required bool selected,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final supplier = d.supplierName ?? d.displayVendor;
    final dateText = d.purchaseDate != null
        ? DateFormat.yMMMd().format(d.purchaseDate!)
        : '—';
    final refRaw = d.orderReference?.trim();
    final refText =
        (refRaw != null && refRaw.isNotEmpty) ? 'Ref: $refRaw' : null;
    final cur = d.currency == 'USD' ? 'USD' : 'CAD';
    final totalText = d.total != null
        ? 'Total: \$${d.total!.toStringAsFixed(2)} $cur'
        : cur;

    return Card(
      color: selected
          ? scheme.secondaryContainer
          : scheme.primaryContainer.withValues(alpha: 0.35),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openDraft(d, usePanel: usePanel),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.inbox_outlined, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(supplier, style: titleStyle),
                    const SizedBox(height: 2),
                    Text(
                      [
                        d.displayVendor,
                        dateText,
                        if (refText != null) refText,
                        if (totalText.isNotEmpty) totalText,
                      ].join(' · '),
                      style: muted,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Chip(
                label: const Text('Review'),
                visualDensity: VisualDensity.compact,
                backgroundColor: scheme.primaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailPanel() {
    if (!_panelOpen) {
      return const SizedBox.shrink();
    }
    if (_selectedDraft != null) {
      return PurchaseDraftReviewScreen(
        key: ValueKey('draft-${_selectedDraft!.id}'),
        draft: _selectedDraft!,
        embedded: true,
        onClosed: _onPanelClosed,
      );
    }
    return AddPurchaseScreen(
      key: ValueKey(
        _creatingNew ? 'purchase-new' : 'purchase-${_selectedPurchase!.id}',
      ),
      purchase: _creatingNew ? null : _selectedPurchase,
      embedded: true,
      onClosed: _onPanelClosed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final titleStyle = textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
    final width = MediaQuery.sizeOf(context).width;
    final isNarrow = width < 700;
    // Master/detail needs room for list + form (and optional pinned drawer).
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
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildPurchaseList(
                    usePanel: usePanel,
                    titleStyle: titleStyle,
                    muted: muted,
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
        title: const Text('Purchases'),
        leading: workspaceMenuLeading(context),
      ),
      body: usePanel && _panelOpen
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: listColumn),
                Expanded(flex: 7, child: _buildDetailPanel()),
              ],
            )
          : listColumn,
    );
  }
}
