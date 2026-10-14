import 'package:flutter/material.dart';
import 'quote_calculations.dart';

class _QuoteSection extends StatefulWidget {
  final String title;
  final bool initiallyOpen;
  final Widget child;

  const _QuoteSection({
    required this.title,
    this.initiallyOpen = false,
    required this.child,
  });

  @override
  State<_QuoteSection> createState() => _QuoteSectionState();
}

class _QuoteSectionState extends State<_QuoteSection> {
  late bool _open;

  @override
  void initState() {
    super.initState();
    _open = widget.initiallyOpen;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(_open ? '▼' : '▶', style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          ),
        ),
        if (_open) Padding(padding: const EdgeInsets.only(bottom: 12), child: widget.child),
        const Divider(height: 1),
      ],
    );
  }
}

/// One quote part / line item (DharmaCore `LineItemCard.jsx`).
class QuoteLineItemCard extends StatefulWidget {
  final Map<String, dynamic> lineItem;
  final Map<String, dynamic> quoteSettings;
  final Map<String, dynamic>? calculated;
  final List<dynamic> suppliers;
  final List<String> alloySuggestions;
  final int lineIndex;
  final Widget? dragHandle;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onDelete;
  final VoidCallback? onDuplicate;
  final VoidCallback? onAddPart;

  const QuoteLineItemCard({
    super.key,
    required this.lineItem,
    required this.quoteSettings,
    required this.calculated,
    required this.suppliers,
    required this.alloySuggestions,
    required this.lineIndex,
    required this.onChanged,
    required this.onDelete,
    this.dragHandle,
    this.onDuplicate,
    this.onAddPart,
  });

  @override
  State<QuoteLineItemCard> createState() => _QuoteLineItemCardState();
}

class _QuoteLineItemCardState extends State<QuoteLineItemCard> {
  bool _detailsOpen = false;

  late final TextEditingController _partNumber;
  late final TextEditingController _partQty;
  late final TextEditingController _qpp;
  late final TextEditingController _usdCost;
  late final TextEditingController _materialCad;
  late final TextEditingController _shippingCad;
  late final TextEditingController _shippingUsd;
  late final TextEditingController _testingCost;
  late final TextEditingController _alloy;
  late final TextEditingController _stockSize;
  late final TextEditingController _pieces;
  late final TextEditingController _orderedLength;
  late final TextEditingController _materialNote;
  late final TextEditingController _toolingCost;
  late final TextEditingController _toolingDesc;
  late final TextEditingController _programmingHrs;
  late final TextEditingController _setupHrs;
  late final TextEditingController _firstRunHrs;
  late final TextEditingController _productionHrs;
  late final TextEditingController _laborNote;
  late final TextEditingController _sub1Service;
  late final TextEditingController _sub1Cost;
  late final TextEditingController _sub1Shipping;
  late final TextEditingController _sub2Service;
  late final TextEditingController _sub2Cost;
  late final TextEditingController _sub2Shipping;
  late final TextEditingController _inspection;
  late final TextEditingController _packaging;
  late final TextEditingController _postShipping;
  late final TextEditingController _prevQuoteRef;

  late final FocusNode _usdCostFocus;
  late final FocusNode _shippingUsdFocus;
  late final FocusNode _materialCadFocus;
  late final FocusNode _shippingCadFocus;

