import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'workspace_layout.dart';
import 'workspace_scaffold.dart';
import 'drawer_behavior.dart';
import 'job_detail_screen.dart';
import 'jobs_only_guard.dart';
import 'erp_quote_defaults.dart';
import 'exchange_rate.dart';
import 'pocketbase_service.dart';
import 'quote_calculations.dart';
import 'part_images_panel.dart';
import 'quote_job_line_picker.dart';
import 'quote_line_item_card.dart';
import 'quote_sidebar.dart';
import 'quote_totals_panel.dart';
import 'ui_breakpoints.dart';

/// DharmaCore-style quote workspace (`QuoteDetail.jsx`).
class QuoteDetailScreen extends StatefulWidget {
  final dynamic quote;

  const QuoteDetailScreen({super.key, this.quote});

  @override
  State<QuoteDetailScreen> createState() => _QuoteDetailScreenState();
}

class _QuoteDetailScreenState extends State<QuoteDetailScreen> with AutoOpenDrawerMixin {
  static const _statusOptions = [
    ('draft', 'Draft'),
    ('sent', 'Sent'),
    ('won', 'Won'),
    ('lost', 'Lost'),
  ];

  Map<String, dynamic>? _quote;
  List<Map<String, dynamic>> _lineItems = [];
  List<dynamic> _customers = [];
  List<dynamic> _suppliers = [];
  bool _loading = true;
  bool _saving = false;
  bool _settingsOpen = true;
  bool _fetchingRate = false;
  String? _saveError;
  String? _jobId;
  final _ratesEdited = {'setup': false, 'firstRun': false, 'production': false};

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  GlobalKey<ScaffoldState> get scaffoldKey => _scaffoldKey;

  bool get _isNew => _quote?['id'] == null;

  @override
  void initState() {
    super.initState();
    guardQuotesAccess(context);
    _settingsOpen = widget.quote == null;
    _load();
  }

  Map<String, dynamic> _recordToMap(dynamic record) {
    if (record == null) return {};
    final d = Map<String, dynamic>.from(record.data as Map<String, dynamic>? ?? {});
    if (record.id != null) d['id'] = record.id;
    return d;
  }

  Map<String, dynamic> _lineFromRecord(dynamic record) {
    final m = _recordToMap(record);
    if (m['material_vendor'] is Map) {
      m['material_vendor'] = m['material_vendor']['id'];
    }
    if (m['subcontractor_1'] is Map) {
      m['subcontractor_1'] = m['subcontractor_1']['id'];
    }
    if (m['subcontractor_2'] is Map) {
      m['subcontractor_2'] = m['subcontractor_2']['id'];
    }
    return m;
  }

  Map<String, dynamic> _defaultQuoteFromShop(Map<String, dynamic> shopFields) => {
        'job_number': generateJobNumber(),
        'engineer': '',
        'status': 'draft',
        ...shopFields,
      };

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pb = PocketBaseService();
      final customers = await pb.getCustomers();
      final suppliers = await pb.getSuppliers();

      Map<String, dynamic> quote;
      List<Map<String, dynamic>> lines;

      if (widget.quote != null) {
        final q = await pb.getQuote(widget.quote.id as String);
        quote = _recordToMap(q);
        final items = await pb.getQuoteLineItems(widget.quote.id as String);
        lines = items.map(_lineFromRecord).toList();
        final job = await pb.getJobByQuoteId(widget.quote.id as String);
        _jobId = job?.id as String?;
      } else {
        final shop = await pb.getShopSettings();
        final shopData = shop.data as Map<String, dynamic>? ?? {};
        quote = _defaultQuoteFromShop(newQuoteFieldsFromShopSettings(shopData));
        lines = [
          {
            'line_number': 1,
            'local_key': 'tmp_new_1',
            'part_quantity': 1,
          },
        ];
      }

      if (lines.isEmpty) {
        lines = [
          {
            'line_number': 1,
            'local_key': 'tmp_empty_1',
            'part_quantity': 1,
          },
        ];
      } else {
        for (var i = 0; i < lines.length; i++) {
          if (lines[i]['id'] == null && lines[i]['local_key'] == null) {
            lines[i] = {
              ...lines[i],
              'local_key': 'tmp_load_$i',
            };
          }
        }
      }

