import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'label_print_service.dart';
import 'material_form_icons.dart';
import 'models.dart';
import 'pocketbase_service.dart';

String materialPieceIdentityLine(ShopMaterial m) {
  final grade = m.grade.trim();
  final form = materialFormLabel(m.form);
  final size = m.sizeLabel.trim();
  return [
    if (grade.isNotEmpty) grade,
    form,
    if (size.isNotEmpty) size,
  ].join(' · ');
}

/// Size for stickers: `1x2.5x12` → `1 x 2.5 x 12`.
String formatMaterialSizeForLabel(String sizeLabel) {
  final t = sizeLabel.trim();
  if (t.isEmpty) return t;
  return t.replaceAllMapped(RegExp(r'\s*[xX×]\s*'), (_) => ' x ');
}

/// Sticker identity: grade + form + spaced size (no middle dots).
String materialPieceLabelIdentityLine(ShopMaterial m) {
  final grade = m.grade.trim();
  final form = materialFormLabel(m.form);
  final size = formatMaterialSizeForLabel(m.sizeLabel);
  return [
    if (grade.isNotEmpty) grade,
    form,
    if (size.isNotEmpty) size,
  ].join(' ');
}

String formatRemnantForLabel(double lengthIn) {
  final v = lengthIn;
  final numPart =
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
  return 'REM: $numPart';
}

/// Printable piece code without dashes, shortened one char for sticker fit
/// (`P-85L20` → `P85L2`).
String materialLabelCodeForSticker(String labelCode) {
  final bare = labelCode.replaceAll('-', '').trim();
  if (bare.length <= 2) return bare;
  return bare.substring(0, bare.length - 1);
}

/// Heat/lot line for stickers (shown after the P-code when present).
String? materialHeatLotForSticker(String? heatLot) {
  final t = (heatLot ?? '').trim();
  if (t.isEmpty) return null;
  final bare = t.replaceFirst(RegExp(r'^(lot|heat)\s*[:#]?\s*', caseSensitive: false), '');
  return 'LOT ${bare.isEmpty ? t : bare}';
}

String _formatInches(double v) {
  if (v == v.roundToDouble()) return '${v.round()} in';
  return '${v.toStringAsFixed(1)} in';
}

