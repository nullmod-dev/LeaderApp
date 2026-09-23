import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../demo/data/demo_workspace.dart';
import '../../../core/access/capability.dart';
import '../../../core/access/capability_guard.dart';
import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../../auth/data/auth_providers.dart';
import '../../detachment/data/detachment_providers.dart';
import '../../detachment/domain/detachment_models.dart';
import '../domain/announcement_models.dart';
import '../domain/announcement_repository.dart';
import '../domain/announcement_selectors.dart';
import 'mock_announcement_repository.dart';

/// Where announcements come from.
///
/// The mock reads the app's injectable clock rather than the wall clock, so a
/// test that pins `clockProvider` gets the seven fixtures positioned exactly
/// where it expects them — the Home promotion inside its hour, the expired one
/// two days past.
final announcementRepositoryProvider = Provider<AnnouncementRepository>((ref) {
  return ref.watch(demoWorkspaceProvider)?.announcements ??
      MockAnnouncementRepository(clock: ref.watch(clockProvider));
});

/// Every announcement this client knows about.
///
/// **Not `autoDispose`**, unlike most reads in this app, and the exception is
/// deliberate: three live surfaces watch it at once — the dashboard's promoted
/// card, the detachment strip, and the Notifications Center — and they come and
/// go independently as the user navigates. An `autoDispose` list would refetch
/// every time the last of them left the tree, which for a handful of small
/// records is a round trip bought for nothing. Publishing and withdrawing
/// invalidate it explicitly.
final announcementListProvider =
    FutureProvider<Result<List<Announcement>>>((ref) {
  return ref.watch(announcementRepositoryProvider).list();
});

/// The rows a result carries in whatever state it is in.
///
/// A failure counts as no announcements rather than throwing. That is what
/// keeps one unreadable announcement source from taking the rest of the
/// Notifications Center down with it: the other kinds still render, and the
/// screen's own offline/failure states still describe the sections that own
/// them.
List<Announcement> announcementsOf(
  AsyncValue<Result<List<Announcement>>> value,
) {
  final result = value.valueOrNull;
  if (result == null) return const [];
  return result.when(
    success: (data, {stale = false}) => data,
    failure: (_, __) => const <Announcement>[],
    offline: (cached) => cached ?? const <Announcement>[],
  );
}

/// Every announcement addressed to one detachment that this session may see,
/// whatever its lifetime state. The history question.
final visibleAnnouncementsProvider = Provider.autoDispose
    .family<List<Announcement>, String>((ref, detachmentId) {
  return visibleAnnouncements(
    announcementsOf(ref.watch(announcementListProvider)),
    detachmentId: detachmentId,
    capabilities: ref.watch(capabilitiesProvider),
  );
});

/// The announcements currently promoted on one detachment's Home, newest
/// first.
///
/// Reads `clockProvider`, never `DateTime.now()` inline: the one-hour boundary
/// is the whole behaviour here and it has to be pinnable. The dashboard card
/// additionally schedules a rebuild for the instant the promotion ends, but the
/// truth is this function — reopening the app an hour later evaluates correctly
/// with no timer having run at all.
final homeAnnouncementsProvider = Provider.autoDispose
    .family<List<Announcement>, String>((ref, detachmentId) {
  return homeAnnouncementsFor(
    ref.watch(visibleAnnouncementsProvider(detachmentId)),
    detachmentId: detachmentId,
    now: ref.watch(clockProvider)(),
  );
});

/// The announcements placed on one detachment's own detail surface.
final detachmentAnnouncementsProvider = Provider.autoDispose
    .family<List<Announcement>, String>((ref, detachmentId) {
  return detachmentAnnouncementsFor(
    ref.watch(visibleAnnouncementsProvider(detachmentId)),
    detachmentId: detachmentId,
    now: ref.watch(clockProvider)(),
  );
});

