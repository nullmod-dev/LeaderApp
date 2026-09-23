import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../demo/data/demo_workspace.dart';
import '../../../core/access/admin_experience.dart';
import '../../../core/access/capability.dart';
import '../../../core/access/capability_guard.dart';
import '../../../core/access/detachment_access.dart';
import '../../../core/result/result.dart';
import '../../auth/data/auth_providers.dart';
import '../domain/detachment_models.dart';
import '../domain/detachment_repository.dart';
import 'mock_detachment_repository.dart';

final detachmentRepositoryProvider = Provider<DetachmentRepository>((ref) {
  return ref.watch(demoWorkspaceProvider)?.detachments ??
      MockDetachmentRepository();
});

/// Cache key for one detachment list.
///
/// A record-shaped key rather than three loose arguments: Dart gives records
/// value equality for free, so two detachment groups can never collide on one
/// cache entry (`DETACHMENT-SCOPING.md` §2, rule 1).
class DetachmentListQuery {
  const DetachmentListQuery({this.detachmentGroupId, this.filter, this.query});

  final String? detachmentGroupId;
  final DetachmentStatus? filter;
  final String? query;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DetachmentListQuery &&
          other.detachmentGroupId == detachmentGroupId &&
          other.filter == filter &&
          other.query == query;

  @override
  int get hashCode => Object.hash(detachmentGroupId, filter, query);
}

/// `autoDispose` on purpose — rule 2. Leaving a detachment group drops its
/// list, so coming back re-enters the loading state and refetches instead of
/// showing what was true minutes ago. One detachment list, narrowed to what
/// this session may actually see.
///
/// The narrowing is here and not in each screen for the reason every access
/// decision in this app is centralised: the dashboard's switcher, the
/// detachment group's detachments, the unscoped list and — later — Global
/// Search all read through this provider, and a filter applied in three of
/// those four is the one that leaks. `AdminView.coversDetachment` resolves it
/// through `Capabilities.canIn` like everything else, so an organisation-wide
/// grant passes the whole list through untouched and a scoped grant sees only
/// the detachments named in it.
///
/// It awaits the session rather than reading `capabilitiesProvider`
/// synchronously: that provider is `Capabilities.none` until the account
/// lands, and filtering against it would flash an empty list on every cold
/// start before quietly refilling.
///
/// TODO(security): a UX filter. The backend must not return a detachment the
/// caller may not see — see the contract at the top of
/// `core/access/capability.dart`.
final detachmentListProvider = FutureProvider.autoDispose
    .family<Result<List<Detachment>>, DetachmentListQuery>((ref, q) async {
  final view = AdminView.of(
    (await ref.watch(currentUserProvider.future))?.capabilities ??
        Capabilities.none,
  );
  final result = await ref.read(detachmentRepositoryProvider).list(
        detachmentGroupId: q.detachmentGroupId,
        filter: q.filter,
        query: q.query,
      );
  List<Detachment> narrow(List<Detachment> items) =>
      visibleDetachments(view, items, (d) => d.id).toList();
  return result.when(
    success: (data, {stale = false}) => Success(narrow(data), stale: stale),
    failure: (message, code) => Failure(message, code: code),
    offline: (cached) =>
        Offline(cached: cached == null ? null : narrow(cached)),
  );
});

final detachmentByIdProvider = FutureProvider.autoDispose
    .family<Result<Detachment>, String>((ref, id) async {
  return ref.read(detachmentRepositoryProvider).byId(id);
});

final detachmentStatsProvider = FutureProvider.autoDispose
    .family<Result<DetachmentStats>, String>((ref, id) async {
  return ref.read(detachmentRepositoryProvider).stats(id);
});

/// One detachment's lifecycle, as far as this client currently knows it.
///
/// Derived from the record itself rather than stored anywhere new: `archived`
/// is already the domain state (`API_CONTRACT.md` §Detachments) and no second
/// archive flag is invented for it.
///
/// A cached copy read while offline still answers — it is the record, just not
/// a fresh one. Only a detachment that could not be read **at all** resolves
/// to [DetachmentMode.unknown], which denies writes rather than guessing the
/// detachment is still open.
final detachmentModeProvider =
    Provider.autoDispose.family<DetachmentMode, String>((ref, id) {
  final detachment = ref.watch(detachmentByIdProvider(id)).whenOrNull(
        data: (r) => r.when(
          success: (Detachment d, {bool stale = false}) => d,
          failure: (_, __) => null,
          offline: (cached) => cached,
        ),
      );
  if (detachment == null) return DetachmentMode.unknown;
  return switch (detachment.status) {
    DetachmentStatus.active => DetachmentMode.active,
    DetachmentStatus.archived => DetachmentMode.historical,
  };
});

/// What this session may do inside one detachment — the grant and the
/// detachment's lifecycle resolved together, in one place.
///
/// Every mutating control on a detachment surface reads this instead of
/// `capabilitiesProvider` directly, so "this detachment has ended" is decided
/// once rather than re-derived per widget.
final detachmentAccessProvider =
    Provider.autoDispose.family<DetachmentAccess, String>((ref, id) {
  return DetachmentAccess(
    detachmentId: id,
    capabilities: ref.watch(capabilitiesProvider),
    mode: ref.watch(detachmentModeProvider(id)),
  );
});

extension DetachmentAccessRef on WidgetRef {
  /// What this session may do inside [detachmentId]. Use inside `build`.
  DetachmentAccess accessIn(String detachmentId) =>
      watch(detachmentAccessProvider(detachmentId));
}
