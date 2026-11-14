import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'material_form_icons.dart';
import 'material_stock_dialogs.dart';
import 'models.dart';
import 'pocketbase_service.dart';

/// On-shelf piece + its catalog material for quote matching.
class ShelfStockCandidate {
  final MaterialPiece piece;
  final ShopMaterial material;
  final int score;
  final String matchLabel;
  final double? lastUnitCost;
  final double? costPerInch;

  const ShelfStockCandidate({
    required this.piece,
    required this.material,
    required this.score,
    required this.matchLabel,
    this.lastUnitCost,
    this.costPerInch,
  });

  String get remLabel => 'REM ${formatInchesValue(piece.lengthIn)}';

  String get identityLine {
    final grade = material.grade.trim();
    final form = materialFormLabel(material.form);
    final size = formatMaterialSizeForLabel(material.sizeLabel);
    return [
      if (grade.isNotEmpty) grade,
      form,
      if (size.isNotEmpty) size,
    ].join(' ');
  }

  String get shelfRefLine {
    final lot = (piece.heatLot ?? '').trim();
    return [
      materialLabelCodeForSticker(piece.labelCode),
      remLabel,
      if (lot.isNotEmpty) 'Lot $lot',
    ].join(' · ');
  }
}

List<double> parseSizeNumbers(String sizeLabel) {
  final matches = RegExp(r'\d+\.?\d*').allMatches(sizeLabel.trim());
  return [
    for (final m in matches)
      double.tryParse(m.group(0) ?? '')
  ].whereType<double>().where((n) => n > 0).toList();
}

/// Cross-section dims only. Catalog labels like `1 × 4 × 144` treat the last
/// number as bar length when there are 3+ dims (same for a cut size like `2×4×6`).
List<double> crossSectionDims(List<double> dims) {
  if (dims.length >= 3) return dims.sublist(0, dims.length - 1);
  return List<double>.from(dims);
}

/// True when [have] can yield [need]: every needed cross-section dim fits in
/// some orientation (sorted pairwise, each stock dim >= needed dim).
bool stockCoversNeed(List<double> need, List<double> have) {
  final n = crossSectionDims(need)..sort();
  final h = crossSectionDims(have)..sort();
  if (n.isEmpty || h.isEmpty || n.length != h.length) return false;
  for (var i = 0; i < n.length; i++) {
    if (h[i] + 0.001 < n[i]) return false;
  }
  return true;
}

/// Higher is better. Exact section beats closer oversize. Undersize scores 0.
int scoreSizeMatch(List<double> need, List<double> have) {
  if (need.isEmpty || have.isEmpty) return 0;
  if (!stockCoversNeed(need, have)) return 0;

  final n = crossSectionDims(need)..sort();
  final h = crossSectionDims(have)..sort();

  var exact = true;
  for (var i = 0; i < n.length; i++) {
    if ((n[i] - h[i]).abs() > 0.001) {
      exact = false;
      break;
    }
  }
  if (exact) return 1000;

  // Prefer the least oversize (less waste).
  var waste = 0.0;
  for (var i = 0; i < n.length; i++) {
    waste += h[i] - n[i];
  }
  return (800 - (waste * 20).round()).clamp(500, 799);
}

String matchLabelForScore(int score) {
  if (score >= 1000) return 'Exact size';
  if (score >= 500) return 'Larger stock';
  return 'Other stock';
}