/// One announcement, re-read at the moment it is opened.
///
/// The Notifications Center's rows are pointers, and an announcement can be
/// withdrawn or cleared between the load and the tap. Resolving it here is what
/// turns that into a sentence instead of a stale screen.
final announcementByIdProvider =
    FutureProvider.autoDispose.family<Result<Announcement>, String>((ref, id) {
  return ref.watch(announcementRepositoryProvider).byId(id);
});

/// Whether this session may publish an announcement **anywhere**.
///
/// The question the entry points ask: a management screen and a compose form
/// are not themselves detachment-scoped, so `canIn(null, ...)` would be the
/// wrong check — it refuses a scoped administrator who genuinely holds the key
/// in one detachment. Still the single resolver underneath.
final canPublishAnnouncementsProvider = Provider<bool>((ref) {
  return ref.watch(capabilitiesProvider).canAnywhere(Cap.announcementPublish);
});

/// The detachments this session may address, in name order.
///
/// Narrowed **twice, before anything is rendered**: `detachmentListProvider`
/// has already dropped every detachment the session cannot see (and every
/// archived one — the query asks for active), and [publishableDetachments]
/// drops those where the publish key is not held. So the picker is built from
/// permitted detachments rather than showing all of them and refusing after a
/// selection, which is the rule Point 14 §18 sets.
final publishableDetachmentsProvider =
    FutureProvider.autoDispose<Result<List<Detachment>>>((ref) async {
  final result = await ref.watch(
    detachmentListProvider(
      const DetachmentListQuery(filter: DetachmentStatus.active),
    ).future,
  );
  final caps = ref.watch(capabilitiesProvider);
  List<Detachment> narrow(List<Detachment> items) =>
      publishableDetachments(items, (d) => d.id, caps);
  return result.when(
    success: (data, {stale = false}) => Success(narrow(data), stale: stale),
    failure: (message, code) => Failure(message, code: code),
    offline: (cached) =>
        Offline(cached: cached == null ? null : narrow(cached)),
  );
});

// ---------------------------------------------------------------------------
// Actions.
// ---------------------------------------------------------------------------

/// What a publish or withdraw attempt did.
///
/// A value rather than a sentence, so a test asserts on the outcome and the
/// widget resolves the Arabic from `strings.dart`.
sealed class AnnouncementOutcome {
  const AnnouncementOutcome();
}

/// The record as it now stands.
class AnnouncementSaved extends AnnouncementOutcome {
  const AnnouncementSaved(this.announcement);
  final Announcement announcement;
}

/// Refused by the client before anything was sent — bad text, no target, a
/// target this session may no longer address, an expiry that is not in the
/// future.
class AnnouncementRefusedOutcome extends AnnouncementOutcome {
  const AnnouncementRefusedOutcome(this.reason);
  final AnnouncementRefusal reason;
}

/// The repository answered with a failure. The form keeps everything the
/// author typed.
class AnnouncementFailed extends AnnouncementOutcome {
  const AnnouncementFailed(this.message, {this.code});
  final String message;
  final String? code;
}

/// No connectivity. Publishing an announcement is **not** queued in the outbox
/// — see [AnnouncementController.publish].
class AnnouncementOffline extends AnnouncementOutcome {
  const AnnouncementOffline();
}

/// A second attempt arrived while the first was still in flight and was
/// dropped. The duplicate-submission guard, at controller level.
class AnnouncementIgnored extends AnnouncementOutcome {
  const AnnouncementIgnored();
}

/// Which announcement actions are in flight.
///
/// Held in the controller rather than in a widget's `setState` because the
/// guard has to survive the widget: a management row rebuilt mid-request, or a
/// compose screen that rebuilt because the grant changed, must not become a
/// second way to fire the same mutation.
class AnnouncementActionState {
  const AnnouncementActionState({this.publishing = false, this.withdrawing});

  final bool publishing;

