/// Build reorder URLs from known vendor part numbers.

final _mcmasterPnRe = RegExp(
  r'\b([0-9]{3,5}[A-Za-z][0-9A-Za-z]{2,8})\b',
);

/// Extract a McMaster-style part number from free text / notes.
String? mcmasterPartNumberFromText(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  // Prefer explicit "McMaster 8741K53"
  final labeled = RegExp(
    r'McMaster(?:-Carr)?\s+([0-9]{3,5}[A-Za-z][0-9A-Za-z]{2,8})\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (labeled != null) return labeled.group(1)!.toUpperCase();
  final m = _mcmasterPnRe.firstMatch(text);
  return m?.group(1)?.toUpperCase();
}

String? mcmasterProductUrl(String? partOrNotes) {
  final pn = mcmasterPartNumberFromText(partOrNotes);
  if (pn == null || pn.isEmpty) return null;
  return 'https://www.mcmaster.com/$pn';
}

String mcmasterNotesSeed(String partNumber) {
  final pn = partNumber.trim().toUpperCase();
  if (pn.isEmpty) return '';
  return 'McMaster $pn';
}
