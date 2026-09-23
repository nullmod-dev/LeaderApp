final RegExp _couponPattern = RegExp(r'^[A-Z0-9-]{3,24}$');

/// Returns the canonical stored spelling, or `null` for an invalid code.
String? normalizeCouponCode(String raw) {
  final normalized = raw.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
  return _couponPattern.hasMatch(normalized) ? normalized : null;
}
