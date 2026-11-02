import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'drawer_behavior.dart';
import 'workspace_layout.dart';
import 'workspace_scaffold.dart';
import 'jobs_only_guard.dart';
import 'pocketbase_service.dart';
import 'quote_calculations.dart';
import 'quote_detail_screen.dart';
import 'list_toolbar_widgets.dart';
import 'quote_sidebar.dart';
import 'job_detail_screen.dart';

/// All quotes list (DharmaCore `QuotesList.jsx` layout).
class QuotesScreen extends StatefulWidget {
  const QuotesScreen({super.key});

  @override
  State<QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends State<QuotesScreen> with AutoOpenDrawerMixin {
  List<dynamic> _quotes = [];
  List<dynamic> _lineItemsForSearch = [];
  bool _isLoading = true;
  String _search = '';
  String _searchDebounced = '';
  String _statusFilter = '';
  String _sortKey = 'job_number';
  String _sortDir = 'desc';
  bool _showTotals = true;
  String? _copyingId;
  Timer? _searchDebounce;

  final _searchController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static final _currencyFormat = NumberFormat.currency(
    locale: 'en_CA',
    symbol: '\$',
    decimalDigits: 0,
  );

  @override
  GlobalKey<ScaffoldState> get scaffoldKey => _scaffoldKey;

  @override
  void initState() {
    super.initState();
    guardQuotesAccess(context);
    _loadData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final pb = PocketBaseService();
      final results = await Future.wait([
        pb.getQuotes(),
        pb.getAllQuoteLineItemsForSearch(),
      ]);
      if (mounted) {
        setState(() {
          _quotes = results[0];
          _lineItemsForSearch = results[1];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading quotes: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _onSearchChanged(String value) {
    setState(() => _search = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchDebounced = _search);
    });
  }

  String _str(dynamic v) => v == null ? '' : v.toString().trim();

  String _customerDisplay(dynamic quote) {
    final data = quote.data as Map<String, dynamic>? ?? {};
    final expand = quote.expand;
    if (expand != null && expand['customer'] != null) {
      final customer = expand['customer'];
      Map<String, dynamic>? cData;
      if (customer is List && customer.isNotEmpty) {
        cData = customer.first.data as Map<String, dynamic>?;
      } else if (customer.data != null) {
        cData = customer.data as Map<String, dynamic>?;
      }
      if (cData != null) {
        final company = _str(cData['company']);
        if (company.isNotEmpty) return company;
        final name = _str(cData['name']);
        if (name.isNotEmpty) return name;
      }
    }
    final snap = _str(data['customer_name']);
    if (snap.isNotEmpty) return snap;
    return '—';
  }

  DateTime? _quoteCreatedDate(Map<String, dynamic> data, dynamic record) {
    final raw = data['quote_created_date'] ?? record.created ?? record.updated;
    if (raw == null) return null;
    try {
      return DateTime.parse(raw.toString());
    } catch (_) {
      return null;
    }
  }

  int _jobNumberToSortKey(String? jobNumber) {
    final s = (jobNumber ?? '').replaceAll(RegExp(r'\D'), '');
    final eight = s.length >= 8 ? s.substring(0, 8) : s;
    if (eight.length != 8) return 0;
    final mm = int.tryParse(eight.substring(0, 2)) ?? 0;
    final dd = int.tryParse(eight.substring(2, 4)) ?? 0;
    final yyyy = int.tryParse(eight.substring(4, 8)) ?? 0;
    return DateTime(yyyy, mm, dd).millisecondsSinceEpoch;
  }

  Map<String, List<dynamic>> get _lineItemsByQuote {
    final m = <String, List<dynamic>>{};
    for (final li in _lineItemsForSearch) {
      final qid = _str(li.data['quote']);
      if (qid.isEmpty) continue;
      m.putIfAbsent(qid, () => []).add(li);
    }
    return m;
  }

  List<dynamic> get _filteredQuotes {
    final searchLower = _searchDebounced.trim().toLowerCase();
    final byQuote = _lineItemsByQuote;

    var list = _quotes.where((q) {
      final data = q.data as Map<String, dynamic>? ?? {};
      if (_statusFilter.isNotEmpty && _str(data['status']) != _statusFilter) {
        return false;
      }
      if (searchLower.isEmpty) return true;
      final fields = [
        data['job_number'],
        data['wave_quote_number'],
        data['customer_name'],
        _customerDisplay(q),
      ];
      if (fields.any((v) => _str(v).toLowerCase().contains(searchLower))) {
        return true;
      }
      final items = byQuote[q.id] ?? [];
      return items.any(
        (li) => _str(li.data['part_number']).toLowerCase().contains(searchLower),
      );
    }).toList();

    final mult = _sortDir == 'asc' ? 1 : -1;
    list.sort((a, b) {
      final ad = a.data as Map<String, dynamic>? ?? {};
      final bd = b.data as Map<String, dynamic>? ?? {};
      if (_sortKey == 'job_number') {
        final ta = _jobNumberToSortKey(ad['job_number']?.toString());
        final tb = _jobNumberToSortKey(bd['job_number']?.toString());
        final cmp = _sortDir == 'desc' ? tb.compareTo(ta) : ta.compareTo(tb);
        if (cmp != 0) return cmp;
        return _sortDir == 'desc'
            ? _str(bd['job_number']).compareTo(_str(ad['job_number']))
            : _str(ad['job_number']).compareTo(_str(bd['job_number']));
      }
      if (_sortKey == 'customer') {
        return mult * _customerDisplay(a).compareTo(_customerDisplay(b));
      }
      if (_sortKey == 'total') {
        final na = (ad['final_total_cad'] as num?)?.toDouble() ?? 0;
        final nb = (bd['final_total_cad'] as num?)?.toDouble() ?? 0;
        return mult * na.compareTo(nb);
      }
      return 0;
    });
    return list;
  }

  double _quoteRevenue(Map<String, dynamic> data) {
    final total = (data['final_total_cad'] as num?)?.toDouble();
    final sub = (data['subtotal'] as num?)?.toDouble();
    if (total != null && total > 0) return total;
    if (sub != null && sub > 0) return sub;
    return 0;
  }

  String _formatCurrency(dynamic n) {
    if (n == null || n == '') return '—';
    final numVal = n is num ? n.toDouble() : double.tryParse(n.toString());
    if (numVal == null) return '—';
    return _currencyFormat.format(numVal);
  }

  Future<void> _deleteQuote(dynamic quote) async {
    final data = quote.data as Map<String, dynamic>? ?? {};
    final label = _str(data['job_number']).isEmpty ? 'this quote' : data['job_number'];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete quote?'),
        content: Text('Delete quote $label? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await PocketBaseService().deleteQuote(quote.id);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quote deleted'), backgroundColor: Colors.green),
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

  String? _relationId(dynamic v) {
    if (v == null || v.toString().isEmpty) return null;
    if (v is String) return v;
    if (v is Map && v['id'] != null) return v['id'].toString();
    return v.toString();
  }

  Future<void> _copyQuote(dynamic quote) async {
    setState(() => _copyingId = quote.id as String);
    try {
      final pb = PocketBaseService();
      final data = quote.data as Map<String, dynamic>? ?? {};
      final items = await pb.getQuoteLineItems(quote.id as String);

      String? customerId;
      final c = data['customer'];
      if (c is String) customerId = c;
      if (c is Map && c['id'] != null) customerId = c['id'].toString();

      final created = await pb.createQuote({
        'job_number': generateJobNumber(),
        'wave_quote_number': '',
        'customer': customerId,
        'customer_name': data['customer_name'] ?? '',
        'po_number': data['po_number'] ?? '',
        'engineer': data['engineer'] ?? '',
        'status': 'draft',
        'shipping_markup_percent': data['shipping_markup_percent'] ?? 30,
        'final_markup_percent': data['final_markup_percent'] ?? 0,
        'subcontractor_markup_percent': data['subcontractor_markup_percent'] ?? 0,
        'exchange_rate_usd_to_cad': data['exchange_rate_usd_to_cad'] ?? 1.3,
        'hourly_rate_programming': data['hourly_rate_programming'] ?? 350,
        'hourly_rate_setup': data['hourly_rate_setup'] ?? 350,
        'hourly_rate_first_run': data['hourly_rate_first_run'] ?? 350,
        'hourly_rate_production': data['hourly_rate_production'] ?? 269,
      });

      for (var i = 0; i < items.length; i++) {
        final d = items[i].data as Map<String, dynamic>? ?? {};
        await pb.createQuoteLineItemRaw({
          'quote': created.id,
          'line_number': d['line_number'] ?? i + 1,
          'part_number': d['part_number'],
          'part_quantity': d['part_quantity'] ?? 1,
          'alloy': d['alloy'],
          'stock_size_per_part': d['stock_size_per_part'],
          'ordered_length': d['ordered_length'],
          'pieces': d['pieces'],
          'material_note': d['material_note'],
          if (_relationId(d['material']) != null)
            'material': _relationId(d['material']),
          if (_relationId(d['material_vendor']) != null)
            'material_vendor': _relationId(d['material_vendor']),
          'material_source': () {
            final src = '${d['material_source'] ?? ''}'.trim();
            if (src.isNotEmpty) return src;
            return '${d['vendor_supplied'] ?? ''}'.toLowerCase() == 'yes'
                ? 'customer_supplied'
                : 'buy';
          }(),
          'vendor_supplied': d['vendor_supplied'],
          'usd_cost': d['usd_cost'] ?? 0,
          'usd_shipping_cost': d['usd_shipping_cost'] ?? 0,
          'material_shipping_cost': d['material_shipping_cost'] ?? 0,
          'testing_cost': d['testing_cost'] ?? 0,
          'tooling_total_cost': d['tooling_total_cost'] ?? 0,
          'tooling_description': d['tooling_description'],
          'programming_hours': d['programming_hours'] ?? 0,
          'setup_hours': d['setup_hours'] ?? 0,
          'first_run_hours': d['first_run_hours'] ?? 0,
          'production_hours_total': d['production_hours_total'] ?? 0,
          'labor_note': d['labor_note'],
          if (_relationId(d['subcontractor_1']) != null)
            'subcontractor_1': _relationId(d['subcontractor_1']),
          'subcontractor_1_service': d['subcontractor_1_service'],
          'subcontractor_1_cost': d['subcontractor_1_cost'] ?? 0,
          'subcontractor_1_shipping': d['subcontractor_1_shipping'] ?? 0,
          if (_relationId(d['subcontractor_2']) != null)
            'subcontractor_2': _relationId(d['subcontractor_2']),
          'subcontractor_2_service': d['subcontractor_2_service'],
          'subcontractor_2_cost': d['subcontractor_2_cost'] ?? 0,
          'subcontractor_2_shipping': d['subcontractor_2_shipping'] ?? 0,
          'heat_treat_cost': d['heat_treat_cost'] ?? 0,
          'inspection_cost': d['inspection_cost'] ?? 0,
          'packaging_cost': d['packaging_cost'] ?? 0,
          'shipping_cost': d['shipping_cost'] ?? 0,
          'previous_quote_reference': d['previous_quote_reference'],
          if (d['quote_part_price_cad'] != null) 'quote_part_price_cad': d['quote_part_price_cad'],
        });
      }

      if (mounted) {
        await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (context) => QuoteDetailScreen(quote: created)),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Copy failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _copyingId = null);
    }
  }

  Future<void> _viewJob(String quoteId) async {
    final job = await PocketBaseService().getJobByQuoteId(quoteId);
    if (!mounted) return;
    if (job == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No job found for this quote')),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => JobDetailScreen(job: job)),
    );
  }

  Future<void> _openQuote(dynamic quote) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => QuoteDetailScreen(quote: quote)),
    );
    if (changed == true) _loadData();
  }

  Future<void> _newQuote() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const QuoteDetailScreen()),
    );
    if (changed == true) _loadData();
  }

  Widget _statCard(String label, String value) {
    final muted = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFD1D5DB)
        : const Color(0xFF4B5563);
    return QuoteSidebarCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: muted)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _statsRow(int quotesThisMonth, int wonCount, int pendingCount, String revenue) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 700) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _statCard('Quotes this month', '$quotesThisMonth')),
                const SizedBox(width: 12),
                Expanded(child: _statCard('Won', '$wonCount')),
                const SizedBox(width: 12),
                Expanded(child: _statCard('Pending', '$pendingCount')),
                const SizedBox(width: 12),
                Expanded(child: _statCard('Revenue this month', revenue)),
              ],
            ),
          );
        }
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: _statCard('Quotes this month', '$quotesThisMonth')),
                const SizedBox(width: 12),
                Expanded(child: _statCard('Won', '$wonCount')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _statCard('Pending', '$pendingCount')),
                const SizedBox(width: 12),
                Expanded(child: _statCard('Revenue this month', revenue)),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _statusFilterDropdown() {
    return SizedBox(
      width: 160,
      child: DropdownButtonFormField<String>(
        value: _statusFilter.isEmpty ? '' : _statusFilter,
        decoration: QuoteSidebarTheme.fieldDecoration(context).copyWith(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        items: const [
          DropdownMenuItem(value: '', child: Text('All statuses')),
          DropdownMenuItem(value: 'draft', child: Text('Draft')),
          DropdownMenuItem(value: 'sent', child: Text('Sent')),
          DropdownMenuItem(value: 'won', child: Text('Won')),
          DropdownMenuItem(value: 'lost', child: Text('Lost')),
        ],
        onChanged: (v) => setState(() => _statusFilter = v ?? ''),
      ),
    );
  }

  TextStyle _tableHeaderStyle(BuildContext context) {
    final muted = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF9CA3AF)
        : const Color(0xFF4B5563);
    return TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: muted);
  }

  Color _tableBorderColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF374151)
        : const Color(0xFFE5E7EB);
  }

  Color _tableHoverColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF374151).withValues(alpha: 0.5)
        : const Color(0xFFF9FAFB);
  }

  Widget _tableHeaderRow(BuildContext context) {
    final border = _tableBorderColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('Job #', style: _tableHeaderStyle(context))),
          Expanded(flex: 4, child: Text('Customer', style: _tableHeaderStyle(context))),
          Expanded(flex: 2, child: Text('Status', style: _tableHeaderStyle(context))),
          Expanded(
            flex: 2,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Total (CAD)', style: _tableHeaderStyle(context)),
                IconButton(
                  icon: Icon(
                    _showTotals ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 18,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => setState(() => _showTotals = !_showTotals),
                  tooltip: _showTotals ? 'Hide totals' : 'Show totals',
                ),
              ],
            ),
          ),
          Expanded(flex: 5, child: Text('Actions', style: _tableHeaderStyle(context))),
        ],
      ),
    );
  }

  Widget _tableDataRow(BuildContext context, dynamic q) {
    final data = q.data as Map<String, dynamic>? ?? {};
    final status = _str(data['status']);
    final job = _str(data['job_number']);
    final copying = _copyingId == q.id;
    final border = _tableBorderColor(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        hoverColor: _tableHoverColor(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: border.withValues(alpha: 0.6))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: () => _openQuote(q),
                  child: Text(
                    job.isEmpty ? '—' : job,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: QuoteSidebarTheme.primary(context),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: Text(
                  _customerDisplay(q),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IntrinsicWidth(
                    child: _statusBadge(status),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  _showTotals ? _formatCurrency(data['final_total_cad']) : '—',
                  style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
              Expanded(
                flex: 5,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      QuoteTableActionButton(
                        label: 'View',
                        onPressed: () => _openQuote(q),
                      ),
                      const SizedBox(width: 6),
                      QuoteTableActionButton(
                        label: copying ? '…' : 'Copy',
                        onPressed: copying ? null : () => _copyQuote(q),
                      ),
                      if (status == 'won') ...[
                        const SizedBox(width: 6),
                        QuoteTableActionButton(
                          label: 'View Job',
                          onPressed: () => _viewJob(q.id as String),
                        ),
                      ],
                      const SizedBox(width: 6),
                      QuoteTableActionButton(
                        label: 'Delete',
                        danger: true,
                        onPressed: () => _deleteQuote(q),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quotesTable(BuildContext context, List<dynamic> filtered) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tableHeaderRow(context),
        ...filtered.map((q) => _tableDataRow(context, q)),
      ],
    );
  }

  Widget _statusBadge(String status) {
    final s = status.isEmpty ? 'draft' : status.toLowerCase();
    Color bg;
    Color fg;
    switch (s) {
      case 'sent':
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF1E40AF);
        break;
      case 'won':
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF065F46);
        break;
      case 'lost':
        bg = const Color(0xFFE5E7EB);
        fg = const Color(0xFF4B5563);
        break;
      default:
        bg = const Color(0xFFE5E7EB);
        fg = const Color(0xFF1F2937);
    }
    if (Theme.of(context).brightness == Brightness.dark) {
      switch (s) {
        case 'sent':
          bg = const Color(0xFF2563EB);
          fg = Colors.white;
          break;
        case 'won':
          bg = const Color(0xFF059669);
          fg = Colors.white;
          break;
        default:
          bg = const Color(0xFF4B5563);
          fg = Colors.white;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        s,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: fg),
      ),
    );
  }

  Widget _sortLink(String label, String key, {String? defaultDir}) {
    final active = _sortKey == key;
  final color = active
        ? (Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : const Color(0xFF111827))
        : (Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF9CA3AF)
            : const Color(0xFF4B5563));
    return InkWell(
      onTap: () {
        setState(() {
          if (_sortKey == key) {
            _sortDir = _sortDir == 'asc' ? 'desc' : 'asc';
          } else {
            _sortKey = key;
            _sortDir = defaultDir ?? 'asc';
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    int quotesThisMonth = 0;
    int wonCount = 0;
    int pendingCount = 0;
    double revenueThisMonth = 0;

    for (final q in _quotes) {
      final data = q.data as Map<String, dynamic>? ?? {};
      final status = _str(data['status']);
      final created = _quoteCreatedDate(data, q);
      if (status == 'won') wonCount++;
      if (status == 'sent') pendingCount++;
      if (created != null &&
          !created.isBefore(monthStart) &&
          !created.isAfter(monthEnd)) {
        quotesThisMonth++;
        if (status == 'won') revenueThisMonth += _quoteRevenue(data);
      }
    }

    final filtered = _filteredQuotes;
    final titleColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF111827);

    final revenueLabel =
        _showTotals ? _formatCurrency(revenueThisMonth) : '—';

    final bodyWidget = RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: workspaceContentFrame(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Spacer(),
                    Flexible(
                      flex: 3,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: InventoryListSearchField(
                          controller: _searchController,
                          hintText: 'Search…',
                          onChanged: _onSearchChanged,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    InventoryListActionButton(
                      label: 'New Quote',
                      onPressed: _newQuote,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _statsRow(
                  quotesThisMonth,
                  wonCount,
                  pendingCount,
                  revenueLabel,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _statusFilterDropdown(),
                    Container(
                      width: 1,
                      height: 28,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: _tableBorderColor(context),
                    ),
                    _sortLink('Job #', 'job_number', defaultDir: 'desc'),
                    _sortLink('Customer', 'customer', defaultDir: 'asc'),
                    Text(
                      'Order',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                    InkWell(
                      onTap: () => setState(() => _sortDir = 'asc'),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          'A→Z',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color:
                                _sortDir == 'asc' ? titleColor : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => setState(() => _sortDir = 'desc'),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          'Z→A',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _sortDir == 'desc'
                                ? titleColor
                                : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                QuoteSidebarCard(
                  padding: EdgeInsets.zero,
                  child: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : filtered.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(32),
                              child: Center(
                                child: Text(
                                  _quotes.isEmpty
                                      ? 'No quotes yet. Create one to get started.'
                                      : 'No quotes match your search or filter.',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              ),
                            )
                          : _quotesTable(context, filtered),
                ),
              ],
            ),
        ),
      ),
    );

    return WorkspaceScaffold(
      scaffoldKey: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Quotes'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: workspaceMenuLeading(context),
      ),
      body: bodyWidget,
    );
  }
}
