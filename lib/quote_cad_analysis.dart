import 'dart:convert';

import 'models.dart';

/// Parse `cad_analysis` JSON stored on a quote line.
Map<String, dynamic>? parseCadAnalysis(dynamic raw) {
  if (raw == null || raw == '') return null;
  if (raw is Map) {
    return Map<String, dynamic>.from(raw);
  }
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  try {
    final decoded = json.decode(s);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return null;
}

String encodeCadAnalysis(Map<String, dynamic> data) => json.encode(data);

String? cadAnalysisStatusOf(Map<String, dynamic>? analysis) {
  if (analysis == null) return null;
  final s = '${analysis['status'] ?? ''}'.trim();
  return s.isEmpty ? null : s;
}

String cadBboxInchesLabel(Map<String, dynamic>? analysis) {
  final box = analysis?['bbox_in'];
  if (box is! Map) return '';
  final x = double.tryParse('${box['x']}') ?? 0;
  final y = double.tryParse('${box['y']}') ?? 0;
  final z = double.tryParse('${box['z']}') ?? 0;
  if (x <= 0 && y <= 0 && z <= 0) return '';
  return '${formatInchesValue(x)} x ${formatInchesValue(y)} x ${formatInchesValue(z)} in';
}

String cadFeatureCountsLabel(Map<String, dynamic>? analysis) {
  if (analysis == null) return '';
  final count = analysis['feature_count'];
  final n = count is num ? count.toInt() : int.tryParse('$count') ?? 0;
  final setups = analysis['setup_count'];
  final s = setups is num ? setups.toInt() : int.tryParse('$setups') ?? 0;
  final parts = <String>[
    if (n > 0) '$n features',
    if (s > 0) '$s setups',
  ];
  return parts.join(' · ');
}

String cadFeatureTypesLabel(Map<String, dynamic>? analysis) {
  final types = analysis?['feature_types'];
  if (types is! Map || types.isEmpty) return '';
  final entries = types.entries.toList()
    ..sort((a, b) {
      final an = a.value is num ? (a.value as num).toInt() : 0;
      final bn = b.value is num ? (b.value as num).toInt() : 0;
      return bn.compareTo(an);
    });
  return entries.take(4).map((e) => '${e.key}×${e.value}').join(', ');
}

String cadFeatureSummaryLabel(Map<String, dynamic>? analysis) {
  final counts = cadFeatureCountsLabel(analysis);
  final types = cadFeatureTypesLabel(analysis);
  if (counts.isEmpty) return types;
  if (types.isEmpty) return counts;
  return '$counts · $types';
}

/// Default pad / step match MCP (`TOOLPATH_STOCK_PAD_IN` / `TOOLPATH_STOCK_STEP_IN`).
const double kCadStockPadIn = 0.1;
const double kCadStockStepIn = 0.5;

double cadCeilToStepInches(double value, [double step = kCadStockStepIn]) {
  if (value <= 0 || step <= 0) return 0;
  return (value / step).ceilToDouble() * step;
}

/// Stock from bbox: +pad, then round each axis up to [step] inches (default ½").
String? cadStockSuggestFromBboxIn(
  Map<String, dynamic>? analysis, {
  double pad = kCadStockPadIn,
  double step = kCadStockStepIn,
}) {
  final box = analysis?['bbox_in'];
  if (box is! Map) return null;
  final x = double.tryParse('${box['x']}') ?? 0;
  final y = double.tryParse('${box['y']}') ?? 0;
  final z = double.tryParse('${box['z']}') ?? 0;
  if (x <= 0 && y <= 0 && z <= 0) return null;
  final dims = [
    cadCeilToStepInches(x + pad, step),
    cadCeilToStepInches(y + pad, step),
    cadCeilToStepInches(z + pad, step),
  ]..sort((a, b) => b.compareTo(a));
  final positive = dims.where((d) => d > 0).toList();
  if (positive.isEmpty) return null;
  return positive.map(formatInchesValue).join(' x ');
}

String? cadStockSuggestOf(Map<String, dynamic>? analysis) {
  // Prefer live rounding from bbox so Apply stock picks up shop 0.5" steps
  // even if the stored suggest was from an older analyze.
  final fromBbox = cadStockSuggestFromBboxIn(analysis);
  if (fromBbox != null) return fromBbox;
  final s = '${analysis?['stock_suggest_in'] ?? ''}'.trim();
  return s.isEmpty ? null : s;
}
