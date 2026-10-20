import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'carrier_tracking.dart';
import 'models.dart';
import 'pocketbase_service.dart';
import 'shop_material_editor.dart';
import 'vendor_part_links.dart';

/// Review / approve / reject an email-ingest purchase draft.
class PurchaseDraftReviewScreen extends StatefulWidget {
  const PurchaseDraftReviewScreen({
    super.key,
    required this.draft,
    this.embedded = false,
    this.onClosed,
  });

  final PurchaseDraft draft;
  final bool embedded;
  final void Function(bool saved)? onClosed;

  @override
  State<PurchaseDraftReviewScreen> createState() =>
      _PurchaseDraftReviewScreenState();
}

class _PurchaseDraftReviewScreenState extends State<PurchaseDraftReviewScreen> {
  late PurchaseDraft _draft;
  List<PurchaseDraftLine> _lines = [];
  List<ShopMaterial> _materials = [];
  List<Tool> _tools = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pb = PocketBaseService();
      final results = await Future.wait([
        pb.getPurchaseDraft(_draft.id),
        pb.getPurchaseDraftLines(_draft.id),
        pb.getMaterials(),
        pb.getTools(),
      ]);
      setState(() {
        _draft = PurchaseDraft.fromRecord(results[0]);
        _lines = (results[1] as List)
            .map((r) => PurchaseDraftLine.fromRecord(r))
            .toList();
        _materials =
            (results[2] as List).map((r) => ShopMaterial.fromRecord(r)).toList();
        _tools = (results[3] as List).map((r) => Tool.fromRecord(r)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading draft: $e')),
        );
      }
    }
  }

  Future<void> _approve() async {
    setState(() => _busy = true);
    try {
      await PocketBaseService().approvePurchaseDraft(_draft.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Purchase created from draft')),
      );
      if (widget.embedded) {
        widget.onClosed?.call(true);
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Approve failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject draft?'),
        content: const Text(
          'This removes it from the review queue. It will not create a purchase.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await PocketBaseService().rejectPurchaseDraft(_draft.id);
      if (!mounted) return;
      if (widget.embedded) {
        widget.onClosed?.call(true);
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reject failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickMaterial(PurchaseDraftLine line) async {
    final selected = await showDialog<ShopMaterial>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: const Text('Match material'),
          children: [
            for (final m in _materials.take(40))
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, m),
                child: Text(m.displayLabel),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
    if (selected == null) return;
    await PocketBaseService().updatePurchaseDraftLine(line.id, {
      'matched_material': selected.id,
      'match_status': 'matched',
    });
    await _load();
  }

  Future<void> _pickTool(PurchaseDraftLine line) async {
    final selected = await showDialog<Tool>(
      context: context,
      builder: (ctx) => _ToolMatchDialog(
        tools: _tools,
        hint: line.partNumber ?? line.description,
      ),
    );
    if (selected == null) return;
    await PocketBaseService().updatePurchaseDraftLine(line.id, {
      'matched_tool': selected.id,
      'match_status': 'matched',
    });
    await _load();
  }

  Future<void> _editProposal(PurchaseDraftLine line) async {
    Map<String, dynamic>? seed = line.proposedMaterial;
    if (line.materialProposalId != null) {
      try {
        final prop =
            await PocketBaseService().getMaterialProposal(line.materialProposalId!);
        seed = Map<String, dynamic>.from(prop.data as Map? ?? {});
      } catch (_) {}
    }
    if (!mounted) return;
    final part = (line.partNumber ?? '').trim();
    var notes = (seed?['notes'] ?? '').toString().trim();
    if (notes.isEmpty && part.isNotEmpty) {
      notes = mcmasterNotesSeed(part);
    } else if (part.isNotEmpty &&
        mcmasterPartNumberFromText(notes) == null) {
      notes = '$notes\n${mcmasterNotesSeed(part)}'.trim();
    }
    final created = await showShopMaterialEditor(
      context,
      existing: ShopMaterial(
        id: '',
        grade: (seed?['grade'] ?? '').toString(),
        form: (seed?['form'] ?? 'other').toString(),
        sizeLabel: (seed?['size_label'] ?? '').toString(),
        unit: (seed?['unit'] ?? 'ea').toString(),
        notes: notes.isEmpty ? null : notes,
      ),
    );
    if (created == null) return;
    // Editor already created the material when saving without id — but our
    // showShopMaterialEditor typically creates on save. Prefer linking result.
    await PocketBaseService().updatePurchaseDraftLine(line.id, {
      'matched_material': created.id,
      'match_status': 'matched',
    });
    if (line.materialProposalId != null && line.materialProposalId!.isNotEmpty) {
      await PocketBaseService().updateMaterialProposal(line.materialProposalId!, {
        'status': 'approved',
        'created_material': created.id,
        'grade': created.grade,
        'form': created.form,
        'size_label': created.sizeLabel,
        'unit': created.unit,
      });
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dateText = _draft.purchaseDate != null
        ? DateFormat.yMMMd().format(_draft.purchaseDate!)
        : '—';
    final cur = _draft.currency;
    final totalText = _draft.total != null
        ? '\$${_draft.total!.toStringAsFixed(2)} $cur'
        : cur;

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                _draft.supplierName ?? _draft.displayVendor,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Chip(
                    label: Text(_draft.displayVendor),
                    visualDensity: VisualDensity.compact,
                  ),
                  if ((_draft.orderReference ?? '').isNotEmpty)
                    Chip(
                      label: Text('Ref: ${_draft.orderReference}'),
                      visualDensity: VisualDensity.compact,
                    ),
                  if ((_draft.invoice ?? '').isNotEmpty)
                    Chip(
                      label: Text('Invoice: ${_draft.invoice}'),
                      visualDensity: VisualDensity.compact,
                    ),
                  Chip(
                    label: Text(dateText),
                    visualDensity: VisualDensity.compact,
                  ),
                  Chip(
                    label: Text(totalText),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              if ((_draft.tracking ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                _TrackingRow(
                  tracking: preferredTrackingValue(_draft.tracking),
                  hint: '${_draft.notes ?? ''} ${_draft.displayVendor}',
                ),
              ],
              Builder(
                builder: (context) {
                  final po = customerRefFromNotes(_draft.notes);
                  final extraNotes = displayNotesWithoutDupes(_draft.notes);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (po != null && po.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Customer ref: $po',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                      if (extraNotes.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          extraNotes,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Text('Lines', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (_lines.isEmpty)
                Text(
                  'No line items extracted — you can still approve an empty purchase or reject.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              for (final line in _lines) _buildLineCard(line, scheme),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _reject,
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _approve,
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Approve → Purchase'),
                    ),
                  ),
                ],
              ),
            ],
          );

    if (widget.embedded) {
      return Column(
        children: [
          AppBar(
            title: const Text('Review draft'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => widget.onClosed?.call(false),
              ),
            ],
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review draft'),
      ),
      body: body,
    );
  }

  Widget _buildLineCard(PurchaseDraftLine line, ColorScheme scheme) {
    final matchLabel = switch (line.lineType) {
      'item' => switch (line.matchStatus) {
          'matched' => 'Matched tool',
          'ambiguous' => 'Pick tool',
          'none' => 'Unmatched tool — add in inventory, then pick',
          _ => 'Tool',
        },
      _ => switch (line.matchStatus) {
          'matched' => 'Matched',
          'ambiguous' => 'Pick material',
          'propose_new' => 'New material',
          'none' => 'Unmatched',
          _ => line.lineType,
        },
    };
    String? toolLabel = line.matchedToolLabel;
    if ((toolLabel == null || toolLabel.isEmpty) &&
        line.matchedToolId != null &&
        line.matchedToolId!.isNotEmpty) {
      for (final t in _tools) {
        if (t.id != line.matchedToolId) continue;
        final model = (t.modelNumber ?? '').trim();
        toolLabel =
            model.isEmpty ? t.toolName : '${t.toolName} ($model)';
        break;
      }
    }
    final shipLabel = () {
      if (line.lineType != 'shipping') return null;
      final d = (line.description ?? '').trim();
      if (d.isNotEmpty && d.toLowerCase() != 'shipping') return d;
      if (line.unitCost != null && (line.unitCost! - 34.95).abs() < 0.01) {
        return 'Next Day Air';
      }
      return null;
    }();
    final subtitle = [
      if ((line.partNumber ?? '').isNotEmpty) 'P/N ${line.partNumber}',
      if (line.lineType == 'shipping')
        (shipLabel ?? 'Shipping')
      else if (line.lineType == 'tax')
        'Tax'
      else
        'Qty ${line.quantity}',
      if (line.unitCost != null) '\$${line.unitCost!.toStringAsFixed(2)}',
      if (line.matchedMaterialLabel != null) line.matchedMaterialLabel!,
      if (toolLabel != null && toolLabel.isNotEmpty) toolLabel,
      if (line.millCertNames.isNotEmpty)
        '${line.millCertNames.length} mill cert${line.millCertNames.length == 1 ? '' : 's'}',
    ].join(' · ');

    Widget? trailing;
    if (line.lineType == 'material') {
      trailing = PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'match') _pickMaterial(line);
          if (v == 'propose') _editProposal(line);
        },
        itemBuilder: (ctx) => [
          const PopupMenuItem(
            value: 'match',
            child: Text('Match existing…'),
          ),
          const PopupMenuItem(
            value: 'propose',
            child: Text('Add / edit material…'),
          ),
        ],
      );
    } else if (line.lineType == 'item') {
      trailing = TextButton(
        onPressed: _busy ? null : () => _pickTool(line),
        child: Text(
          (line.matchedToolId == null || line.matchedToolId!.isEmpty)
              ? 'Match tool…'
              : 'Change tool…',
        ),
      );
    }

    final title = () {
      if (line.lineType == 'shipping') {
        return shipLabel ?? 'Shipping';
      }
      if (line.description?.isNotEmpty == true) return line.description!;
      return line.partNumber ?? line.lineType;
    }();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(title),
        subtitle: Text('$matchLabel\n$subtitle'),
        isThreeLine: true,
        trailing: trailing,
      ),
    );
  }
}

class _ToolMatchDialog extends StatefulWidget {
  const _ToolMatchDialog({required this.tools, this.hint});

  final List<Tool> tools;
  final String? hint;

  @override
  State<_ToolMatchDialog> createState() => _ToolMatchDialogState();
}

class _ToolMatchDialogState extends State<_ToolMatchDialog> {
  late final TextEditingController _ctrl;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _q = (widget.hint ?? '').trim();
    _ctrl = TextEditingController(text: _q);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<Tool> get _filtered {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return widget.tools.take(60).toList();
    final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    return widget.tools.where((t) {
      final hay = [
        t.toolName,
        t.modelNumber ?? '',
        t.manufacturerBarcode ?? '',
        t.brand ?? '',
        t.size ?? '',
      ].join(' ').toLowerCase();
      return tokens.every((tok) => hay.contains(tok));
    }).take(60).toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return AlertDialog(
      title: const Text('Match tool'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _ctrl,
              decoration: const InputDecoration(
                labelText: 'Search catalog',
                hintText: 'Name, model, Harvey #…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 8),
            Text(
              'If the tool is new, add it in Inventory first, then search here.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('No tools match'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (ctx, i) {
                        final t = items[i];
                        final model = (t.modelNumber ?? '').trim();
                        final label = model.isEmpty
                            ? t.toolName
                            : '${t.toolName} ($model)';
                        return ListTile(
                          dense: true,
                          title: Text(label),
                          subtitle: Text(
                            [
                              if ((t.brand ?? '').isNotEmpty) t.brand!,
                              if ((t.manufacturerBarcode ?? '').isNotEmpty)
                                t.manufacturerBarcode!,
                            ].join(' · '),
                          ),
                          onTap: () => Navigator.pop(context, t),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _TrackingRow extends StatelessWidget {
  const _TrackingRow({required this.tracking, this.hint});

  final String tracking;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final value = preferredTrackingValue(tracking);
    final uri = trackingUri(value, hint: hint);
    final label = trackingDisplayLabel(value);
    if (uri == null) {
      return Text('Tracking: $label');
    }
    return InkWell(
      onTap: () async {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open $uri')),
          );
        }
      },
      child: Row(
        children: [
          Icon(
            Icons.local_shipping_outlined,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Tracking: $label',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.open_in_new,
            size: 14,
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }
}
