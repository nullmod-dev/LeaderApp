/// Whether a detachment is still being run, or is being read back.
///
/// A detachment's lifecycle is already a domain state — `DetachmentStatus`
/// (`active` / `archived`), sent on the wire and filterable on the list
/// endpoint (`API_CONTRACT.md` §Detachments). Nothing here invents a second
/// one. What this file adds is the *consequence* of that state for the
/// screens: an archived detachment is history, and history is read.
///
/// **One resolver, not a check per screen.** The detachment surfaces already
/// resolve every action through `Capabilities.canIn` — the single-resolver
/// rule at the top of `capability.dart`. [DetachmentAccess] wraps that
/// resolver rather than sitting beside it, so a control and the handler
/// behind it can never disagree about whether this detachment may still be
/// written to. Scattering `if (archived)` through the tabs is precisely how a
/// forgotten branch ships a live "delete shift" button on a closed record.
///
/// TODO(security): a UX gate, like every other access decision on the client.
/// The backend must refuse a write against an archived detachment on its own
/// — see the contract at the top of `capability.dart`.
///
/// Pure Dart on purpose, like the rest of `core/access/`.
library;

import 'capability.dart';

/// How a detachment's surfaces behave.
enum DetachmentMode {
  /// Being run right now. Every capability the session holds applies.
  active,

  /// Finished. Its records are read, exported, and left alone.
  historical,

  /// Not known yet — the record has not landed, or could not be read at all.
  ///
  /// Resolves like [historical] for writing, never like [active]. A session
  /// that cannot tell whether a detachment is closed must not be offered the
  /// controls that would close over it.
  unknown;

  bool get isHistorical => this == DetachmentMode.historical;

  /// True only for [active]. The one question every mutating control asks.
  bool get allowsOperationalWrites => this == DetachmentMode.active;
}

/// The per-detachment capabilities that **write operational data**.
///
/// Everything a detachment's day-to-day running changes: its roster, its
/// schedule, the attendance on it, and its stock. These are the keys an
/// archived detachment stops honouring.
///
/// Two scoped keys are deliberately **not** here:
///
/// * `detachment.view`, `member.view`, `member.contact.view` and `stats.view`
///   are reads — the whole point of an archive.
/// * `detachment.archive` is the *lifecycle* key, and moving a detachment
///   between `active` and `archived` is exactly what it exists for. Closing
///   it here would make archiving a one-way door that no capability could
///   undo, which is a product decision nobody made.
///
/// `detachment.edit` **is** here: renaming or re-describing a finished
/// detachment is a historical correction, and this domain has no correction
/// workflow for it (§8 — reported, not invented).
const Set<String> historicallyClosedCapabilities = <String>{
  Cap.detachmentEdit,
  Cap.memberInvite,
  Cap.memberEdit,
  Cap.memberDeactivate,
  Cap.memberRoleAssign,
  Cap.shiftManage,
  Cap.shiftDelete,
  Cap.shiftAssign,
  Cap.shiftPublish,
  Cap.shiftAttendanceRecord,
  Cap.shiftAttendanceOverride,
  Cap.shiftOccurrenceManage,
  Cap.inventoryAdjust,
  Cap.inventoryItemManage,
  // Publishing a notice to a detachment that has finished running is an
  // operational write with nobody left to read it. Reading the announcements
  // it already carries stays open, like the rest of its history.
  Cap.announcementPublish,
};

/// What one session may do inside one detachment, lifecycle included.
///
/// Built from the grant and the detachment's own state, and read wherever a
/// detachment-scoped control decides whether it exists. [can] is the only
/// question a screen asks; it delegates to `Capabilities.canIn` for the grant
/// and adds exactly one rule of its own.
class DetachmentAccess {
  const DetachmentAccess({
    required this.detachmentId,
    required this.capabilities,
    required this.mode,
  });

  final String detachmentId;
  final Capabilities capabilities;
  final DetachmentMode mode;

  /// This detachment has ended. What the read-only presentation reads.
  bool get isHistorical => mode.isHistorical;

  /// True when the session holds [key] here **and** this detachment still
  /// accepts the kind of change [key] describes.
  bool can(String key) {
    if (!mode.allowsOperationalWrites &&
        historicallyClosedCapabilities.contains(key)) {
      return false;
    }
    return capabilities.canIn(detachmentId, key);
  }

  /// True when **any** of [keys] resolves. The two-key case, narrowed the
  /// same way.
  bool canAny(Iterable<String> keys) => keys.any(can);

  /// [value] when [key] resolves, otherwise `null` — the shape a control
  /// wants when it renders its own disabled state rather than vanishing.
  T? when<T>(String key, T value) => can(key) ? value : null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DetachmentAccess &&
          other.detachmentId == detachmentId &&
          other.mode == mode &&
          other.capabilities == capabilities;

  @override
  int get hashCode => Object.hash(detachmentId, mode, capabilities);

  @override
  String toString() => 'DetachmentAccess($detachmentId, ${mode.name})';
}
