/// Shared parsing for free-text material size labels (`3×6`, `1.5" OD x 12"`).

List<double> parseSizeNumbers(String sizeLabel) {
  final matches = RegExp(r'\d+\.?\d*').allMatches(sizeLabel.trim());
  return [
    for (final m in matches) double.tryParse(m.group(0) ?? '')
  ].whereType<double>().where((n) => n > 0).toList();
}

/// Cross-section dims only. Catalog labels like `1 × 4 × 144` treat the last
/// number as bar length when there are 3+ dims.
List<double> crossSectionDims(List<double> dims) {
  if (dims.length >= 3) return dims.sublist(0, dims.length - 1);
  return List<double>.from(dims);
}

/// Cut / bar length when 3+ numbers (e.g. `1×4×20` → 20).
double? neededLengthFromSize(List<double> dims) {
  if (dims.length < 3) return null;
  return dims.last;
}

/// Trailing bar length from a catalog size that still embeds length
/// (e.g. `3×6×23` → 23). Null when size looks like cross-section only.
double? barLengthFromSizeLabel(String sizeLabel) {
  return neededLengthFromSize(parseSizeNumbers(sizeLabel));
}

/// Strip trailing bar length from a size label (`3×6×23` → `3×6`).
/// Returns null when there is nothing to strip.
String? stripTrailingLengthFromSizeLabel(String sizeLabel) {
  final trimmed = sizeLabel.trim();
  if (parseSizeNumbers(trimmed).length < 3) return null;
  final stripped = trimmed.replaceFirst(
    RegExp(r'[\s×xX*/\-]+[\d.]+(?:\s*(?:["″]|in(?:ch(?:es)?)?))?\s*$'),
    '',
  );
  final out = stripped.trim();
  if (out.isEmpty || out == trimmed) return null;
  return out;
}
