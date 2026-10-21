import 'package:flutter/material.dart';
import 'models.dart';
import 'pocketbase_service.dart';

/// Settings for Gmail purchase ingest: enable, poll interval, vendors, sync status.
class EmailIngestSettingsScreen extends StatefulWidget {
  const EmailIngestSettingsScreen({super.key});

  @override
  State<EmailIngestSettingsScreen> createState() =>
      _EmailIngestSettingsScreenState();
}

class _EmailIngestSettingsScreenState extends State<EmailIngestSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _settingsId;
  bool _enabled = false;
  final _pollCtrl = TextEditingController(text: '30');
  String _lastSyncAt = '';
  String _lastSyncStatus = '';
  String _lastError = '';
  List<EmailIngestVendor> _vendors = [];
  List<dynamic> _suppliers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pb = PocketBaseService();
      final shop = await pb.getShopSettings();
      List<dynamic> vendorRecs = [];
      List<dynamic> suppliers = [];
      try {
        vendorRecs = await pb.getEmailIngestVendors();
      } catch (_) {}
      try {
        suppliers = await pb.getSuppliers();
      } catch (_) {}
      final data = shop.data as Map<String, dynamic>? ?? {};
      setState(() {
        _settingsId = shop.id as String?;
        _enabled = data['email_ingest_enabled'] == true;
        final poll = (data['email_ingest_poll_minutes'] as num?)?.toInt() ?? 30;
        _pollCtrl.text = '$poll';
        _lastSyncAt = (data['email_ingest_last_sync_at'] ?? '').toString();
        _lastSyncStatus =
            (data['email_ingest_last_sync_status'] ?? '').toString();
        _lastError = (data['email_ingest_last_error'] ?? '').toString();
        _vendors = vendorRecs.map(EmailIngestVendor.fromRecord).toList();
        _suppliers = suppliers;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _saveMain() async {
    if (_settingsId == null) return;
    final poll = int.tryParse(_pollCtrl.text.trim()) ?? 30;
    setState(() => _saving = true);
    try {
      await PocketBaseService().updateShopSettings(_settingsId!, {
        'email_ingest_enabled': _enabled,
        'email_ingest_poll_minutes': poll < 1 ? 1 : poll,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ingest settings saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleVendor(EmailIngestVendor v, bool enabled) async {
    try {
      await PocketBaseService().updateEmailIngestVendor(v.id, {
        'enabled': enabled,
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e')),
        );
      }
    }
  }

  Future<void> _editVendor(EmailIngestVendor v) async {
    final domainsCtrl = TextEditingController(text: v.fromDomains);
    String currency = v.defaultCurrency;
    String? supplierId = v.supplierId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(v.name),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: domainsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'From domains (comma-separated)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: currency == 'CAD' ? 'CAD' : 'USD',
                      decoration: const InputDecoration(labelText: 'Currency'),
                      items: const [
                        DropdownMenuItem(value: 'USD', child: Text('USD')),
                        DropdownMenuItem(value: 'CAD', child: Text('CAD')),
                      ],
                      onChanged: (x) => setLocal(() => currency = x ?? 'USD'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      value: () {
                        if (supplierId == null) return null;
                        for (final s in _suppliers) {
                          if (s.id == supplierId) return supplierId;
                        }
                        return null;
                      }(),
                      decoration: const InputDecoration(labelText: 'Supplier'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('(none)'),
                        ),
                        for (final s in _suppliers)
                          DropdownMenuItem<String?>(
                            value: s.id as String?,
                            child: Text(
                              (s.data['company_name'] ?? s.id).toString(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (x) => setLocal(() => supplierId = x),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Adapter: ${v.adapterStatus} · key: ${v.vendorKey}',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;
    try {
      await PocketBaseService().updateEmailIngestVendor(v.id, {
        'from_domains': domainsCtrl.text.trim(),
        'default_currency': currency,
        if (supplierId != null) 'supplier': supplierId,
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.mail_outline),
                      title: const Text('Enable email purchase ingest'),
                      subtitle: const Text(
                        'Poll Gmail for vendor order emails into the Purchases review queue',
                      ),
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _pollCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Poll interval (minutes)',
                                helperText: 'Default 30 — service re-reads each cycle',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: _saving ? null : _saveMain,
                            child: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Save'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('Last sync'),
                  subtitle: Text(
                    [
                      if (_lastSyncStatus.isNotEmpty) 'Status: $_lastSyncStatus',
                      if (_lastSyncAt.isNotEmpty) _lastSyncAt,
                      if (_lastError.isNotEmpty) 'Error: $_lastError',
                      if (_lastSyncStatus.isEmpty && _lastSyncAt.isEmpty)
                        'No sync yet — enable ingest and run the ingest service',
                    ].join('\n'),
                  ),
                  isThreeLine: true,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'EMAIL VENDORS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              if (_vendors.isEmpty)
                const Card(
                  child: ListTile(
                    title: Text('No vendors yet'),
                    subtitle: Text(
                      'Apply migration 1776400000_email_purchase_ingest.js to seed McMaster / DGI',
                    ),
                  ),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < _vendors.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        SwitchListTile(
                          title: Text(_vendors[i].name),
                          subtitle: Text(
                            [
                              _vendors[i].fromDomains,
                              if (_vendors[i].supplierName != null)
                                _vendors[i].supplierName!,
                              'adapter: ${_vendors[i].adapterStatus}',
                            ].join(' · '),
                          ),
                          value: _vendors[i].enabled,
                          onChanged: (v) => _toggleVendor(_vendors[i], v),
                          secondary: IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _editVendor(_vendors[i]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                'OAuth and service install: see docs/GMAIL_PURCHASE_INGEST.md',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Email purchase ingest'),
      ),
      body: body,
    );
  }
}
