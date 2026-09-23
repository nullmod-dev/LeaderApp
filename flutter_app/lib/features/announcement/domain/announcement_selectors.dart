import '../../../core/access/capability.dart';
import '../../detachment/domain/detachment_models.dart';
import 'announcement_models.dart';

/// The announcement system's decision layer, as pure functions.
///
/// Nothing here touches Flutter, Riverpod, or a repository — the same split the
/// notification and shift selectors already keep. Every rule the product states
/// about *when* an announcement is seen lives in this file and is tested
/// against a pinned clock, because every one of them is a boundary somebody
/// will cross at 11:00:00 exactly.
///
/// Four rules govern all of it:
///
/// 1. **Addressing is a capability question.** A session sees an announcement
///    when its grants cover one of the detachments the announcement names, and
///    may *publish* to a detachment only where it holds
///    [Cap.announcementPublish] there. Both resolve through
///    `Capabilities.canIn` — the single-resolver rule.
/// 2. **The Home promotion is one hour from publication**, and it is not the
///    announcement's lifetime.
/// 3. **Active placement is not history.** Expiry and withdrawal end
///    placements; the Notifications Center entry is a separate concern and
///    outlives both.
/// 4. **Nothing reads the wall clock.** Every function here takes `now`, so
///    reopening the app a day later evaluates the same way a test does.

/// How long a Home-placed announcement is promoted on the dashboard.
///
/// Exactly one hour, and the boundary convention is stated once, here:
/// **`now - publishedAt < homePromotionWindow`**. So `+59m59s` is promoted and
/// `+1h00m00s` is not — the same half-open convention the attendance window
/// uses, and the reason a test can assert both sides of it.
const Duration homePromotionWindow = Duration(hours: 1);

// ---------------------------------------------------------------------------
// Lifetime.
// ---------------------------------------------------------------------------

/// True while [a] is still being actively delivered: not withdrawn, and not
/// past its expiry.
///
/// This governs **placements only**. An announcement that fails it has not
/// stopped existing — its Notifications Center row is untouched.
bool isAnnouncementActive(Announcement a, DateTime now) =>
    !a.isWithdrawn && now.isBefore(a.expiresAt);

/// True while [a] is inside its one-hour Home promotion.
///
/// Both clocks have to agree: an announcement given a thirty-minute lifetime
/// leaves Home when it expires, not an hour after it was published.
bool isPromotedOnHome(Announcement a, DateTime now) {
  if (!a.showsOnHome) return false;
  if (!isAnnouncementActive(a, now)) return false;
  if (now.isBefore(a.publishedAt)) return false;
  return now.difference(a.publishedAt) < homePromotionWindow;
}

/// When [a]'s Home promotion ends — the instant it stops being promoted.
///
/// The earlier of "an hour after publication" and its own expiry, so a caller
/// scheduling a refresh never waits past the moment the state actually changes.
DateTime homePromotionEndsAt(Announcement a) {
  final hour = a.publishedAt.add(homePromotionWindow);
  return a.expiresAt.isBefore(hour) ? a.expiresAt : hour;
}

// ---------------------------------------------------------------------------
// Addressing.
// ---------------------------------------------------------------------------

/// Every announcement addressed to [detachmentId] that this session may see,
/// **whatever its lifetime state**.
///
/// This is the history question, and it is what the Notifications Center is
/// built from: an expired or withdrawn announcement is still something the
/// detachment was told. Visibility rests on [Cap.detachmentView], which any
/// scoped grant implies (`CAPABILITIES.md` §4/Q3) — there is no separate
/// announcement-view key, because it would gate nothing.
///
/// TODO(security): a UX gate, like every capability check in this app. A real
/// backend must not put an announcement in the payload the caller may not see —
/// see the contract at the top of `capability.dart`.
List<Announcement> visibleAnnouncements(
  List<Announcement> items, {
  required String detachmentId,
  required Capabilities capabilities,
}) {
  if (!capabilities.canIn(detachmentId, Cap.detachmentView)) {
    return const [];
  }
  return [
    for (final a in items)
      if (a.targets(detachmentId)) a,
  ];
}

