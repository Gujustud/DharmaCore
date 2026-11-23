import 'dart:convert';
import 'dart:math' as math;

import 'app_config.dart';
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
  // Thickness × width × length (small → large), same convention as stock.
  final dims = [x, y, z]..sort();
  return '${formatInchesValue(dims[0])} x ${formatInchesValue(dims[1])} x ${formatInchesValue(dims[2])} in';
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

/// Stock from AABB extents: +pad, round each axis up to [step], then
/// thickness × width × length (small → large) for shelf matching.
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
  ]..sort();
  final positive = dims.where((d) => d > 0).toList();
  if (positive.isEmpty) return null;
  return positive.map(formatInchesValue).join(' x ');
}

class CadVec3 {
  final double x;
  final double y;
  final double z;

  const CadVec3(this.x, this.y, this.z);

  factory CadVec3.fromJson(dynamic raw) {
    if (raw is! Map) return const CadVec3(0, 0, 0);
    return CadVec3(
      double.tryParse('${raw['x']}') ?? 0,
      double.tryParse('${raw['y']}') ?? 0,
      double.tryParse('${raw['z']}') ?? 0,
    );
  }

  Map<String, double> toJson() => {'x': x, 'y': y, 'z': z};

  double get length {
    final l = _hypot3(x, y, z);
    return l;
  }

  CadVec3 normalized() {
    final l = length;
    if (l < 1e-9) return const CadVec3(0, 0, 1);
    return CadVec3(x / l, y / l, z / l);
  }

  CadVec3 operator -() => CadVec3(-x, -y, -z);

  double dot(CadVec3 o) => x * o.x + y * o.y + z * o.z;

  CadVec3 cross(CadVec3 o) => CadVec3(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );

  bool nearlyEquals(CadVec3 o, [double eps = 1e-3]) =>
      (x - o.x).abs() <= eps &&
      (y - o.y).abs() <= eps &&
      (z - o.z).abs() <= eps;
}

double _hypot3(double a, double b, double c) => math.sqrt(a * a + b * b + c * c);

List<CadVec3> cadCandidateDirectionsOf(Map<String, dynamic>? analysis) {
  final raw = analysis?['candidate_directions'];
  if (raw is! List) return const [];
  return raw
      .map(CadVec3.fromJson)
      .where((v) => v.length > 1e-6)
      .map((v) => v.normalized())
      .toList();
}

CadVec3? cadBottomDirectionOf(Map<String, dynamic>? analysis) {
  final raw = analysis?['bottom_direction'];
  if (raw == null) return null;
  final v = CadVec3.fromJson(raw);
  if (v.length < 1e-6) return null;
  return v.normalized();
}

/// Short axis-ish label for a unit direction (e.g. −Z, +X).
String cadDirectionLabel(CadVec3 v) {
  final n = v.normalized();
  const axes = <(String, CadVec3)>[
    ('+X', CadVec3(1, 0, 0)),
    ('−X', CadVec3(-1, 0, 0)),
    ('+Y', CadVec3(0, 1, 0)),
    ('−Y', CadVec3(0, -1, 0)),
    ('+Z', CadVec3(0, 0, 1)),
    ('−Z', CadVec3(0, 0, -1)),
  ];
  var best = axes.first;
  var bestDot = -2.0;
  for (final a in axes) {
    final d = n.dot(a.$2);
    if (d > bestDot) {
      bestDot = d;
      best = a;
    }
  }
  if (bestDot >= 0.92) return best.$1;
  return '(${n.x.toStringAsFixed(2)}, '
      '${n.y.toStringAsFixed(2)}, '
      '${n.z.toStringAsFixed(2)})';
}

