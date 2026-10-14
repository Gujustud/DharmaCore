import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'workspace_layout.dart';
import 'workspace_scaffold.dart';
import 'auth_service.dart';
import 'drawer_behavior.dart';
import 'material_lot_picker.dart';
import 'part_images_panel.dart';
import 'pocketbase_service.dart';
import 'quote_detail_screen.dart';
import 'quote_sidebar.dart';
import 'supplier_search_field.dart';
import 'tracking_link.dart';
import 'ui_breakpoints.dart';

/// Job workspace aligned with DharmaCore `JobDetail.jsx` (see `c:\dharmacore\frontend\src\pages\JobDetail.jsx`):
/// Notion-style detail rows + images/notes column for existing jobs. New jobs keep a full editor form.
class JobDetailScreen extends StatefulWidget {
  final dynamic job;

  const JobDetailScreen({super.key, this.job});

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> with AutoOpenDrawerMixin {
  static const _statusOptions = [
    ('planning', 'Planning'),
    ('in_progress', 'In Progress'),
    ('done', 'Done'),
    ('cancelled', 'Cancelled'),
  ];

  static const _trackingStatusOptions = [
    ('not_shipped', 'Not shipped'),
    ('in_transit', 'In transit'),
    ('delivered', 'Delivered'),
  ];

  final _jobNumberController = TextEditingController();
  final _customerNameController = TextEditingController();
  final _partsDescriptionController = TextEditingController();
  final _dueDateController = TextEditingController();
  final _completionDateController = TextEditingController();
  final _shipDateController = TextEditingController();
  final _deliveredDateController = TextEditingController();
  final _trackingNumber1Controller = TextEditingController();
  final _trackingLink1Controller = TextEditingController();
  final _trackingNumber2Controller = TextEditingController();
  final _trackingLink2Controller = TextEditingController();
  final _waveInvoiceNumberController = TextEditingController();
  final _poNumberController = TextEditingController();
  final _materialLotController = TextEditingController();
  final _materialSourceController = TextEditingController();
  final _projectNotesController = TextEditingController();

  List<dynamic> _customers = [];
  List<dynamic> _quotes = [];
  List<dynamic> _suppliers = [];
  String? _customerId;
  String? _quoteId;
  String? _materialSourceVendorId;
  /// Linked purchase line for mill cert PDFs (`jobs.material_purchase_item`).
  String? _materialPurchaseItemId;
  MaterialLotPick? _materialLotPick;
  String _status = 'planning';
  String _trackingStatus = 'not_shipped';
  bool _loading = true;
  bool _isSaving = false;
  bool _showTracking2 = false;
  List<String> _partImages = [];

  /// Fresh record from server (expand, created, updated); null while new job.
  dynamic _record;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  GlobalKey<ScaffoldState> get scaffoldKey => _scaffoldKey;

  bool get _isNew => widget.job == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? _relationId(dynamic v) {
    if (v == null || v.toString().isEmpty) return null;
    if (v is String) return v;
    if (v is Map && v['id'] != null) return v['id'].toString();
    return v.toString();
  }

  void _setDate(TextEditingController c, dynamic v) {
    if (v == null || v.toString().isEmpty) return;
    try {
      c.text = DateFormat('yyyy-MM-dd').format(DateTime.parse(v.toString()));
    } catch (_) {
      c.text = v.toString();
    }
  }

  void _populateFromRecord(Map<String, dynamic> d) {
    _jobNumberController.text = '${d['job_number'] ?? ''}';
    _customerNameController.text = '${d['customer_name'] ?? ''}';
    _partsDescriptionController.text = '${d['parts_description'] ?? ''}';
    _customerId = _relationId(d['customer']);
    _quoteId = _relationId(d['quote']);
    _materialSourceVendorId = _relationId(d['material_source_vendor']);

    final st = '${d['status'] ?? 'planning'}';
    _status = _statusOptions.any((o) => o.$1 == st) ? st : 'planning';

    final ts = '${d['tracking_status'] ?? 'not_shipped'}';
    _trackingStatus = _trackingStatusOptions.any((o) => o.$1 == ts) ? ts : 'not_shipped';

    _setDate(_dueDateController, d['due_date']);
    _setDate(_completionDateController, d['completion_date']);
    _setDate(_shipDateController, d['ship_date']);
    _setDate(_deliveredDateController, d['delivered_date']);

    _trackingNumber1Controller.text = '${d['tracking_number_1'] ?? ''}';
    _trackingLink1Controller.text = '${d['tracking_link_1'] ?? ''}';
    _trackingNumber2Controller.text = '${d['tracking_number_2'] ?? ''}';
    _trackingLink2Controller.text = '${d['tracking_link_2'] ?? ''}';
    _waveInvoiceNumberController.text = '${d['wave_invoice_number'] ?? ''}';
    _poNumberController.text = '${d['po_number'] ?? ''}';
    _materialLotController.text = '${d['material_lot'] ?? ''}';
    _materialSourceController.text = '${d['material_source'] ?? ''}';
    _projectNotesController.text = '${d['project_notes'] ?? ''}';
    _partImages = PartImagesPanel.normalizeFilenames(d['part_images']);
    _showTracking2 = _trackingNumber2Controller.text.trim().isNotEmpty;
    _hydrateMaterialLotFromRecord(d);
  }

  void _hydrateMaterialLotFromRecord(Map<String, dynamic> d) {
    _materialPurchaseItemId = _relationId(d['material_purchase_item']);
    _materialLotPick = null;
    try {
      final expand = _record?.expand?['material_purchase_item'];
      final raw = (expand is List && expand.isNotEmpty) ? expand.first : expand;
      if (raw != null) {
        final pick = MaterialLotPick.fromRecord(raw);
        if (pick.heatLot.isNotEmpty) {
          _materialLotPick = pick;
          _materialPurchaseItemId = pick.purchaseItemId;
          if (_materialLotController.text.trim().isEmpty) {
            _materialLotController.text = pick.heatLot;
          }
        }
      }
    } catch (_) {}
    // Expand missing (older list payload) — fetch linked line for cert chips.
    if (_materialLotPick == null &&
        _materialPurchaseItemId != null &&
        _materialPurchaseItemId!.isNotEmpty) {
      _loadLinkedMaterialLot(_materialPurchaseItemId!);
    }
  }

  Future<void> _loadLinkedMaterialLot(String purchaseItemId) async {
    try {
      final record = await PocketBaseService().getPurchaseItem(purchaseItemId);
      if (!mounted) return;
      final pick = MaterialLotPick.fromRecord(record);
      if (pick.heatLot.isEmpty) return;
      setState(() {
        _materialLotPick = pick;
        _materialPurchaseItemId = pick.purchaseItemId;
        if (_materialLotController.text.trim().isEmpty) {
          _materialLotController.text = pick.heatLot;
        }
      });
    } catch (_) {}
  }

  Future<void> _pickMaterialLot() async {
    final picked = await showMaterialLotPicker(
      context,
      selectedPurchaseItemId: _materialPurchaseItemId,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _materialLotPick = picked;
      _materialPurchaseItemId = picked.purchaseItemId;
      _materialLotController.text = picked.heatLot;
      if (picked.supplierId != null &&
          picked.supplierId!.isNotEmpty &&
          (_materialSourceVendorId == null ||
              _materialSourceVendorId!.isEmpty)) {
        _materialSourceVendorId = picked.supplierId;
      }
    });
  }

