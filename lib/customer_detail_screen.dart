import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'workspace_layout.dart';
import 'workspace_scaffold.dart';
import 'customer_labels.dart';
import 'drawer_behavior.dart';
import 'job_detail_screen.dart';
import 'pocketbase_service.dart';
import 'quote_detail_screen.dart';
import 'quote_sidebar.dart';
import 'ui_breakpoints.dart';

/// Add or edit a `customers` record (DharmaCore `CustomerDetail.jsx` parity for edit view).
class CustomerDetailScreen extends StatefulWidget {
  /// null = new customer, non-null = edit
  final dynamic customer;

  /// When true, renders as a side panel (no scaffold / route pop).
  final bool embedded;
  final ValueChanged<bool>? onClosed;

  const CustomerDetailScreen({
    super.key,
    this.customer,
    this.embedded = false,
    this.onClosed,
  });

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> with AutoOpenDrawerMixin {
  final _nameController = TextEditingController();
  final _companyController = TextEditingController();
  final _addressController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();
  double _notesBoxHeight = 96;

  bool _isSaving = false;
  bool _loadingRelated = false;
  List<dynamic> _jobs = [];
  List<dynamic> _quotes = [];
  List<dynamic> _shipTos = [];

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  static final _dateDisplay = DateFormat.yMMMd();

  @override
  GlobalKey<ScaffoldState> get scaffoldKey => _scaffoldKey;

  bool get _isNew => widget.customer == null;

  String? get _customerId => _isNew ? null : widget.customer.id as String?;

  @override
  void initState() {
    super.initState();
    if (!_isNew) {
      final d = widget.customer.data as Map<String, dynamic>? ?? {};
      _applyFormFromData(d);
      _loadRelated();
    }
  }

  void _applyFormFromData(Map<String, dynamic> d) {
    _nameController.text = '${d['name'] ?? ''}';
    _companyController.text = '${d['company'] ?? ''}';
    _addressController.text = '${d['address'] ?? ''}';
    _emailController.text = '${d['email'] ?? ''}';
    _phoneController.text = '${d['phone'] ?? ''}';
    _notesController.text = '${d['notes'] ?? ''}';
  }

  Future<void> _loadRelated() async {
    final id = _customerId;
    if (id == null) return;
    setState(() => _loadingRelated = true);
    try {
      final pb = PocketBaseService();
      final results = await Future.wait([
        pb.getCustomer(id),
        pb.getJobsForCustomer(id),
        pb.getQuotesForCustomer(id),
        pb.getCustomerShipTos(id),
      ]);
      if (!mounted) return;
      final customer = results[0];
      final jobs = results[1] as List<dynamic>;
      final quotes = List<dynamic>.from(results[2] as List<dynamic>);
      final shipTos = List<dynamic>.from(results[3] as List<dynamic>);
      quotes.sort((a, b) {
        final ad = a.data as Map<String, dynamic>? ?? {};
        final bd = b.data as Map<String, dynamic>? ?? {};
        final at = _parseDate(ad['updated'] ?? ad['created']);
        final bt = _parseDate(bd['updated'] ?? bd['created']);
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
      setState(() {
        _applyFormFromData(customer.data as Map<String, dynamic>? ?? {});
        _jobs = jobs;
        _quotes = quotes;
        _shipTos = shipTos;
        _loadingRelated = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadingRelated = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading customer: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _companyController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String get _displayName {
    final data = {
      'company': _companyController.text.trim(),
      'name': _nameController.text.trim(),
    };
    return customerDisplayLabel(data, fallback: 'Customer');
  }

  double get _wonRevenue {
    var sum = 0.0;
    for (final q in _quotes) {
      final data = q.data as Map<String, dynamic>? ?? {};
      if ('${data['status'] ?? ''}'.toLowerCase() != 'won') continue;
      sum += (data['final_total_cad'] as num?)?.toDouble() ?? 0;
    }
    return sum;
  }

  void _close({required bool saved}) {
    if (widget.embedded) {
      widget.onClosed?.call(saved);
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context, saved);
    }
  }

  Future<void> _save() async {
    if (_companyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Company is required')),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final pb = PocketBaseService();
      final company = _companyController.text.trim();
      final name = _nameController.text.trim();
      final address = _addressController.text.trim();
      final email = _emailController.text.trim();
      final phone = _phoneController.text.trim();
      final notes = _notesController.text.trim();

      if (_isNew) {
        await pb.createCustomer(
          company: company,
          name: name.isEmpty ? null : name,
          address: address.isEmpty ? null : address,
          email: email.isEmpty ? null : email,
          phone: phone.isEmpty ? null : phone,
          notes: notes.isEmpty ? null : notes,
        );
      } else {
        await pb.updateCustomer(
          id: _customerId!,
          company: company,
          name: name.isEmpty ? null : name,
          address: address.isEmpty ? null : address,
          email: email.isEmpty ? null : email,
          phone: phone.isEmpty ? null : phone,
          notes: notes.isEmpty ? null : notes,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isNew ? 'Customer added' : 'Customer updated'),
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

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete customer'),
        content: Text(
          'Delete "${_displayName}"? This won\'t remove them from existing quotes or jobs.',
        ),
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
      await PocketBaseService().deleteCustomer(_customerId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Customer deleted'),
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

  void _openJob(dynamic job) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => JobDetailScreen(job: job)),
    ).then((changed) {
      if (changed == true) _loadRelated();
    });
  }

  void _openQuote(dynamic quote) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => QuoteDetailScreen(quote: quote)),
    ).then((changed) {
      if (changed == true) _loadRelated();
    });
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null || v.toString().isEmpty) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  String _formatDate(dynamic v) {
    final d = _parseDate(v);
    if (d == null) return '—';
    return _dateDisplay.format(d);
  }

  String _formatCurrency(dynamic n) {
    if (n == null || n == '') return '—';
    final num = double.tryParse(n.toString());
    if (num == null) return '—';
    return NumberFormat.currency(locale: 'en_CA', symbol: r'$', decimalDigits: 0).format(num);
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

  Widget _resizableNotesField() {
    final handleColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Stack(
        children: [
          SizedBox(
            height: _notesBoxHeight,
            child: TextField(
              controller: _notesController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                alignLabelWithHint: true,
                contentPadding: EdgeInsets.fromLTRB(12, 16, 28, 12),
              ),
            ),
          ),
          Positioned(
            right: 2,
            bottom: 2,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (details) {
                  setState(() {
                    _notesBoxHeight =
                        (_notesBoxHeight + details.delta.dy).clamp(72.0, 480.0);
                  });
                },
                child: Tooltip(
                  message: 'Drag to resize',
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.south_east,
                      size: 16,
                      color: handleColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _jobStatusBadge(String status) {
    final s = status.isEmpty ? 'planning' : status.toLowerCase();
    Color bg;
    Color fg;
    switch (s) {
      case 'in_progress':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFF92400E);
        break;
      case 'done':
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF065F46);
        break;
      case 'cancelled':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFF991B1B);
        break;
      default:
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF1E40AF);
    }
    if (Theme.of(context).brightness == Brightness.dark) {
      switch (s) {
        case 'in_progress':
          bg = const Color(0xFFD97706);
          fg = Colors.white;
          break;
        case 'done':
          bg = const Color(0xFF059669);
          fg = Colors.white;
          break;
        case 'cancelled':
          bg = const Color(0xFFDC2626);
          fg = Colors.white;
          break;
        default:
          bg = const Color(0xFF2563EB);
          fg = Colors.white;
      }
    }
    final label = switch (s) {
      'in_progress' => 'In progress',
      'done' => 'Done',
      'cancelled' => 'Cancelled',
      'planning' => 'Planning',
      _ => s.replaceAll('_', ' '),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: fg)),
    );
  }

  Widget _quoteStatusBadge(String status) {
    final s = status.isEmpty ? 'draft' : status.toLowerCase();
    Color bg;
    Color fg;
    String label;
    switch (s) {
      case 'sent':
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF1E40AF);
        label = 'Sent';
        break;
      case 'won':
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF065F46);
        label = 'Won';
        break;
      case 'lost':
        bg = const Color(0xFFD1D5DB);
        fg = const Color(0xFF4B5563);
        label = 'Lost';
        break;
      default:
        bg = const Color(0xFFE5E7EB);
        fg = const Color(0xFF1F2937);
        label = 'Draft';
    }
    if (Theme.of(context).brightness == Brightness.dark) {
      switch (s) {
        case 'sent':
          bg = const Color(0xFF2563EB);
          fg = Colors.white;
          label = 'Sent';
          break;
        case 'won':
          bg = const Color(0xFF059669);
          fg = Colors.white;
          label = 'Won';
          break;
        case 'lost':
          bg = const Color(0xFF6B7280);
          fg = Colors.white;
          label = 'Lost';
          break;
        default:
          bg = const Color(0xFF4B5563);
          fg = Colors.white;
          label = 'Draft';
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: fg)),
    );
  }

