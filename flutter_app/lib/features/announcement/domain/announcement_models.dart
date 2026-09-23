import 'package:flutter/foundation.dart';

/// The internal announcement — one administrator telling the administrators of
/// one or more detachments something operational, in plain words.
///
/// **What this is not.** It is not advertising, not a public notice, and not a
/// message to volunteers: nobody but an administrator signs into this app
/// (`CAPABILITIES.md`). It is the operational equivalent of a note pinned to
/// the wall of a detachment's office.
///
/// **Text is the whole content, deliberately.** There is no shift picker, no
/// member picker, no item picker, no attachment and no formatting. An admin who
/// needs to talk about a shift writes «بخصوص شفت ٤–١٠…» — which costs one
/// sentence, against a second form to fill in and a second record to keep
/// consistent. Everything else on this record is *addressing* and *lifetime*,
/// not content.
///
/// **Two lifetimes, and they are not the same thing** (see
/// `announcement_selectors.dart`):
///
/// * [expiresAt] ends the announcement's **active placements** — the Home
///   promotion, the detachment strip. Finite, always: there is no permanent
///   announcement.
/// * The Notifications Center entry is **history** and outlives both. It
///   disappears only when an administrator clears notification history
///   deliberately.
///
/// Carries **no copy**: the Arabic lives in `strings.dart` and is resolved by
/// the widget, exactly as `AppNotification` does, so a test can assert on a
/// value without matching translated text.

/// Where a published announcement is allowed to appear.
///
/// Three values and no more in V1. Shifts, inventory, statistics, security and
/// settings are deliberately not placements: a notice that can appear anywhere
/// is a notice nobody can predict.
enum AnnouncementPlacement {
  /// The Notifications Center. **Canonical and always present** — it is the
  /// durable history surface, so an announcement that appeared nowhere else
  /// still exists to be found. [Announcement.placements] always contains it.
  notifications,

  /// The Home dashboard, for exactly one hour after publication. A promotion,
  /// not a home for the announcement: see `homePromotionWindow`.
  home,

  /// The targeted detachment's own detail surface, until [Announcement
  /// .expiresAt]. The existing status strip under the detachment app bar
  /// hosts it — no new detachment submodule.
  detachment,
}

/// Whether an announcement is still being delivered.
///
/// Two values. `withdrawn` stops the *active* placements and nothing else: the
/// Notifications Center entry stays, because it is a record that the notice was
/// sent, and deleting it would rewrite what the detachment was told.
enum AnnouncementStatus { active, withdrawn }

/// The shortest text worth publishing, in characters after trimming. Low
/// enough that «الاجتماع أُلغي» passes, high enough that a stray keystroke
/// does not become a notice on five dashboards.
const int announcementTextMin = 5;

/// The longest. A notice is read on a phone, at the top of a dashboard, in a
/// hurry; past this it is a document and belongs somewhere else.
const int announcementTextMax = 500;

/// One published internal announcement.
@immutable
class Announcement {
  const Announcement({
    required this.id,
    required this.text,
    required this.detachmentIds,
    required this.placements,
    required this.publishedAt,
    required this.expiresAt,
    this.status = AnnouncementStatus.active,
    this.authorName,
  });

  final String id;

  /// Plain text. Trimmed before it ever reaches this constructor.
  final String text;

  /// The detachments this announcement addresses. **At least one**, never
  /// empty, and never a wildcard — there is no "all detachments" value in this
  /// model, because there is no product decision behind one.
  ///
  /// Order is the order the author chose, de-duplicated. The client shows the
  /// announcement to a session whose grants cover *any* of these; who actually
  /// receives it server-side is a backend fan-out question — see
  /// `API_CONTRACT.md` § Announcements.
  final List<String> detachmentIds;

  /// Always contains [AnnouncementPlacement.notifications].
  final Set<AnnouncementPlacement> placements;

  final DateTime publishedAt;

  /// When the **active placements** stop. Always in the future at publication;
  /// never null, because "forever" is not an option the product offers.
  final DateTime expiresAt;

  final AnnouncementStatus status;

  /// Who published it, as a display name. Optional because the client has no
  /// admin directory: the mock carries the signed-in session's own name and a
  /// backend may serve a real one. Never an id, never an email.
  final String? authorName;

  bool get isWithdrawn => status == AnnouncementStatus.withdrawn;

  bool get showsOnHome => placements.contains(AnnouncementPlacement.home);

  bool get showsOnDetachment =>
      placements.contains(AnnouncementPlacement.detachment);

  /// True when this announcement addresses [detachmentId].
  bool targets(String detachmentId) => detachmentIds.contains(detachmentId);

  Announcement copyWith({AnnouncementStatus? status}) => Announcement(
        id: id,
        text: text,
        detachmentIds: detachmentIds,
        placements: placements,
        publishedAt: publishedAt,
        expiresAt: expiresAt,
        status: status ?? this.status,
        authorName: authorName,
      );

  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
        id: j['id'] as String,
        text: j['text'] as String,
        detachmentIds: List<String>.unmodifiable(
            (j['detachmentIds'] as List).cast<String>()),
        placements: {
          // The canonical placement is re-asserted rather than trusted: a
          // payload that omitted it would otherwise produce an announcement
          // with no history surface at all.
          AnnouncementPlacement.notifications,
          for (final name
              in (j['placements'] as List? ?? const []).cast<String>())
            for (final p in AnnouncementPlacement.values)
              if (p.name == name) p,
        },
        publishedAt: DateTime.parse(j['publishedAt'] as String),
        expiresAt: DateTime.parse(j['expiresAt'] as String),
        status: AnnouncementStatus.values.firstWhere(
          (s) => s.name == j['status'],
          // An unknown status from a newer server reads as active rather than
          // silently retiring a notice the detachment is still meant to see.
          orElse: () => AnnouncementStatus.active,
        ),
        authorName: j['authorName'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'detachmentIds': detachmentIds,
        'placements': [for (final p in placements) p.name],
        'publishedAt': publishedAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'status': status.name,
        if (authorName != null) 'authorName': authorName,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Announcement &&
          other.id == id &&
          other.text == text &&
          listEquals(other.detachmentIds, detachmentIds) &&
          setEquals(other.placements, placements) &&
          other.publishedAt == publishedAt &&
          other.expiresAt == expiresAt &&
          other.status == status &&
          other.authorName == authorName;

  @override
  int get hashCode => Object.hash(
        id,
        text,
        Object.hashAll(detachmentIds),
        Object.hashAllUnordered(placements),
        publishedAt,
        expiresAt,
        status,
        authorName,
      );

  @override
  String toString() =>
      'Announcement($id, ${detachmentIds.length} target(s), ${status.name})';
}

/// The finite lifetimes the compose screen offers.
///
/// Presets rather than a duration picker, because the person publishing is
/// answering "how long does this matter for", not "how many minutes". [custom]
/// is the escape hatch and is the only value with no [span] of its own.
enum AnnouncementDuration {
  hour(Duration(hours: 1)),
  sixHours(Duration(hours: 6)),
  twelveHours(Duration(hours: 12)),
  day(Duration(days: 1)),
  twoDays(Duration(days: 2)),
  custom(null);

  const AnnouncementDuration(this.span);

  /// Null only for [custom], where the author names an instant instead.
  final Duration? span;
}
