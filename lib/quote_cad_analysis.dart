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

String cadFeatureSummaryLabel(Map<String, dynamic>? analysis) {
  if (analysis == null) return '';
  final count = analysis['feature_count'];
  final n = count is num ? count.toInt() : int.tryParse('$count') ?? 0;
  final setups = analysis['setup_count'];
  final s = setups is num ? setups.toInt() : int.tryParse('$setups') ?? 0;
  final types = analysis['feature_types'];
  String typeBit = '';
  if (types is Map && types.isNotEmpty) {
    final entries = types.entries.toList()
      ..sort((a, b) {
        final an = a.value is num ? (a.value as num).toInt() : 0;
        final bn = b.value is num ? (b.value as num).toInt() : 0;
        return bn.compareTo(an);
      });
    typeBit = entries
        .take(4)
        .map((e) => '${e.key}×${e.value}')
        .join(', ');
  }
  final parts = <String>[
    if (n > 0) '$n features',
    if (s > 0) '$s setups',
    if (typeBit.isNotEmpty) typeBit,
  ];
  return parts.join(' · ');
}

String? cadStockSuggestOf(Map<String, dynamic>? analysis) {
  final s = '${analysis?['stock_suggest_in'] ?? ''}'.trim();
  return s.isEmpty ? null : s;
}
