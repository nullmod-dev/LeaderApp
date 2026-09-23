import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The app's injectable "now" for widgets.
///
/// The repositories that already needed a pinnable clock take one through
/// their constructor (`MockShiftRepository`, `PendingOperation`, `UuidV7`).
/// A widget has no constructor a test can reach, so the same seam is offered
/// here as a provider: the default is `DateTime.now` and production behaviour
/// is unchanged, while a test can pin the instant a time-dependent screen
/// reads.
///
/// Use it only where "now" actually decides what is rendered — a screen that
/// merely formats a stored timestamp needs no clock.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