/// The detachments [capabilities] may publish an announcement into, out of
/// [available].
///
/// [available] is expected to be a list that has **already** been narrowed to
/// what the session may see (`detachmentListProvider` does that once, for every
/// caller). This narrows it a second time by the publish key, so the target
/// picker is built from permitted detachments rather than showing all of them
/// and refusing afterwards.
List<T> publishableDetachments<T>(
  Iterable<T> available,
  String Function(T) idOf,
  Capabilities capabilities,
) =>
    [
      for (final item in available)
        if (capabilities.canIn(idOf(item), Cap.announcementPublish)) item,
    ];

/// [ids] with duplicates removed, order preserved.
///
/// The target list is a user-built list and a double tap on the same row must
/// not address one detachment twice.
List<String> dedupeTargets(Iterable<String> ids) {
  final seen = <String>{};
  return [
    for (final id in ids)
      if (seen.add(id)) id,
  ];
}

/// The subset of [ids] this session may still publish to.
///
/// **The revalidation function.** A compose screen can be open for minutes
/// while the server re-issues the session or an administrator narrows the
/// grant; publishing against the target list the form was built with would
/// address a detachment the author no longer holds. The controller calls this
/// again at submit and refuses when it removed anything.
List<String> authorizedTargets(
  Iterable<String> ids,
  Capabilities capabilities,
) =>
    [
      for (final id in ids)
        if (capabilities.canIn(id, Cap.announcementPublish)) id,
    ];

/// True when this session may **act on** an existing announcement — withdraw
/// it, or see it on the management screen.
///
/// The publish key held in *any one* of the detachments the announcement
/// addresses. A notice sent to three detachments is one record: the person who
/// runs one of them may stop it, and a session holding the key in none of them
/// may not touch it at all. The management list and the withdraw path both
/// resolve through this one function, so a row that renders and the action
/// behind it can never disagree.
bool canManageAnnouncement(Announcement a, Capabilities capabilities) =>
    a.detachmentIds
        .any((id) => capabilities.canIn(id, Cap.announcementPublish));

