/// Build a carrier tracking URL from a raw tracking value (PIN or full URL).
Uri? trackingUri(String? raw, {String? hint}) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return null;

  if (t.startsWith('http://') || t.startsWith('https://')) {
    return Uri.tryParse(t);
  }

  final upper = t.toUpperCase();
  final h = (hint ?? '').toLowerCase();

  // UPS
  if (upper.startsWith('1Z') || h.contains('ups')) {
    return Uri.parse(
      'https://www.ups.com/track?tracknum=${Uri.encodeComponent(t)}',
    );
  }

  // FedEx
  if (h.contains('fedex')) {
    return Uri.parse(
      'https://www.fedex.com/fedextrack/?trknbr=${Uri.encodeComponent(t)}',
    );
  }

  // DHL
  if (h.contains('dhl')) {
    return Uri.parse(
      'https://www.dhl.com/en/express/tracking.html?AWB=${Uri.encodeComponent(t)}',
    );
  }

  // Purolator — numeric PINs or alphanumeric like CPK004315941
  if (h.contains('purolator') ||
      RegExp(r'^\d{11,16}$').hasMatch(t) ||
      RegExp(r'^[A-Za-z]{2,4}\d{8,14}$').hasMatch(t)) {
    return Uri.parse(
      'https://www.purolator.com/en/shipping/tracker?pin=${Uri.encodeComponent(t)}',
    );
  }

  // McMaster US often UPS — last resort open a generic search
  return Uri.parse(
    'https://www.google.com/search?q=${Uri.encodeComponent('tracking $t')}',
  );
}

String trackingDisplayLabel(String? raw) {
  final t = preferredTrackingValue(raw);
  if (t.isEmpty) return '';
  if (t.startsWith('http://') || t.startsWith('https://')) {
    final u = Uri.tryParse(t);
    if (u != null && u.host.isNotEmpty) {
      // Prefer showing the PIN when present in the URL
      final pin = u.queryParameters['pin'];
      if (pin != null && pin.isNotEmpty) return pin;
      return u.host.replaceFirst(RegExp(r'^www\.'), '');
    }
  }
  return t;
}

/// When merge stuffed "CPK… https://…pin=CPK…", keep one value (prefer URL).
String preferredTrackingValue(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return '';
  final parts = t.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.length <= 1) return t;

  String? url;
  String? pin;
  for (final p in parts) {
    if (p.startsWith('http://') || p.startsWith('https://')) {
      url ??= p;
    } else if (RegExp(r'^[A-Za-z]{2,4}\d{8,14}$').hasMatch(p) ||
        RegExp(r'^\d{11,16}$').hasMatch(p)) {
      pin ??= p;
    }
  }
  if (url != null) return url;
  if (pin != null) return pin;
  return parts.first;
}

/// Pull "Customer ref: 1013ASOLANKI" out of merged notes (first good hit).
String? customerRefFromNotes(String? notes) {
  if (notes == null || notes.trim().isEmpty) return null;
  final re = RegExp(r'Customer\s*ref\s*:\s*([A-Za-z0-9\-]+)', caseSensitive: false);
  for (final m in re.allMatches(notes)) {
    final v = m.group(1)?.trim() ?? '';
    if (v.isEmpty) continue;
    final upper = v.toUpperCase();
    if (upper == 'ORDER' || upper == 'DATE' || upper == 'NUMBER') continue;
    return v;
  }
  return null;
}

/// Notes for display: drop Customer ref / Tracking lines (shown as chips/link).
String displayNotesWithoutDupes(String? notes) {
  if (notes == null || notes.trim().isEmpty) return '';
  final out = <String>[];
  final seen = <String>{};
  for (final raw in notes.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final lower = line.toLowerCase();
    if (lower.startsWith('customer ref:')) continue;
    if (lower.startsWith('tracking:')) continue;
    if (seen.contains(lower)) continue;
    seen.add(lower);
    out.add(line);
  }
  return out.join('\n');
}