  Widget _summaryStat(String label, String value) {
    final muted = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFD1D5DB)
        : const Color(0xFF4B5563);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: muted)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _jobsTable() {
    if (_jobs.isEmpty) {
      return Text(
        'No jobs for this customer.',
        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 520),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(1.1),
            1: FlexColumnWidth(1.2),
            2: FlexColumnWidth(1.4),
            3: FlexColumnWidth(1.4),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
              ),
              children: [
                _tableHeader('Job #'),
                _tableHeader('Status'),
                _tableHeader('Ship date'),
                _tableHeader('Delivered date'),
              ],
            ),
            ..._jobs.map((job) {
              final data = job.data as Map<String, dynamic>? ?? {};
              final jobNumber = '${data['job_number'] ?? ''}'.trim();
              final status = '${data['status'] ?? ''}'.trim();
              return TableRow(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                children: [
                  _tableLinkCell(
                    jobNumber.isEmpty ? '—' : jobNumber,
                    onTap: () => _openJob(job),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _jobStatusBadge(status),
                    ),
                  ),
                  _tableTextCell(_formatDate(data['ship_date'])),
                  _tableTextCell(_formatDate(data['delivered_date'])),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _quotesTable() {
    if (_quotes.isEmpty) {
      return Text(
        'No quotes for this customer.',
        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 520),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(1.1),
            1: FlexColumnWidth(1.2),
            2: FlexColumnWidth(1.4),
            3: FlexColumnWidth(1.4),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
              ),
              children: [
                _tableHeader('Job #'),
                _tableHeader('Status'),
                _tableHeader('Total'),
                _tableHeader('Updated'),
              ],
            ),
            ..._quotes.map((quote) {
              final data = quote.data as Map<String, dynamic>? ?? {};
              final jobNumber = '${data['job_number'] ?? ''}'.trim();
              final status = '${data['status'] ?? ''}'.trim();
              return TableRow(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                children: [
                  _tableLinkCell(
                    jobNumber.isEmpty ? '—' : jobNumber,
                    onTap: () => _openQuote(quote),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _quoteStatusBadge(status),
                    ),
                  ),
                  _tableTextCell(_formatCurrency(data['final_total_cad'])),
                  _tableTextCell(_formatDate(data['updated'])),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _tableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4, left: 8, right: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Colors.grey[700],
        ),
      ),
    );
  }

  Widget _tableTextCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Text(text, style: const TextStyle(fontSize: 14)),
    );
  }

  Widget _tableLinkCell(String text, {required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: InkWell(
        onTap: onTap,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: QuoteSidebarTheme.primary(context),
            decoration: TextDecoration.underline,
            decorationColor: QuoteSidebarTheme.primary(context),
          ),
        ),
      ),
    );
  }

  /// Ship-to list under Bill-to — same outlined box style as other Details fields.
  Widget _shipTosSection() {
    if (_isNew) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Ship-to addresses',
          border: OutlineInputBorder(),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          contentPadding: EdgeInsets.fromLTRB(12, 16, 8, 8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _editShipToDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ),
            if (_shipTos.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 4),
                child: Text(
                  'None yet',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              )
            else
              ..._shipTos.map(_shipToTile),
          ],
        ),
      ),
    );
  }

  Widget _shipToTile(dynamic site) {
    final d = site.data as Map<String, dynamic>? ?? {};
    final label = '${d['label'] ?? ''}'.trim();
    final address = '${d['address'] ?? ''}'.trim();
    final isDefault = d['is_default'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: ListTile(
        dense: true,
        title: Row(
          children: [
            Expanded(child: Text(label.isEmpty ? 'Ship-to' : label)),
            if (isDefault)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Default',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
          ],
        ),
        subtitle: address.isEmpty ? null : Text(address),
        isThreeLine: address.contains('\n'),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'edit') {
              await _editShipToDialog(existing: site);
            } else if (value == 'default') {
              await _setDefaultShipTo(site.id as String);
            } else if (value == 'delete') {
              await _deleteShipTo(site);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            if (!isDefault)
              const PopupMenuItem(value: 'default', child: Text('Set as default')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }

  Future<void> _setDefaultShipTo(String shipToId) async {
    final id = _customerId;
    if (id == null) return;
    try {
      await PocketBaseService().setCustomerShipToDefault(
        customerId: id,
        shipToId: shipToId,
      );
      await _loadRelated();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteShipTo(dynamic site) async {
    final d = site.data as Map<String, dynamic>? ?? {};
    final label = '${d['label'] ?? 'this ship-to'}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete ship-to'),
        content: Text('Delete "$label"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PocketBaseService().deleteCustomerShipTo(site.id as String);
      await _loadRelated();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _editShipToDialog({dynamic existing}) async {
    final id = _customerId;
    if (id == null) return;
    final d = existing?.data as Map<String, dynamic>? ?? {};
    // Prefill: prefer existing label, else legacy attn, else company name.
    final existingLabel = '${d['label'] ?? ''}'.trim();
    final legacyAttn = '${d['attn'] ?? ''}'.trim();
    final labelC = TextEditingController(
      text: existingLabel.isNotEmpty
          ? existingLabel
          : (legacyAttn.isNotEmpty
              ? legacyAttn
              : (existing == null ? _companyController.text.trim() : '')),
    );
    final addressC = TextEditingController(
      text: '${d['address'] ?? ''}'.trim().isEmpty && existing == null
          ? _addressController.text.trim()
          : '${d['address'] ?? ''}',
    );
    var isDefault = d['is_default'] == true || (_shipTos.isEmpty && existing == null);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text(existing == null ? 'Add ship-to' : 'Edit ship-to'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: labelC,
                      decoration: const InputDecoration(
                        labelText: 'Name / ATTN *',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressC,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Address *',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: isDefault,
                      onChanged: (v) => setLocal(() => isDefault = v ?? false),
                      title: const Text('Default for new jobs'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    final label = labelC.text.trim();
    final address = addressC.text.trim();
    labelC.dispose();
    addressC.dispose();
    if (saved != true) return;
    if (label.isEmpty || address.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name / ATTN and address are required')),
      );
      return;
    }

    try {
      final pb = PocketBaseService();
      // Keep attn in sync with label (single name field in the UI).
      final body = <String, dynamic>{
        'customer': id,
        'label': label,
        'address': address,
        'attn': label,
        'is_default': isDefault,
      };
      if (existing == null) {
        final created = await pb.createCustomerShipTo(body);
        if (isDefault) {
          await pb.setCustomerShipToDefault(
            customerId: id,
            shipToId: created.id as String,
          );
        }
      } else {
        await pb.updateCustomerShipTo(existing.id as String, body);
        if (isDefault) {
          await pb.setCustomerShipToDefault(
            customerId: id,
            shipToId: existing.id as String,
          );
        }
      }
      await _loadRelated();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _detailsCard() {
    return QuoteSidebarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Details'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _field(controller: _companyController, label: 'Company *')),
              const SizedBox(width: 12),
              Expanded(child: _field(controller: _nameController, label: 'Contact name')),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _field(
                  controller: _emailController,
                  label: 'Email',
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _field(
                  controller: _phoneController,
                  label: 'Phone',
                  keyboardType: TextInputType.phone,
                ),
              ),
            ],
          ),
          _field(controller: _addressController, label: 'Bill-to / default address', maxLines: 2),
          _shipTosSection(),
          _resizableNotesField(),
          const SizedBox(height: 4),
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
                    : const Text('Save customer'),
              ),
              if (!_isNew) ...[
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _isSaving ? null : _confirmDelete,
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  child: const Text('Delete'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmbeddedHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = _isNew ? 'Add customer' : _displayName;
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
                  title,
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

  Widget _editBody(bool wide) {
    if (_loadingRelated && !_isNew) {
      return const Center(child: CircularProgressIndicator());
    }

    final mainColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _detailsCard(),
        const SizedBox(height: 16),
        QuoteSidebarCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle('Jobs'),
              _jobsTable(),
            ],
          ),
        ),
        const SizedBox(height: 16),
        QuoteSidebarCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle('Quotes'),
              _quotesTable(),
            ],
          ),
        ),
      ],
    );

    final summary = QuoteSidebarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Summary'),
          _summaryStat('Revenue (won quotes)', _formatCurrency(_wonRevenue)),
          const SizedBox(height: 16),
          _summaryStat('Jobs', '${_jobs.length}'),
          const SizedBox(height: 16),
          _summaryStat('Quotes', '${_quotes.length}'),
        ],
      ),
    );

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: mainColumn),
          const SizedBox(width: 16),
          SizedBox(width: 280, child: summary),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        mainColumn,
        const SizedBox(height: 16),
        summary,
      ],
    );
  }

  Widget _newCustomerBody() {
    return QuoteSidebarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Details'),
          _field(controller: _companyController, label: 'Company *'),
          _field(controller: _nameController, label: 'Contact name'),
          _field(controller: _addressController, label: 'Address', maxLines: 2),
          Row(
            children: [
              Expanded(
                child: _field(
                  controller: _emailController,
                  label: 'Email',
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _field(
                  controller: _phoneController,
                  label: 'Phone',
                  keyboardType: TextInputType.phone,
                ),
              ),
            ],
          ),
          _resizableNotesField(),
          const SizedBox(height: 8),
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
                    : const Text('Save customer'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormScroll() {
    final wide = MediaQuery.sizeOf(context).width >= kWorkspaceWideBreakpointPx;
    return RefreshIndicator(
      onRefresh: _isNew ? () async {} : _loadRelated,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: widget.embedded ? kWorkspaceContentMaxWidth : 1100,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_isNew && !widget.embedded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _displayName,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                _isNew ? _newCustomerBody() : _editBody(wide),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isNew ? 'Add customer' : _displayName;
    final form = _buildFormScroll();

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
        title: Text(title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: workspaceMenuLeading(context),
      ),
      body: form,
    );
  }
}