Future<List<ShelfStockCandidate>> loadShelfStockCandidates({
  required String stockSizeQuery,
  String? alloyHint,
}) async {
  final pb = PocketBaseService();
  final pieceRecords = await pb.getOnShelfPiecesExpanded();
  final need = parseSizeNumbers(stockSizeQuery);
  final alloyQ = (alloyHint ?? '').trim().toLowerCase();

  // Last unit cost by material (newest first from purchase history).
  final costCache = <String, ({double? unit, double? perInch})>{};

  final out = <ShelfStockCandidate>[];
  for (final row in pieceRecords) {
    final piece = row.piece;
    final material = row.material;
    if (!piece.isOnShelf || piece.lengthIn <= 0) continue;

    final have = parseSizeNumbers(material.sizeLabel);
    var score = scoreSizeMatch(need, have);
    if (need.isNotEmpty && score == 0) continue;

    if (alloyQ.isNotEmpty) {
      final grade = material.grade.trim().toLowerCase();
      if (grade.contains(alloyQ) || alloyQ.contains(grade)) {
        score += 40;
      }
    }

    if (!costCache.containsKey(material.id)) {
      try {
        final hist = await pb.getPurchaseItemsByMaterial(material.id);
        double? unit;
        for (final r in hist) {
          final item = PurchaseItem.fromRecord(r);
          if (item.unitCost != null && item.unitCost! > 0) {
            unit = item.unitCost;
            break;
          }
        }
        double? perInch;
        if (unit != null) {
          final u = material.unit.trim().toLowerCase();
          if (u == 'in') {
            perInch = unit;
          } else if (u == 'ft') {
            perInch = unit / 12;
          } else {
            final nums = parseSizeNumbers(material.sizeLabel);
            if (nums.isNotEmpty) perInch = unit / nums.last;
          }
        }
        costCache[material.id] = (unit: unit, perInch: perInch);
      } catch (_) {
        costCache[material.id] = (unit: null, perInch: null);
      }
    }
    final costs = costCache[material.id]!;

    out.add(ShelfStockCandidate(
      piece: piece,
      material: material,
      score: score,
      matchLabel: matchLabelForScore(score),
      lastUnitCost: costs.unit,
      costPerInch: costs.perInch,
    ));
  }

  out.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return b.piece.lengthIn.compareTo(a.piece.lengthIn);
  });
  return out;
}

/// Picker: optional on-shelf match for a quote line. Does not change stock size.
Future<ShelfStockCandidate?> showFindShelfStockDialog(
  BuildContext context, {
  required String stockSizeQuery,
  String? alloyHint,
}) async {
  return showDialog<ShelfStockCandidate>(
    context: context,
    builder: (ctx) => _FindShelfStockDialog(
      stockSizeQuery: stockSizeQuery,
      alloyHint: alloyHint,
    ),
  );
}

class _FindShelfStockDialog extends StatefulWidget {
  final String stockSizeQuery;
  final String? alloyHint;

  const _FindShelfStockDialog({
    required this.stockSizeQuery,
    this.alloyHint,
  });

  @override
  State<_FindShelfStockDialog> createState() => _FindShelfStockDialogState();
}

class _FindShelfStockDialogState extends State<_FindShelfStockDialog> {
  bool _loading = true;
  String? _error;
  List<ShelfStockCandidate> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await loadShelfStockCandidates(
        stockSizeQuery: widget.stockSizeQuery,
        alloyHint: widget.alloyHint,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final money = NumberFormat.currency(symbol: '\$');
    final sizeQ = widget.stockSizeQuery.trim();

    return AlertDialog(
      title: const Text('Find on shelf'),
      content: SizedBox(
        width: 480,
        child: _loading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? Text(_error!, style: TextStyle(color: scheme.error))
                : _rows.isEmpty
                    ? Text(
                        sizeQ.isEmpty
                            ? 'Enter a stock size per part first, then search the shelf.'
                            : 'No on-shelf pieces match "$sizeQ".',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            sizeQ.isEmpty
                                ? 'On-shelf pieces'
                                : 'Matches for $sizeQ (stock size is unchanged)',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 360),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: _rows.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final c = _rows[index];
                                final costHint = c.costPerInch != null
                                    ? '${money.format(c.costPerInch)}/in'
                                    : c.lastUnitCost != null
                                        ? 'Last ${money.format(c.lastUnitCost)}'
                                        : null;
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(c.identityLine),
                                  subtitle: Text(
                                    [
                                      c.matchLabel,
                                      c.shelfRefLine,
                                      if (costHint != null) costHint,
                                    ].join(' · '),
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => Navigator.pop(context, c),
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