  @override
  void initState() {
    super.initState();
    final item = widget.lineItem;
    _partNumber = TextEditingController(text: _str(item['part_number']));
    _partQty = TextEditingController(text: _numText(item['part_quantity']));
    _qpp = TextEditingController(text: _qppInitialText());
    _usdCost = TextEditingController(text: _numText(item['usd_cost']));
    _materialCad = TextEditingController(text: _materialCadInitialText());
    _shippingCad =
        TextEditingController(text: _numText(item['material_shipping_cost']));
    _shippingUsd =
        TextEditingController(text: _numText(item['usd_shipping_cost']));
    _testingCost = TextEditingController(text: _numText(item['testing_cost']));
    _alloy = TextEditingController(text: _str(item['alloy']));
    _stockSize = TextEditingController(text: _str(item['stock_size_per_part']));
    _pieces = TextEditingController(text: _numText(item['pieces']));
    _orderedLength = TextEditingController(text: _str(item['ordered_length']));
    _materialNote = TextEditingController(text: _str(item['material_note']));
    _toolingCost =
        TextEditingController(text: _numText(item['tooling_total_cost']));
    _toolingDesc =
        TextEditingController(text: _str(item['tooling_description']));
    _programmingHrs =
        TextEditingController(text: _numText(item['programming_hours']));
    _setupHrs = TextEditingController(text: _numText(item['setup_hours']));
    _firstRunHrs =
        TextEditingController(text: _numText(item['first_run_hours']));
    _productionHrs =
        TextEditingController(text: _numText(item['production_hours_total']));
    _laborNote = TextEditingController(text: _str(item['labor_note']));
    _sub1Service =
        TextEditingController(text: _str(item['subcontractor_1_service']));
    _sub1Cost =
        TextEditingController(text: _numText(item['subcontractor_1_cost']));
    _sub1Shipping =
        TextEditingController(text: _numText(item['subcontractor_1_shipping']));
    _sub2Service =
        TextEditingController(text: _str(item['subcontractor_2_service']));
    _sub2Cost =
        TextEditingController(text: _numText(item['subcontractor_2_cost']));
    _sub2Shipping =
        TextEditingController(text: _numText(item['subcontractor_2_shipping']));
    _inspection =
        TextEditingController(text: _numText(item['inspection_cost']));
    _packaging = TextEditingController(text: _numText(item['packaging_cost']));
    _postShipping =
        TextEditingController(text: _numText(item['shipping_cost']));
    _prevQuoteRef =
        TextEditingController(text: _str(item['previous_quote_reference']));

    _usdCostFocus = FocusNode();
    _shippingUsdFocus = FocusNode();
    _materialCadFocus = FocusNode();
    _shippingCadFocus = FocusNode();
  }

  @override
  void didUpdateWidget(covariant QuoteLineItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync controllers from parent only when not focused (avoids reverse-typing).
    final item = widget.lineItem;
    _syncIfIdle(_partNumber, _str(item['part_number']));
    _syncIfIdle(_partQty, _numText(item['part_quantity']));
    if (!_usdCostFocus.hasFocus) {
      _syncIfIdle(_usdCost, _numText(item['usd_cost']));
    }
    if (!_materialCadFocus.hasFocus) {
      _syncIfIdle(_materialCad, _materialCadInitialText());
    }
    if (!_shippingCadFocus.hasFocus) {
      _syncIfIdle(_shippingCad, _numText(item['material_shipping_cost']));
    }
    if (!_shippingUsdFocus.hasFocus) {
      _syncIfIdle(_shippingUsd, _numText(item['usd_shipping_cost']));
    }
    _syncIfIdle(_testingCost, _numText(item['testing_cost']));
    _syncIfIdle(_alloy, _str(item['alloy']));
    _syncIfIdle(_stockSize, _str(item['stock_size_per_part']));
    _syncIfIdle(_pieces, _numText(item['pieces']));
    _syncIfIdle(_orderedLength, _str(item['ordered_length']));
    _syncIfIdle(_materialNote, _str(item['material_note']));
    _syncIfIdle(_toolingCost, _numText(item['tooling_total_cost']));
    _syncIfIdle(_toolingDesc, _str(item['tooling_description']));
    _syncIfIdle(_programmingHrs, _numText(item['programming_hours']));
    _syncIfIdle(_setupHrs, _numText(item['setup_hours']));
    _syncIfIdle(_firstRunHrs, _numText(item['first_run_hours']));
    _syncIfIdle(_productionHrs, _numText(item['production_hours_total']));
    _syncIfIdle(_laborNote, _str(item['labor_note']));
    _syncIfIdle(_sub1Service, _str(item['subcontractor_1_service']));
    _syncIfIdle(_sub1Cost, _numText(item['subcontractor_1_cost']));
    _syncIfIdle(_sub1Shipping, _numText(item['subcontractor_1_shipping']));
    _syncIfIdle(_sub2Service, _str(item['subcontractor_2_service']));
    _syncIfIdle(_sub2Cost, _numText(item['subcontractor_2_cost']));
    _syncIfIdle(_sub2Shipping, _numText(item['subcontractor_2_shipping']));
    _syncIfIdle(_inspection, _numText(item['inspection_cost']));
    _syncIfIdle(_packaging, _numText(item['packaging_cost']));
    _syncIfIdle(_postShipping, _numText(item['shipping_cost']));
    _syncIfIdle(_prevQuoteRef, _str(item['previous_quote_reference']));
  }

