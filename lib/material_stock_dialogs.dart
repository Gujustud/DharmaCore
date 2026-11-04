import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'auth_service.dart';
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
  return 'REM: ${formatInchesValue(lengthIn)}';
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

String _formatInches(double v) => '${formatInchesValue(v)} in';

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
      title: Text('Sticker ${materialLabelCodeForSticker(piece.labelCode)}'),
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
  final lengthCtrl =
      TextEditingController(text: formatInchesValue(piece.lengthIn));
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
            title: Text('Edit piece ${materialLabelCodeForSticker(piece.labelCode)}'),
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

/// Saw blade width taken per cut when "Saw kerf" is on.
const double kDefaultSawKerfIn = 0.125;

/// Leftovers shorter than this prompt "keep or scrap?" after a cut.
const double kSmallLeftoverIn = 2.0;

/// Job number of a `jobs` record (empty when missing).
String jobNumberOf(dynamic job) {
  final data = job.data as Map<String, dynamic>? ?? {};
  return (data['job_number'] ?? '').toString().trim();
}

/// Customer company (or name) of a `jobs` record with `customer` expanded.
String jobCustomerOf(dynamic job) {
  final data = job.data as Map<String, dynamic>? ?? {};
  dynamic c;
  try {
    c = job.expand?['customer'];
  } catch (_) {}
  if (c is List && c.isNotEmpty) c = c.first;
  if (c != null) {
    final cd = c.data as Map<String, dynamic>? ?? {};
    final company = (cd['company'] ?? '').toString().trim();
    if (company.isNotEmpty) return company;
    final name = (cd['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
  }
  return (data['customer_name'] ?? '').toString().trim();
}

class _CutOutcome {
  const _CutOutcome(this.piece, {required this.printRemnant});
  final MaterialPiece piece;
  final bool printRemnant;
}

/// Returns the updated piece after a cut, or null if cancelled.
Future<MaterialPiece?> showCutMaterialPieceDialog(
  BuildContext context, {
  required ShopMaterial material,
  required MaterialPiece piece,
}) async {
  final outcome = await showDialog<_CutOutcome>(
    context: context,
    builder: (_) => _CutPieceDialog(material: material, piece: piece),
  );
  if (outcome == null) return null;
  final updated = outcome.piece;
  if (outcome.printRemnant &&
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

class _CutPieceDialog extends StatefulWidget {
  const _CutPieceDialog({required this.material, required this.piece});

  final ShopMaterial material;
  final MaterialPiece piece;

  @override
  State<_CutPieceDialog> createState() => _CutPieceDialogState();
}

class _CutPieceDialogState extends State<_CutPieceDialog> {
  final _lengthCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _notesCtrl = TextEditingController();
  TextEditingController? _jobFieldCtrl;

  bool _useKerf = true;
  bool _printRemnant = true;
  bool _saving = false;

  List<dynamic> _jobs = const [];
  bool _jobsLoading = true;
  bool _jobsFailed = false;
  dynamic _job;

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  Future<void> _loadJobs() async {
    try {
      final jobs = await PocketBaseService().getOpenJobsForMaterial();
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _jobsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _jobsLoading = false;
        _jobsFailed = true;
      });
    }
  }

  @override
  void dispose() {
    _lengthCtrl.dispose();
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double? get _cutIn => parseLengthToInches(_lengthCtrl.text);

  int? get _qty {
    final q = int.tryParse(_qtyCtrl.text.trim());
    if (q == null || q < 1) return null;
    return q;
  }

  double get _kerf => _useKerf ? kDefaultSawKerfIn : 0;

  MaterialCutPlan? get _plan {
    final cut = _cutIn;
    final qty = _qty;
    if (cut == null || cut <= 0 || qty == null) return null;
    return MaterialCutPlan.compute(
      onShelfIn: widget.piece.lengthIn,
      cutLengthIn: cut,
      quantity: qty,
      kerfIn: _kerf,
    );
  }

  String _jobLabel(dynamic job) {
    final number = jobNumberOf(job);
    final customer = jobCustomerOf(job);
    if (customer.isEmpty) return number;
    return '$number — $customer';
  }

  Iterable<dynamic> _matchJobs(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _jobs.take(8);
    final starts = <dynamic>[];
    final contains = <dynamic>[];
    for (final j in _jobs) {
      final number = jobNumberOf(j).toLowerCase();
      final customer = jobCustomerOf(j).toLowerCase();
      if (number.startsWith(q)) {
        starts.add(j);
      } else if (number.contains(q) || customer.contains(q)) {
        contains.add(j);
      }
    }
    return [...starts, ...contains].take(12);
  }

  Future<bool?> _askAboutSmallLeftover(double remainingIn) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Only ${_formatInches(remainingIn)} left'),
        content: const Text(
          'Keep the leftover on the shelf, or scrap it?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Back'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Scrap leftover'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep on shelf'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final plan = _plan;
    final cut = _cutIn;
    final qty = _qty;
    if (plan == null || !plan.fits || cut == null || qty == null) return;

    var scrapRemainder = false;
    if (plan.remainingIn > 0 && plan.remainingIn < kSmallLeftoverIn) {
      final choice = await _askAboutSmallLeftover(plan.remainingIn);
      if (choice == null) return;
      scrapRemainder = choice;
    }

    final typedJob = _jobFieldCtrl?.text.trim() ?? '';
    final jobId = _job?.id as String?;
    final jobRef = _job != null ? jobNumberOf(_job) : typedJob;

    setState(() => _saving = true);
    try {
      final rec = await PocketBaseService().cutMaterialPiece(
        pieceId: widget.piece.id,
        cutLengthIn: cut,
        quantity: qty,
        kerfIn: _kerf,
        jobId: jobId,
        jobRef: jobRef,
        notes: _notesCtrl.text,
        scrapRemainder: scrapRemainder,
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        _CutOutcome(
          MaterialPiece.fromRecord(rec),
          printRemnant: _printRemnant && !scrapRemainder,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cut failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _summary(ThemeData theme) {
    final scheme = theme.colorScheme;
    final raw = _lengthCtrl.text.trim();
    final plan = _plan;
    final cut = _cutIn;
    final qty = _qty;

    String headline;
    String? detail;
    var isError = false;

    if (raw.isEmpty) {
      headline = 'Enter a length';
      detail = 'Decimal inches, or add mm / cm';
    } else if (cut == null || cut <= 0) {
      headline = 'Can\'t read "$raw"';
      detail = 'Try 12.5 or 300mm';
      isError = true;
    } else if (qty == null) {
      headline = 'Quantity must be 1 or more';
      isError = true;
    } else if (plan == null || !plan.fits) {
      headline = 'Too long for this piece';
      detail = 'Needs ${_formatInches(plan?.usedIn ?? cut * qty)}, '
          '${widget.piece.lengthLabel} on shelf';
      isError = true;
    } else {
      headline = plan.remainingIn <= 0
          ? 'Uses the whole piece'
          : 'Leaves ${_formatInches(plan.remainingIn)}';
      final parts = <String>[
        qty > 1
            ? '$qty × ${_formatInches(cut)}'
            : _formatInches(cut),
        if (plan.kerfTotalIn > 0)
          '${formatInchesValue(plan.kerfTotalIn)} in kerf',
      ];
      detail = parts.length > 1 || qty > 1
          ? '${parts.join(' + ')} = ${_formatInches(plan.usedIn)}'
          : null;
    }

    final color = isError ? scheme.error : scheme.onSurface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isError
            ? scheme.errorContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            style: theme.textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 2),
            Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isError ? scheme.error : scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _jobField(ThemeData theme) {
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Autocomplete<Object>(
          displayStringForOption: _jobLabel,
          optionsBuilder: (value) => _matchJobs(value.text).cast<Object>(),
          onSelected: (job) => setState(() => _job = job),
          fieldViewBuilder: (context, ctrl, focusNode, onSubmit) {
            _jobFieldCtrl = ctrl;
            return TextField(
              controller: ctrl,
              focusNode: focusNode,
              decoration: InputDecoration(
                labelText: 'Job (optional)',
                hintText: 'Type a job # or customer',
                helperText: _jobsFailed
                    ? 'Couldn\'t load jobs — what you type is saved as text'
                    : _job == null && ctrl.text.trim().isNotEmpty
                        ? 'Not linked — pick a job from the list to link it'
                        : null,
                prefixIcon: Icon(
                  _job != null ? Icons.link : Icons.work_outline,
                  size: 20,
                  color: _job != null ? scheme.primary : null,
                ),
                suffixIcon: _jobsLoading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : ctrl.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() {
                              ctrl.clear();
                              _job = null;
                            }),
                          ),
              ),
              onChanged: (text) {
                setState(() {
                  if (_job != null && text != _jobLabel(_job)) _job = null;
                });
              },
              onSubmitted: (_) => onSubmit(),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final list = options.toList();
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: 280,
                    maxWidth: constraints.maxWidth,
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final job = list[i];
                      final highlighted =
                          AutocompleteHighlightedOption.of(context) == i;
                      final customer = jobCustomerOf(job);
                      return InkWell(
                        onTap: () => onSelected(job),
                        child: Container(
                          color: highlighted
                              ? scheme.primary.withValues(alpha: 0.08)
                              : null,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 96,
                                child: Text(
                                  jobNumberOf(job),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  customer.isEmpty ? '—' : customer,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final piece = widget.piece;
    final plan = _plan;
    final canCut = !_saving && plan != null && plan.fits;
    final leavesRemnant = plan != null && plan.fits && plan.remainingIn > 0;
    final lot = materialHeatLotForSticker(piece.heatLot);

    return AlertDialog(
      title: Text('Cut piece ${materialLabelCodeForSticker(piece.labelCode)}'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                materialPieceLabelIdentityLine(widget.material),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  '${piece.lengthLabel} on shelf',
                  ?lot,
                ].join('     '),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _lengthCtrl,
                      autofocus: true,
                      keyboardType: TextInputType.text,
                      decoration: const InputDecoration(
                        labelText: 'Length each (in)',
                        hintText: '12.5  or  300mm',
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) {
                        if (canCut) _submit();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 88,
                    child: TextField(
                      controller: _qtyCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Qty',
                        prefixText: '× ',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Saw kerf ${formatInchesValue(kDefaultSawKerfIn)} in per cut',
                ),
                value: _useKerf,
                onChanged: (v) => setState(() => _useKerf = v ?? true),
              ),
              const SizedBox(height: 4),
              _summary(theme),
              const SizedBox(height: 16),
              _jobField(theme),
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
              if (leavesRemnant)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Print sticker for the leftover'),
                  value: _printRemnant,
                  onChanged: (v) => setState(() => _printRemnant = v ?? true),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: canCut ? _submit : null,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.content_cut, size: 18),
          label: const Text('Cut'),
        ),
      ],
    );
  }
}

String _formatEventInches(num? v) {
  if (v == null) return '?';
  return '${formatInchesValue(v.toDouble())} in';
}

/// Who logged a material event: saved name, else the signed-in user's name
/// for their own older events, else the email.
String materialEventByName(Map<String, dynamic> data) {
  final name = (data['created_by_name'] ?? '').toString().trim();
  if (name.isNotEmpty) return name;
  final email = (data['created_by_email'] ?? '').toString().trim();
  final auth = AuthService.instance;
  final me = auth.name;
  if (me != null &&
      email.isNotEmpty &&
      email.toLowerCase() == (auth.email ?? '').trim().toLowerCase()) {
    return me;
  }
  return email;
}

String describeMaterialEvent(dynamic record, {bool includeJob = true}) {
  final data = record.data as Map<String, dynamic>? ?? {};
  final type = (data['event_type'] ?? '').toString();
  final before = data['length_before'] as num?;
  final after = data['length_after'] as num?;
  final cut = data['cut_length'] as num?;
  final qty = (data['quantity'] as num?)?.toInt() ?? 1;
  final job = (data['job_ref'] ?? '').toString().trim();
  final notes = (data['notes'] ?? '').toString().trim();

  String base;
  switch (type) {
    case 'intake':
      base = 'Received ${_formatEventInches(after ?? before)}';
      break;
    case 'cut':
      final pieces = qty > 1
          ? '$qty × ${_formatEventInches(cut)}'
          : _formatEventInches(cut);
      final left = (after ?? 0) > 0
          ? '${_formatEventInches(after)} left'
          : 'none left';
      base = 'Cut $pieces → $left';
      if (includeJob && job.isNotEmpty) base = '$base · job $job';
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
        title: Text('Scrap piece ${materialLabelCodeForSticker(piece.labelCode)}'),
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

enum _HistoryKind { purchase, intake, cut, adjust, scrap, other, error }

class _MaterialHistoryRow {
  _MaterialHistoryRow({
    required this.when,
    required this.kind,
    required this.headline,
    this.detail = '',
    this.dateOnly = false,
  });
  final DateTime? when;
  final _HistoryKind kind;
  final String headline;
  final String detail;

  /// Purchase dates are calendar days (no meaningful time of day).
  final bool dateOnly;
}

_HistoryKind _historyKindForEvent(String type) {
  switch (type) {
    case 'intake':
      return _HistoryKind.intake;
    case 'cut':
      return _HistoryKind.cut;
    case 'adjust':
      return _HistoryKind.adjust;
    case 'scrap':
      return _HistoryKind.scrap;
    default:
      return _HistoryKind.other;
  }
}

/// PocketBase autodate may live in [data] and/or [record.created].
DateTime? _parsePbDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  var s = raw.toString().trim();
  if (s.isEmpty) return null;
  // PB often returns "2026-11-03 12:00:00.000Z" (space); normalize for parse.
  if (s.length > 10 && s[10] == ' ') {
    s = '${s.substring(0, 10)}T${s.substring(11)}';
  }
  return DateTime.tryParse(s);
}

DateTime? _recordCreatedAt(dynamic rec) {
  try {
    final data = rec.data as Map<String, dynamic>? ?? {};
    return _parsePbDate(data['created']) ??
        _parsePbDate(rec.created) ??
        _parsePbDate(data['updated']);
  } catch (_) {
    try {
      return _parsePbDate(rec.created);
    } catch (_) {
      return null;
    }
  }
}

Future<List<_MaterialHistoryRow>> _loadMaterialHistoryRows(
  ShopMaterial material,
) async {
  final pb = PocketBaseService();
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
        when = _parsePbDate(purchaseData?['purchase_date']);
        when ??= _recordCreatedAt(rec);
      } catch (_) {}
      final supplier = () {
        try {
          final p = rec.expand?['purchase'];
          final purchaseRec = (p is List && p.isNotEmpty) ? p.first : p;
          final s = purchaseRec?.expand?['supplier'];
          final supplierRec = (s is List && s.isNotEmpty) ? s.first : s;
          final d = supplierRec?.data as Map<String, dynamic>? ?? {};
          return (d['company_name'] ?? d['name'] ?? '').toString().trim();
        } catch (_) {
          return '';
        }
      }();
      final lot = (item.heatLot ?? '').trim();
      final qty = item.quantity;
      final cost = item.unitCost;
      rows.add(
        _MaterialHistoryRow(
          when: when,
          kind: _HistoryKind.purchase,
          dateOnly: true,
          headline: supplier.isEmpty ? 'Purchased' : 'Purchased from $supplier',
          detail: [
            cost != null
                ? 'Qty $qty at \$${cost.toStringAsFixed(2)}'
                : 'Qty $qty',
            if (lot.isNotEmpty) 'Lot $lot',
          ].join('     '),
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
        r.id.toString(): materialLabelCodeForSticker(
          MaterialPiece.fromRecord(r).labelCode,
        ),
    };
    final events = await pb.getMaterialEventsForMaterial(material.id);
    for (final rec in events) {
      final when = _recordCreatedAt(rec);
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
            code = materialLabelCodeForSticker(
              MaterialPiece.fromRecord(pieceRec).labelCode,
            );
          }
        } catch (_) {}
      }
      final by = materialEventByName(data);
      rows.add(
        _MaterialHistoryRow(
          when: when,
          kind: _historyKindForEvent((data['event_type'] ?? '').toString()),
          headline: describeMaterialEvent(rec),
          detail: [
            if (code.isNotEmpty) code,
            if (by.isNotEmpty) by,
          ].join('     '),
        ),
      );
    }
  } catch (e) {
    final msg = '$e';
    final lower = msg.toLowerCase();
    // Only treat true "collection missing" as a migration problem.
    // Auth / filter / expand failures must show the real server error.
    final missingCollection = lower.contains('collection missing') ||
        lower.contains('collection not found') ||
        lower.contains('1776820000') ||
        (lower.contains("couldn't find the collection") &&
            lower.contains('material_events'));
    // HTTP 400 on sort=-created usually means missing AutodateFields.
    final needsAutodate = !missingCollection &&
        (lower.contains('sort=-created') ||
            lower.contains('1776840000') ||
            (lower.contains('statuscode: 400') &&
                lower.contains('material_events')));
    rows.add(
      _MaterialHistoryRow(
        when: null,
        kind: _HistoryKind.error,
        headline: missingCollection
            ? 'Cut / scrap log not on this server yet'
            : needsAutodate
                ? 'Cut / scrap log needs a PocketBase schema update'
                : 'Could not load cut / scrap log',
        detail: missingCollection
            ? 'On the laptop run: scp pb_migrations/1776820000_material_events_create.js '
                'to CT105 /opt/pocketbase-erp-dev/pb_migrations/ then '
                'systemctl restart pocketbase-erp-dev. ($msg)'
            : needsAutodate
                ? 'On the laptop run: powershell -File .\\deploy\\ct105_material_events.ps1 '
                    '(applies 177684 autodate). Then hard-refresh. ($msg)'
                : msg,
      ),
    );
  }

  // Newest first. Undated rows are shelf events logged before PocketBase had
  // timestamps on material_events, which is newer than any purchase history.
  rows.sort((a, b) {
    final aw = a.when;
    final bw = b.when;
    if (aw == null && bw == null) return 0;
    if (aw == null) return -1;
    if (bw == null) return 1;
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
        title: Text('History of ${materialPieceLabelIdentityLine(material)}'),
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
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (ctx, i) => _MaterialHistoryRowView(row: rows[i]),
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

class _MaterialHistoryRowView extends StatelessWidget {
  const _MaterialHistoryRowView({required this.row});

  final _MaterialHistoryRow row;

  static final _dayFmt = DateFormat('MMM d yyyy');
  static final _timeFmt = DateFormat('HH:mm');

  IconData get _icon {
    switch (row.kind) {
      case _HistoryKind.purchase:
        return Icons.local_shipping_outlined;
      case _HistoryKind.intake:
        return Icons.add_box_outlined;
      case _HistoryKind.cut:
        return Icons.content_cut;
      case _HistoryKind.adjust:
        return Icons.edit_outlined;
      case _HistoryKind.scrap:
        return Icons.delete_sweep_outlined;
      case _HistoryKind.error:
        return Icons.error_outline;
      case _HistoryKind.other:
        return Icons.circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final isProblem =
        row.kind == _HistoryKind.scrap || row.kind == _HistoryKind.error;

    final when = row.when;
    // Purchase dates are calendar days; showing them in local time would
    // shift them to the previous evening.
    final day = when == null
        ? null
        : _dayFmt.format(row.dateOnly ? when.toUtc() : when.toLocal());
    final time = when == null || row.dateOnly
        ? null
        : _timeFmt.format(when.toLocal());

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day ?? 'No date',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: day == null ? FontWeight.w400 : FontWeight.w600,
                    color: day == null ? scheme.onSurfaceVariant : null,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (time != null)
                  Text(
                    time,
                    style: muted?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              _icon,
              size: 18,
              color: isProblem ? scheme.error : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.headline,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: row.kind == _HistoryKind.error ? scheme.error : null,
                  ),
                ),
                if (row.detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(row.detail, style: muted),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Material cut for this job" list on the job page (cut events linked via
/// `material_events.job`). Renders nothing until something has been cut.
class JobMaterialCutsSection extends StatefulWidget {
  const JobMaterialCutsSection({super.key, required this.jobId});

  final String jobId;

  @override
  State<JobMaterialCutsSection> createState() => _JobMaterialCutsSectionState();
}

class _JobMaterialCutsSectionState extends State<JobMaterialCutsSection> {
  List<dynamic> _events = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant JobMaterialCutsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jobId != widget.jobId) _load();
  }

  Future<void> _load() async {
    try {
      final events =
          await PocketBaseService().getMaterialEventsForJob(widget.jobId);
      final cuts = events.where((e) {
        final d = e.data as Map<String, dynamic>? ?? {};
        return (d['event_type'] ?? '') == 'cut';
      }).toList()
        ..sort((a, b) {
          final ta = _recordCreatedAt(a);
          final tb = _recordCreatedAt(b);
          if (ta == null || tb == null) return 0;
          return tb.compareTo(ta);
        });
      if (mounted) setState(() => _events = cuts);
    } catch (_) {
      // Older servers without material_events.job: just show nothing.
    }
  }

  static dynamic _single(dynamic expanded) =>
      (expanded is List && expanded.isNotEmpty) ? expanded.first : expanded;

  @override
  Widget build(BuildContext context) {
    if (_events.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateFmt = DateFormat('MMM d');
    final tabular = const [FontFeature.tabularFigures()];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          'Material cut for this job',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              for (var i = 0; i < _events.length; i++) ...[
                if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                () {
                  final rec = _events[i];
                  final data = rec.data as Map<String, dynamic>? ?? {};
                  final when = _recordCreatedAt(rec);
                  var identity = '';
                  var code = '';
                  try {
                    final pieceRec = _single(rec.expand?['piece']);
                    if (pieceRec != null) {
                      code = materialLabelCodeForSticker(
                        MaterialPiece.fromRecord(pieceRec).labelCode,
                      );
                      final matRec = _single(pieceRec.expand?['material']);
                      if (matRec != null) {
                        identity = materialPieceLabelIdentityLine(
                          ShopMaterial.fromRecord(matRec),
                        );
                      }
                    }
                  } catch (_) {}
                  final by = materialEventByName(data);
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 56,
                          child: Text(
                            when == null ? '—' : dateFmt.format(when.toLocal()),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontFeatures: tabular,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                identity.isEmpty ? 'Material' : identity,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                [
                                  describeMaterialEvent(rec, includeJob: false),
                                  if (code.isNotEmpty) code,
                                  if (by.isNotEmpty) by,
                                ].join('     '),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontFeatures: tabular,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }(),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
