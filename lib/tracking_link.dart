/// Normalized tracking number (no spaces, uppercased), or empty.
String _cleanTrackingNumber(String? trackingNumber) {
  if (trackingNumber == null || trackingNumber.isEmpty) return '';
  return trackingNumber.replaceAll(RegExp(r'\s'), '').toUpperCase();
}

/// Guessed carrier label for a tracking number, or null if unknown.
String? trackingCarrierName(String? trackingNumber) {
  final clean = _cleanTrackingNumber(trackingNumber);
  if (clean.isEmpty) return null;
  if (RegExp(r'^\d{12,14}$').hasMatch(clean)) return 'FedEx';
  if (clean.startsWith('1Z')) return 'UPS';
  if (RegExp(r'^\d{13}$').hasMatch(clean)) return 'Canada Post';
  if (clean.startsWith('P')) return 'Purolator';
  if (RegExp(r'^\d{9,11}$').hasMatch(clean)) return 'DHL';
  return null;
}

/// Carrier tracking URLs from a tracking number (DharmaCore `generateTrackingLink`).
String generateTrackingLink(String? trackingNumber) {
  final clean = _cleanTrackingNumber(trackingNumber);
  if (clean.isEmpty) return '';

  if (RegExp(r'^\d{12,14}$').hasMatch(clean)) {
    return 'https://www.fedex.com/fedextrack/?tracknumbers=$clean';
  }
  if (clean.startsWith('1Z')) {
    return 'https://www.ups.com/track?tracknum=$clean';
  }
  if (RegExp(r'^\d{13}$').hasMatch(clean)) {
    return 'https://www.canadapost-postescanada.ca/track-reperage/en#/search?searchFor=$clean';
  }
  if (clean.startsWith('P')) {
    return 'https://www.purolator.com/en/shipping/tracker?pin=$clean';
  }
  if (RegExp(r'^\d{9,11}$').hasMatch(clean)) {
    return 'https://mydhl.express.dhl/ca/en/tracking.html#/results?id=$clean';
  }
  return '';
}
