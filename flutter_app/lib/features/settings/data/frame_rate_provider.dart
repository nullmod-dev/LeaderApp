import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/display/display_refresh.dart';
import '../../../core/display/frame_rate.dart';
import 'settings_providers.dart';

/// The one [DisplayRefresh] for the app. It caches the panel's mode list,
/// so sharing it means the settings screen asks the platform once.
final displayRefreshProvider =
    Provider<DisplayRefresh>((ref) => DisplayRefresh());

/// What this device's display can actually be asked for. Read once and
/// kept: a panel's mode list does not change while the app runs.
final displayCapabilitiesProvider =
    FutureProvider<DisplayCapabilities>((ref) async {
  return ref.read(displayRefreshProvider).capabilities();
});

/// The frame-rate target, persisted via `SettingsRepository` and pushed to
/// the platform whenever it changes.
///
/// [FrameRatePreference.auto] is the default and the fallback for anything
/// unreadable, because it is the only value that is valid on every device.
/// A stored choice the current device cannot honour — a 120Hz preference
/// restored on a 60Hz phone — is *kept* rather than rewritten: the device
/// may not be the one it was chosen on, and `DisplayRefresh.apply` already
/// resolves it down to the nearest real mode.
class FrameRateController extends AsyncNotifier<FrameRatePreference> {
  @override
  Future<FrameRatePreference> build() async {
    final r = await ref.read(settingsRepositoryProvider).frameRate();
    final stored = r.when(
      success: (data, {stale = false}) => data,
      failure: (_, __) => null,
      offline: (cached) => cached,
    );
    final pref = stored ?? FrameRatePreference.auto;
    // Apply on start-up too: the platform forgets the preference between
    // launches, so restoring it is part of restoring the setting.
    await ref.read(displayRefreshProvider).apply(pref);
    return pref;
  }

  Future<void> set(FrameRatePreference pref) async {
    state = AsyncValue.data(pref);
    try {
      await ref.read(displayRefreshProvider).apply(pref);
      await ref.read(settingsRepositoryProvider).updateFrameRate(pref);
    } catch (e) {
      // Same rule as the other preferences: a failed write never rolls the
      // user's visible choice back.
      debugPrint('FrameRateController: preference not stored: $e');
    }
  }
}

final frameRateProvider =
    AsyncNotifierProvider<FrameRateController, FrameRatePreference>(
  FrameRateController.new,
);