Future<void> printOrPreviewMaterialLabel(
  BuildContext context, {
  required ShopMaterial material,
  required MaterialPiece piece,
}) async {
  final identity = materialPieceLabelIdentityLine(material);
  final location = (piece.locationNote ?? '').trim();
  final rem = formatRemnantForLabel(piece.lengthIn);
  final remLine = location.isEmpty ? rem : '$rem $location';
  final codeLine = materialLabelCodeForSticker(piece.labelCode);
  final heatLine = materialHeatLotForSticker(piece.heatLot);
  final bytes = await LabelPrintService.generateMaterialLabelImage(
    line1: identity,
    line2: remLine,
    heatLotLine: heatLine,
    codeLine: codeLine,
    pieceId: piece.id,
  );

  try {
    await LabelPrintService.sendLabelPng(
      bytes,
      jobName: 'material-${piece.labelCode}',
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb
                ? 'Opened system print — PT-P910BT, 18mm paper, short Length (not 100mm)'
                : 'Label sent to printer',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
    return;
  } on PlatformException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Print failed: ${e.message ?? e.code}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Print failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Label · ${piece.labelCode}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            kIsWeb
                ? 'Print dialog unavailable. Preview (use Print again or check the printer):'
                : 'Preview (printer unavailable):',
            style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          ColoredBox(
            color: Colors.white,
            child: Image.memory(
              Uint8List.fromList(bytes),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
            try {
              await LabelPrintService.sendLabelPng(
                bytes,
                jobName: 'material-${piece.labelCode}',
              );
            } catch (_) {}
          },
          child: const Text('Print'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// Returns the created [MaterialPiece] (and prints/previews label when asked).
Future<MaterialPiece?> showAddMaterialStockDialog(
  BuildContext context, {
  required ShopMaterial material,
}) async {
  final lengthCtrl = TextEditingController();
  final locationCtrl = TextEditingController();
  final heatCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  var printAfter = true;

  final saved = await showDialog<MaterialPiece>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text('Add stock'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      materialPieceIdentityLine(material),
                      style: Theme.of(ctx).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: lengthCtrl,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Length (inches)',
                        hintText: 'e.g. 50',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: locationCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Location (optional)',
                        hintText: 'e.g. Rack B',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: heatCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Heat / lot (optional)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Print sticker after save'),
                      value: printAfter,
                      onChanged: (v) =>
                          setLocal(() => printAfter = v ?? true),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final raw = lengthCtrl.text.trim().replaceAll(',', '');
                  final length = double.tryParse(raw);
                  if (length == null || length <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Enter a length greater than zero'),
                      ),
                    );
                    return;
                  }
                  try {
                    final rec = await PocketBaseService().createMaterialPiece(
                      materialId: material.id,
                      lengthIn: length,
                      source: 'legacy',
                      locationNote: locationCtrl.text,
                      heatLot: heatCtrl.text,
                      notes: notesCtrl.text,
                    );
                    final piece = MaterialPiece.fromRecord(rec);
                    if (ctx.mounted) Navigator.pop(ctx, piece);
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text('Could not add stock: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      );
    },
  );

  lengthCtrl.dispose();
  locationCtrl.dispose();
  heatCtrl.dispose();
  notesCtrl.dispose();

  if (saved != null && printAfter && context.mounted) {
    await printOrPreviewMaterialLabel(
      context,
      material: material,
      piece: saved,
    );
  }
  return saved;
}

/// Edit an on-shelf remnant (length, location, heat, notes).
Future<MaterialPiece?> showEditMaterialPieceDialog(
  BuildContext context, {
  required ShopMaterial material,
  required MaterialPiece piece,
}) async {
  final lengthCtrl = TextEditingController(
    text: piece.lengthIn == piece.lengthIn.roundToDouble()
        ? '${piece.lengthIn.round()}'
        : piece.lengthIn.toStringAsFixed(1),
  );
  final locationCtrl =
      TextEditingController(text: piece.locationNote ?? '');
  final heatCtrl = TextEditingController(text: piece.heatLot ?? '');
  final notesCtrl = TextEditingController(text: piece.notes ?? '');
  var printAfter = false;

  final saved = await showDialog<MaterialPiece>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: Text('Edit · ${piece.labelCode}'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      materialPieceIdentityLine(material),
                      style: Theme.of(ctx).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: lengthCtrl,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Remnant length (inches)',
                        hintText: 'e.g. 3.5',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: locationCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Location (optional)',
                        hintText: 'e.g. Rack B',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: heatCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Heat / lot (optional)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Print sticker after save'),
                      value: printAfter,
                      onChanged: (v) =>
                          setLocal(() => printAfter = v ?? false),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final raw = lengthCtrl.text.trim().replaceAll(',', '');
                  final length = double.tryParse(raw);
                  if (length == null || length <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Enter a length greater than zero'),
                      ),
                    );
                    return;
                  }
                  try {
                    final rec = await PocketBaseService().updateMaterialPiece(
                      pieceId: piece.id,
                      lengthIn: length,
                      locationNote: locationCtrl.text,
                      heatLot: heatCtrl.text,
                      notes: notesCtrl.text,
                    );
                    final updated = MaterialPiece.fromRecord(rec);
                    if (ctx.mounted) Navigator.pop(ctx, updated);
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text('Could not update: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );

  lengthCtrl.dispose();
  locationCtrl.dispose();
  heatCtrl.dispose();
  notesCtrl.dispose();

  if (saved != null && printAfter && context.mounted) {
    await printOrPreviewMaterialLabel(
      context,
      material: material,
      piece: saved,
    );
  }
  return saved;
}

/// Returns the updated piece after a cut, or null if cancelled.
Future<MaterialPiece?> showCutMaterialPieceDialog(
  BuildContext context, {
  required ShopMaterial material,
  required MaterialPiece piece,
}) async {
  final cutCtrl = TextEditingController();
  final jobCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  var printAfter = true;

  final updated = await showDialog<MaterialPiece>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final raw = cutCtrl.text.trim().replaceAll(',', '');
          final cut = double.tryParse(raw);
          final remaining = cut == null ? null : piece.lengthIn - cut;

          return AlertDialog(
            title: Text('Cut · ${piece.labelCode}'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${materialPieceIdentityLine(material)} · ${piece.lengthLabel} on shelf',
                      style: Theme.of(ctx).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: cutCtrl,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Cut length (inches)',
                        hintText: 'e.g. 12',
                      ),
                      onChanged: (_) => setLocal(() {}),
                    ),
                    if (remaining != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        remaining < -0.001
                            ? 'Cut exceeds remaining length'
                            : remaining <= 0.001
                                ? 'Remaining: none (piece depleted)'
                                : 'Remaining: ${_formatInches(remaining)}',
                        style: TextStyle(
                          color: remaining < -0.001
                              ? Theme.of(ctx).colorScheme.error
                              : Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: jobCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Job # (optional)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Print remnant sticker'),
                      value: printAfter,
                      onChanged: (v) =>
                          setLocal(() => printAfter = v ?? true),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final rawCut = cutCtrl.text.trim().replaceAll(',', '');
                  final cutLen = double.tryParse(rawCut);
                  if (cutLen == null || cutLen <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Enter a cut length greater than zero'),
                      ),
                    );
                    return;
                  }
                  try {
                    final rec = await PocketBaseService().cutMaterialPiece(
                      pieceId: piece.id,
                      cutLengthIn: cutLen,
                      jobRef: jobCtrl.text,
                      notes: notesCtrl.text,
                    );
                    final next = MaterialPiece.fromRecord(rec);
                    if (ctx.mounted) Navigator.pop(ctx, next);
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text('Cut failed: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Cut'),
              ),
            ],
          );
        },
      );
    },
  );

  cutCtrl.dispose();
  jobCtrl.dispose();
  notesCtrl.dispose();

  if (updated != null &&
      printAfter &&
      updated.isOnShelf &&
      updated.lengthIn > 0 &&
      context.mounted) {
    await printOrPreviewMaterialLabel(
      context,
      material: material,
      piece: updated,
    );
  }
  return updated;
}

