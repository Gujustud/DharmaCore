import 'package:flutter/material.dart';

import 'material_form_icons.dart';
import 'material_size_parse.dart';
import 'models.dart';
import 'pocketbase_service.dart';
import 'shop_material_editor.dart';

/// Merge [source] into a survivor catalog row (pick or create).
///
/// Returns the survivor when merge succeeds; null if cancelled.
Future<ShopMaterial?> showMaterialMergeDialog(
  BuildContext context, {
  required ShopMaterial source,
  required List<ShopMaterial> catalog,
}) {
  return showDialog<ShopMaterial>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _MaterialMergeDialog(
      source: source,
      catalog: catalog,
    ),
  );
}

class _MaterialMergeDialog extends StatefulWidget {
  const _MaterialMergeDialog({
    required this.source,
    required this.catalog,
  });

  final ShopMaterial source;
  final List<ShopMaterial> catalog;

  @override
  State<_MaterialMergeDialog> createState() => _MaterialMergeDialogState();
}

class _MaterialMergeDialogState extends State<_MaterialMergeDialog> {
  ShopMaterial? _survivor;
  MaterialMergePreview? _preview;
  bool _loadingPreview = true;
  bool _merging = false;
  bool _inferLength = true;
  bool _stripSurvivorLength = true;
  String? _error;

  List<ShopMaterial> get _candidates {
    final src = widget.source;
    final others = widget.catalog.where((m) => m.id != src.id).toList();
    int score(ShopMaterial m) {
      var s = 0;
      if (m.grade.trim().toLowerCase() == src.grade.trim().toLowerCase()) {
        s += 4;
      }
      if (canonicalMaterialForm(m.form) == canonicalMaterialForm(src.form)) {
        s += 2;
      }
      final srcCross = crossSectionDims(parseSizeNumbers(src.sizeLabel));
      final mCross = crossSectionDims(parseSizeNumbers(m.sizeLabel));
      if (srcCross.isNotEmpty &&
          mCross.length == srcCross.length &&
          _dimsClose(srcCross, mCross)) {
        s += 3;
      }
      return s;
    }

    others.sort((a, b) {
      final d = score(b).compareTo(score(a));
      if (d != 0) return d;
      return a.displayLabel.compareTo(b.displayLabel);
    });
    return others;
  }

