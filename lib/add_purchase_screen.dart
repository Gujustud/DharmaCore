import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:url_launcher/url_launcher.dart';
import 'pocketbase_service.dart';
import 'models.dart';
import 'shop_material_editor.dart';
import 'ui_breakpoints.dart';
import 'workspace_layout.dart';
import 'workspace_scaffold.dart';
import 'drawer_behavior.dart';

http.MultipartFile _purchaseCertPart(String filename, List<int> bytes) {
  return http.MultipartFile.fromBytes(
    'attachments+',
    bytes,
    filename: filename,
  );
}

http.MultipartFile _lineMillCertPart(String filename, List<int> bytes) {
  return http.MultipartFile.fromBytes(
    'mill_certs+',
    bytes,
    filename: filename,
  );
}

typedef _PendingCert = ({String name, List<int> bytes});

class AddPurchaseScreen extends StatefulWidget {
  /// When non-null, opens in edit mode for this purchase.
  final Purchase? purchase;

  /// When true, render as an inline panel (no app shell / drawer).
  final bool embedded;

  /// Called when the panel should close. [saved] is true after save/delete.
  final ValueChanged<bool>? onClosed;

  const AddPurchaseScreen({
    super.key,
    this.purchase,
    this.embedded = false,
    this.onClosed,
  });

  @override
  State<AddPurchaseScreen> createState() => _AddPurchaseScreenState();
}