  /// The id currently being withdrawn, or null. One at a time: withdrawing two
  /// announcements at once is not a thing the screen offers, and allowing it
  /// would make the busy state unreadable.
  final String? withdrawing;

  bool isWithdrawing(String id) => withdrawing == id;

  AnnouncementActionState copyWith({
    bool? publishing,
    String? withdrawing,
    bool clearWithdrawing = false,
  }) =>
      AnnouncementActionState(
        publishing: publishing ?? this.publishing,
        withdrawing: clearWithdrawing ? null : withdrawing ?? this.withdrawing,
      );
}

/// Publishing and withdrawing, with the duplicate guard and the capability
/// revalidation that make both safe.
class AnnouncementController extends Notifier<AnnouncementActionState> {
  @override
  AnnouncementActionState build() => const AnnouncementActionState();

  /// Publishes one announcement.
  ///
  /// Three things happen before the repository is touched, in this order:
  ///
  /// 1. **The duplicate guard.** A second call while one is in flight returns
  ///    [AnnouncementIgnored] and sends nothing. This is the guard, not the
  ///    disabled button — a disabled button is what the user sees, and it is
  ///    not what stops a second mutation.
  /// 2. **Revalidation against the live grant.** [refuseAnnouncement] resolves
  ///    the targets against `capabilitiesProvider` **as it is now**, not as it
  ///    was when the form opened. A session whose grants narrowed while the
  ///    author was typing is refused rather than publishing to a detachment it
  ///    no longer holds.
  /// 3. **The clock.** `publishedAt` comes from `clockProvider`, and the
  ///    expiry the caller computed is checked against the same instant, so the
  ///    one-hour Home promotion and the announcement's own lifetime are
  ///    measured from one reading.
  /// 4. **The lifecycle.** Every target is resolved to its detachment record
  ///    and refused if it is archived — or if it could not be read at all.
  ///    `announcement.publish` is in `historicallyClosedCapabilities`, and
  ///    this is the only action that addresses a detachment without standing
  ///    on its surface, so it is the only place that rule can be applied.
  ///
  /// **Not queued offline.** The outbox exists and it would have accepted a
  /// `PendingOperation` here, and that is precisely why it is worth saying no:
  /// there is no announcement endpoint for a queued write to ever reach, so an
  /// operation enqueued now would sit in the outbox forever while the author
  /// believed their notice was sent. `Result.offline` is reported honestly
  /// instead. When a real endpoint exists this is the one method that changes.
  Future<AnnouncementOutcome> publish({
    required String text,
    required List<String> detachmentIds,
    required Set<AnnouncementPlacement> placements,
    required DateTime expiresAt,
  }) async {
    if (state.publishing) return const AnnouncementIgnored();

    final now = ref.read(clockProvider)();
    final targets = dedupeTargets(detachmentIds);
    final refusal = refuseAnnouncement(
      text: text,
      detachmentIds: targets,
      expiresAt: expiresAt,
      now: now,
      capabilities: ref.read(capabilitiesProvider),
    );
    if (refusal != null) return AnnouncementRefusedOutcome(refusal);

    state = state.copyWith(publishing: true);
    try {
      // 4. The lifecycle check. `announcement.publish` is one of the keys an
      //    archived detachment stops honouring
      //    (`historicallyClosedCapabilities`), and this is the one action that
      //    reaches a detachment without standing on its surface — so nothing
      //    else would have applied that rule. The picker never offers an
      //    archived detachment; this is what makes the *action* refuse one.
      final lifecycle = await _refuseByLifecycle(targets);
      if (lifecycle != null) return lifecycle;

      final result = await ref.read(announcementRepositoryProvider).publish(
            text: text.trim(),
            detachmentIds: targets,
            placements: placements,
            publishedAt: now,
            expiresAt: expiresAt,
            authorName: ref.read(currentUserProvider).valueOrNull?.name,
          );
      return _finish(result);
    } finally {
      state = state.copyWith(publishing: false);
    }
  }

