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

/// Plate blanks keep all three dims on the catalog (`1.5×3` + `3.5` → `1.5×3×3.5`).
/// Other forms store cross-section only; length lives on the purchase line.
bool catalogStoresBlankLength(String form) {
  final f = form.trim().toLowerCase();
  return f == 'plate';
}

/// Catalog [size_label] from the Size + Length fields.
String catalogSizeLabel({
  required String sectionSize,
  double? lengthIn,
  required String form,
}) {
  final section = (stripTrailingLengthFromSizeLabel(sectionSize) ??
          sectionSize.trim())
      .trim();
  if (section.isEmpty) return section;
  if (catalogStoresBlankLength(form) &&
      lengthIn != null &&
      lengthIn > 0) {
    // Prefer × to match existing shop labels.
    return '$section×${_formatInchesForSize(lengthIn)}';
  }
  return section;
}

String _formatInchesForSize(double v) {
  if (v == v.roundToDouble()) return '${v.round()}';
  var s = v.toStringAsFixed(3);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s;
}