  void _clearMaterialLot() {
    setState(() {
      _materialLotPick = null;
      _materialPurchaseItemId = null;
      _materialLotController.clear();
    });
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

  Widget _materialLotPickerField(BuildContext context, {bool compact = false}) {
    final scheme = Theme.of(context).colorScheme;
    final lotText = _materialLotController.text.trim();
    final hasLink = _materialPurchaseItemId != null;
    final label = lotText.isNotEmpty
        ? lotText
        : (hasLink ? 'Linked lot' : 'Select heat/lot…');
    final subtitle = _materialLotPick == null
        ? null
        : [
            _materialLotPick!.materialLabel,
            if (_materialLotPick!.supplierName.isNotEmpty)
              _materialLotPick!.supplierName,
          ].join(' · ');
    final certs = _materialLotPick?.millCertNames ?? const <String>[];
    final certRecord = _materialLotPick?.record;

    final field = InputDecorator(
      decoration: (compact
              ? QuoteSidebarTheme.fieldDecoration(context).copyWith(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                )
              : QuoteSidebarTheme.fieldDecoration(context))
          .copyWith(
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (lotText.isNotEmpty || hasLink)
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.clear, size: 18),
                onPressed: _clearMaterialLot,
              ),
            IconButton(
              tooltip: 'Search lots',
              icon: const Icon(Icons.search, size: 20),
              onPressed: _pickMaterialLot,
            ),
          ],
        ),
      ),
      child: InkWell(
        onTap: _pickMaterialLot,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: compact ? 14 : 15,
                  color: lotText.isEmpty && !hasLink
                      ? scheme.onSurfaceVariant
                      : null,
                  fontWeight:
                      lotText.isNotEmpty ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field,
        if (certs.isNotEmpty && certRecord != null) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final name in certs)
                ActionChip(
                  avatar: const Icon(Icons.picture_as_pdf, size: 16),
                  label: Text(name, overflow: TextOverflow.ellipsis),
                  onPressed: () => _openMillCert(certRecord, name),
                ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    for (final c in [
      _jobNumberController,
      _customerNameController,
      _partsDescriptionController,
      _dueDateController,
      _completionDateController,
      _shipDateController,
      _deliveredDateController,
      _trackingNumber1Controller,
      _trackingLink1Controller,
      _trackingNumber2Controller,
      _trackingLink2Controller,
      _waveInvoiceNumberController,
      _poNumberController,
      _materialLotController,
      _materialSourceController,
      _projectNotesController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pb = PocketBaseService();
      if (!_isNew && widget.job != null) {
        try {
          _record = await pb.getJob(widget.job.id as String);
          _populateFromRecord(_record.data as Map<String, dynamic>? ?? {});
        } catch (_) {
          _record = widget.job;
          _populateFromRecord(widget.job.data as Map<String, dynamic>? ?? {});
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not refresh job; showing cached data.')),
            );
          }
        }
      } else {
        _record = null;
      }

      final results = await Future.wait([
        pb.getCustomers(),
        pb.getQuotes(),
        pb.getSuppliers(),
      ]);
      if (mounted) {
        setState(() {
          _customers = results[0];
          _quotes = results[1];
          _suppliers = results[2];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _quoteLabel(dynamic quote) {
    final d = quote.data as Map<String, dynamic>? ?? {};
    final jn = '${d['job_number'] ?? ''}'.trim();
    if (jn.isNotEmpty) return jn;
    return quote.id.toString();
  }

  String _customerLabel(dynamic c) {
    final d = c.data as Map<String, dynamic>? ?? {};
    return '${d['company'] ?? d['name'] ?? c.id}'.trim();
  }

  Map<String, dynamic>? _expandData(dynamic expanded) {
    if (expanded == null) return null;
    if (expanded is List && expanded.isNotEmpty) {
      return expanded.first.data as Map<String, dynamic>?;
    }
    if (expanded.data != null) {
      return expanded.data as Map<String, dynamic>?;
    }
    return null;
  }

  dynamic _expandedQuote() {
    final record = _record;
    if (record == null) return null;
    final expand = record.expand;
    if (expand == null || expand['quote'] == null) return null;
    final q = expand['quote'];
    if (q is List && q.isNotEmpty) return q.first;
    return q;
  }

  String? _linkedQuoteDisplayLabel() {
    final q = _expandedQuote();
    if (q != null) return _quoteLabel(q);
    if (_quoteId == null) return null;
    try {
      final match = _quotes.where((x) => x.id == _quoteId);
      if (match.isEmpty) return 'Quote $_quoteId';
      return _quoteLabel(match.first);
    } catch (_) {
      return 'Quote';
    }
  }

  String? _formatStamp(dynamic raw) {
    if (raw == null || '$raw'.isEmpty) return null;
    try {
      return DateFormat.yMMMd().add_jm().format(DateTime.parse(raw.toString()));
    } catch (_) {
      return raw.toString();
    }
  }

  void _onQuoteChanged(String? quoteId) {
    setState(() {
      _quoteId = quoteId;
      if (quoteId == null) return;
      final match = _quotes.where((q) => q.id == quoteId);
      if (match.isEmpty) return;
      final qData = match.first.data as Map<String, dynamic>? ?? {};
      final custFromQuote = _relationId(qData['customer']);
      if (custFromQuote != null) {
        _customerId = custFromQuote;
      }
      final cn = '${qData['customer_name'] ?? ''}'.trim();
      if (cn.isNotEmpty) {
        _customerNameController.text = cn;
      }
    });
  }

  String? _optText(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  /// Parse flexible user input into a date, or null if empty/invalid.
  /// Accepts `yyyy-MM-dd`, `yyyy-M-d`, `M/d/yyyy`, `MM/dd/yyyy`.
  DateTime? _parseFlexibleDate(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;

    DateTime? tryFmt(String pattern) {
      try {
        return DateFormat(pattern).parseStrict(t);
      } catch (_) {
        return null;
      }
    }

    return tryFmt('yyyy-MM-dd') ??
        tryFmt('yyyy-M-d') ??
        tryFmt('M/d/yyyy') ??
        tryFmt('MM/dd/yyyy') ??
        (() {
          try {
            return DateTime.parse(t);
          } catch (_) {
            return null;
          }
        })();
  }

  /// Normalize controller text to `yyyy-MM-dd`. Returns false if non-empty but invalid.
  bool _normalizeDateField(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) {
      if (c.text.isNotEmpty) c.text = '';
      return true;
    }
    final d = _parseFlexibleDate(t);
    if (d == null) return false;
    final normalized = DateFormat('yyyy-MM-dd').format(d);
    if (c.text != normalized) c.text = normalized;
    return true;
  }

  String? _optDate(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    final d = _parseFlexibleDate(t);
    if (d == null) return t; // leave as-is; save validates first
    return DateFormat('yyyy-MM-dd').format(d);
  }

  Map<String, dynamic> _buildBody() {
    return {
      'job_number': _jobNumberController.text.trim(),
      'status': _status,
      'tracking_status': _trackingStatus,
      'customer': _customerId,
      'quote': _quoteId,
      'material_source_vendor': _materialSourceVendorId,
      'customer_name': _optText(_customerNameController),
      'parts_description': _optText(_partsDescriptionController),
      'due_date': _optDate(_dueDateController),
      'completion_date': _optDate(_completionDateController),
      'ship_date': _optDate(_shipDateController),
      'delivered_date': _optDate(_deliveredDateController),
      'tracking_number_1': _optText(_trackingNumber1Controller),
      'tracking_link_1': _optText(_trackingLink1Controller),
      'tracking_number_2': _optText(_trackingNumber2Controller),
      'tracking_link_2': _optText(_trackingLink2Controller),
      'wave_invoice_number': _optText(_waveInvoiceNumberController),
      'po_number': _optText(_poNumberController),
      'material_lot': _optText(_materialLotController),
      'material_purchase_item': _materialPurchaseItemId,
      'material_source': _optText(_materialSourceController),
      'project_notes': _optText(_projectNotesController),
    };
  }

  Future<void> _save() async {
    if (_jobNumberController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job number is required')),
      );
      return;
    }

    final dateFields = [
      ('Due date', _dueDateController),
      ('Completion date', _completionDateController),
      ('Ship date', _shipDateController),
      ('Delivered date', _deliveredDateController),
    ];
    for (final (label, c) in dateFields) {
      if (!_normalizeDateField(c)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$label must be a valid date (yyyy-mm-dd or m/d/yyyy)',
            ),
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      final pb = PocketBaseService();
      final body = _buildBody();
      if (_isNew) {
        await pb.createJob(body);
      } else {
        await pb.updateJob(widget.job.id, body);
      }
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isNew ? 'Job added' : 'Job updated'),
            backgroundColor: Colors.green,
          ),
        );
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

  Future<void> _openLinkedQuote() async {
    final id = _quoteId;
    if (id == null || id.isEmpty) return;
    try {
      final q = await PocketBaseService().getQuote(id);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (context) => QuoteDetailScreen(quote: q)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open quote: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmDelete() async {
    if (_isNew || widget.job == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete job'),
        content: const Text('Are you sure you want to delete this job?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _isSaving = true);
    try {
      await PocketBaseService().deleteJob(widget.job.id as String);
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Job deleted'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Color _labelColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFD1D5DB)
        : const Color(0xFF374151);
  }

  Widget _labeledField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: _labelColor(context),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 15),
          decoration: QuoteSidebarTheme.fieldDecoration(context),
        ),
      ],
    );
  }

  InputDecoration _dropdownDecoration(BuildContext context) {
    return QuoteSidebarTheme.fieldDecoration(context).copyWith(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }

  Color _notionDividerColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF374151)
        : const Color(0xFFF3F4F6);
  }

  TextStyle _notionLabelStyle(BuildContext context) {
    return TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF9CA3AF)
          : const Color(0xFF6B7280),
    );
  }

  Widget _notionRow(
    BuildContext context,
    String label,
    Widget child, {
    bool showDivider = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 140, child: Text(label, style: _notionLabelStyle(context))),
              Expanded(child: child),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: _notionDividerColor(context)),
      ],
    );
  }

  ({Color bg, Color border, Color fg}) _statusPillPalette(String v, bool dark) {
    switch (v) {
      case 'planning':
        return dark
            ? (bg: const Color(0xFF2563EB), border: const Color(0xFF3B82F6), fg: Colors.white)
            : (bg: const Color(0xFFEFF6FF), border: const Color(0xFFBFDBFE), fg: const Color(0xFF1E40AF));
      case 'in_progress':
        return dark
            ? (bg: const Color(0xFFD97706), border: const Color(0xFFF59E0B), fg: Colors.white)
            : (bg: const Color(0xFFFFFBEB), border: const Color(0xFFFDE68A), fg: const Color(0xFF92400E));
      case 'done':
        return dark
            ? (bg: const Color(0xFF16A34A), border: const Color(0xFF22C55E), fg: Colors.white)
            : (bg: const Color(0xFFF0FDF4), border: const Color(0xFFBBF7D0), fg: const Color(0xFF166534));
      case 'cancelled':
      default:
        return dark
            ? (bg: const Color(0xFF4B5563), border: const Color(0xFF6B7280), fg: Colors.white)
            : (bg: const Color(0xFFF3F4F6), border: const Color(0xFFE5E7EB), fg: const Color(0xFF374151));
    }
  }

  ({Color bg, Color border, Color fg}) _trackingPillPalette(String v, bool dark) {
    switch (v) {
      case 'in_transit':
        return dark
            ? (bg: const Color(0xFFD97706), border: const Color(0xFFF59E0B), fg: Colors.white)
            : (bg: const Color(0xFFFFFBEB), border: const Color(0xFFFDE68A), fg: const Color(0xFF92400E));
      case 'delivered':
        return dark
            ? (bg: const Color(0xFF16A34A), border: const Color(0xFF22C55E), fg: Colors.white)
            : (bg: const Color(0xFFF0FDF4), border: const Color(0xFFBBF7D0), fg: const Color(0xFF166534));
      case 'not_shipped':
      default:
        return dark
            ? (bg: const Color(0xFF4B5563), border: const Color(0xFF6B7280), fg: Colors.white)
            : (bg: const Color(0xFFF3F4F6), border: const Color(0xFFE5E7EB), fg: const Color(0xFF374151));
    }
  }

  Widget _jobStatusPill(BuildContext context, String value, String label) {
    final selected = _status == value;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = _statusPillPalette(value, dark);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => setState(() => _status = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? QuoteSidebarTheme.primary(context) : c.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.fg),
          ),
        ),
      ),
    );
  }

  Widget _jobTrackingPill(BuildContext context, String value, String label) {
    final selected = _trackingStatus == value;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = _trackingPillPalette(value, dark);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => setState(() => _trackingStatus = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? QuoteSidebarTheme.primary(context) : c.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.fg),
          ),
        ),
      ),
    );
  }

  String _displayTrackingUrl(String number, TextEditingController manualLink) {
    final auto = generateTrackingLink(number);
    if (auto.isNotEmpty) return auto;
    return manualLink.text.trim();
  }

  String _shortLinkLabel(String url, int maxLen) {
    if (url.length <= maxLen) return url;
    return '${url.substring(0, maxLen - 1)}…';
  }

  Future<void> _openExternalUrl(String url) async {
    final u = Uri.tryParse(url);
    if (u == null || !u.hasScheme) return;
    if (await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _pickJobDate(BuildContext context, TextEditingController c) async {
    var initial = DateTime.now();
    final parsed = _parseFlexibleDate(c.text);
    if (parsed != null) initial = parsed;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => c.text = DateFormat('yyyy-MM-dd').format(picked));
    }
  }

  /// Editable date + calendar button. Type `yyyy-mm-dd` / `m/d/yyyy`, or pick.
  Widget _jobDateField(BuildContext context, TextEditingController c) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? const Color(0xFF4B5563) : const Color(0xFFD1D5DB);
    final fieldDeco = QuoteSidebarTheme.fieldDecoration(context).copyWith(
      hintText: 'yyyy-mm-dd',
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: c,
              enabled: !_isSaving,
              style: const TextStyle(fontSize: 14),
              keyboardType: TextInputType.datetime,
              decoration: fieldDeco,
              onEditingComplete: () {
                _normalizeDateField(c);
                FocusScope.of(context).unfocus();
              },
              onTapOutside: (_) => _normalizeDateField(c),
            ),
          ),
          const SizedBox(width: 6),
          Material(
            color: isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: _isSaving ? null : () => _pickJobDate(context, c),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor, width: 1.5),
                ),
                child: Icon(
                  Icons.calendar_today_outlined,
                  size: 18,
                  color: isDark ? Colors.white70 : const Color(0xFF4B5563),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact secondary action (DharmaCore header `Button variant="secondary"`).
  Widget _headerActionButton(
    BuildContext context, {
    required String label,
    VoidCallback? onPressed,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(
          color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF9CA3AF),
        ),
        backgroundColor: isDark ? const Color(0xFF6B7280) : const Color(0xFFE5E7EB),
        foregroundColor: isDark ? Colors.white : const Color(0xFF1F2937),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),
    );
  }

  String _customerSubtitle() {
    if (_record != null && _record.expand != null) {
      final map = _expandData(_record.expand['customer']);
      if (map != null) {
        final co = '${map['company'] ?? ''}'.trim();
        if (co.isNotEmpty) return co;
        final na = '${map['name'] ?? ''}'.trim();
        if (na.isNotEmpty) return na;
      }
    }
    final snap = _customerNameController.text.trim();
    if (snap.isNotEmpty) return snap;
    return '—';
  }

  String? _expandedMaterialVendorName() {
    if (_record == null || _record.expand == null) return null;
    final v = _record.expand['material_source_vendor'];
    final m = _expandData(v);
    if (m == null) return null;
    return '${m['company_name'] ?? m['name'] ?? ''}'.trim();
  }

  Widget _existingJobHeaderBar(BuildContext context) {
    final jn = _jobNumberController.text.trim();
    final narrow = MediaQuery.sizeOf(context).width < 640;

    final actions = [
      if (!AuthService.instance.isJobsOnly &&
          _quoteId != null &&
          _quoteId!.isNotEmpty)
        _headerActionButton(
          context,
          label: 'View Quote →',
          onPressed: _isSaving ? null : _openLinkedQuote,
        ),
      _headerActionButton(
        context,
        label: 'Back to Jobs',
        onPressed: _isSaving ? null : () => Navigator.maybePop(context),
      ),
      _headerActionButton(
        context,
        label: _isSaving ? 'Saving…' : 'Save',
        onPressed: _isSaving ? null : _save,
      ),
      _headerActionButton(
        context,
        label: 'Delete job',
        onPressed: _isSaving ? null : _confirmDelete,
      ),
    ];

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Job: ${jn.isEmpty ? '—' : jn}',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          _customerSubtitle(),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72),
              ),
        ),
      ],
    );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titleBlock,
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titleBlock),
        const SizedBox(width: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: actions,
        ),
      ],
    );
  }

  Widget _dharmaLeftDetailsCard(BuildContext context) {
    final link1 = _displayTrackingUrl(_trackingNumber1Controller.text, _trackingLink1Controller);
    final link2 = _displayTrackingUrl(_trackingNumber2Controller.text, _trackingLink2Controller);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _notionRow(
              context,
              'Status',
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _statusOptions
                    .map((o) => _jobStatusPill(context, o.$1, o.$2))
                    .toList(),
              ),
            ),
            _notionRow(context, 'Due Date', _jobDateField(context, _dueDateController)),
            _notionRow(context, 'Completion', _jobDateField(context, _completionDateController)),
            _notionRow(context, 'Ship Date', _jobDateField(context, _shipDateController)),
            _notionRow(context, 'Delivered Date', _jobDateField(context, _deliveredDateController)),
            _notionRow(
              context,
              'Tracking Status',
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _trackingStatusOptions
                    .map((o) => _jobTrackingPill(context, o.$1, o.$2))
                    .toList(),
              ),
            ),
            _notionRow(
              context,
              '# Tracking Number',
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: TextField(
                  controller: _trackingNumber1Controller,
                  style: const TextStyle(fontSize: 14),
                  decoration: QuoteSidebarTheme.fieldDecoration(context).copyWith(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            _notionRow(
              context,
              'Tracking Link',
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: link1.isEmpty
                        ? Text(
                            'Empty',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? const Color(0xFF9CA3AF)
                                  : const Color(0xFF9CA3AF),
                            ),
                          )
                        : InkWell(
                            onTap: () => _openExternalUrl(link1),
                            child: Text(
                              _shortLinkLabel(link1, 45),
                              style: TextStyle(
                                fontSize: 14,
                                color: QuoteSidebarTheme.primary(context),
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _showTracking2 = !_showTracking2),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(_showTracking2 ? '− Hide 2nd' : '+ Add 2nd'),
                  ),
                ],
              ),
            ),
            if (_showTracking2) ...[
              _notionRow(
                context,
                'Tracking 2',
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: TextField(
                    controller: _trackingNumber2Controller,
                    style: const TextStyle(fontSize: 14),
                    decoration: QuoteSidebarTheme.fieldDecoration(context).copyWith(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              _notionRow(
                context,
                'Tracking Link 2',
                link2.isEmpty
                    ? const SizedBox.shrink()
                    : InkWell(
                        onTap: () => _openExternalUrl(link2),
                        child: Text(
                          _shortLinkLabel(link2, 45),
                          style: TextStyle(
                            fontSize: 14,
                            color: QuoteSidebarTheme.primary(context),
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
              ),
            ],
            _notionRow(
              context,
              'Invoice',
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: TextField(
                  controller: _waveInvoiceNumberController,
                  style: const TextStyle(fontSize: 14),
                  decoration: QuoteSidebarTheme.fieldDecoration(context).copyWith(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
            ),
            _notionRow(
              context,
              'PO #',
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: TextField(
                  controller: _poNumberController,
                  style: const TextStyle(fontSize: 14),
                  decoration: QuoteSidebarTheme.fieldDecoration(context).copyWith(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
            ),
            _notionRow(
              context,
              'Material LOT',
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: _materialLotPickerField(context, compact: true),
              ),
            ),
            _notionRow(
              context,
              'Material source',
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: SupplierSearchField(
                  suppliers: _suppliers,
                  selectedSupplierId: _materialSourceVendorId,
                  selectedLabelFallback: _expandedMaterialVendorName(),
                  noneOptionLabel: '— Select vendor —',
                  decoration: _dropdownDecoration(context),
                  onSupplierSelected: (id) => setState(() => _materialSourceVendorId = id),
                ),
              ),
              showDivider: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _dharmaRightColumn(BuildContext context) {
    final parts = _partsDescriptionController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: PartImagesPanel(
              recordId: widget.job?.id as String?,
              collectionName: 'jobs',
              filenames: _partImages,
              fillHeight: false,
              onFilenamesChanged: (list) => setState(() => _partImages = list),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notes',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _labelColor(context),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Project notes',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF9CA3AF)
                        : const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _projectNotesController,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 14),
                  decoration: QuoteSidebarTheme.fieldDecoration(context),
                ),
                if (parts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Parts in this job',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF9CA3AF)
                          : const Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF374151)
                          : const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      parts,
                      style: const TextStyle(fontSize: 14, height: 1.35),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExistingJobBody(BuildContext context, {required bool wide}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _existingJobHeaderBar(context),
        const SizedBox(height: 20),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _dharmaLeftDetailsCard(context)),
              const SizedBox(width: 16),
              Expanded(child: _dharmaRightColumn(context)),
            ],
          )
        else ...[
          _dharmaLeftDetailsCard(context),
          const SizedBox(height: 16),
          _dharmaRightColumn(context),
        ],
      ],
    );
  }

  Widget _buildNewJobBody(BuildContext context, {required bool wide}) {
    final mainColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _headerCard(context),
        const SizedBox(height: 16),
        _datesCard(context),
        const SizedBox(height: 16),
        _shippingCard(context),
        const SizedBox(height: 16),
        _materialsCard(context),
        const SizedBox(height: 16),
        _notesImagesCard(context),
      ],
    );
    final sidebar = _sidebar(context);
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: mainColumn),
          const SizedBox(width: 16),
          SizedBox(width: 360, child: sidebar),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        mainColumn,
        const SizedBox(height: 24),
        sidebar,
      ],
    );
  }

  Widget _headerCard(BuildContext context) {
    final customers = [..._customers]..sort((a, b) {
        final an = _customerLabel(a).toLowerCase();
        final bn = _customerLabel(b).toLowerCase();
        return an.compareTo(bn);
      });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _labeledField(
                    context,
                    label: 'Job number *',
                    controller: _jobNumberController,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Quote',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _labelColor(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String?>(
                        key: ValueKey('job_quote_${_quoteId ?? 'none'}'),
                        initialValue:
                            _quoteId != null && _quotes.any((q) => q.id == _quoteId) ? _quoteId : null,
                        decoration: _dropdownDecoration(context),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('— None —')),
                          ..._quotes.map(
                            (q) => DropdownMenuItem<String?>(
                              value: q.id as String,
                              child: Text(_quoteLabel(q)),
                            ),
                          ),
                        ],
                        onChanged: _onQuoteChanged,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Customer',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _labelColor(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String?>(
                        key: ValueKey('job_customer_${_customerId ?? 'none'}'),
                        initialValue: _customerId != null &&
                                customers.any((c) => c.id == _customerId)
                            ? _customerId
                            : null,
                        decoration: _dropdownDecoration(context),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('— None —')),
                          ...customers.map(
                            (c) => DropdownMenuItem<String?>(
                              value: c.id as String,
                              child: Text(_customerLabel(c)),
                            ),
                          ),
                        ],
                        onChanged: (id) {
                          setState(() {
                            _customerId = id;
                            if (id != null) {
                              try {
                                final c = customers.firstWhere((x) => x.id == id);
                                _customerNameController.text = _customerLabel(c);
                              } catch (_) {}
                            }
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _labeledField(
                    context,
                    label: 'Customer name (snapshot)',
                    controller: _customerNameController,
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
                    children: _statusOptions.map((o) {
                      final selected = _status == o.$1;
                      return ChoiceChip(
                        label: Text(o.$2),
                        selected: selected,
                        onSelected: (_) => setState(() => _status = o.$1),
                      );
                    }).toList(),
                  ),
                ),
                if (!_isNew && _record != null)
                  Text(
                    'Updated: ${_formatStamp(_record.updated) ?? '—'}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _labeledField(
              context,
              label: 'Parts description',
              controller: _partsDescriptionController,
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _labeledDateField(BuildContext context, String label, TextEditingController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: _labelColor(context),
          ),
        ),
        const SizedBox(height: 4),
        _jobDateField(context, c),
      ],
    );
  }

  Widget _datesCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dates', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _labeledDateField(context, 'Due date', _dueDateController),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _labeledDateField(context, 'Completion date', _completionDateController),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _labeledDateField(context, 'Ship date', _shipDateController),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _labeledDateField(context, 'Delivered date', _deliveredDateController),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _shippingCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Shipping & tracking', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _trackingStatusOptions.map((o) {
                final selected = _trackingStatus == o.$1;
                return ChoiceChip(
                  label: Text(o.$2),
                  selected: selected,
                  onSelected: (_) => setState(() => _trackingStatus = o.$1),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _labeledField(
                    context,
                    label: 'Tracking number 1',
                    controller: _trackingNumber1Controller,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _labeledField(
                    context,
                    label: 'Tracking link 1',
                    controller: _trackingLink1Controller,
                    keyboardType: TextInputType.url,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _labeledField(
                    context,
                    label: 'Tracking number 2',
                    controller: _trackingNumber2Controller,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _labeledField(
                    context,
                    label: 'Tracking link 2',
                    controller: _trackingLink2Controller,
                    keyboardType: TextInputType.url,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _materialsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Materials & PO', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _labeledField(context, label: 'PO number', controller: _poNumberController),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _labeledField(
                    context,
                    label: 'Wave invoice number',
                    controller: _waveInvoiceNumberController,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Material lot',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _labelColor(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _materialLotPickerField(context),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _labeledField(
                    context,
                    label: 'Material source',
                    controller: _materialSourceController,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Material source vendor',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _labelColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                SupplierSearchField(
                  suppliers: _suppliers,
                  selectedSupplierId: _materialSourceVendorId,
                  selectedLabelFallback: _expandedMaterialVendorName(),
                  decoration: _dropdownDecoration(context),
                  onSupplierSelected: (id) => setState(() => _materialSourceVendorId = id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _notesImagesCard(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 720;
    final notesBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Project notes', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _projectNotesController,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Project notes…',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
    final imagesBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Project images', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        PartImagesPanel(
          recordId: _isNew ? null : (widget.job?.id as String?),
          collectionName: 'jobs',
          filenames: _partImages,
          fillHeight: !narrow,
          onFilenamesChanged: (list) => setState(() => _partImages = list),
        ),
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  notesBlock,
                  const SizedBox(height: 16),
                  imagesBlock,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: notesBlock),
                  const SizedBox(width: 16),
                  Expanded(child: imagesBlock),
                ],
              ),
      ),
    );
  }

  Widget _sidebar(BuildContext context) {
    final quoteLabel = _linkedQuoteDisplayLabel();
    final expandCustomer = _record?.expand != null ? _expandData(_record.expand['customer']) : null;
    String customerSummary = '—';
    if (expandCustomer != null) {
      final co = '${expandCustomer['company'] ?? ''}'.trim();
      final na = '${expandCustomer['name'] ?? ''}'.trim();
      if (co.isNotEmpty) {
        customerSummary = na.isNotEmpty ? '$co · $na' : co;
      } else if (na.isNotEmpty) {
        customerSummary = na;
      }
    } else if (_customerNameController.text.trim().isNotEmpty) {
      customerSummary = _customerNameController.text.trim();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QuoteSidebarCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Job',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: _labelColor(context),
                ),
              ),
              const SizedBox(height: 8),
              Text('Customer: $customerSummary', style: TextStyle(fontSize: 13, color: Colors.grey[800])),
              const SizedBox(height: 4),
              Text(
                'Linked quote: ${quoteLabel ?? '—'}',
                style: TextStyle(fontSize: 13, color: Colors.grey[800]),
              ),
              if (!_isNew && _record != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Created: ${_formatStamp(_record.created) ?? '—'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ],
          ),
        ),
        if (!AuthService.instance.isJobsOnly &&
            _quoteId != null &&
            _quoteId!.isNotEmpty) ...[
          const SizedBox(height: 12),
          QuoteSidebarSecondaryButton(
            label: 'Open quote',
            onPressed: _isSaving ? null : _openLinkedQuote,
          ),
        ],
        const SizedBox(height: 16),
        QuoteSidebarPrimaryButton(
          label: _isSaving ? 'Saving…' : 'Save',
          loading: _isSaving,
          onPressed: _isSaving ? null : _save,
        ),
        if (!_isNew) ...[
          const SizedBox(height: 8),
          QuoteSidebarSecondaryButton(
            label: 'Delete job',
            onPressed: _isSaving ? null : _confirmDelete,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isNew
        ? 'New job'
        : (_jobNumberController.text.trim().isEmpty ? 'Job' : _jobNumberController.text.trim());

    if (_loading) {
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
    final body = _isNew
        ? _buildNewJobBody(context, wide: wide)
        : _buildExistingJobBody(context, wide: wide);

    return WorkspaceScaffold(
      scaffoldKey: _scaffoldKey,
      appBar: AppBar(
        title: _isNew ? Text(title) : null,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: workspaceMenuLeading(context),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: body,
      ),
    );
  }
}
