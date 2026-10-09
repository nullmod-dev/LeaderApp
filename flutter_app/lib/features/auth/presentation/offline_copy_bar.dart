import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/animated_counter.dart';
import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../../l10n/strings.dart';
import '../data/auth_providers.dart';
import '../data/http_auth_repository.dart';
import '../domain/auth_models.dart';

/// Whether the app is running on the stored copy of the account: the last
/// session read could not reach the server and opened the copy instead.
final runningOnOfflineCopyProvider = Provider<bool>((ref) {
  final result = ref.watch(currentUserResultProvider).valueOrNull;
  return result is Offline<AuthUser?> && result.cached != null;
});

/// The offline bar above every page of a shell (tenant and platform).
///
/// **Shown** while the session runs on the stored copy, with the hours left
/// once the offline window is in its last 48 — the moment it is worth
/// knowing that the app will stop opening without a connection.
///
/// **Back online, silently.** While it shows, the session is re-read every
/// [recheckEvery] (and on resume, by the app itself). The previous answer
/// stays on screen while it reloads, so a still-offline phone sees nothing
/// change; one that is back sees the bar close — or, if the server ended the
/// session meanwhile, the classifier moves it to `/session-expired`. No
/// connectivity plugin: the session read is the only question that matters.
class OfflineCopyBar extends ConsumerStatefulWidget {
  const OfflineCopyBar({super.key});

  static const Duration recheckEvery = Duration(seconds: 60);

  /// The last stretch of the offline window, when the bar counts it down.
  static const Duration countdownFrom = Duration(hours: 48);

  @override
  ConsumerState<OfflineCopyBar> createState() => _OfflineCopyBarState();
}

class _OfflineCopyBarState extends ConsumerState<OfflineCopyBar> {
  Timer? _recheck;

  @override
  void dispose() {
    _recheck?.cancel();
    super.dispose();
  }

  void _syncRecheck(bool offline) {
    if (!offline) {
      _recheck?.cancel();
      _recheck = null;
      return;
    }
    _recheck ??= Timer.periodic(OfflineCopyBar.recheckEvery, (_) {
      if (mounted) ref.invalidate(currentUserResultProvider);
    });
  }

  /// «ينتهي الدخول دون اتصال خلال {n} ساعة» in the last 48 hours; otherwise
  /// nothing. Hours round up, so the bar never says «٠ ساعة» while the copy
  /// still opens.
  String? _countdown() {
    final repository = ref.watch(authRepositoryProvider);
    if (repository is! HttpAuthRepository) return null;
    final endsAt = repository.offlineTrustEndsAt;
    if (endsAt == null) return null;
    final left = endsAt.difference(ref.watch(clockProvider)().toUtc());
    if (left.isNegative || left > OfflineCopyBar.countdownFrom) return null;
    final hours = (left.inMinutes / 60).ceil().clamp(1, 48);
    return S.offlineCopyEndsIn.replaceFirst('%s', toArabicIndic('$hours'));
  }

  @override
  Widget build(BuildContext context) {
    final offline = ref.watch(runningOnOfflineCopyProvider);
    _syncRecheck(offline);
    return OfflineBanner(
      visible: offline,
      detail: offline ? _countdown() : null,
    );
  }
}

/// The other half of [OfflineCopyBar]: while the bar shows it owns the status
/// bar inset, so everything under it must not reserve it a second time.
class OfflineCopyInset extends ConsumerWidget {
  const OfflineCopyInset({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(runningOnOfflineCopyProvider)) return child;
    return MediaQuery.removePadding(
        context: context, removeTop: true, child: child);
  }
}
