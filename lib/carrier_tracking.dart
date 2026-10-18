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
  final t = (raw ?? '').trim();
  if (t.isEmpty) return '';
  if (t.startsWith('http://') || t.startsWith('https://')) {
    final u = Uri.tryParse(t);
    if (u != null && u.host.isNotEmpty) {
      return u.host.replaceFirst(RegExp(r'^www\.'), '');
    }
  }
  return t;
}
