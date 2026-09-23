import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion_level.dart';
import 'device_settings_bootstrap.dart';
import 'settings_providers.dart';

/// User-selectable animation quality, persisted via [SettingsRepository].
///
/// On first read the notifier asks the repository for the stored value.
/// If none is stored, it seeds from the OS: `performance` when the platform
/// reports reduce-motion, otherwise `balanced`.
///
/// The seed is only a starting point. Whether an accessibility request is
/// *honoured* is decided at render time in `motionSpec`, which returns
/// `MotionSpec.none` whenever the platform asks for animations off — so a
/// user who later picks a richer level still gets the accessible
/// behaviour they asked the OS for.
///
/// Every setter persists immediately — no restart is needed.
class MotionLevelController extends AsyncNotifier<MotionLevel> {
  @override
  Future<MotionLevel> build() async {
    final r = await ref.read(settingsRepositoryProvider).motionLevel();
    return r.when(
      success: (data, {stale = false}) {
        if (data != null) return data;
        return _osDefault();
      },
      failure: (_, __) => _osDefault(),
      offline: (cached) => cached ?? _osDefault(),
    );
  }

  MotionLevel _osDefault() {
    // WidgetsBinding is safe to touch here — Riverpod's build runs on the
    // Flutter main isolate after binding is up (main.dart calls
    // `WidgetsFlutterBinding.ensureInitialized()`).
    //
    // Read the accessibility flag straight off the dispatcher. It is
    // populated whether or not a view exists yet, so gating on `views`
    // would report "not reduced" for a device that asked for reduced
    // motion, purely because the question was asked early.
    final osReduced = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    return osReduced ? MotionLevel.performance : MotionLevel.balanced;
  }

  Future<void> set(MotionLevel level) async {
    // Optimistic update — user feedback is immediate.
    state = AsyncValue.data(level);
    try {
      await ref.read(settingsRepositoryProvider).updateMotionLevel(level);
    } catch (e) {
      // A storage failure costs the choice its durability, not its effect:
      // the level is already applied and stays applied for this session.
      debugPrint('MotionLevelController: level not stored: $e');
    }
  }
}

final motionLevelProvider =
    AsyncNotifierProvider<MotionLevelController, MotionLevel>(
  MotionLevelController.new,
);

/// The motion level the widget tree should use right now.
///
/// On a real launch [deviceSettingsSnapshotProvider] was hydrated before
/// `runApp`, so Intro and Login never spend a frame on the balanced fallback
/// while the async controller catches up. Once the controller has a value it
/// remains the live source for changes made in Settings.
final activeMotionLevelProvider = Provider<MotionLevel>((ref) {
  return ref.watch(motionLevelProvider).valueOrNull ??
      ref.watch(deviceSettingsSnapshotProvider).motionLevel;
});