/// The lifecycle half of target validation, as a pure function.
///
/// [statuses] maps every requested target id to the detachment's status, or to
/// null when the record could not be read at all. Both an archived detachment
/// and an unreadable one refuse: a session that cannot tell whether a
/// detachment is still running must not publish into it, which is exactly the
/// rule `DetachmentMode.unknown` states for every other write.
///
/// Kept out of the controller so the rule is testable without a repository,
/// and kept out of [refuseAnnouncement] because resolving a status is a read —
/// that function stays synchronous and pure over what the form already holds.
AnnouncementRefusal? refuseArchivedTargets(
  Iterable<String> ids,
  Map<String, DetachmentStatus?> statuses,
) {
  for (final id in ids) {
    if (statuses[id] != DetachmentStatus.active) {
      return AnnouncementRefusal.archivedTarget;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Placement queries.
// ---------------------------------------------------------------------------

/// Every announcement currently promoted on [detachmentId]'s Home, newest
/// first.
///
/// Ties break on id so the order is **total**: two announcements published in
/// the same millisecond must not swap places between two rebuilds, or the
/// dashboard's top card would flicker between them.
List<Announcement> homeAnnouncementsFor(
  List<Announcement> items, {
  required String detachmentId,
  required DateTime now,
}) {
  final rows = [
    for (final a in items)
      if (a.targets(detachmentId) && isPromotedOnHome(a, now)) a,
  ];
  rows.sort((a, b) {
    final byTime = b.publishedAt.compareTo(a.publishedAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
  return rows;
}

/// Every announcement placed on [detachmentId]'s own detail surface, newest
/// first. Ordered by the same total rule as [homeAnnouncementsFor].
List<Announcement> detachmentAnnouncementsFor(
  List<Announcement> items, {
  required String detachmentId,
  required DateTime now,
}) {
  final rows = [
    for (final a in items)
      if (a.targets(detachmentId) &&
          a.showsOnDetachment &&
          isAnnouncementActive(a, now))
        a,
  ];
  rows.sort((a, b) {
    final byTime = b.publishedAt.compareTo(a.publishedAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
  return rows;
}

/// The announcements a management screen lists, newest first.
///
/// Active ones first and then the rest, because the screen exists to *stop* an
/// announcement — the ones that can still be stopped belong at the top. Inside
/// each half the order is the same total newest-first rule.
List<Announcement> manageableAnnouncements(
  List<Announcement> items,
  DateTime now,
) {
  final rows = List<Announcement>.of(items);
  rows.sort((a, b) {
    final activeA = isAnnouncementActive(a, now);
    final activeB = isAnnouncementActive(b, now);
    if (activeA != activeB) return activeA ? -1 : 1;
    final byTime = b.publishedAt.compareTo(a.publishedAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
  return rows;
}

// ---------------------------------------------------------------------------
// Validation.
// ---------------------------------------------------------------------------

/// Why a publish attempt was refused before anything left the client.
///
/// A value, not a sentence: the copy is resolved by the widget from
/// `strings.dart`, so a test asserts on the reason and never on translated
/// text.
enum AnnouncementRefusal {
  /// Nothing, or only whitespace.
  emptyText,
  textTooShort,
  textTooLong,

  /// No detachment selected. At least one is always required — there is no
  /// broadcast.
  noTarget,

  /// A selected detachment is not (or is no longer) one this session may
  /// publish to. Raised by the revalidation at submit.
  unauthorizedTarget,

  /// A selected detachment has been archived. Publishing a notice into a
  /// detachment that has stopped running is an operational write with nobody
  /// left to read it — the same rule `historicallyClosedCapabilities` states
  /// for every other write key, applied to the one action that reaches a
  /// detachment without standing on its surface.
  archivedTarget,

  /// The chosen expiry is not in the future. There is no permanent
  /// announcement and no announcement that expired before it was published.
  expiryNotInFuture,
}

/// Checks a would-be announcement, returning the first reason it cannot be
/// published or null when it can.
///
/// Ordered so the author is told about the thing they can see: the text they
/// typed, then the detachments they picked, then the lifetime they chose.
AnnouncementRefusal? refuseAnnouncement({
  required String text,
  required List<String> detachmentIds,
  required DateTime expiresAt,
  required DateTime now,
  required Capabilities capabilities,
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return AnnouncementRefusal.emptyText;
  if (trimmed.length < announcementTextMin) {
    return AnnouncementRefusal.textTooShort;
  }
  if (trimmed.length > announcementTextMax) {
    return AnnouncementRefusal.textTooLong;
  }

  final targets = dedupeTargets(detachmentIds);
  if (targets.isEmpty) return AnnouncementRefusal.noTarget;
  // Resolved against the grant *as it is now*, not as it was when the form
  // opened. This is the check that makes a narrowed session unable to publish
  // with the targets it was allowed a minute ago.
  if (authorizedTargets(targets, capabilities).length != targets.length) {
    return AnnouncementRefusal.unauthorizedTarget;
  }

  if (!expiresAt.isAfter(now)) return AnnouncementRefusal.expiryNotInFuture;
  return null;
}

/// The placement set an author's choices resolve to.
///
/// [AnnouncementPlacement.notifications] is added whatever was passed: the
/// history surface is not optional, and a caller that could omit it would be a
/// caller that could publish an announcement nobody can find later.
Set<AnnouncementPlacement> resolvePlacements({
  bool onHome = false,
  bool onDetachment = false,
}) =>
    {
      AnnouncementPlacement.notifications,
      if (onHome) AnnouncementPlacement.home,
      if (onDetachment) AnnouncementPlacement.detachment,
    };
