import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models.dart';
import 'pocketbase_service.dart';
import 'shop_material_editor.dart';

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
      ]);
      setState(() {
        _draft = PurchaseDraft.fromRecord(results[0]);
        _lines = (results[1] as List)
            .map((r) => PurchaseDraftLine.fromRecord(r))
            .toList();
        _materials =
            (results[2] as List).map((r) => ShopMaterial.fromRecord(r)).toList();
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
    final created = await showShopMaterialEditor(
      context,
      existing: seed == null
          ? null
          : ShopMaterial(
              id: '',
              grade: (seed['grade'] ?? '').toString(),
              form: (seed['form'] ?? 'other').toString(),
              sizeLabel: (seed['size_label'] ?? '').toString(),
              unit: (seed['unit'] ?? 'ea').toString(),
              notes: seed['notes']?.toString(),
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
              if ((_draft.tracking ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Tracking: ${_draft.tracking}'),
              ],
              if ((_draft.notes ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_draft.notes!, style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
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
    final matchLabel = switch (line.matchStatus) {
      'matched' => 'Matched',
      'ambiguous' => 'Pick material',
      'propose_new' => 'New material',
      'none' => 'Unmatched',
      _ => line.lineType,
    };
    final subtitle = [
      if ((line.partNumber ?? '').isNotEmpty) 'P/N ${line.partNumber}',
      'Qty ${line.quantity}',
      if (line.unitCost != null) '\$${line.unitCost!.toStringAsFixed(2)}',
      if (line.matchedMaterialLabel != null) line.matchedMaterialLabel!,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(line.description?.isNotEmpty == true
            ? line.description!
            : (line.partNumber ?? line.lineType)),
        subtitle: Text('$matchLabel\n$subtitle'),
        isThreeLine: true,
        trailing: line.lineType == 'material'
            ? PopupMenuButton<String>(
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
              )
            : null,
      ),
    );
  }
}
