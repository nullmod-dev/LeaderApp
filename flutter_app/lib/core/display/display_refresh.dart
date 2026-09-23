import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'frame_rate.dart';

/// Applies a [FrameRatePreference] using the platform's own display APIs.
///
/// ## What this does *not* do
///
/// It never throttles Flutter, never sleeps a timer between frames and
/// never skips a frame to fake a lower number. Those all produce real jank
/// — uneven frame times — while claiming to be a smoothness setting. What
/// it does instead is tell the platform which refresh rate the app would
/// like the *display* to run at, and let the compositor schedule frames the
/// way it already knows how.
///
/// ## Per platform
///
/// - **Android** (`MainActivity`): `Display.getSupportedModes()` reports the
///   modes the panel really has, and `WindowManager.LayoutParams`'
///   `preferredDisplayModeId` switches to one. On API 30+ the window also
///   takes a `setFrameRate` hint, which reaches rates that have no mode of
///   their own (30 on a 60Hz panel). Auto clears both.
/// - **Everywhere else**: the display link belongs to the engine and there
///   is no supported way to move it, so only [FrameRatePreference.auto] is
///   offered. The active rate is still read, from
///   `PlatformDispatcher.displays`, so the settings row can at least say
///   what the device is doing.
///
/// A device that cannot honour an exact request is reported honestly:
/// [DisplayCapabilities] carries what is really available and the settings
/// row shows the nearest rate rather than the one that was asked for.
class DisplayRefresh {
  DisplayRefresh({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  /// Matches the channel name registered in `MainActivity.kt`.
  static const String channelName = 'mtm/display';

  final MethodChannel _channel;

  DisplayCapabilities? _cached;

  /// What the display can be asked for. Cached for the process — a panel's
  /// mode list does not change while the app is running, and the settings
  /// screen would otherwise hit the channel on every rebuild.
  Future<DisplayCapabilities> capabilities() async {
    final cached = _cached;
    if (cached != null) return cached;
    final caps = await _readCapabilities();
    _cached = caps;
    return caps;
  }

  Future<DisplayCapabilities> _readCapabilities() async {
    final engineRate = _engineRefreshRate();
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'capabilities',
      );
      if (raw == null) return _fallback(engineRate);
      final rates = (raw['supportedRates'] as List?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const <double>[];
      rates.sort();
      return DisplayCapabilities(
        supportedRates: rates,
        activeRate: (raw['activeRate'] as num?)?.toDouble() ?? engineRate,
        canSelectMode: raw['canSelectMode'] as bool? ?? false,
        supportsFrameRateHint: raw['supportsFrameRateHint'] as bool? ?? false,
      );
    } on MissingPluginException {
      // No native side on this platform — the honest answer is "auto only".
      return _fallback(engineRate);
    } on PlatformException catch (e) {
      debugPrint('DisplayRefresh.capabilities failed: ${e.message}');
      return _fallback(engineRate);
    }
  }

  DisplayCapabilities _fallback(double? engineRate) => DisplayCapabilities(
        supportedRates: engineRate == null ? const [] : [engineRate],
        activeRate: engineRate,
        canSelectMode: false,
        supportsFrameRateHint: false,
      );

  /// The rate the engine says the view is running at. Read-only on every
  /// platform, and the only refresh-rate fact available without native code.
  double? _engineRefreshRate() {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final display = dispatcher.implicitView?.display ??
        (dispatcher.displays.isEmpty ? null : dispatcher.displays.first);
    final rate = display?.refreshRate;
    // A view that has not been laid out yet reports 0.
    return (rate == null || rate <= 0) ? null : rate;
  }

  /// Asks the platform for [pref]. Returns the rate that was actually
  /// requested (`null` for auto, or when the platform could do nothing),
  /// so the caller can report the truth rather than the intention.
  Future<double?> apply(FrameRatePreference pref) async {
    final caps = await capabilities();
    if (!caps.canChoose) return null;
    final resolved = resolveFrameRate(pref, caps);
    try {
      final applied = await _channel.invokeMethod<num?>('setFrameRate', {
        'hz': resolved,
      });
      return applied?.toDouble();
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('DisplayRefresh.apply failed: ${e.message}');
      return null;
    }
  }

  @visibleForTesting
  void resetCacheForTest() => _cached = null;
}