  /// Stops an announcement's active placements.
  ///
  /// Withdraw, never delete: the Notifications Center entry is a record that
  /// the notice was sent, and it survives. A failure leaves the announcement
  /// exactly as it was — the caller re-reads the list rather than assuming.
  ///
  /// **Authorized here, not by the row that was tapped.** The record is
  /// re-read and checked against the live grant through
  /// [canManageAnnouncement], for the same reason `publish` revalidates its
  /// targets: a narrowed session, a stale screen, or a direct call with an
  /// id must all end in the same refusal.
  Future<AnnouncementOutcome> withdraw(String id) async {
    if (state.withdrawing != null) return const AnnouncementIgnored();

    state = state.copyWith(withdrawing: id);
    try {
      final repository = ref.read(announcementRepositoryProvider);
      // The record is re-read and authorized here, not trusted from the row
      // that was tapped. A management list narrowed on screen is a *view*; the
      // action is the boundary, and an id is the one thing a caller can supply
      // freely. Without this, `withdraw('a_seed_7')` from any session with a
      // publish key anywhere would stop a notice belonging to a detachment it
      // cannot even see.
      final current = await repository.byId(id);
      final refusal = current.when<AnnouncementOutcome?>(
        success: (Announcement a, {bool stale = false}) =>
            _refuseUnmanageable(a),
        failure: (message, code) => AnnouncementFailed(message, code: code),
        // A cached copy still names its detachments, which is all the check
        // needs. Nothing cached at all denies rather than guesses.
        offline: (cached) => cached == null
            ? const AnnouncementOffline()
            : _refuseUnmanageable(cached),
      );
      if (refusal != null) return refusal;

      return _finish(await repository.withdraw(id));
    } finally {
      state = state.copyWith(clearWithdrawing: true);
    }
  }

  /// Null when this session may act on [a], a refusal otherwise.
  AnnouncementOutcome? _refuseUnmanageable(Announcement a) =>
      canManageAnnouncement(a, ref.read(capabilitiesProvider))
          ? null
          : const AnnouncementRefusedOutcome(
              AnnouncementRefusal.unauthorizedTarget,
            );

  /// Null when every id in [targets] is an active detachment, a refusal
  /// otherwise.
  ///
  /// Reads the detachment repository directly rather than
  /// `detachmentByIdProvider`: this runs inside an action, not a build, and an
  /// `autoDispose` family read whose only listener is a completed await is a
  /// provider disposed mid-flight. The rule itself lives in
  /// [refuseArchivedTargets], where it is testable without a repository.
  Future<AnnouncementOutcome?> _refuseByLifecycle(List<String> targets) async {
    final repository = ref.read(detachmentRepositoryProvider);
    final statuses = <String, DetachmentStatus?>{};
    for (final id in targets) {
      final record = await repository.byId(id);
      statuses[id] = record.when(
        success: (Detachment d, {bool stale = false}) => d.status,
        // Unreadable is not "active". A detachment whose record could not be
        // read is `DetachmentMode.unknown`, which denies writes.
        failure: (_, __) => null,
        offline: (cached) => cached?.status,
      );
    }
    final refusal = refuseArchivedTargets(targets, statuses);
    return refusal == null ? null : AnnouncementRefusedOutcome(refusal);
  }

  /// Maps a repository answer to an outcome, invalidating the list only when
  /// something actually changed.
  AnnouncementOutcome _finish(Result<Announcement> result) => result.when(
        success: (data, {stale = false}) {
          ref.invalidate(announcementListProvider);
          return AnnouncementSaved(data);
        },
        failure: (message, code) => AnnouncementFailed(message, code: code),
        offline: (_) => const AnnouncementOffline(),
      );
}

final announcementControllerProvider =
    NotifierProvider<AnnouncementController, AnnouncementActionState>(
  AnnouncementController.new,
);
