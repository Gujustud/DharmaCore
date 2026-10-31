import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import 'auth_service.dart';
import 'packing_slip_pdf.dart';
import 'pocketbase_service.dart';

/// Preview / print / export packing slip for a job.
class PackingSlipScreen extends StatefulWidget {
  const PackingSlipScreen({
    super.key,
    required this.jobId,
  });

  final String jobId;

  @override
  State<PackingSlipScreen> createState() => _PackingSlipScreenState();
}

class _PackingSlipScreenState extends State<PackingSlipScreen> {
  bool _loading = true;
  String? _error;
  String _psNumber = '';
  String _purchaseOrder = '';
  final _trackingController = TextEditingController();
  final _packedByController = TextEditingController();
  DateTime _date = DateTime.now();
  DateTime _packedDate = DateTime.now();
  List<String> _shipToLines = [];
  List<_EditableLine> _lines = [];
  String? _customerName;

  @override
  void initState() {
    super.initState();
    final display = AuthService.instance.displayName ?? '';
    final email = AuthService.instance.email ?? '';
    final fromEmail = email.contains('@') ? email.split('@').first : email;
    final name = display.trim().isNotEmpty ? display.trim() : fromEmail;
    _packedByController.text = name.isEmpty ? 'Amish' : _titleCase(name);
    _load();
  }

