import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_providers.dart';
import 'admin_experience.dart';
import 'capability.dart';

/// The Flutter/Riverpod side of the access layer. `capability.dart` and
/// `capability_presets.dart` stay pure Dart; everything that needs a widget
/// tree lives here.
///
/// TODO(security): every check in this file is a UX gate. It hides and
/// disables controls so a user is not offered an action that would fail. It
/// is not a security boundary — see the contract at the top of
/// `capability.dart`.

/// The signed-in session's capabilities.
///
/// While the session is still loading this is [Capabilities.none], i.e. deny
/// everything. Screens must render their own loading state; a gated screen
/// showing "you have no access" during a 400 ms fetch is a bug in the screen,
/// not in this provider.
final capabilitiesProvider = Provider<Capabilities>((ref) {
  return ref.watch(currentUserProvider).valueOrNull?.capabilities ??
      Capabilities.none;
});

/// How much of the app this session is shown — the one place breadth is
/// decided, so no widget carries an `if (isMainAdmin)` of its own.
///
/// Derived from [capabilitiesProvider], which means a grant that changes
/// mid-session re-shapes the UI on the next build, and a session still
/// loading resolves to [AdminView.none] — deny everything, and the *scoped*
/// experience, never the broad one.
///
/// **Presentation only.** Nothing here is a check; see the contract at the
/// top of `admin_experience.dart`.
final adminViewProvider = Provider<AdminView>((ref) {
  return AdminView.of(ref.watch(capabilitiesProvider));
});

/// How a [CapabilityGate] renders a capability the session does not hold.
enum GateMode {
  /// Remove the control from the tree. The default, and the house rule:
  /// prefer a removed affordance over an inert one.
  remove,

  /// Keep the control visible but non-interactive and visibly dimmed. Use it
  /// only where the control's absence would make a layout unreadable, or
  /// where a user needs to see that the action exists but is not theirs.
  disable,
}

/// Material's disabled-content opacity. Applied by [GateMode.disable].
const double _disabledOpacity = 0.38;

/// Shows [child] only when the session holds the capability.
///
/// Resolves through [Capabilities.canIn] like everything else — the
/// single-resolver rule. Pass [detachmentId] for any of the nineteen
/// per-detachment keys; omit it for the ten organisation-level ones.
///
/// ```dart
/// CapabilityGate(
///   capability: Cap.shiftManage,
///   detachmentId: detachmentId,
///   child: FilledButton(onPressed: _addShift, child: const Text(S.addShift)),
/// )
/// ```
///
/// For a control that should render read-only rather than disappear, do not
/// wrap it — hand it a null handler with [CapabilityRef.whenCan] instead, so
/// the widget itself decides how a disabled state looks.
class CapabilityGate extends ConsumerWidget {
  const CapabilityGate({
    super.key,
    required String capability,
    this.detachmentId,
    this.mode = GateMode.remove,
    this.denied,
    required this.child,
  })  : _capability = capability,
        _anyOf = null;

  /// Opens on **any** of [capabilities]. The two-key case: a shift screen
  /// opens for schedule management *or* attendance recording, while the
  /// controls inside are still gated one at a time.
  const CapabilityGate.anyOf({
    super.key,
    required Set<String> capabilities,
    this.detachmentId,
    this.mode = GateMode.remove,
    this.denied,
    required this.child,
  })  : _capability = null,
        _anyOf = capabilities;

  final String? _capability;
  final Set<String>? _anyOf;

  /// Required for a per-detachment key, meaningless for an org-level one.
  final String? detachmentId;
  final GateMode mode;

  /// Rendered instead of [child] when the capability is missing and [mode] is
  /// [GateMode.remove]. Defaults to nothing at all.
  final Widget? denied;

  final Widget child;

  bool _granted(Capabilities caps) {
    final anyOf = _anyOf;
    return anyOf != null
        ? caps.canAnyIn(detachmentId, anyOf)
        : caps.canIn(detachmentId, _capability!);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (_granted(ref.watch(capabilitiesProvider))) return child;

    return switch (mode) {
      GateMode.remove => denied ?? const SizedBox.shrink(),
      GateMode.disable => Semantics(
          enabled: false,
          child: IgnorePointer(
            child: Opacity(opacity: _disabledOpacity, child: child),
          ),
        ),
    };
  }
}

extension CapabilityRef on WidgetRef {
  /// Watches the session's capabilities. Use inside `build`.
  Capabilities get capabilities => watch(capabilitiesProvider);

  /// [value] when the capability is held, otherwise `null`.
  ///
  /// This is how a control renders read-only instead of vanishing: hand the
  /// widget a null handler and let it draw its own disabled state. The rule it
  /// serves is that the UI must never present a control that does nothing.
  ///
  /// ```dart
  /// IconButton(
  ///   onPressed: ref.whenCan(Cap.memberEdit, _edit, detachmentId: id),
  ///   icon: const Icon(Icons.edit),
  /// )
  /// ```
  T? whenCan<T>(String capability, T value, {String? detachmentId}) =>
      watch(capabilitiesProvider).canIn(detachmentId, capability)
          ? value
          : null;
}

/// Route guard for `go_router`'s `redirect`.
///
/// Returns [fallback] when none of [anyOf] is held, or `null` to let the route
/// open. It resolves through the same [Capabilities.canIn] the in-screen
/// controls use, which is the point — a guard that resolves access its own way
/// drifts from the controls it protects, and the user lands on a screen where
/// nothing works.
///
/// ```dart
/// GoRoute(
///   path: ':id/shifts',
///   redirect: (context, state) => requireCapability(
///     ref,
///     anyOf: Cap.shiftRoute,
///     detachmentId: state.pathParameters['id'],
///   ),
///   builder: ...,
/// )
/// ```
String? requireCapability(
  Ref ref, {
  required Set<String> anyOf,
  String? detachmentId,
  String fallback = '/home',
}) {
  // TODO(security): a client-side redirect. The backend must reject the
  // request too — a modified client simply does not run this.
  //
  // While the session is still unknown this decides nothing, for the same
  // reason the auth gate does not: the session read is async, so every cold
  // start and every offline relaunch passes through that state, and bouncing
  // a legitimate deep link to `/home` because the grant had not landed yet
  // would break the app for exactly the conditions it is built for. Nothing
  // gated renders in the meantime — `capabilitiesProvider` is
  // `Capabilities.none` throughout — and the router's `refreshListenable`
  // re-runs every redirect the moment the gate resolves, so a link that
  // should be refused is refused a frame later rather than never.
  if (ref.read(authGateProvider).isUnresolved) return null;
  final caps = ref.read(capabilitiesProvider);
  return caps.canAnyIn(detachmentId, anyOf) ? null : fallback;
}
