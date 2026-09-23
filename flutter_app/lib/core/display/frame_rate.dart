import 'package:flutter/foundation.dart';

/// The user's chosen refresh-rate target.
///
/// This is a *display* setting, deliberately separate from `MotionLevel`:
/// the quality level decides how much work a single frame does, this
/// decides how often the platform is asked to produce one. Neither is
/// implemented in terms of the other, and nothing here throttles Flutter
/// or skips frames — see [DisplayRefresh] for how a choice is applied.
enum FrameRatePreference {
  /// Let the platform pick, which is what it does best: it can drop to a
  /// low-power mode on a static screen and come back up for a scroll.
  auto,
  fps30,
  fps60,
  fps90,
  fps120;

  /// The requested rate in hertz, or `null` for [auto].
  double? get hz => switch (this) {
        FrameRatePreference.auto => null,
        FrameRatePreference.fps30 => 30,
        FrameRatePreference.fps60 => 60,
        FrameRatePreference.fps90 => 90,
        FrameRatePreference.fps120 => 120,
      };

  String toJson() => name;

  /// Anything unrecognised — including a value written by a newer build —
  /// falls back to [auto], which is always valid on every device.
  static FrameRatePreference fromJson(String s) =>
      FrameRatePreference.values.firstWhere(
        (v) => v.name == s,
        orElse: () => FrameRatePreference.auto,
      );
}

/// What the device's display can actually be asked for.
///
/// Filled in by [DisplayRefresh] from the platform. Every field is
/// deliberately a fact about the hardware, not a preference: the UI decides
/// what to *offer* from this, and the resolver decides what to *request*.
@immutable
class DisplayCapabilities {
  const DisplayCapabilities({
    required this.supportedRates,
    required this.activeRate,
    required this.canSelectMode,
    required this.supportsFrameRateHint,
  });

  /// Refresh rates the panel has an actual display mode for, at the
  /// resolution it is currently running. Empty when the platform would not
  /// tell us.
  final List<double> supportedRates;

  /// The rate the display is running at right now, if known.
  final double? activeRate;

  /// True when the platform lets the app ask for a specific display mode
  /// (Android's `preferredDisplayModeId`). False elsewhere — on iOS,
  /// desktop and web the display link belongs to the engine and there is no
  /// supported way to move it, so [FrameRatePreference.auto] is the only
  /// honest option.
  final bool canSelectMode;

  /// True when the platform accepts a frame-rate *hint* for rates that have
  /// no mode of their own (Android 11's `Surface.setFrameRate`). The
  /// compositor decides what to do with it; we never enforce it ourselves.
  final bool supportsFrameRateHint;

  /// What we know before, or without, a platform answer: nothing
  /// selectable.
  static const DisplayCapabilities unknown = DisplayCapabilities(
    supportedRates: [],
    activeRate: null,
    canSelectMode: false,
    supportsFrameRateHint: false,
  );

  /// True when the device can honour anything other than [auto]. When this
  /// is false the settings row says so rather than offering choices that
  /// would quietly do nothing.
  bool get canChoose => canSelectMode || supportsFrameRateHint;

  double? get maxSupportedRate => supportedRates.isEmpty
      ? null
      : supportedRates.reduce((a, b) => a > b ? a : b);
}

/// How close two rates have to be to count as the same one. Panels report
/// 59.94, 60.000004 and 120.00001; a whole hertz of slack is far below the
/// gap between any two options here and well above that noise.
const double _rateTolerance = 1.0;

/// The options worth putting in front of the user on *this* device.
///
/// [FrameRatePreference.auto] is always offered, and on a platform that
/// will not take a request it is the *only* thing offered. Elsewhere a
/// fixed rate appears only when the device could actually deliver it:
/// either the panel has a display mode for it, or the platform takes
/// frame-rate hints and the rate is not above what the panel can do.
/// Asking a 60Hz phone for 120 is not a setting, it is a lie.
List<FrameRatePreference> availableFrameRates(DisplayCapabilities caps) {
  final options = <FrameRatePreference>[FrameRatePreference.auto];
  // Knowing the panel's rates is not the same as being allowed to ask for
  // one. Where the platform will not take the request, auto is the only
  // truthful option — a pill that silently does nothing is worse than an
  // absent pill.
  if (!caps.canChoose) return options;
  final max = caps.maxSupportedRate;
  for (final p in FrameRatePreference.values) {
    final hz = p.hz;
    if (hz == null) continue;
    final hasMode = caps.canSelectMode &&
        caps.supportedRates.any((r) => (r - hz).abs() <= _rateTolerance);
    // A hint can reach a rate the panel has no dedicated mode for (30 on a
    // 60Hz panel), but never one above the panel's ceiling.
    final canHint =
        caps.supportsFrameRateHint && max != null && hz <= max + _rateTolerance;
    if (hasMode || canHint) options.add(p);
  }
  return options;
}

/// The rate actually sent to the platform for [pref].
///
/// `null` means "auto — stop asking and hand the display back to the
/// system". Otherwise, when the panel has modes, the *closest* supported
/// one wins, preferring the lower of two equally close rates: overshooting
/// a request costs battery for smoothness the user just said they did not
/// want. When the panel reported no modes at all the request passes through
/// unchanged, for the platform to interpret.
double? resolveFrameRate(FrameRatePreference pref, DisplayCapabilities caps) {
  final target = pref.hz;
  if (target == null) return null;
  if (caps.supportedRates.isEmpty) return target;

  double best = caps.supportedRates.first;
  for (final r in caps.supportedRates.skip(1)) {
    final d = (r - target).abs();
    final bestD = (best - target).abs();
    if (d < bestD - 0.001 || ((d - bestD).abs() <= 0.001 && r < best)) {
      best = r;
    }
  }
  return best;
}

/// True when [pref] can be delivered exactly, rather than as the nearest
/// thing the panel has. The settings row uses this to say so out loud
/// instead of letting the user believe an approximation is the real value.
bool isFrameRateExact(FrameRatePreference pref, DisplayCapabilities caps) {
  final target = pref.hz;
  if (target == null) return true;
  final resolved = resolveFrameRate(pref, caps);
  if (resolved == null) return false;
  return (resolved - target).abs() <= _rateTolerance;
}
