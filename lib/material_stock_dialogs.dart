import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

String _formatInches(double v) {
  if (v == v.roundToDouble()) return '${v.round()} in';
  return '${v.toStringAsFixed(1)} in';
}

Future<void> printOrPreviewMaterialLabel(
  BuildContext context, {
  required ShopMaterial material,
  required MaterialPiece piece,
}) async {
  final identity = materialPieceIdentityLine(material);
  final location = (piece.locationNote ?? '').trim();
  final lengthLine = location.isEmpty
      ? piece.lengthLabel
      : '${piece.lengthLabel} · $location';

  final canNativePrint = !kIsWeb;
  if (canNativePrint) {
    try {
      await LabelPrintService.printMaterialLabel(
        labelCode: piece.labelCode,
        identityLine: identity,
        lengthLine: lengthLine,
        pieceId: piece.id,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Label sent to printer'),
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
      // Fall through to preview so the shop can still see the sticker.
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
  }

  if (!context.mounted) return;
  final bytes = LabelPrintService.generateMaterialLabelImage(
    labelCode: piece.labelCode,
    identityLine: identity,
    lengthLine: lengthLine,
    pieceId: piece.id,
  );
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Label · ${piece.labelCode}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            kIsWeb
                ? 'Brother print works from the Android app. Preview:'
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