  static bool _dimsClose(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 0.001) return false;
    }
    return true;
  }

  double? get _inferredLength => barLengthFromSizeLabel(widget.source.sizeLabel);

  String? get _survivorStrippedSize {
    final s = _survivor;
    if (s == null) return null;
    return stripTrailingLengthFromSizeLabel(s.sizeLabel);
  }

  bool get _sourceIsPlate => catalogStoresBlankLength(widget.source.form);

  bool get _survivorIsPlate =>
      _survivor != null && catalogStoresBlankLength(_survivor!.form);

  @override
  void initState() {
    super.initState();
    final cands = _candidates;
    if (cands.isNotEmpty) {
      _survivor = cands.first;
    }
    // Plate blanks should stay separate; don't strip blank size on merge.
    if (_sourceIsPlate || _survivorIsPlate) {
      _stripSurvivorLength = false;
    }
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _loadingPreview = true;
      _error = null;
    });
    try {
      final preview =
          await PocketBaseService().previewMaterialMerge(widget.source.id);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _loadingPreview = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loadingPreview = false;
      });
    }
  }

  Future<void> _createSurvivor() async {
    final suggested = stripTrailingLengthFromSizeLabel(widget.source.sizeLabel);
    final result = await showShopMaterialEditor(
      context,
      existing: ShopMaterial(
        id: '',
        grade: widget.source.grade,
        form: widget.source.form,
        sizeLabel: suggested ?? widget.source.sizeLabel,
        unit: widget.source.unit,
        notes: widget.source.notes,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _survivor = result.material);
  }

  Future<void> _runMerge() async {
    final survivor = _survivor;
    if (survivor == null) {
      setState(() => _error = 'Pick a material to merge into');
      return;
    }
    setState(() {
      _merging = true;
      _error = null;
    });
    try {
      final result = await PocketBaseService().mergeMaterials(
        sourceId: widget.source.id,
        survivorId: survivor.id,
        inferLengthFromSize: _inferLength,
        stripSurvivorSizeLength: _stripSurvivorLength,
      );
      // Re-fetch survivor in case size was stripped.
      final rec =
          await PocketBaseService().pb.collection('materials').getOne(
                result.survivorId,
              );
      if (!mounted) return;
      Navigator.pop(context, ShopMaterial.fromRecord(rec));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _merging = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final src = widget.source;
    final inferred = _inferredLength;
    final stripped = _survivorStrippedSize;
    final preview = _preview;
    final cands = _candidates;

    return AlertDialog(
      title: const Text('Merge material'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Move everything from this catalog row onto another, then delete it.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              if (_sourceIsPlate || _survivorIsPlate) ...[
                const SizedBox(height: 8),
                Text(
                  'Plate blanks are usually kept separate (grain / cut size). '
                  'Merge only if you really want one catalog row.',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
              ],
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Merging away',
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  src.displayLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 12),
              if (_loadingPreview)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                )
              else if (preview != null) ...[
                Text(
                  _previewSummary(preview),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _survivor?.id,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Merge into',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        if (_survivor != null &&
                            !cands.any((m) => m.id == _survivor!.id))
                          DropdownMenuItem(
                            value: _survivor!.id,
                            child: Text(
                              _survivor!.displayLabel,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        for (final m in cands)
                          DropdownMenuItem(
                            value: m.id,
                            child: Text(
                              m.displayLabel,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _merging
                          ? null
                          : (id) {
                              if (id == null) return;
                              setState(() {
                                if (_survivor?.id == id) return;
                                for (final m in cands) {
                                  if (m.id == id) {
                                    _survivor = m;
                                    break;
                                  }
                                }
                                if (_survivorIsPlate) {
                                  _stripSurvivorLength = false;
                                }
                              });
                            },
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _merging ? null : _createSurvivor,
                    child: const Text('New…'),
                  ),
                ],
              ),
              if (inferred != null && inferred > 0) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _inferLength,
                  onChanged: _merging
                      ? null
                      : (v) => setState(() => _inferLength = v ?? true),
                  title: Text(
                    'Set Length ${formatInchesValue(inferred)} in on purchase '
                    'lines that have no Length',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
              if (stripped != null && !_survivorIsPlate) ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _stripSurvivorLength,
                  onChanged: _merging
                      ? null
                      : (v) =>
                          setState(() => _stripSurvivorLength = v ?? true),
                  title: Text(_stripSurvivorCheckboxLabel(stripped)),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: scheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _merging ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _merging || _survivor == null ? null : _runMerge,
          child: _merging
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Merge'),
        ),
      ],
    );
  }

  String _stripSurvivorCheckboxLabel(String strippedSize) {
    final survLen = barLengthFromSizeLabel(_survivor!.sizeLabel);
    if (survLen != null && survLen > 0) {
      return 'Strip survivor size → “$strippedSize”, and set Length '
          '${formatInchesValue(survLen)} in on its purchase lines that have '
          'no Length';
    }
    return 'Strip survivor size → “$strippedSize”';
  }

  String _previewSummary(MaterialMergePreview p) {
    final parts = <String>[];
    if (p.purchaseLines > 0) {
      parts.add(
        '${p.purchaseLines} purchase line${p.purchaseLines == 1 ? '' : 's'}',
      );
    }
    if (p.pieces > 0) {
      parts.add('${p.pieces} stock piece${p.pieces == 1 ? '' : 's'}');
    }
    if (p.quoteLines > 0) {
      parts.add('${p.quoteLines} quote line${p.quoteLines == 1 ? '' : 's'}');
    }
    if (p.draftLines > 0) {
      parts.add('${p.draftLines} draft line${p.draftLines == 1 ? '' : 's'}');
    }
    if (p.proposals > 0) {
      parts.add('${p.proposals} proposal${p.proposals == 1 ? '' : 's'}');
    }
    if (parts.isEmpty) {
      return 'No linked purchases, stock, or quotes — safe empty merge.';
    }
    return 'Will move: ${parts.join(', ')}.';
  }
}
