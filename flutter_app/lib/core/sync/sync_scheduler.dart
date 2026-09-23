import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_coordinator.dart';

/// The Auto Sync trigger seam.
///
/// Auto Sync is the primary path (roadmap §3A): the user should not have to
/// press anything for normal work to travel. This object turns the app's
/// existing lifecycle signals into a request that the coordinator drain
/// whatever is already pending. It **never creates operations** and it does
/// not itself decide connectivity.
///
/// What is wired now: a request on app start and on every resume
/// (`main.dart` forwards `AppLifecycleState.resumed`). What is deliberately
/// **not** wired: a connectivity stream — MTM has no connectivity plugin in
/// its dependencies and adding one is outside a frontend-only task. When one
/// is added it becomes one more call to [request]; nothing else changes.
///
/// Every path funnels through [request], which is a no-op when the outbox is
/// empty and joins any run already in flight (the coordinator's re-entrancy
/// guard). So a flapping signal cannot fan a write out twice — the concern
/// verification §21 / prompt §12 raise.
class SyncScheduler {
  SyncScheduler(this._ref);

  final Ref _ref;

  /// Ask for a background sync of pending work. Safe to call often.
  Future<void> request() async {
    try {
      await _ref
          .read(syncCoordinatorProvider.notifier)
          .syncNow(trigger: SyncTrigger.auto);
    } catch (e, s) {
      // A background sync that throws must never take the app down.
      assert(() {
        debugPrint('SyncScheduler.request failed: $e\n$s');
        return true;
      }());
    }
  }

  /// Call once the first frame is up.
  void onAppStart() => request();

  /// Call when the app returns to the foreground.
  void onAppResumed() => request();
}

final syncSchedulerProvider = Provider<SyncScheduler>(SyncScheduler.new);