  void _syncIfIdle(TextEditingController c, String next) {
    if (c.text == next) return;
    c.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  @override
  void dispose() {
    _partNumber.dispose();
    _partQty.dispose();
    _qpp.dispose();
    _usdCost.dispose();
    _materialCad.dispose();
    _shippingCad.dispose();
    _shippingUsd.dispose();
    _testingCost.dispose();
    _alloy.dispose();
    _stockSize.dispose();
    _pieces.dispose();
    _orderedLength.dispose();
    _materialNote.dispose();
    _toolingCost.dispose();
    _toolingDesc.dispose();
    _programmingHrs.dispose();
    _setupHrs.dispose();
    _firstRunHrs.dispose();
    _productionHrs.dispose();
    _laborNote.dispose();
    _sub1Service.dispose();
    _sub1Cost.dispose();
    _sub1Shipping.dispose();
    _sub2Service.dispose();
    _sub2Cost.dispose();
    _sub2Shipping.dispose();
    _inspection.dispose();
    _packaging.dispose();
    _postShipping.dispose();
    _prevQuoteRef.dispose();
    _usdCostFocus.dispose();
    _shippingUsdFocus.dispose();
    _materialCadFocus.dispose();
    _shippingCadFocus.dispose();
    super.dispose();
  }

  void _patch(Map<String, dynamic> updates) {
    widget.onChanged({...widget.lineItem, ...updates});
  }

  String _str(dynamic v) => v == null ? '' : v.toString();

  String _numText(dynamic v) {
    if (v == null || v == '') return '';
    if (v is num) {
      if (v == 0) return ''; // treat zero as empty for display (copied defaults)
      final d = v.toDouble();
      if (d == d.roundToDouble()) return '${d.toInt()}';
      return '$d';
    }
    final s = v.toString().trim();
    if (s.isEmpty || s == '0' || s == '0.0') return '';
    return s;
  }

  String _qppInitialText() {
    final item = widget.lineItem;
    if (item['quote_part_price_cad'] != null && item['quote_part_price_cad'] != '') {
      final r = quoteRound2(_num(item['quote_part_price_cad']));
      return r == null ? '' : '$r';
    }
    final calc = widget.calculated?['quoted_price_per_part_cad'];
    if (calc != null) return '$calc';
    return '';
  }

  String _materialCadInitialText() {
    final item = widget.lineItem;
    final calc = widget.calculated;
    final usdSet = item['usd_cost'] != null &&
        item['usd_cost'] != '' &&
        item['usd_cost'] != 0;
    final cadEmpty = item['material_cost_cad'] == null ||
        item['material_cost_cad'] == '' ||
        item['material_cost_cad'] == 0;
    if (usdSet && cadEmpty && calc?['material_actual_cost_cad'] != null) {
      return '${calc!['material_actual_cost_cad']}';
    }
    return _numText(item['material_cost_cad']);
  }

  double? _dollarFromInput(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final n = double.tryParse(raw.trim());
    if (n == null || n.isNaN) return null;
    return quoteRound2(n);
  }

  double get _exchangeRate =>
      double.tryParse(
          '${widget.quoteSettings['exchange_rate_usd_to_cad'] ?? 1.3}') ??
      1.3;

  void _onUsdMaterialChanged(String v) {
    final usd = _dollarFromInput(v);
    final cad = usd != null && _exchangeRate > 0
        ? quoteRound2(usd * _exchangeRate)
        : null;
    if (cad != null && !_materialCadFocus.hasFocus) {
      _syncIfIdle(_materialCad, '$cad');
    } else if (usd == null && !_materialCadFocus.hasFocus) {
      // leave CAD as-is if user cleared USD mid-edit of CAD
    }
    _patch({
      'usd_cost': usd ?? '',
      if (cad != null) 'material_cost_cad': cad,
    });
  }

  void _onUsdShippingChanged(String v) {
    final usd = _dollarFromInput(v);
    final cad = usd != null && _exchangeRate > 0
        ? quoteRound2(usd * _exchangeRate)
        : null;
    if (cad != null && !_shippingCadFocus.hasFocus) {
      _syncIfIdle(_shippingCad, '$cad');
    }
    _patch({
      'usd_shipping_cost': usd ?? '',
      if (cad != null) 'material_shipping_cost': cad,
    });
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );

  @override
  Widget build(BuildContext context) {
    final item = widget.lineItem;
    final calc = widget.calculated;

    String supplierLabel(dynamic s) {
      final d = s.data as Map<String, dynamic>? ?? {};
      return '${d['company_name'] ?? d['name'] ?? s.id}'.trim();
    }

    Widget supplierDropdown(String field, String label) {
      final current = _relationId(item[field]);
      return DropdownButtonFormField<String>(
        // ignore: deprecated_member_use
        value: current != null && widget.suppliers.any((s) => s.id == current)
            ? current
            : null,
        decoration: _dec(label),
        items: [
          const DropdownMenuItem(value: null, child: Text('— Select —')),
          ...widget.suppliers.map(
            (s) => DropdownMenuItem(
              value: s.id as String,
              child: Text(supplierLabel(s)),
            ),
          ),
        ],
        onChanged: (id) => _patch({field: id}),
      );
    }

    final markup = calc?['material_with_markup'];
    final materialCadLabel = markup != null
        ? 'Actual cost (CAD) (Markup cost (CAD): \$${formatQuoteMoney(_num(markup))})'
        : 'Actual cost (CAD)';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.dragHandle != null) widget.dragHandle!,
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Part ${widget.lineIndex + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _partNumber,
                    decoration: _dec('Part number'),
                    onChanged: (v) => _patch({'part_number': v}),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: TextField(
                    controller: _partQty,
                    decoration: _dec('Qty'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      if (v.isEmpty) {
                        _patch({'part_quantity': null});
                        return;
                      }
                      final n = int.tryParse(v) ?? double.tryParse(v);
                      if (n != null && n >= 0) _patch({'part_quantity': n});
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _qpp,
                    decoration: _dec('QPP'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) {
                      if (v.trim().isEmpty) {
                        _patch({'quote_part_price_cad': null});
                        return;
                      }
                      final n = double.tryParse(v);
                      if (n != null && n >= 0) {
                        _patch({'quote_part_price_cad': quoteRound2(n)});
                      }
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(
                      _detailsOpen ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => setState(() => _detailsOpen = !_detailsOpen),
                  tooltip: _detailsOpen ? 'Hide details' : 'Show details',
                ),
              ],
            ),
            if (_detailsOpen) ...[
              const SizedBox(height: 8),
              _QuoteSection(
                title: 'Materials',
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _materialCad,
                            focusNode: _materialCadFocus,
                            decoration: _dec(materialCadLabel),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (v) {
                              if (v.trim().isEmpty) {
                                _patch({'material_cost_cad': null});
                              } else {
                                final n = double.tryParse(v);
                                if (n != null) {
                                  _patch({
                                    'material_cost_cad': quoteRound2(n),
                                  });
                                }
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _usdCost,
                            focusNode: _usdCostFocus,
                            decoration: _dec('Actual cost (USD)'),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: _onUsdMaterialChanged,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _shippingCad,
                            focusNode: _shippingCadFocus,
                            decoration: _dec('Shipping cost (CAD)'),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (v) => _patch({
                              'material_shipping_cost':
                                  _dollarFromInput(v) ?? '',
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _shippingUsd,
                            focusNode: _shippingUsdFocus,
                            decoration: _dec('Shipping cost (USD)'),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: _onUsdShippingChanged,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _testingCost,
                            decoration: _dec('Testing cost'),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (v) => _patch({
                              'testing_cost': _dollarFromInput(v) ?? '',
                            }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _alloy,
                      decoration: _dec('Alloy'),
                      onChanged: (v) => _patch({'alloy': v}),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _stockSize,
                            decoration: _dec('Stock size per part'),
                            onChanged: (v) =>
                                _patch({'stock_size_per_part': v}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _pieces,
                            decoration: _dec('Pieces'),
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              final n = int.tryParse(v);
                              _patch({'pieces': n});
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _orderedLength,
                      decoration: _dec('Ordered length'),
                      onChanged: (v) => _patch({'ordered_length': v}),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: supplierDropdown(
                              'material_vendor', 'Material supplier'),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Vendor supplied',
                                style: TextStyle(fontSize: 12)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                ChoiceChip(
                                  label: const Text('Yes'),
                                  selected: _str(item['vendor_supplied'])
                                          .toLowerCase() ==
                                      'yes',
                                  onSelected: (_) =>
                                      _patch({'vendor_supplied': 'yes'}),
                                ),
                                const SizedBox(width: 4),
                                ChoiceChip(
                                  label: const Text('No'),
                                  selected: _str(item['vendor_supplied'])
                                          .toLowerCase() ==
                                      'no',
                                  onSelected: (_) =>
                                      _patch({'vendor_supplied': 'no'}),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _materialNote,
                      decoration: _dec('Material note'),
                      onChanged: (v) => _patch({'material_note': v}),
                    ),
                  ],
                ),
              ),
              _QuoteSection(
                title: 'Tooling',
                child: Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _toolingCost,
                        decoration: _dec('Total cost'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (v) => _patch({
                          'tooling_total_cost': _dollarFromInput(v) ?? '',
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _toolingDesc,
                        decoration: _dec('Description'),
                        onChanged: (v) => _patch({'tooling_description': v}),
                      ),
                    ),
                  ],
                ),
              ),
              _QuoteSection(
                title: 'Labor',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _programmingHrs,
                            decoration: _dec('Programming (hrs)'),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (v) => _patch({
                              'programming_hours': v.isEmpty ? null : v,
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _setupHrs,
                            decoration: _dec('Setup (hrs)'),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (v) => _patch({
                              'setup_hours': v.isEmpty ? null : v,
                            }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _firstRunHrs,
                            decoration: _dec('First run (hrs)'),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (v) => _patch({
                              'first_run_hours': v.isEmpty ? null : v,
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _productionHrs,
                            decoration: _dec('Production total (hrs)'),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (v) => _patch({
                              'production_hours_total': v.isEmpty ? null : v,
                            }),
                          ),
                        ),
                      ],
                    ),
                    if (calc != null && calc['labor_cost'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '→ Labor total: \$${formatQuoteMoney(_num(calc['labor_cost']))}',
                          style:
                              TextStyle(color: Colors.grey[700], fontSize: 13),
                        ),
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _laborNote,
                      decoration: _dec('Note'),
                      maxLines: 2,
                      onChanged: (v) => _patch({'labor_note': v}),
                    ),
                  ],
                ),
              ),
              _QuoteSection(
                title: 'Subcontractors',
                child: Column(
                  children: [
                    supplierDropdown('subcontractor_1', 'Subcontractor 1'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _sub1Service,
                      decoration: _dec('Service'),
                      onChanged: (v) =>
                          _patch({'subcontractor_1_service': v}),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _sub1Cost,
                            decoration: _dec('Cost'),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (v) => _patch({
                              'subcontractor_1_cost':
                                  _dollarFromInput(v) ?? '',
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _sub1Shipping,
                            decoration: _dec('Shipping'),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (v) => _patch({
                              'subcontractor_1_shipping':
                                  _dollarFromInput(v) ?? '',
                            }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    supplierDropdown('subcontractor_2', 'Subcontractor 2'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _sub2Service,
                      decoration: _dec('Service'),
                      onChanged: (v) =>
                          _patch({'subcontractor_2_service': v}),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _sub2Cost,
                            decoration: _dec('Cost'),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (v) => _patch({
                              'subcontractor_2_cost':
                                  _dollarFromInput(v) ?? '',
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _sub2Shipping,
                            decoration: _dec('Shipping'),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (v) => _patch({
                              'subcontractor_2_shipping':
                                  _dollarFromInput(v) ?? '',
                            }),
                          ),
                        ),
                      ],
                    ),
                    if (calc != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '→ Subcontractor total: \$${formatQuoteMoney(_num(calc['subcontractor_1_total']) + _num(calc['subcontractor_2_total']))}',
                          style:
                              TextStyle(color: Colors.grey[700], fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
              _QuoteSection(
                title: 'Post-processing',
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _inspection,
                            decoration: _dec('Inspection'),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (v) => _patch({
                              'inspection_cost': _dollarFromInput(v) ?? '',
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _packaging,
                            decoration: _dec('Packaging'),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (v) => _patch({
                              'packaging_cost': _dollarFromInput(v) ?? '',
                            }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _postShipping,
                      decoration: _dec('Shipping'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (v) => _patch({
                        'shipping_cost': _dollarFromInput(v) ?? '',
                      }),
                    ),
                  ],
                ),
              ),
              _QuoteSection(
                title: 'Reference',
                child: TextField(
                  controller: _prevQuoteRef,
                  decoration: _dec('Previous quote reference'),
                  onChanged: (v) => _patch({'previous_quote_reference': v}),
                ),
              ),
            ],
            const Divider(height: 24),
            if (calc != null) ...[
              Text(
                'Total (CAD): \$${formatQuoteMoney(_num(calc['line_total_cad']))}',
                style: const TextStyle(fontSize: 13),
              ),
              Text(
                'Per part (CAD): \$${formatQuoteMoney(_num(calc['price_per_part_cad']))} | '
                'Per part (USD): \$${formatQuoteMoney(_num(calc['price_per_part_usd']))}',
                style: const TextStyle(fontSize: 13),
              ),
              Text(
                'Quoted per part (CAD): \$${formatQuoteMoney(_num(calc['quoted_price_per_part_cad']))} | '
                'Quoted per part (USD): \$${formatQuoteMoney(_num(calc['quoted_price_per_part_usd']))}',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (widget.onAddPart != null)
                  OutlinedButton(
                    onPressed: widget.onAddPart,
                    child: const Text('Add part'),
                  ),
                if (widget.onDuplicate != null)
                  OutlinedButton(
                    onPressed: widget.onDuplicate,
                    child: const Text('Duplicate part'),
                  ),
                OutlinedButton(
                  onPressed: widget.onDelete,
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Delete part'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? _relationId(dynamic v) {
    if (v == null || v.toString().isEmpty) return null;
    if (v is String) return v;
    if (v is Map && v['id'] != null) return v['id'].toString();
    return v.toString();
  }

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }
}