/// Oriented stock with [bottom] as fixture-down normal.
///
/// Extents are measured in the fixture frame (thickness along [bottom], plus
/// the two table-plane spans), then each is padded/ceiled and **all three are
/// sorted ascending** → thickness × width × length (small → large) for Find
/// on shelf. Same order as AABB stock so a face pick never yields `5 x 1 x 7.5`.
String? cadStockSuggestFromBottom(
  Map<String, dynamic>? analysis,
  CadVec3 bottom, {
  double pad = kCadStockPadIn,
  double step = kCadStockStepIn,
}) {
  final lower = analysis?['bbox_lower_mm'];
  final upper = analysis?['bbox_upper_mm'];
  if (lower is! Map || upper is! Map) {
    // Old analyses without corners — fall back to AABB sort.
    return cadStockSuggestFromBboxIn(analysis, pad: pad, step: step);
  }
  final lo = CadVec3.fromJson(lower);
  final hi = CadVec3.fromJson(upper);
  final down = bottom.normalized();

  // Orthonormal frame: ez = down, ex/ey span the table plane.
  CadVec3 helper = down.x.abs() < 0.9
      ? const CadVec3(1, 0, 0)
      : const CadVec3(0, 1, 0);
  var ex = helper.cross(down).normalized();
  if (ex.length < 1e-6) {
    helper = const CadVec3(0, 0, 1);
    ex = helper.cross(down).normalized();
  }
  final ey = down.cross(ex).normalized();

  final corners = <CadVec3>[
    for (final x in [lo.x, hi.x])
      for (final y in [lo.y, hi.y])
        for (final z in [lo.z, hi.z]) CadVec3(x, y, z),
  ];

  var minX = double.infinity, maxX = -double.infinity;
  var minY = double.infinity, maxY = -double.infinity;
  var minZ = double.infinity, maxZ = -double.infinity;
  for (final c in corners) {
    final px = c.dot(ex);
    final py = c.dot(ey);
    final pz = c.dot(down);
    if (px < minX) minX = px;
    if (px > maxX) maxX = px;
    if (py < minY) minY = py;
    if (py > maxY) maxY = py;
    if (pz < minZ) minZ = pz;
    if (pz > maxZ) maxZ = pz;
  }

  // mm → inches
  const mmPerIn = 25.4;
  final thicknessIn = (maxZ - minZ).abs() / mmPerIn;
  final aIn = (maxX - minX).abs() / mmPerIn;
  final bIn = (maxY - minY).abs() / mmPerIn;
  if (thicknessIn <= 0 && aIn <= 0 && bIn <= 0) return null;

  final dims = [
    cadCeilToStepInches(thicknessIn + pad, step),
    cadCeilToStepInches(aIn + pad, step),
    cadCeilToStepInches(bIn + pad, step),
  ]..sort();
  final positive = dims.where((d) => d > 0).toList();
  if (positive.isEmpty) return null;
  return positive.map(formatInchesValue).join(' x ');
}

/// Normalize stock size strings for equality (`5 x 1 x 7.5` vs `5 × 1 × 7.5`).
String cadStockSizeKey(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll('×', 'x')
      .replaceAll(RegExp(r'\s+'), '');
}

String? cadStockSuggestOf(Map<String, dynamic>? analysis) {
  final bottom = cadBottomDirectionOf(analysis);
  if (bottom != null) {
    final oriented = cadStockSuggestFromBottom(analysis, bottom);
    if (oriented != null) return oriented;
  }
  // Prefer live rounding from bbox so Apply stock picks up shop 0.5" steps
  // even if the stored suggest was from an older analyze.
  final fromBbox = cadStockSuggestFromBboxIn(analysis);
  if (fromBbox != null) return fromBbox;
  final s = '${analysis?['stock_suggest_in'] ?? ''}'.trim();
  return s.isEmpty ? null : s;
}

/// Toolpath Engine part id from a successful analysis (for mesh proxy).
String? cadToolpathPartIdOf(Map<String, dynamic>? analysis) {
  if (analysis == null) return null;
  final id = '${analysis['toolpath_part_id'] ?? ''}'.trim();
  return id.isEmpty ? null : id;
}

/// MCP proxy URL for the display GLB (auth key stays on the server).
String cadToolpathMeshGlbUrl(String partId) {
  final base = AppConfig.mcpUrl.replaceAll(RegExp(r'/+$'), '');
  return '$base/api/toolpath/parts/$partId/mesh.glb';
}