      if (mounted) {
        setState(() {
          _customers = customers;
          _suppliers = suppliers;
          _quote = quote;
          _lineItems = lines;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _quote ??= _defaultQuoteFromShop(newQuoteFieldsFromShopSettings(null));
          _lineItems = [
            {
              'line_number': 1,
              'local_key': _newLocalLineKey(),
              'part_quantity': 1,
            },
          ];
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Load error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _patchQuote(Map<String, dynamic> updates) {
    setState(() {
      _quote = {...?_quote, ...updates};
      // When FX changes, rewrite CAD from any USD amounts on line items.
      if (updates.containsKey('exchange_rate_usd_to_cad')) {
        _refreshCadFromUsd(updates['exchange_rate_usd_to_cad']);
      }
    });
  }

  String _newLocalLineKey() =>
      'tmp_${DateTime.now().microsecondsSinceEpoch}_${_lineItems.length}';

  void _renumberLineItems() {
    for (var i = 0; i < _lineItems.length; i++) {
      _lineItems[i] = {..._lineItems[i], 'line_number': i + 1};
    }
  }

  void _onReorderLineItems(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _lineItems.removeAt(oldIndex);
      _lineItems.insert(newIndex, item);
      _renumberLineItems();
    });
  }

  int _nextLineNumber() {
    return _lineItems
            .map((i) => (i['line_number'] is num)
                ? (i['line_number'] as num).toInt()
                : int.tryParse('${i['line_number']}') ?? 0)
            .fold<int>(0, (a, b) => a > b ? a : b) +
        1;
  }

  /// Recalculate material / shipping CAD from stored USD using [rateRaw].
  /// Leaves CAD alone when there is no USD (manual CAD-only entry).
  void _refreshCadFromUsd(dynamic rateRaw) {
    final rate = double.tryParse('$rateRaw') ?? 0;
    if (rate <= 0) return;
    _lineItems = _lineItems.map((item) {
      final next = Map<String, dynamic>.from(item);
      final usdMat = _num(item['usd_cost']);
      if (usdMat > 0) {
        next['material_cost_cad'] = quoteRound2(usdMat * rate);
      }
      final usdShip = _num(item['usd_shipping_cost']);
      if (usdShip > 0) {
        next['material_shipping_cost'] = quoteRound2(usdShip * rate);
      }
      return next;
    }).toList();
  }

  Future<void> _openLinkedJob() async {
    final id = _jobId;
    if (id == null || id.isEmpty) return;
    try {
      final job = await PocketBaseService().getJob(id);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (context) => JobDetailScreen(job: job)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open job: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _calculatedLines {
    final settings = getQuoteSettings(_quote);
    return _lineItems.map((i) => calculateLineItem(i, settings)).toList();
  }

  Map<String, dynamic> get _calculatedQuote {
    return calculateQuoteTotals(_quote ?? {}, _calculatedLines);
  }

  List<String> get _alloySuggestions {
    final fromLines = _lineItems
        .map((i) => '${i['alloy'] ?? ''}'.trim())
        .where((s) => s.isNotEmpty);
    return {...fromLines}.toList()..sort();
  }

  String? _relationId(dynamic v) {
    if (v == null || v.toString().isEmpty) return null;
    if (v is String) return v;
    if (v is Map && v['id'] != null) return v['id'].toString();
    return v.toString();
  }

  String? _quoteCreatedLabel() {
    final raw = _quote?['quote_created_date'] ?? _quote?['created'] ?? _quote?['updated'];
    if (raw == null || '$raw'.isEmpty) return null;
    try {
      return DateFormat.yMMMd().add_jm().format(DateTime.parse(raw.toString()));
    } catch (_) {
      return raw.toString();
    }
  }

  Future<void> _save() async {
    final quote = _quote;
    if (quote == null) return;

    final jobNum = '${quote['job_number'] ?? ''}'.trim();
    if (jobNum.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job number is required')),
      );
      return;
    }
    final customerId = _relationId(quote['customer']);
    if (customerId == null || customerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer is required')),
      );
      return;
    }

    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      final pb = PocketBaseService();
      final calcQ = _calculatedQuote;
      final toSave = Map<String, dynamic>.from(quote);
      toSave['customer'] = customerId;
      toSave['materials_total'] = calcQ['materials_total'];
      toSave['tooling_total'] = calcQ['tooling_total'];
      toSave['labor_total'] = calcQ['labor_total'];
      toSave['subcontractor_total'] = calcQ['subcontractor_total'];
      toSave['subtotal'] = calcQ['subtotal'];
      toSave['final_total_cad'] = calcQ['final_total_cad'];
      toSave['final_total_usd'] = calcQ['final_total_usd'];

      toSave.remove('id');
      toSave.remove('created');
      toSave.remove('updated');
      toSave.remove('expand');
      toSave.remove('collectionId');
      toSave.remove('collectionName');

      String quoteId;
      if (_isNew) {
        toSave['quote_created_date'] = DateTime.now().toIso8601String();
        if ('${toSave['engineer'] ?? ''}'.trim().isEmpty) {
          toSave['engineer'] = '—';
        }
        final created = await pb.createQuote(toSave);
        quoteId = created.id as String;
        setState(() => _quote = {...quote, 'id': quoteId});
      } else {
        quoteId = quote['id'] as String;
        toSave.remove('quote_created_date');
        await pb.updateQuote(quoteId, toSave);
      }

      final existing = await pb.getQuoteLineItems(quoteId);
      final currentIds = _lineItems
          .where((i) => i['id'] != null)
          .map((i) => i['id'] as String)
          .toSet();
      for (final old in existing) {
        if (!currentIds.contains(old.id)) {
          await pb.deleteQuoteLineItem(old.id);
        }
      }

      var calculated = _calculatedLines;
      for (var i = 0; i < calculated.length; i++) {
        final item = calculated[i];
        final payload = _linePayload(item, quoteId, i);
        if (item['id'] != null) {
          await pb.updateQuoteLineItemRaw(item['id'] as String, payload);
        } else {
          final created = await pb.createQuoteLineItemRaw(payload);
          _lineItems[i]['id'] = created.id;
        }
      }
      // Refresh so newly created line ids are available for job line links.
      calculated = _calculatedLines;

      var jobCreated = false;
      if ('${quote['status']}' == 'won' && _jobId == null) {
        // Pause saving spinner state for the picker dialog.
        if (!mounted) return;
        setState(() => _saving = false);
        final selected = await showQuoteJobLinePicker(
          context: context,
          quoteLines: calculated
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
        );
        if (selected == null) {
          // User cancelled job creation; quote lines were already saved.
          if (mounted) {
            final messenger = ScaffoldMessenger.of(context);
            Navigator.pop(context, true);
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Quote saved (job not created)'),
                backgroundColor: Colors.green,
              ),
            );
          }
          return;
        }
        if (mounted) setState(() => _saving = true);

        String? firstVendor;
        for (final s in selected) {
          if (s.materialVendorId != null) {
            firstVendor = s.materialVendorId;
            break;
          }
        }

        String? defaultShipToId;
        try {
          final ship = await pb.getDefaultCustomerShipTo(customerId);
          defaultShipToId = ship?.id as String?;
        } catch (_) {}

        final partsDesc = PocketBaseService.partsDescriptionFromJobLines([
          for (final s in selected)
            {'description': s.description, 'quantity': s.quantity},
        ]);

        final job = await pb.createJob({
          'quote': quoteId,
          'job_number': quote['job_number'],
          'customer': customerId,
          'customer_name': quote['customer_name'] ?? '',
          'parts_description': partsDesc,
          'status': 'planning',
          'po_number': quote['po_number'] ?? '',
          if (firstVendor != null) 'material_source_vendor': firstVendor,
          if (defaultShipToId != null) 'ship_to': defaultShipToId,
        });
        _jobId = job.id as String?;
        if (_jobId != null) {
          await pb.replaceJobLineItems(
            jobId: _jobId!,
            lines: [
              for (final s in selected)
                {
                  'description': s.description,
                  'quantity': s.quantity,
                  if (s.quoteLineItemId != null)
                    'quote_line_item': s.quoteLineItemId,
                },
            ],
          );
        }
        jobCreated = true;
      }

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context, true);
        messenger.showSnackBar(
          SnackBar(
            content: Text(jobCreated ? 'Quote saved — job created' : 'Quote saved'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _saving = false;
        _saveError = e.toString();
      });
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
    }
  }

  Map<String, dynamic> _linePayload(Map<String, dynamic> item, String quoteId, int index) {
    double? materialCostCad;
    final rawCad = item['material_cost_cad'];
    if (rawCad != null && rawCad != '') {
      final n = double.tryParse(rawCad.toString());
      if (n != null && !n.isNaN) materialCostCad = quoteRound2(n);
    }

    double materialShipping = 0;
    if (item['material_shipping_cost'] != null && item['material_shipping_cost'] != '') {
      materialShipping = _num(item['material_shipping_cost']);
    }

    double? qpp;
    if (item['quote_part_price_cad'] != null && item['quote_part_price_cad'] != '') {
      final n = double.tryParse(item['quote_part_price_cad'].toString());
      if (n != null && !n.isNaN) qpp = quoteRound2(n);
    }

    return {
      'quote': quoteId,
      'line_number': index + 1,
      'part_number': item['part_number'],
      'part_quantity': item['part_quantity'] ?? 1,
      'alloy': item['alloy'],
      'stock_size_per_part': item['stock_size_per_part'],
      'ordered_length': item['ordered_length'],
      'pieces': item['pieces'],
      'material_note': item['material_note'],
      if (_relationId(item['material_vendor']) != null)
        'material_vendor': _relationId(item['material_vendor']),
      'vendor_supplied': item['vendor_supplied'],
      'usd_cost': quoteRound2(_num(item['usd_cost'])) ?? 0,
      'usd_shipping_cost': quoteRound2(_num(item['usd_shipping_cost'])) ?? 0,
      'material_shipping_cost': quoteRound2(materialShipping) ?? 0,
      'testing_cost': quoteRound2(_num(item['testing_cost'])) ?? 0,
      'tooling_total_cost': quoteRound2(_num(item['tooling_total_cost'])) ?? 0,
      'tooling_description': item['tooling_description'],
      'programming_hours': _num(item['programming_hours']),
      'setup_hours': _num(item['setup_hours']),
      'first_run_hours': _num(item['first_run_hours']),
      'production_hours_total': _num(item['production_hours_total']),
      if ('${item['labor_note'] ?? ''}'.isNotEmpty) 'labor_note': item['labor_note'],
      if (_relationId(item['subcontractor_1']) != null)
        'subcontractor_1': _relationId(item['subcontractor_1']),
      'subcontractor_1_service': item['subcontractor_1_service'],
      'subcontractor_1_cost': quoteRound2(_num(item['subcontractor_1_cost'])) ?? 0,
      'subcontractor_1_shipping': quoteRound2(_num(item['subcontractor_1_shipping'])) ?? 0,
      if (_relationId(item['subcontractor_2']) != null)
        'subcontractor_2': _relationId(item['subcontractor_2']),
      'subcontractor_2_service': item['subcontractor_2_service'],
      'subcontractor_2_cost': quoteRound2(_num(item['subcontractor_2_cost'])) ?? 0,
      'subcontractor_2_shipping': quoteRound2(_num(item['subcontractor_2_shipping'])) ?? 0,
      'heat_treat_cost': quoteRound2(_num(item['heat_treat_cost'])) ?? 0,
      'inspection_cost': quoteRound2(_num(item['inspection_cost'])) ?? 0,
      'packaging_cost': quoteRound2(_num(item['packaging_cost'])) ?? 0,
      'shipping_cost': quoteRound2(_num(item['shipping_cost'])) ?? 0,
      'previous_quote_reference': item['previous_quote_reference'],
      'material_actual_cost_cad': quoteRound2(_num(item['material_actual_cost_cad'])) ?? 0,
      if (materialCostCad != null) 'material_cost_cad': materialCostCad,
      'material_with_markup': quoteRound2(_num(item['material_with_markup'])) ?? 0,
      'labor_cost': quoteRound2(_num(item['labor_cost'])) ?? 0,
      'subcontractor_1_total': quoteRound2(_num(item['subcontractor_1_total'])) ?? 0,
      'subcontractor_2_total': quoteRound2(_num(item['subcontractor_2_total'])) ?? 0,
      'line_total_cad': quoteRound2(_num(item['line_total_cad'])) ?? 0,
      'price_per_part_cad': quoteRound2(_num(item['price_per_part_cad'])) ?? 0,
      'price_per_part_usd': quoteRound2(_num(item['price_per_part_usd'])) ?? 0,
      if (qpp != null) 'quote_part_price_cad': qpp,
    };
  }

  double _num(dynamic v) {
    if (v == null || v == '') return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  Future<void> _copyQuote() async {
    if (_quote == null) return;
    setState(() => _saving = true);
    try {
      final pb = PocketBaseService();
      final copy = {
        'job_number': generateJobNumber(),
        'wave_quote_number': '',
        'customer': _relationId(_quote!['customer']),
        'customer_name': _quote!['customer_name'] ?? '',
        'po_number': _quote!['po_number'] ?? '',
        'engineer': _quote!['engineer'] ?? '',
        'status': 'draft',
        'shipping_markup_percent': _quote!['shipping_markup_percent'] ?? 30,
        'final_markup_percent': _quote!['final_markup_percent'] ?? 0,
        'subcontractor_markup_percent': _quote!['subcontractor_markup_percent'] ?? 0,
        'exchange_rate_usd_to_cad': _quote!['exchange_rate_usd_to_cad'] ?? 1.3,
        'hourly_rate_programming': _quote!['hourly_rate_programming'] ?? 350,
        'hourly_rate_setup': _quote!['hourly_rate_setup'] ?? 350,
        'hourly_rate_first_run': _quote!['hourly_rate_first_run'] ?? 350,
        'hourly_rate_production': _quote!['hourly_rate_production'] ?? 269,
      };
      final created = await pb.createQuote(copy);
      for (var i = 0; i < _lineItems.length; i++) {
        final item = _lineItems[i];
        final payload = _linePayload(item, created.id as String, i);
        payload.remove('material_cost_cad');
        await pb.createQuoteLineItemRaw(payload);
      }
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => QuoteDetailScreen(quote: created),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Copy failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _fetchRate() async {
    setState(() => _fetchingRate = true);
    try {
      final rate = await fetchUsdCadExchangeRate();
      if (rate != null) {
        _patchQuote({'exchange_rate_usd_to_cad': quoteRound2(rate)});
      }
    } finally {
      if (mounted) setState(() => _fetchingRate = false);
    }
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      );

  Widget _headerCard() {
    final q = _quote!;
    final customers = [..._customers]..sort((a, b) {
        final an = '${a.data['company'] ?? a.data['name'] ?? ''}'.toLowerCase();
        final bn = '${b.data['company'] ?? b.data['name'] ?? ''}'.toLowerCase();
        return an.compareTo(bn);
      });

    String customerLabel(dynamic c) {
      final d = c.data as Map<String, dynamic>? ?? {};
      return '${d['company'] ?? d['name'] ?? c.id}'.trim();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey('jn_${q['job_number']}'),
                    initialValue: '${q['job_number'] ?? ''}',
                    decoration: _dec('Job number'),
                    onChanged: (v) => _patchQuote({'job_number': v}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: '${q['wave_quote_number'] ?? ''}',
                    decoration: _dec('Quote #'),
                    onChanged: (v) => _patchQuote({'wave_quote_number': v}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: '${q['po_number'] ?? ''}',
                    decoration: _dec('PO number'),
                    onChanged: (v) => _patchQuote({'po_number': v}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _relationId(q['customer']) != null &&
                            customers.any((c) => c.id == _relationId(q['customer']))
                        ? _relationId(q['customer'])
                        : null,
                    decoration: _dec('Customer'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('— Select —')),
                      ...customers.map(
                        (c) => DropdownMenuItem(
                          value: c.id as String,
                          child: Text(customerLabel(c)),
                        ),
                      ),
                    ],
                    onChanged: (id) {
                      final c = customers.where((x) => x.id == id).firstOrNull;
                      _patchQuote({
                        'customer': id,
                        'customer_name': c != null ? customerLabel(c) : '',
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: '${q['engineer'] ?? ''}',
                    decoration: _dec('Engineer'),
                    onChanged: (v) => _patchQuote({'engineer': v}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ..._statusOptions.map((o) {
                        final selected = (q['status'] ?? 'draft') == o.$1;
                        return ChoiceChip(
                          label: Text(o.$2),
                          selected: selected,
                          onSelected: (_) => _patchQuote({'status': o.$1}),
                        );
                      }),
                      if ((q['status'] ?? 'draft') == 'won' && _jobId != null)
                        OutlinedButton(
                          onPressed: _openLinkedJob,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('View Job'),
                        ),
                    ],
                  ),
                ),
                Text(
                  'Quote created date: ${_quoteCreatedLabel() ?? '—'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _notesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Project notes', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: '${_quote?['notes'] ?? ''}',
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Notes about this project...',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => _patchQuote({'notes': v}),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Project images', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  PartImagesPanel(
                    recordId: _quote?['id'] as String?,
                    collectionName: 'quotes',
                    filenames: PartImagesPanel.normalizeFilenames(_quote?['part_images']),
                    fillHeight: true,
                    saveFirstHint: 'Save this quote first to upload images or PDFs.',
                    onFilenamesChanged: (list) => _patchQuote({'part_images': list}),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fieldStr(dynamic v) => v == null ? '' : v.toString();

  Widget _settingsCard() {
    final q = _quote!;
    final settingsTitleColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFD1D5DB)
        : const Color(0xFF374151);

    return QuoteSidebarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _settingsOpen = !_settingsOpen),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Settings',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: settingsTitleColor,
                    ),
                  ),
                ),
                Text(
                  _settingsOpen ? '▼' : '▶',
                  style: TextStyle(color: settingsTitleColor),
                ),
              ],
            ),
          ),
          if (_settingsOpen) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: QuoteSidebarField(
                    label: 'Material markup %',
                    value: _fieldStr(q['shipping_markup_percent']),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) => _patchQuote({
                      'shipping_markup_percent': double.tryParse(v) ?? 0,
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: QuoteSidebarField(
                    label: 'Subcontractor markup %',
                    value: _fieldStr(q['subcontractor_markup_percent']),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) => _patchQuote({
                      'subcontractor_markup_percent': double.tryParse(v) ?? 0,
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: QuoteSidebarField(
                    label: 'Final markup %',
                    value: _fieldStr(q['final_markup_percent']),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) =>
                        _patchQuote({'final_markup_percent': double.tryParse(v) ?? 0}),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(child: SizedBox()),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: QuoteSidebarField(
                    label: 'Exchange rate (USD→CAD)',
                    value: _fieldStr(q['exchange_rate_usd_to_cad']),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) => _patchQuote({
                      'exchange_rate_usd_to_cad': double.tryParse(v) ?? 1.3,
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 88,
                  child: QuoteSidebarSecondaryButton(
                    label: _fetchingRate ? '…' : 'Fetch',
                    onPressed: _fetchingRate ? null : _fetchRate,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: QuoteSidebarField(
                    label: 'Programming \$/hr',
                    value: _fieldStr(q['hourly_rate_programming']),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) {
                      final rate = double.tryParse(v) ?? 0;
                      final updates = <String, dynamic>{
                        'hourly_rate_programming': rate,
                      };
                      if (!_ratesEdited['setup']!) updates['hourly_rate_setup'] = rate;
                      if (!_ratesEdited['firstRun']!) {
                        updates['hourly_rate_first_run'] = rate;
                      }
                      if (!_ratesEdited['production']!) {
                        updates['hourly_rate_production'] = rate;
                      }
                      _patchQuote(updates);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: QuoteSidebarField(
                    label: 'Setup \$/hr',
                    value: _fieldStr(q['hourly_rate_setup']),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) {
                      _ratesEdited['setup'] = true;
                      _patchQuote({'hourly_rate_setup': double.tryParse(v) ?? 0});
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: QuoteSidebarField(
                    label: 'First run \$/hr',
                    value: _fieldStr(q['hourly_rate_first_run']),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) {
                      _ratesEdited['firstRun'] = true;
                      _patchQuote({'hourly_rate_first_run': double.tryParse(v) ?? 0});
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: QuoteSidebarField(
                    label: 'Production \$/hr',
                    value: _fieldStr(q['hourly_rate_production']),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) {
                      _ratesEdited['production'] = true;
                      _patchQuote({'hourly_rate_production': double.tryParse(v) ?? 0});
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isNew
        ? 'New quote'
        : '${_quote?['job_number'] ?? 'Quote'}';

    if (_loading || _quote == null) {
      return WorkspaceScaffold(
        scaffoldKey: _scaffoldKey,
        appBar: AppBar(
          title: Text(title),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          leading: workspaceMenuLeading(context),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final wide = MediaQuery.sizeOf(context).width >= kWorkspaceWideBreakpointPx;
    final calcLines = _calculatedLines;

    final mainColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _headerCard(),
        const SizedBox(height: 16),
        _notesCard(),
        const SizedBox(height: 16),
        Text('Line items', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _lineItems.length,
          onReorder: _onReorderLineItems,
          itemBuilder: (context, index) {
            final item = _lineItems[index];
            final keyId = item['id'] ?? item['local_key'] ?? 'line_$index';
            return QuoteLineItemCard(
              key: ValueKey('line_$keyId'),
              lineItem: item,
              quoteSettings: getQuoteSettings(_quote),
              calculated: calcLines[index],
              suppliers: _suppliers,
              alloySuggestions: _alloySuggestions,
              lineIndex: index,
              dragHandle: ReorderableDragStartListener(
                index: index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Tooltip(
                    message: 'Drag to reorder',
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4, top: 8),
                      child: Icon(
                        Icons.drag_handle,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
              onChanged: (next) {
                setState(() => _lineItems[index] = next);
              },
              onDelete: () {
                setState(() {
                  _lineItems.removeAt(index);
                  _renumberLineItems();
                });
              },
              onDuplicate: () {
                final source = Map<String, dynamic>.from(_lineItems[index]);
                source.remove('id');
                source['local_key'] = _newLocalLineKey();
                source['line_number'] = _nextLineNumber();
                setState(() {
                  _lineItems.insert(index + 1, source);
                  _renumberLineItems();
                });
              },
              onAddPart: () {
                setState(() {
                  _lineItems.add({
                    'line_number': _nextLineNumber(),
                    'local_key': _newLocalLineKey(),
                    'part_quantity': 1,
                  });
                  _renumberLineItems();
                });
              },
            );
          },
        ),
      ],
    );

    final sidebar = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QuoteTotalsPanel(quote: _calculatedQuote),
        if (_jobId != null) ...[
          const SizedBox(height: 16),
          QuoteSidebarCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Actual time / machining notes',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: '${_quote?['actual_time_notes'] ?? ''}',
                  maxLines: 3,
                  decoration: QuoteSidebarTheme.fieldDecoration(context),
                  onChanged: (v) => _patchQuote({'actual_time_notes': v}),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        _settingsCard(),
        if (_saveError != null) ...[
          const SizedBox(height: 12),
          Text(_saveError!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: QuoteSidebarPrimaryButton(
                label: _saving ? 'Saving…' : 'Save',
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: QuoteSidebarSecondaryButton(
                label: 'Copy',
                onPressed: _saving || _isNew ? null : _copyQuote,
              ),
            ),
          ],
        ),
      ],
    );

    return WorkspaceScaffold(
      scaffoldKey: _scaffoldKey,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: workspaceMenuLeading(context),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: mainColumn),
                  const SizedBox(width: 16),
                  SizedBox(width: 500, child: sidebar),
                ],
              )
            : Column(
                children: [
                  mainColumn,
                  const SizedBox(height: 24),
                  sidebar,
                ],
              ),
      ),
    );
  }
}