String _formatEventInches(num? v) {
  if (v == null) return '?';
  final d = v.toDouble();
  if (d == d.roundToDouble()) return '${d.round()} in';
  return '${d.toStringAsFixed(1)} in';
}

String describeMaterialEvent(dynamic record) {
  final data = record.data as Map<String, dynamic>? ?? {};
  final type = (data['event_type'] ?? '').toString();
  final before = data['length_before'] as num?;
  final after = data['length_after'] as num?;
  final cut = data['cut_length'] as num?;
  final job = (data['job_ref'] ?? '').toString().trim();
  final notes = (data['notes'] ?? '').toString().trim();

  String base;
  switch (type) {
    case 'intake':
      base = 'Received ${_formatEventInches(after ?? before)}';
      break;
    case 'cut':
      base =
          'Cut ${_formatEventInches(cut)} → ${_formatEventInches(after)} left';
      if (job.isNotEmpty) base = '$base · job $job';
      break;
    case 'adjust':
      base =
          'Adjusted ${_formatEventInches(before)} → ${_formatEventInches(after)}';
      break;
    case 'scrap':
      base = before != null
          ? 'Scrapped (${_formatEventInches(before)})'
          : 'Scrapped';
      break;
    case 'reprint':
      base = 'Sticker reprinted';
      break;
    default:
      base = type.isEmpty ? 'Event' : type;
  }
  if (notes.isNotEmpty) return '$base · $notes';
  return base;
}

/// Confirm scrap (soft remove) for a remnant. Returns true if scrapped.
Future<bool> showScrapMaterialPieceDialog(
  BuildContext context, {
  required ShopMaterial material,
  required MaterialPiece piece,
}) async {
  final notesCtrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text('Scrap · ${piece.labelCode}'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                materialPieceIdentityLine(material),
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Removes ${piece.lengthLabel} from the shelf. '
                'The piece stays in history as scrap (not hard-deleted).',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  hintText: 'e.g. too short, damaged',
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () async {
              try {
                await PocketBaseService().scrapMaterialPiece(
                  piece.id,
                  notes: notesCtrl.text,
                );
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('Could not scrap: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Scrap'),
          ),
        ],
      );
    },
  );
  notesCtrl.dispose();
  return ok == true;
}

class _MaterialHistoryRow {
  _MaterialHistoryRow({
    required this.when,
    required this.title,
    required this.subtitle,
  });
  final DateTime? when;
  final String title;
  final String subtitle;
}