class _AddPurchaseScreenState extends State<AddPurchaseScreen> with AutoOpenDrawerMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  GlobalKey<ScaffoldState> get scaffoldKey => _scaffoldKey;

  List<dynamic> _suppliers = [];
  List<Tool> _tools = [];
  List<ShopMaterial> _materials = [];
  bool _isLoadingData = true;

  DateTime _purchaseDate = DateTime.now();
  String? _supplierId;
  final _orderRefController = TextEditingController();
  final _invoiceController = TextEditingController();
  final _notesController = TextEditingController();
  late final TextEditingController _dateController;

  // Line items: type 'item'|'material'|'misc'|'shipping' (tax is GST/PST checkboxes)
  final List<Map<String, dynamic>> _lineItems = [];

  bool _gstChecked = false;
  bool _pstChecked = false;
  /// Vendor/invoice tax amounts (e.g. DGI $16.84). When set, prefer these over
  /// rate × (items + shipping), which can be 1¢ off due to rounding.
  double? _gstAmountOverride;
  double? _pstAmountOverride;
  /// Invoice currency tag — no FX conversion (`CAD` default, `USD` for McMaster).
  String _currency = 'CAD';

  RecordModel? _purchaseRecord;
  final List<_PendingCert> _pendingCerts = [];
  bool _uploadingCerts = false;

  static const double _gstRate = 0.05; // 5%
  static const double _pstRate = 0.07; // 7%

  String _money(double amount) =>
      '\$${amount.toStringAsFixed(2)} $_currency';

  static double _round2(double v) => (v * 100).round() / 100;

  @override
  void initState() {
    super.initState();
    final p = widget.purchase;
    if (p != null) {
      _purchaseDate = p.purchaseDate;
      _supplierId = p.supplierId;
      _orderRefController.text = p.orderReference ?? '';
      _invoiceController.text = p.invoice ?? '';
      _notesController.text = p.notes ?? '';
      _currency = p.currency == 'USD' ? 'USD' : 'CAD';
    }
    _dateController = TextEditingController(text: DateFormat.yMMMd().format(_purchaseDate));
    _loadData();
    if (p == null) {
      _lineItems.add(_newLineMap());
    }
  }

  @override
  void dispose() {
    _orderRefController.dispose();
    _invoiceController.dispose();
    _notesController.dispose();
    _dateController.dispose();
    // Dispose any per-line TextEditingControllers we created
    for (final item in _lineItems) {
      final qtyCtrl = item['quantityController'];
      if (qtyCtrl is TextEditingController) {
        qtyCtrl.dispose();
      }
      final unitCtrl = item['unitCostController'];
      if (unitCtrl is TextEditingController) {
        unitCtrl.dispose();
      }
      final heatCtrl = item['heatLotController'];
      if (heatCtrl is TextEditingController) {
        heatCtrl.dispose();
      }
      final descCtrl = item['descriptionController'];
      if (descCtrl is TextEditingController) {
        descCtrl.dispose();
      }
    }
    super.dispose();
  }

  void _openDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _purchaseDate = picked;
        _dateController.text = DateFormat.yMMMd().format(_purchaseDate);
      });
    }
  }

  void _parseDateFromField() {
    final text = _dateController.text.trim();
    if (text.isEmpty) return;
    DateTime? parsed;
    try {
      parsed = DateFormat.yMMMd().parse(text);
    } catch (_) {}
    if (parsed == null) {
      try {
        parsed = DateFormat('M/d/yyyy').parse(text);
      } catch (_) {}
    }
    if (parsed == null) {
      parsed = DateTime.tryParse(text);
    }
    if (parsed != null) {
      setState(() {
        _purchaseDate = parsed!;
        _dateController.text = DateFormat.yMMMd().format(_purchaseDate);
      });
    } else {
      _dateController.text = DateFormat.yMMMd().format(_purchaseDate);
    }
  }

  num _qtyOf(Map<String, dynamic> item) {
    final q = item['quantity'];
    if (q is num) return q;
    return num.tryParse('$q') ?? 0;
  }

  Future<void> _loadData() async {
    setState(() => _isLoadingData = true);
    try {
      final pbService = PocketBaseService();
      final p = widget.purchase;
      final futures = <Future>[
        pbService.getSuppliers(),
        pbService.getTools(),
        pbService.getMaterials(),
        if (p != null) pbService.getPurchaseItems(p.id),
        if (p != null) pbService.getPurchase(p.id),
      ];
      final results = await Future.wait(futures);
      final suppliers = results[0] as List<dynamic>;
      final toolRecords = results[1] as List<dynamic>;
      final materialRecords = results[2] as List<dynamic>;
      List<dynamic> existingItemRecords = [];
      RecordModel? purchaseRecord;
      var idx = 3;
      if (p != null) {
        existingItemRecords = results[idx++] as List<dynamic>;
        purchaseRecord = results[idx] as RecordModel;
      }
      setState(() {
        _suppliers = suppliers;
        _tools = toolRecords.map((r) => Tool.fromRecord(r)).toList();
        _materials = materialRecords.map(ShopMaterial.fromRecord).toList();
        _purchaseRecord = purchaseRecord;
        if (p != null && existingItemRecords.isNotEmpty) {
          _lineItems.clear();
          bool gst = false, pst = false;
          double? gstAmt;
          double? pstAmt;
          for (final record in existingItemRecords) {
            final item = PurchaseItem.fromRecord(record);
            if (item.lineType == 'tax') {
              final d = (item.description ?? '').toUpperCase();
              if (d.contains('GST')) {
                gst = true;
                if (item.unitCost != null) gstAmt = item.unitCost;
              }
              if (d.contains('PST') && !d.contains('GST')) {
                pst = true;
                if (item.unitCost != null) pstAmt = item.unitCost;
              }
              continue;
            }
            final raw = item.lineType;
            final type = raw == 'shipping' ||
                    raw == 'material' ||
                    raw == 'misc'
                ? raw
                : 'item';
            // Resolve tool label from catalog when expand did not populate toolName
            var toolName = item.toolName ?? '';
            final toolId = item.toolId;
            if (type == 'item' &&
                toolName.isEmpty &&
                toolId != null &&
                toolId.isNotEmpty) {
              for (final t in _tools) {
                if (t.id != toolId) continue;
                final model = (t.modelNumber ?? '').trim();
                toolName = model.isEmpty
                    ? t.toolName
                    : '${t.toolName} ($model)';
                break;
              }
            }
            var shipDesc = (type == 'shipping') ? (item.description ?? '') : '';
            if (type == 'shipping') {
              final d = shipDesc.trim();
              if (d.toLowerCase() == 'shipping') {
                shipDesc = (item.unitCost != null &&
                        (item.unitCost! - 34.95).abs() < 0.01)
                    ? 'Next Day Air'
                    : '';
              }
            }
            _lineItems.add({
              'type': type,
              'toolId': toolId,
              'toolName': toolName,
              'materialId': item.materialId,
              'materialLabel': item.materialLabel ?? '',
              'quantity': item.quantity,
              'unitCost': item.unitCost,
              'description': (type == 'shipping' || type == 'misc')
                  ? (type == 'shipping' ? shipDesc : (item.description ?? ''))
                  : '',
              'itemText': type == 'item'
                  ? toolName
                  : (type == 'material' ? (item.materialLabel ?? '') : ''),
              'heatLot': item.heatLot ?? '',
              'sourceItemId': item.id,
              'sourceItemRecord': record,
              'millCertNames': List<String>.from(item.millCertNames),
              'pendingMillCerts': <_PendingCert>[],
            });
          }
          _gstChecked = gst;
          _pstChecked = pst;
          _gstAmountOverride = gstAmt;
          _pstAmountOverride = pstAmt;
          if (_lineItems.isEmpty) {
            _lineItems.add(_newLineMap());
          }
        } else if (p == null) {
          if (_lineItems.isNotEmpty) {
            _lineItems[0]['itemText'] ??= '';
          }
        }
        _isLoadingData = false;
      });
    } catch (e) {
      setState(() => _isLoadingData = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Map<String, dynamic> _newLineMap({String type = 'item'}) => {
        'type': type,
        'toolId': null as String?,
        'toolName': '',
        'materialId': null as String?,
        'materialLabel': '',
        'quantity': 1,
        'unitCost': null as double?,
        'description': '',
        'itemText': '',
        'heatLot': '',
        'sourceItemId': null as String?,
        'sourceItemRecord': null,
        'millCertNames': <String>[],
        'pendingMillCerts': <_PendingCert>[],
      };

  List<_PendingCert> _pendingMillCertsOf(Map<String, dynamic> line) {
    final raw = line['pendingMillCerts'];
    if (raw is List<_PendingCert>) return raw;
    if (raw is List) {
      final cast = <_PendingCert>[];
      for (final e in raw) {
        if (e is _PendingCert) cast.add(e);
      }
      line['pendingMillCerts'] = cast;
      return cast;
    }
    final empty = <_PendingCert>[];
    line['pendingMillCerts'] = empty;
    return empty;
  }

  List<String> _millCertNamesOf(Map<String, dynamic> line) {
    final raw = line['millCertNames'];
    if (raw is List<String>) return raw;
    if (raw is List) {
      return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    return const [];
  }

  /// Pull existing line mill certs into pending bytes so recreate-on-save keeps them.
  Future<void> _hydrateLineMillCertsForSave() async {
    final pb = PocketBaseService();
    for (final line in _lineItems) {
      if ((line['type'] as String?) != 'material') continue;
      final pending = _pendingMillCertsOf(line);
      final names = _millCertNamesOf(line);
      final source = line['sourceItemRecord'];
      if (source == null || names.isEmpty) continue;
      for (final name in names) {
        if (pending.any((p) => p.name == name)) continue;
        try {
          final bytes = await pb.downloadRecordFile(source, name);
          if (bytes.isEmpty) continue;
          pending.add((name: name, bytes: bytes));
        } catch (e) {
          print('Could not keep mill cert $name: $e');
        }
      }
      line['pendingMillCerts'] = pending;
    }
  }

  Future<void> _pickLineMillCerts(int lineIndex) async {
    final line = _lineItems[lineIndex];
    final pending = _pendingMillCertsOf(line);
    final named = _millCertNamesOf(line);
    final existingCount = named.length + pending.length;
    if (existingCount >= 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum 8 mill cert files per material line.'),
        ),
      );
      return;
    }
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      final remaining = 8 - named.length - pending.length;
      for (final f in result.files) {
        if (pending.length >= remaining) break;
        final bytes = f.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        pending.add((name: f.name, bytes: bytes));
      }
      line['pendingMillCerts'] = pending;
    });
  }

  void _removePendingLineMillCert(int lineIndex, int pendingIndex) {
    setState(() {
      final pending = _pendingMillCertsOf(_lineItems[lineIndex]);
      if (pendingIndex < 0 || pendingIndex >= pending.length) return;
      pending.removeAt(pendingIndex);
    });
  }

  void _removeExistingLineMillCertName(int lineIndex, String filename) {
    setState(() {
      final names = List<String>.from(_millCertNamesOf(_lineItems[lineIndex]));
      names.remove(filename);
      _lineItems[lineIndex]['millCertNames'] = names;
    });
  }

  Future<void> _openLineMillCert(int lineIndex, String filename) async {
    final source = _lineItems[lineIndex]['sourceItemRecord'];
    if (source == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Save the purchase to open existing mill certs.'),
        ),
      );
      return;
    }
    final url = PocketBaseService().pb.files.getUrl(source, filename);
    final uri = Uri.parse(url.toString());
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $filename')),
      );
    }
  }

  Widget? _buildMaterialLineMillCertChips(int lineIndex) {
    final line = _lineItems[lineIndex];
    final named = _millCertNamesOf(line);
    final pending = _pendingMillCertsOf(line);
    if (named.isEmpty && pending.isEmpty) return null;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 128),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final name in named)
            InputChip(
              label: Text(name, overflow: TextOverflow.ellipsis),
              avatar: Icon(Icons.picture_as_pdf, size: 18, color: scheme.primary),
              onPressed: () => _openLineMillCert(lineIndex, name),
              onDeleted: () => _removeExistingLineMillCertName(lineIndex, name),
            ),
          for (var p = 0; p < pending.length; p++)
            InputChip(
              label: Text(
                '${pending[p].name} (pending)',
                overflow: TextOverflow.ellipsis,
              ),
              avatar: const Icon(Icons.schedule, size: 18),
              onDeleted: () => _removePendingLineMillCert(lineIndex, p),
            ),
        ],
      ),
    );
  }

  void _addLine() {
    setState(() {
      _lineItems.add(_newLineMap());
    });
  }

  static const int _toolSuggestionsMax = 5;
  static const int _materialSuggestionsMax = 8;

  bool _isQtyCostLine(String type) =>
      type == 'item' || type == 'material' || type == 'misc';

  String _lineTotal(int index) {
    final item = _lineItems[index];
    final type = item['type'] as String? ?? 'item';
    if (!_isQtyCostLine(type)) return '';
    final qty = _qtyOf(item);
    final unit = (item['unitCost'] as double?) ?? 0;
    if (qty <= 0 || unit <= 0) return '';
    return '\$${(qty * unit).toStringAsFixed(2)}';
  }

  double _subtotalItems() {
    double sum = 0;
    for (final item in _lineItems) {
      final type = item['type'] as String? ?? 'item';
      if (!_isQtyCostLine(type)) continue;
      final qty = _qtyOf(item);
      final unit = (item['unitCost'] as double?) ?? 0;
      sum += qty * unit;
    }
    return sum;
  }

  double _shippingTotal() {
    double shipping = 0;
    for (final item in _lineItems) {
      final type = item['type'] as String? ?? 'item';
      if (type == 'shipping') {
        shipping += (item['unitCost'] as double?) ?? 0;
      }
    }
    return shipping;
  }

  double _taxableBase() {
    return _subtotalItems() + _shippingTotal();
  }

  double _computedGst() => _round2(_taxableBase() * _gstRate);

  double _computedPst() => _round2(_taxableBase() * _pstRate);

  /// Prefer invoice-stored GST when present; otherwise rate × taxable base.
  double _gstAmount() {
    if (!_gstChecked) return 0;
    return _gstAmountOverride ?? _computedGst();
  }

  double _pstAmount() {
    if (!_pstChecked) return 0;
    return _pstAmountOverride ?? _computedPst();
  }

  double _totalTaxAndShipping() {
    return _shippingTotal() + _gstAmount() + _pstAmount();
  }

  Iterable<Tool> _filterTools(String text) {
    if (text.trim().isEmpty) return _tools.take(_toolSuggestionsMax);
    final lower = text.toLowerCase();
    return _tools.where((t) {
      final nameMatch = t.toolName.toLowerCase().contains(lower);
      final modelMatch = t.modelNumber?.toLowerCase().contains(lower) ?? false;
      return nameMatch || modelMatch;
    }).take(_toolSuggestionsMax);
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete purchase?'),
        content: const Text('This will delete the purchase and all its line items.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || widget.purchase == null) return;
    try {
      await PocketBaseService().deletePurchase(widget.purchase!.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase deleted'), backgroundColor: Colors.green),
        );
        _close(saved: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _close({required bool saved}) {
    if (widget.embedded) {
      widget.onClosed?.call(saved);
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  Future<void> _save() async {
    final validLines = _lineItems.where((e) {
      final type = e['type'] as String? ?? 'item';
      if (type == 'item') {
        return e['toolId'] != null && _qtyOf(e) > 0;
      }
      if (type == 'material') {
        return e['materialId'] != null && _qtyOf(e) > 0;
      }
      if (type == 'misc') {
        final desc = (e['description'] as String?)?.trim() ?? '';
        final unit = (e['unitCost'] as double?) ?? 0;
        return desc.isNotEmpty && _qtyOf(e) > 0 && unit > 0;
      }
      if (type == 'shipping') {
        final amount = (e['unitCost'] as double?) ?? 0;
        return amount > 0;
      }
      return false;
    }).toList();
    if (validLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add at least one line (tool, material, misc, or shipping)',
          ),
        ),
      );
      return;
    }

    try {
      final pbService = PocketBaseService();
      // Keep line mill certs across delete+recreate of purchase_items.
      await _hydrateLineMillCertsForSave();
      String id;
      final subtotal = _subtotalItems();
      // Prefer invoice GST/PST amounts when loaded; else rate × (items + shipping).
      final gstAmt = _gstAmount();
      final pstAmt = _pstAmount();
      final grandTotal = subtotal + _totalTaxAndShipping();
      if (widget.purchase != null) {
        id = widget.purchase!.id;
        await pbService.updatePurchase(id,
          purchaseDate: _purchaseDate,
          supplierId: _supplierId,
          orderReference: _orderRefController.text.isEmpty ? null : _orderRefController.text,
          invoice: _invoiceController.text.isEmpty ? '' : _invoiceController.text,
          notes: _notesController.text.isEmpty ? null : _notesController.text,
          total: grandTotal,
          currency: _currency,
        );
        final existing = await pbService.getPurchaseItems(id);
        for (final item in existing) {
          await pbService.deletePurchaseItem(item.id);
        }
      } else {
        final record = await pbService.createPurchase(
          purchaseDate: _purchaseDate,
          supplierId: _supplierId,
          orderReference: _orderRefController.text.isEmpty ? null : _orderRefController.text,
          invoice: _invoiceController.text.isEmpty ? null : _invoiceController.text,
          notes: _notesController.text.isEmpty ? null : _notesController.text,
          total: grandTotal,
          currency: _currency,
        );
        id = record.id;
        _purchaseRecord = record is RecordModel ? record : null;
      }
      for (final line in validLines) {
        final type = line['type'] as String? ?? 'item';
        final desc = (line['description'] as String?)?.trim();
        final heat = (line['heatLot'] as String?)?.trim();
        final pending = type == 'material' ? _pendingMillCertsOf(line) : const <_PendingCert>[];
        final millFiles = [
          for (final f in pending) _lineMillCertPart(f.name, f.bytes),
        ];
        await pbService.createPurchaseItem(
          purchaseId: id,
          toolId: type == 'item' ? (line['toolId'] as String?) : null,
          materialId: type == 'material' ? (line['materialId'] as String?) : null,
          quantity: type == 'shipping' ? 1 : _qtyOf(line),
          unitCost: line['unitCost'] as double?,
          lineType: type,
          description: type == 'shipping'
              ? ((desc == null || desc.isEmpty) ? 'Shipping' : desc)
              : (type == 'misc' ? desc : null),
          heatLot: type == 'material' ? heat : null,
          millCertFiles: millFiles.isEmpty ? null : millFiles,
        );
      }
      if (gstAmt > 0) {
        await pbService.createPurchaseItem(
          purchaseId: id,
          quantity: 1,
          unitCost: gstAmt,
          lineType: 'tax',
          description: 'GST',
        );
      }
      if (pstAmt > 0) {
        await pbService.createPurchaseItem(
          purchaseId: id,
          quantity: 1,
          unitCost: pstAmt,
          lineType: 'tax',
          description: 'PST',
        );
      }

      if (_pendingCerts.isNotEmpty) {
        final uploads = [
          for (final f in _pendingCerts) _purchaseCertPart(f.name, f.bytes),
        ];
        final updated = await pbService.uploadPurchaseAttachments(id, uploads);
        if (updated is RecordModel) {
          _purchaseRecord = updated;
        }
        _pendingCerts.clear();
      } else if (_purchaseRecord == null || _purchaseRecord!.id != id) {
        final fresh = await pbService.getPurchase(id);
        if (fresh is RecordModel) _purchaseRecord = fresh;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.purchase != null ? 'Purchase updated' : 'Purchase added'),
            backgroundColor: Colors.green,
          ),
        );
        _close(saved: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<String> get _existingCertNames {
    final rec = _purchaseRecord;
    if (rec == null) return const [];
    final v = rec.data['attachments'];
    if (v is List) {
      return v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    return const [];
  }

  Future<void> _pickMillCerts() async {
    final existing = _existingCertNames.length + _pendingCerts.length;
    if (existing >= 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 12 mill cert files per purchase.')),
      );
      return;
    }
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final purchaseId = _purchaseRecord?.id ?? widget.purchase?.id;
    if (purchaseId != null) {
      setState(() => _uploadingCerts = true);
      try {
        final remaining = 12 - _existingCertNames.length;
        final uploads = <http.MultipartFile>[];
        for (final f in result.files) {
          if (uploads.length >= remaining) break;
          final bytes = f.bytes;
          if (bytes == null || bytes.isEmpty) continue;
          uploads.add(_purchaseCertPart(f.name, bytes));
        }
        if (uploads.isEmpty) return;
        final updated =
            await PocketBaseService().uploadPurchaseAttachments(purchaseId, uploads);
        if (mounted && updated is RecordModel) {
          setState(() => _purchaseRecord = updated);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _uploadingCerts = false);
      }
      return;
    }

    setState(() {
      final remaining = 12 - _pendingCerts.length;
      for (final f in result.files) {
        if (_pendingCerts.length >= remaining) break;
        final bytes = f.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        _pendingCerts.add((name: f.name, bytes: bytes));
      }
    });
  }

  Future<void> _removeCert(String filename) async {
    final id = _purchaseRecord?.id ?? widget.purchase?.id;
    if (id == null) return;
    try {
      final updated =
          await PocketBaseService().removePurchaseAttachment(id, filename);
      if (mounted && updated is RecordModel) {
        setState(() => _purchaseRecord = updated);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Remove failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _openCert(String filename) async {
    final rec = _purchaseRecord;
    if (rec == null) return;
    final url = PocketBaseService().pb.files.getUrl(rec, filename);
    final uri = Uri.parse(url.toString());
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $filename')),
      );
    }
  }

  Future<ShopMaterial?> _showCreateMaterialDialog() =>
      showShopMaterialEditor(context);

  Iterable<ShopMaterial> _filterMaterials(String text) {
    if (text.trim().isEmpty) return _materials.take(_materialSuggestionsMax);
    final lower = text.toLowerCase();
    return _materials.where((m) {
      return m.grade.toLowerCase().contains(lower) ||
          m.form.toLowerCase().contains(lower) ||
          m.sizeLabel.toLowerCase().contains(lower) ||
          m.displayLabel.toLowerCase().contains(lower);
    }).take(_materialSuggestionsMax);
  }

  String get _title =>
      widget.purchase != null ? 'Edit Purchase' : 'Add Purchase';

  Widget _buildFormBody() {
    if (_isLoadingData) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            // Embedded panel uses the full detail column; standalone form stays readable.
            maxWidth: widget.embedded ? kWorkspaceContentMaxWidth : 900,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
                  // Date: type or tap calendar
                  TextField(
                    controller: _dateController,
                    decoration: InputDecoration(
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      labelText: 'Date',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: _openDatePicker,
                        tooltip: 'Pick date',
                      ),
                    ),
                    onSubmitted: (_) => _parseDateFromField(),
                    onEditingComplete: _parseDateFromField,
                  ),
                  const SizedBox(height: 16),
                  // Supplier + Order reference on same row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Supplier: type to search or pick from dropdown
                      Expanded(
                        flex: 3,
                        child: Autocomplete<Object>(
                    initialValue: widget.purchase != null &&
                            widget.purchase!.supplierName != null &&
                            widget.purchase!.supplierName!.isNotEmpty
                        ? TextEditingValue(text: widget.purchase!.supplierName!)
                        : null,
                    optionsBuilder: (textValue) {
                      final query = textValue.text.trim().toLowerCase();
                      if (query.isEmpty) {
                        return List<Object>.from([const _SupplierNone(), ..._suppliers]);
                      }
                      return List<Object>.from(_suppliers.where((s) {
                        final name = (s.data['company_name'] ?? '').toString().toLowerCase();
                        return name.contains(query);
                      }));
                    },
                    displayStringForOption: (option) {
                      if (option is _SupplierNone) return '— None —';
                      final s = option as dynamic;
                      return (s.data['company_name'] ?? s.id) as String;
                    },
                    onSelected: (option) {
                      setState(() {
                        _supplierId = option is _SupplierNone ? null : (option as dynamic).id as String;
                      });
                    },
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                                  floatingLabelBehavior: FloatingLabelBehavior.always,
                          labelText: 'Supplier',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.arrow_drop_down),
                        ),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(4),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 240),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (context, index) {
                                final opt = options.elementAt(index);
                                final label = opt is _SupplierNone
                                    ? '— None —'
                                    : ((opt as dynamic).data['company_name'] ?? (opt as dynamic).id) as String;
                                return ListTile(
                                  dense: true,
                                  title: Text(label),
                                  onTap: () => onSelected(opt),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                      ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _invoiceController,
                          decoration: const InputDecoration(
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                            labelText: 'Invoice',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _orderRefController,
                          decoration: const InputDecoration(
                                  floatingLabelBehavior: FloatingLabelBehavior.always,
                            labelText: 'Order reference',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                                  floatingLabelBehavior: FloatingLabelBehavior.always,
                      labelText: 'Notes',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Line items',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(_lineItems.length, (i) {
                    final item = _lineItems[i];
                    final rawType = item['type'] as String? ?? 'item';
                    final lineType = rawType == 'tax' ? 'item' : rawType;
                    // Lazily ensure the visible text backing field exists.
                    item['itemText'] ??= lineType == 'material'
                        ? (item['materialLabel'] ?? '')
                        : (item['toolName'] ?? '');
                    item['heatLotController'] ??= TextEditingController(
                      text: (item['heatLot'] as String?) ?? '',
                    );
                    item['descriptionController'] ??= TextEditingController(
                      text: (item['description'] as String?) ?? '',
                    );
                    // Lazily create controllers per line so typing doesn't fight rebuilds.
                    if (lineType == 'item' ||
                        lineType == 'material' ||
                        lineType == 'misc') {
                      item['quantityController'] ??=
                          TextEditingController(text: '${item['quantity']}');
                      item['unitCostController'] ??= TextEditingController(
                        text: item['unitCost'] != null
                            ? (item['unitCost'] as double).toString()
                            : '',
                      );
                    } else {
                      // Shipping: only unit cost controller is used
                      item['unitCostController'] ??= TextEditingController(
                        text: item['unitCost'] != null
                            ? (item['unitCost'] as double).toString()
                            : '',
                      );
                    }
                    return Padding(
                      key: ValueKey('line_$i'),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 120,
                            child: DropdownButtonFormField<String>(
                              // ignore: deprecated_member_use
                              value: lineType == 'tax' ? 'item' : lineType,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                floatingLabelBehavior:
                                    FloatingLabelBehavior.always,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: 'item', child: Text('Tool')),
                                DropdownMenuItem(
                                    value: 'material', child: Text('Material')),
                                DropdownMenuItem(
                                    value: 'misc', child: Text('Misc')),
                                DropdownMenuItem(
                                    value: 'shipping', child: Text('Shipping')),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() {
                                    _lineItems[i]['type'] = v;
                                    if (v == 'material') {
                                      _lineItems[i]['toolId'] = null;
                                      _lineItems[i]['itemText'] =
                                          _lineItems[i]['materialLabel'] ?? '';
                                    } else if (v == 'item') {
                                      _lineItems[i]['materialId'] = null;
                                      _lineItems[i]['itemText'] =
                                          _lineItems[i]['toolName'] ?? '';
                                    } else if (v == 'misc') {
                                      _lineItems[i]['toolId'] = null;
                                      _lineItems[i]['materialId'] = null;
                                    }
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (lineType == 'material') ...[
                            Expanded(
                              flex: 2,
                              child: Autocomplete<ShopMaterial>(
                                key: ValueKey('material_autocomplete_$i'),
                                optionsBuilder: (textValue) =>
                                    _filterMaterials(textValue.text),
                                displayStringForOption: (m) => m.displayLabel,
                                onSelected: (m) {
                                  setState(() {
                                    _lineItems[i]['materialId'] = m.id;
                                    _lineItems[i]['materialLabel'] =
                                        m.displayLabel;
                                    _lineItems[i]['itemText'] = m.displayLabel;
                                  });
                                },
                                fieldViewBuilder: (context, controller,
                                    focusNode, onFieldSubmitted) {
                                  final desiredText =
                                      (item['itemText'] as String?) ?? '';
                                  if (controller.text != desiredText) {
                                    controller.text = desiredText;
                                    controller.selection =
                                        TextSelection.fromPosition(
                                      TextPosition(
                                          offset: controller.text.length),
                                    );
                                  }
                                  return TextField(
                                    controller: controller,
                                    focusNode: focusNode,
                                    decoration: InputDecoration(
                                      floatingLabelBehavior:
                                          FloatingLabelBehavior.always,
                                      labelText: 'Material',
                                      border: const OutlineInputBorder(),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      suffixIcon: IconButton(
                                        tooltip: 'New material',
                                        icon: const Icon(Icons.add, size: 20),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 40,
                                          minHeight: 40,
                                        ),
                                        onPressed: () async {
                                          final created =
                                              await _showCreateMaterialDialog();
                                          if (created == null) return;
                                          setState(() {
                                            _materials = [..._materials, created]
                                              ..sort(
                                                (a, b) => a.displayLabel
                                                    .compareTo(b.displayLabel),
                                              );
                                            _lineItems[i]['materialId'] =
                                                created.id;
                                            _lineItems[i]['materialLabel'] =
                                                created.displayLabel;
                                            _lineItems[i]['itemText'] =
                                                created.displayLabel;
                                          });
                                        },
                                      ),
                                    ),
                                    onChanged: (value) {
                                      item['itemText'] = value;
                                    },
                                  );
                                },
                                optionsViewBuilder:
                                    (context, onSelected, options) {
                                  return Align(
                                    alignment: Alignment.topLeft,
                                    child: Material(
                                      elevation: 4,
                                      borderRadius: BorderRadius.circular(4),
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                            maxHeight: 220),
                                        child: ListView.builder(
                                          padding: EdgeInsets.zero,
                                          shrinkWrap: true,
                                          itemCount: options.length,
                                          itemBuilder: (context, index) {
                                            final m = options.elementAt(index);
                                            return ListTile(
                                              dense: true,
                                              title: Text(
                                                m.grade,
                                                style: const TextStyle(
                                                    fontSize: 14),
                                              ),
                                              subtitle: Text(
                                                '${m.form} · ${m.sizeLabel}',
                                              ),
                                              onTap: () => onSelected(m),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Line mill cert',
                              onPressed: () => _pickLineMillCerts(i),
                              icon: const Icon(Icons.attach_file, size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                            ),
                            const SizedBox(width: 4),
                            // Heat/lot before Qty so cost columns align with tool rows.
                            SizedBox(
                              width: 90,
                              child: TextField(
                                decoration: const InputDecoration(
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  labelText: 'Heat/lot',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 12,
                                  ),
                                ),
                                controller: item['heatLotController']
                                    as TextEditingController,
                                onChanged: (v) {
                                  _lineItems[i]['heatLot'] = v;
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 70,
                              child: TextField(
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: const InputDecoration(
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  labelText: 'Qty',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                                controller: item['quantityController']
                                    as TextEditingController,
                                onChanged: (v) {
                                  _lineItems[i]['quantity'] =
                                      num.tryParse(v) ?? 1;
                                  setState(() {});
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: const InputDecoration(
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  labelText: 'Unit',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                                controller: item['unitCostController']
                                    as TextEditingController,
                                onChanged: (v) {
                                  _lineItems[i]['unitCost'] =
                                      double.tryParse(v);
                                  setState(() {});
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 110,
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  labelText: 'Subtotal',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                                child: Text(
                                  _lineTotal(i),
                                  style:
                                      Theme.of(context).textTheme.bodyMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ] else if (lineType == 'item') ...[
                            Expanded(
                              flex: 2,
                              child: Autocomplete<Tool>(
                                key: ValueKey('tool_autocomplete_$i'),
                                optionsBuilder: (textValue) =>
                                    _filterTools(textValue.text),
                                displayStringForOption: (t) => t.toolName,
                                onSelected: (tool) {
                                  setState(() {
                                    _lineItems[i]['toolId'] = tool.id;
                                    _lineItems[i]['toolName'] = tool.toolName;
                                    final model = tool.modelNumber;
                                    _lineItems[i]['itemText'] =
                                        (model != null && model.isNotEmpty)
                                            ? '${tool.toolName} ($model)'
                                            : tool.toolName;
                                  });
                                },
                                fieldViewBuilder: (context, controller,
                                    focusNode, onFieldSubmitted) {
                                  final desiredText =
                                      (item['itemText'] as String?) ?? '';
                                  if (controller.text != desiredText) {
                                    controller.text = desiredText;
                                    controller.selection =
                                        TextSelection.fromPosition(
                                      TextPosition(
                                          offset: controller.text.length),
                                    );
                                  }
                                  return TextField(
                                    controller: controller,
                                    focusNode: focusNode,
                                    decoration: const InputDecoration(
                                      floatingLabelBehavior:
                                          FloatingLabelBehavior.always,
                                      labelText: 'Item',
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      suffixIcon: Icon(Icons.search, size: 20),
                                    ),
                                    onChanged: (value) {
                                      item['itemText'] = value;
                                    },
                                  );
                                },
                                optionsViewBuilder:
                                    (context, onSelected, options) {
                                  return Align(
                                    alignment: Alignment.topLeft,
                                    child: Material(
                                      elevation: 4,
                                      borderRadius: BorderRadius.circular(4),
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                            maxHeight: 220),
                                        child: ListView.builder(
                                          padding: EdgeInsets.zero,
                                          shrinkWrap: true,
                                          itemCount: options.length,
                                          itemBuilder: (context, index) {
                                            final t = options.elementAt(index);
                                            return ListTile(
                                              dense: true,
                                              title: Text(
                                                t.toolName,
                                                style: const TextStyle(
                                                    fontSize: 14),
                                              ),
                                              subtitle: t.modelNumber != null
                                                  ? Text(
                                                      t.modelNumber!,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            color: Theme.of(
                                                                    context)
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                          ),
                                                    )
                                                  : null,
                                              onTap: () => onSelected(t),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 70,
                              child: TextField(
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  labelText: 'Qty',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                                controller: item['quantityController']
                                    as TextEditingController,
                                onChanged: (v) {
                                  _lineItems[i]['quantity'] =
                                      int.tryParse(v) ?? 1;
                                  setState(() {});
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: const InputDecoration(
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  labelText: 'Unit',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                                controller: item['unitCostController']
                                    as TextEditingController,
                                onChanged: (v) {
                                  _lineItems[i]['unitCost'] =
                                      double.tryParse(v);
                                  setState(() {});
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 110,
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  labelText: 'Subtotal',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                                child: Text(
                                  _lineTotal(i),
                                  style:
                                      Theme.of(context).textTheme.bodyMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ] else if (lineType == 'misc') ...[
                            Expanded(
                              flex: 2,
                              child: TextField(
                                decoration: const InputDecoration(
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  labelText: 'Description',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                                controller: item['descriptionController']
                                    as TextEditingController,
                                onChanged: (v) {
                                  _lineItems[i]['description'] = v;
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 70,
                              child: TextField(
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: const InputDecoration(
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  labelText: 'Qty',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                                controller: item['quantityController']
                                    as TextEditingController,
                                onChanged: (v) {
                                  _lineItems[i]['quantity'] =
                                      num.tryParse(v) ?? 1;
                                  setState(() {});
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: const InputDecoration(
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  labelText: 'Unit',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                                controller: item['unitCostController']
                                    as TextEditingController,
                                onChanged: (v) {
                                  _lineItems[i]['unitCost'] =
                                      double.tryParse(v);
                                  setState(() {});
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 110,
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  labelText: 'Subtotal',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                                child: Text(
                                  _lineTotal(i),
                                  style:
                                      Theme.of(context).textTheme.bodyMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ] else ...[
                            Expanded(
                              child: TextField(
                                decoration: const InputDecoration(
                                  floatingLabelBehavior: FloatingLabelBehavior.always,
                                  labelText: 'Shipping',
                                  border: OutlineInputBorder(),
                                ),
                                controller: TextEditingController(
                                  text: item['description'] as String? ?? '',
                                ),
                                onChanged: (v) {
                                  _lineItems[i]['description'] = v;
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 110,
                              child: TextField(
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  floatingLabelBehavior: FloatingLabelBehavior.always,
                                  labelText: 'Subtotal',
                                  prefixText: '\$',
                                  border: OutlineInputBorder(),
                                ),
                                controller: item['unitCostController'] as TextEditingController,
                                onChanged: (v) {
                                  _lineItems[i]['unitCost'] = double.tryParse(v);
                                  _lineItems[i]['quantity'] = 1;
                                  setState(() {});
                                },
                                onEditingComplete: () {
                                  final ctrl = item['unitCostController'] as TextEditingController;
                                  final parsed = double.tryParse(ctrl.text);
                                  if (parsed != null) {
                                    final formatted = parsed.toStringAsFixed(2);
                                    if (ctrl.text != formatted) {
                                      ctrl.text = formatted;
                                      ctrl.selection = TextSelection.fromPosition(
                                        TextPosition(offset: ctrl.text.length),
                                      );
                                    }
                                  }
                                },
                                onSubmitted: (_) {
                                  final ctrl = item['unitCostController'] as TextEditingController;
                                  final parsed = double.tryParse(ctrl.text);
                                  if (parsed != null) {
                                    final formatted = parsed.toStringAsFixed(2);
                                    if (ctrl.text != formatted) {
                                      ctrl.text = formatted;
                                      ctrl.selection = TextSelection.fromPosition(
                                        TextPosition(offset: ctrl.text.length),
                                      );
                                    }
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          // Fixed-width button column: always reserves space for both icons
                          SizedBox(
                            width: 52,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 18),
                                  onPressed: () {
                                    // Clean up controllers for this line before removing it
                                    final removed = _lineItems.removeAt(i);
                                    final qtyCtrl = removed['quantityController'];
                                    if (qtyCtrl is TextEditingController) {
                                      qtyCtrl.dispose();
                                    }
                                    final unitCtrl = removed['unitCostController'];
                                    if (unitCtrl is TextEditingController) {
                                      unitCtrl.dispose();
                                    }
                                    final heatCtrl = removed['heatLotController'];
                                    if (heatCtrl is TextEditingController) {
                                      heatCtrl.dispose();
                                    }
                                    final descCtrl =
                                        removed['descriptionController'];
                                    if (descCtrl is TextEditingController) {
                                      descCtrl.dispose();
                                    }
                                    setState(() {});
                                  },
                                  tooltip: 'Remove line',
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                const SizedBox(width: 8),
                                Opacity(
                                  opacity: i == _lineItems.length - 1 ? 1.0 : 0.0,
                                  child: IconButton(
                                    icon: const Icon(Icons.add, size: 18),
                                    onPressed: i == _lineItems.length - 1 ? _addLine : null,
                                    tooltip: 'Add line item',
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                          if (lineType == 'material') ...[
                            Builder(
                              builder: (context) {
                                final chips = _buildMaterialLineMillCertChips(i);
                                if (chips == null) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: chips,
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  // Summary: GST/PST/USD toggles; amounts listed under Items/Shipping.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: _gstChecked,
                                onChanged: (v) => setState(() {
                                  _gstChecked = v == true;
                                  // Manual toggle drops invoice lock → use rate.
                                  _gstAmountOverride = null;
                                }),
                              ),
                              const Text('GST'),
                              const SizedBox(width: 16),
                              Checkbox(
                                value: _pstChecked,
                                onChanged: (v) => setState(() {
                                  _pstChecked = v == true;
                                  _pstAmountOverride = null;
                                }),
                              ),
                              const Text('PST'),
                              const SizedBox(width: 16),
                              Checkbox(
                                value: _currency == 'USD',
                                onChanged: (v) => setState(
                                  () => _currency = v == true ? 'USD' : 'CAD',
                                ),
                              ),
                              const Text('USD'),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('Items: ${_money(_subtotalItems())}'),
                          Text('Shipping: ${_money(_shippingTotal())}'),
                          if (_gstChecked)
                            Text(
                              'GST: ${_money(_gstAmount())}',
                            ),
                          if (_pstChecked)
                            Text(
                              'PST: ${_money(_pstAmount())}',
                            ),
                          const SizedBox(height: 4),
                          Text(
                            'Total: ${_money(_subtotalItems() + _totalTaxAndShipping())}',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      const SizedBox(width: 52),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Attachments',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _isLoadingData || _uploadingCerts
                            ? null
                            : _pickMillCerts,
                        icon: _uploadingCerts
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.attach_file),
                        label: const Text('Add attachment'),
                      ),
                      for (final name in _existingCertNames)
                        InputChip(
                          label: Text(name, overflow: TextOverflow.ellipsis),
                          avatar: const Icon(Icons.picture_as_pdf, size: 18),
                          onPressed: () => _openCert(name),
                          onDeleted: () => _removeCert(name),
                        ),
                      for (var i = 0; i < _pendingCerts.length; i++)
                        InputChip(
                          label: Text(
                            '${_pendingCerts[i].name} (pending)',
                            overflow: TextOverflow.ellipsis,
                          ),
                          avatar: const Icon(Icons.schedule, size: 18),
                          onDeleted: () {
                            setState(() => _pendingCerts.removeAt(i));
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton(
                        onPressed: _isLoadingData ? null : _save,
                        child: const Text('Save purchase'),
                      ),
                      if (widget.purchase != null) ...[
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _isLoadingData ? null : _delete,
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
                  const SizedBox(height: 24),
                ],
          ),
        ),
      ),
    );
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
        leading: workspaceMenuLeading(context),
      ),
      body: form,
    );
  }
}

class _SupplierNone {
  const _SupplierNone();
}