  String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  @override
  void dispose() {
    _trackingController.dispose();
    _packedByController.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pb = PocketBaseService();
      final job = await pb.getJob(widget.jobId);
      final d = job.data as Map<String, dynamic>? ?? {};
      final linesRaw = await pb.getJobLineItems(widget.jobId);

      final ps = await pb.allocatePackingSlipNumber(jobId: widget.jobId);

      final shipLines = await _resolveShipTo(pb, job, d);
      final tracking = _defaultTracking(d);

      final editable = <_EditableLine>[];
      if (linesRaw.isEmpty) {
        // Fallback: parse parts_description bullets if no structured lines yet.
        final parts = '${d['parts_description'] ?? ''}'.trim();
        var i = 1;
        for (final raw in parts.split('\n')) {
          final line = raw.trim();
          if (line.isEmpty) continue;
          final cleaned = line.replaceFirst(RegExp(r'^•\s*'), '');
          final m = RegExp(r'^(.*)\s*\(qty\s*([^)]+)\)\s*$', caseSensitive: false)
              .firstMatch(cleaned);
          final desc = (m?.group(1) ?? cleaned).trim();
          final qty = num.tryParse('${m?.group(2) ?? 1}'.trim()) ?? 1;
          editable.add(_EditableLine(itemNumber: i++, description: desc, quantity: qty, packed: qty));
        }
      } else {
        var i = 1;
        for (final row in linesRaw) {
          final rd = row.data as Map<String, dynamic>? ?? {};
          final qty = (rd['quantity'] as num?) ?? 1;
          final packed = (rd['packed_quantity'] as num?) ?? qty;
          editable.add(
            _EditableLine(
              id: row.id as String?,
              itemNumber: i++,
              description: '${rd['description'] ?? ''}'.trim(),
              quantity: qty,
              packed: packed,
            ),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _psNumber = ps;
        _purchaseOrder = '${d['po_number'] ?? ''}'.trim();
        _trackingController.text = tracking;
        _shipToLines = shipLines;
        _customerName = '${d['customer_name'] ?? ''}'.trim();
        _lines = editable;
        final shipDate = d['ship_date'];
        if (shipDate != null && '$shipDate'.isNotEmpty) {
          try {
            _date = DateTime.parse('$shipDate');
            _packedDate = _date;
          } catch (_) {}
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<List<String>> _resolveShipTo(
    PocketBaseService pb,
    dynamic job,
    Map<String, dynamic> d,
  ) async {
    final override = '${d['ship_to_override'] ?? ''}'.trim();
    if (override.isNotEmpty) {
      return override.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    }

    Map<String, dynamic>? shipData;
    try {
      final expand = job.expand?['ship_to'];
      final raw = (expand is List && expand.isNotEmpty) ? expand.first : expand;
      if (raw != null) {
        shipData = raw.data as Map<String, dynamic>?;
      }
    } catch (_) {}

    if (shipData == null) {
      final shipId = d['ship_to'];
      if (shipId is String && shipId.isNotEmpty) {
        try {
          final rec = await pb.getCustomerShipTo(shipId);
          shipData = rec.data as Map<String, dynamic>?;
        } catch (_) {}
      }
    }

    if (shipData != null) {
      final lines = <String>[];
      // Label and ATTN are the same in the UI — prefer label, fall back to attn.
      final name = '${shipData['label'] ?? ''}'.trim().isNotEmpty
          ? '${shipData['label']}'.trim()
          : '${shipData['attn'] ?? ''}'.trim();
      if (name.isNotEmpty) lines.add(name);
      final addr = '${shipData['address'] ?? ''}'.trim();
      if (addr.isNotEmpty) {
        lines.addAll(addr.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty));
      }
      if (lines.isNotEmpty) return lines;
    }

    // Fallback: customer address / name
    Map<String, dynamic>? cust;
    try {
      final expand = job.expand?['customer'];
      final raw = (expand is List && expand.isNotEmpty) ? expand.first : expand;
      if (raw != null) cust = raw.data as Map<String, dynamic>?;
    } catch (_) {}

    final lines = <String>[];
    final company = '${cust?['company'] ?? d['customer_name'] ?? ''}'.trim();
    if (company.isNotEmpty) lines.add(company);
    final contact = '${cust?['name'] ?? ''}'.trim();
    if (contact.isNotEmpty) lines.add(contact);
    final addr = '${cust?['address'] ?? ''}'.trim();
    if (addr.isNotEmpty) {
      lines.addAll(addr.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty));
    }
    return lines;
  }

  String _defaultTracking(Map<String, dynamic> d) {
    final n1 = '${d['tracking_number_1'] ?? ''}'.trim();
    if (n1.isEmpty) {
      final status = '${d['tracking_status'] ?? ''}';
      if (status == 'not_shipped') return 'pickup';
      return '';
    }
    // Heuristic carrier prefix for display (matches manual slips loosely).
    final upper = n1.toUpperCase();
    if (upper.startsWith('1Z')) return 'UPS $n1';
    if (RegExp(r'^\d{12,}$').hasMatch(n1)) return 'Fedex $n1';
    return n1;
  }

  PackingSlipData _buildData() {
    return PackingSlipData(
      packingSlipNumber: _psNumber,
      shipToLines: _shipToLines.isEmpty
          ? [_customerName?.isNotEmpty == true ? _customerName! : '—']
          : _shipToLines,
      date: _date,
      purchaseOrder: _purchaseOrder,
      tracking: _trackingController.text.trim(),
      lines: [
        for (final l in _lines)
          PackingSlipLine(
            itemNumber: l.itemNumber,
            quantity: num.tryParse(l.qtyController.text.trim()) ?? l.quantity,
            description: l.descController.text.trim(),
            packed: num.tryParse(l.packedController.text.trim()) ?? l.packed,
          ),
      ],
      packedBy: _packedByController.text.trim(),
      packedDate: _packedDate,
    );
  }

  Future<void> _persistPackedQtys() async {
    final pb = PocketBaseService();
    for (final l in _lines) {
      final id = l.id;
      if (id == null || id.isEmpty) continue;
      final packed = num.tryParse(l.packedController.text.trim());
      if (packed == null) continue;
      await pb.updateJobLineItem(id, {'packed_quantity': packed});
    }
  }

  Future<void> _print() async {
    try {
      await _persistPackedQtys();
      final bytes = await buildPackingSlipPdf(_buildData());
      await Printing.layoutPdf(
        name: _psNumber,
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _exportPdf() async {
    try {
      await _persistPackedQtys();
      final bytes = await buildPackingSlipPdf(_buildData());
      final safeCust = (_customerName ?? 'customer')
          .replaceAll(RegExp(r'[^\w\-]+'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${_psNumber}-$safeCust.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_psNumber.isEmpty ? 'Packing slip' : 'Packing slip $_psNumber'),
        actions: [
          TextButton.icon(
            onPressed: _loading || _error != null ? null : _print,
            icon: const Icon(Icons.print),
            label: const Text('Print'),
          ),
          TextButton.icon(
            onPressed: _loading || _error != null ? null : _exportPdf,
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Export PDF'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Ship to',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _shipToLines.isEmpty ? '—' : _shipToLines.join('\n'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Date',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            child: Text(DateFormat.yMMMd().format(_date)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'PO',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            child: Text(_purchaseOrder.isEmpty ? '—' : _purchaseOrder),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _trackingController,
                      decoration: const InputDecoration(
                        labelText: 'Tracking',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Line items', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    ..._lines.map(_lineEditor),
                    if (_lines.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No parts on this job. Add job lines first.'),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _packedByController,
                            decoration: const InputDecoration(
                              labelText: 'Packed by',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Packed date',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            child: InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _packedDate,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setState(() => _packedDate = picked);
                                }
                              },
                              child: Text(DateFormat.yMMMd().format(_packedDate)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
    );
  }

  Widget _lineEditor(_EditableLine line) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('${line.itemNumber}'),
            ),
          ),
          SizedBox(
            width: 64,
            child: TextField(
              controller: line.qtyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Qty',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: line.descController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: TextField(
              controller: line.packedController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Packed',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableLine {
  _EditableLine({
    this.id,
    required this.itemNumber,
    required this.description,
    required this.quantity,
    required this.packed,
  })  : descController = TextEditingController(text: description),
        qtyController = TextEditingController(text: '$quantity'),
        packedController = TextEditingController(text: '$packed');

  final String? id;
  final int itemNumber;
  final String description;
  final num quantity;
  final num packed;
  final TextEditingController descController;
  final TextEditingController qtyController;
  final TextEditingController packedController;

  void dispose() {
    descController.dispose();
    qtyController.dispose();
    packedController.dispose();
  }
}