Future<List<_MaterialHistoryRow>> _loadMaterialHistoryRows(
  ShopMaterial material,
) async {
  final pb = PocketBaseService();
  final dateFmt = DateFormat('MMM d yyyy · HH:mm');
  final rows = <_MaterialHistoryRow>[];

  // Purchases = incoming stock for this alloy/form/size.
  try {
    final purchases = await pb.getPurchaseItemsByMaterial(material.id);
    for (final rec in purchases) {
      final item = PurchaseItem.fromRecord(rec);
      DateTime? when;
      try {
        final purchaseData = () {
          final p = rec.expand?['purchase'];
          final purchaseRec = (p is List && p.isNotEmpty) ? p.first : p;
          return purchaseRec?.data as Map<String, dynamic>?;
        }();
        final raw = purchaseData?['purchase_date'];
        if (raw != null) when = DateTime.tryParse(raw.toString());
        when ??= DateTime.tryParse(rec.created?.toString() ?? '');
      } catch (_) {}
      final supplier = () {
        try {
          final p = rec.expand?['purchase'];
          final purchaseRec = (p is List && p.isNotEmpty) ? p.first : p;
          final s = purchaseRec?.expand?['supplier'];
          final supplierRec = (s is List && s.isNotEmpty) ? s.first : s;
          return (supplierRec?.data?['name'] ?? '').toString().trim();
        } catch (_) {
          return '';
        }
      }();
      final lot = (item.heatLot ?? '').trim();
      final qty = item.quantity;
      final cost = item.unitCost;
      final bits = <String>[
        if (supplier.isNotEmpty) supplier,
        'Qty $qty',
        if (cost != null) '\$${cost.toStringAsFixed(2)}/unit',
        if (lot.isNotEmpty) 'lot $lot',
      ];
      rows.add(
        _MaterialHistoryRow(
          when: when,
          title: 'Purchased · ${bits.join(' · ')}',
          subtitle: when != null ? dateFmt.format(when.toLocal()) : 'Purchase',
        ),
      );
    }
  } catch (_) {
    // Purchases may fail independently; still show piece events.
  }

  // Piece events = intake / cut / adjust / scrap across all rems.
  try {
    final pieces = await pb.getMaterialPiecesForMaterial(material.id);
    final codeById = <String, String>{
      for (final r in pieces)
        r.id.toString(): MaterialPiece.fromRecord(r).labelCode,
    };
    final events = await pb.getMaterialEventsForMaterial(material.id);
    for (final rec in events) {
      DateTime? when;
      try {
        when = DateTime.tryParse(rec.created?.toString() ?? '');
      } catch (_) {}
      final data = rec.data as Map<String, dynamic>? ?? {};
      final pieceId = () {
        final raw = data['piece'];
        if (raw is String) return raw;
        if (raw is Map) return (raw['id'] ?? '').toString();
        return raw?.toString() ?? '';
      }();
      var code = codeById[pieceId] ?? '';
      if (code.isEmpty) {
        try {
          final expanded = rec.expand?['piece'];
          final pieceRec =
              (expanded is List && expanded.isNotEmpty) ? expanded.first : expanded;
          if (pieceRec != null) {
            code = MaterialPiece.fromRecord(pieceRec).labelCode;
          }
        } catch (_) {}
      }
      final by = (data['created_by_email'] ?? '').toString().trim();
      final desc = describeMaterialEvent(rec);
      rows.add(
        _MaterialHistoryRow(
          when: when,
          title: code.isEmpty ? desc : '$code · $desc',
          subtitle: [
            if (when != null) dateFmt.format(when.toLocal()),
            if (by.isNotEmpty) by,
          ].join(' · '),
        ),
      );
    }
  } catch (e) {
    final msg = '$e';
    final migrationHint = msg.contains('material_events') ||
        msg.contains('1776810000') ||
        msg.contains('1776820000') ||
        msg.contains('missing');
    rows.add(
      _MaterialHistoryRow(
        when: null,
        title: migrationHint
            ? 'Cut / scrap log not on this server yet'
            : 'Could not load cut / scrap log',
        subtitle: migrationHint
            ? 'On the laptop run: scp pb_migrations/1776820000_material_events_create.js '
                'to CT105 /opt/pocketbase-erp-dev/pb_migrations/ then '
                'systemctl restart pocketbase-erp-dev. ($msg)'
            : msg,
      ),
    );
  }

  rows.sort((a, b) {
    final aw = a.when;
    final bw = b.when;
    if (aw == null && bw == null) return 0;
    if (aw == null) return 1;
    if (bw == null) return -1;
    return bw.compareTo(aw);
  });
  return rows;
}

/// Full incoming/outgoing history for a catalog material (alloy / form / size).
Future<void> showMaterialHistoryDialog(
  BuildContext context, {
  required ShopMaterial material,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final size = MediaQuery.sizeOf(ctx);
      final dialogW = (size.width - 48).clamp(480.0, 920.0);
      final dialogH = (size.height - 160).clamp(360.0, 720.0);
      return AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        title: Text('History · ${material.displayLabel}'),
        content: SizedBox(
          width: dialogW,
          height: dialogH,
          child: FutureBuilder<List<_MaterialHistoryRow>>(
            future: _loadMaterialHistoryRows(material),
            builder: (ctx, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Text(
                  'Could not load history: ${snap.error}',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                );
              }
              final rows = snap.data ?? const [];
              if (rows.isEmpty) {
                return Text(
                  'No purchases or piece activity for this material yet.',
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                );
              }
              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final row = rows[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    title: Text(row.title),
                    subtitle:
                        row.subtitle.isEmpty ? null : Text(row.subtitle),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
