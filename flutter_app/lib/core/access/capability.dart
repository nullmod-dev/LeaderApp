/// Capability keys and the single resolver every access check goes through.
///
/// Ruled 2026-09-02 — see `CAPABILITIES.md` §0. 29 keys, three presets.
/// `announcement.publish` was added 2026-09-07 (§10) — 30.
///
/// SECURITY CONTRACT — read this before adding a check anywhere:
///
/// Capability checks in this app hide, disable, and gate UI. They are a
/// usability device — they stop a user being offered an action that would
/// fail. They are **not** a security boundary. Anyone can modify a client.
/// Real enforcement of every capability in this file is the backend
/// developer's responsibility, on every request, server-side. Every
/// `TODO(security)` marker in the access code points back to this paragraph.
///
/// Pure Dart on purpose — no Flutter import. The Super Admin surface is a web
/// dashboard that comes much later (`CAPABILITIES.md` §5) and reuses this file
/// verbatim. Keep it importable from a non-Flutter target.
library;

/// The 30 capability keys.
///
/// A capability is a plain string. The signed-in profile carries a *set* of
/// them as runtime data; there is deliberately no role enum. Roles exist only
/// as presets at grant time — see `capability_presets.dart`.
abstract final class Cap {
  // ---------- Detachment ----------
  static const detachmentView = 'detachment.view';
  static const detachmentCreate = 'detachment.create';
  static const detachmentEdit = 'detachment.edit';
  static const detachmentArchive = 'detachment.archive';

  // ---------- Members ----------
  static const memberView = 'member.view';

  /// Phone numbers and personal details. Split from [memberView] so a
  /// volunteer can see who is on their own shift without reading everyone's
  /// contact details.
  static const memberContactView = 'member.contact.view';
  static const memberInvite = 'member.invite';
  static const memberEdit = 'member.edit';
  static const memberDeactivate = 'member.deactivate';
  static const memberRoleAssign = 'member.role.assign';

  // ---------- Shifts ----------
  /// Create a weekly shift template and edit its name, leader, times.
  ///
  /// The weekday of a shift is immutable for everyone. That is a data rule
  /// carried from legacy, not a permission — it must never become a key.
  static const shiftManage = 'shift.manage';
  static const shiftDelete = 'shift.delete';
  static const shiftAssign = 'shift.assign';

  /// Reserved. The legacy program has no draft/published concept, so this key
  /// only means something if the scheduling redesign introduces a draft week.
  /// Granted by preset, checked by nothing yet. See `CAPABILITIES.md` §8.
  static const shiftPublish = 'shift.publish';

  /// Mark present/absent inside the one-hour window.
  static const shiftAttendanceRecord = 'shift.attendance.record';

  /// Correct attendance *after* the one-hour lock. A supervisor act, and the
  /// one that wants an audit trail — hence separate from recording.
  static const shiftAttendanceOverride = 'shift.attendance.override';
  static const shiftOccurrenceManage = 'shift.occurrence.manage';

  // ---------- Inventory ----------
  /// The daily act: a medic logs an inflow or outflow.
  static const inventoryAdjust = 'inventory.adjust';

  /// The setup act: deciding what the detachment stocks.
  static const inventoryItemManage = 'inventory.item.manage';

  // ---------- Workshops (org-level — see [global]) ----------
  static const workshopCreate = 'workshop.create';
  static const workshopEdit = 'workshop.edit';
  static const workshopArchive = 'workshop.archive';
  static const workshopPeopleManage = 'workshop.people.manage';
  static const workshopAttendanceRecord = 'workshop.attendance.record';
  static const workshopPaymentRecord = 'workshop.payment.record';

  /// Conditional on open decision #8 — if workshop sections do not carry over
  /// from legacy, delete this constant and its preset rows.
  static const workshopSectionManage = 'workshop.section.manage';

  // ---------- Statistics ----------
  static const statsView = 'stats.view';

  // ---------- Announcements ----------
  /// Publish, withdraw and manage an internal announcement *inside one
  /// detachment*.
  ///
  /// Added 2026-09-07 for the internal announcement system. Per-detachment,
  /// not global, because an announcement is targeted at detachments and the
  /// question the target picker asks is "may this session publish **here**".
  /// A session holding it globally may target every detachment it can see; a
  /// scoped session may target only the detachments its grant names.
  ///
  /// There is deliberately **no** matching `announcement.view` key. Reading an
  /// announcement targeted at a detachment is implied by being able to see
  /// that detachment at all, which is exactly what [detachmentView] already
  /// says — the same rule `shiftStartingSoon` follows in the notification
  /// feed. A second key would gate nothing, which is why the three `*.view`
  /// keys were dropped on 2026-09-02.
  static const announcementPublish = 'announcement.publish';

  // ---------- Administration ----------
  static const adminManage = 'admin.manage';
  static const orgEdit = 'org.edit';

  /// Capabilities held everywhere in the organisation.
  ///
  /// Workshops are org-level: legacy has no detachment-to-workshop relation at
  /// all — a workshop belongs to a centre. So no workshop screen carries a
  /// detachment id and `workshop.*` is checked with [Capabilities.can].
  static const global = <String>{
    detachmentCreate,
    workshopCreate,
    workshopEdit,
    workshopArchive,
    workshopPeopleManage,
    workshopAttendanceRecord,
    workshopPaymentRecord,
    workshopSectionManage,
    adminManage,
    orgEdit,
  };

  /// Capabilities that live inside one detachment, granted per detachment id
  /// and checked with [Capabilities.canIn].
  static const scoped = <String>{
    detachmentView,
    detachmentEdit,
    detachmentArchive,
    memberView,
    memberContactView,
    memberInvite,
    memberEdit,
    memberDeactivate,
    memberRoleAssign,
    shiftManage,
    shiftDelete,
    shiftAssign,
    shiftPublish,
    shiftAttendanceRecord,
    shiftAttendanceOverride,
    shiftOccurrenceManage,
    inventoryAdjust,
    inventoryItemManage,
    statsView,
    announcementPublish,
  };

  /// Every key this build understands. A key outside this set is **denied**,
  /// never granted — adding a key server-side must not silently unlock a
  /// client that does not know it.
  static const all = <String>{...global, ...scoped};

  /// Keys the shift screens open on. A two-key route: it opens for schedule
  /// management *or* attendance recording, while the edit controls and the
  /// attendance toggles inside are gated individually.
  static const shiftRoute = <String>{shiftManage, shiftAttendanceRecord};
}

/// The signed-in session's granted capabilities.
///
/// Two grant sets checked through one resolver:
///
/// - [global] — held everywhere in the organisation.
/// - [scoped] — detachment id to the keys held inside that detachment.
///
/// **The single-resolver rule.** [canIn] is the only place access is decided.
/// [can] and [canAnyIn] delegate to it, and so do the route guard and
/// `CapabilityGate`. When a guard and the controls it protects resolve access
/// separately they drift, and a user reaches a screen where every control is
/// disabled — or worse, a control works on a screen they should not have
/// reached.
class Capabilities {
  const Capabilities({
    this.global = const <String>{},
    this.scoped = const <String, Set<String>>{},
  });

  /// Deny everything. The correct value while a session is still loading and
  /// for a signed-out user.
  static const none = Capabilities();

  final Set<String> global;
  final Map<String, Set<String>> scoped;

  /// Whether this session holds **any** capability at all, anywhere.
  ///
  /// The one place that question is answered, so the startup classifier does
  /// not have to know how a grant is shaped. A scoped entry with an empty key
  /// set counts as nothing held — it names a detachment and grants nothing in
  /// it, which is indistinguishable from not being named at all.
  ///
  /// **What this is not.** It is not "may do X" and nothing may branch on it
  /// to allow an action; `canIn` is still the single resolver. It exists to
  /// tell a session with an empty grant from one with a grant, so the former
  /// gets a screen that explains itself instead of an app full of hidden
  /// controls.
  bool get hasAny =>
      global.isNotEmpty || scoped.values.any((keys) => keys.isNotEmpty);

  /// Resolve an organisation-level capability.
  ///
  /// Asserts in debug if handed a per-detachment key, because the answer would
  /// silently be `false` and the control would silently vanish.
  bool can(String key) {
    assert(
      !Cap.scoped.contains(key),
      'canIn(detachmentId, ...) is the check for the per-detachment key "$key".',
    );
    return canIn(null, key);
  }

  /// Resolve a capability, optionally inside one detachment.
  ///
  /// Union, not override: true when the key is held globally **or** in that
  /// detachment. A Main Admin holds everything globally and needs no entry per
  /// detachment; revoking for one detachment means removing the global key and
  /// re-granting per detachment, which is explicit and auditable rather than a
  /// silent negative override.
  ///
  /// A grant inside a detachment implies the right to see it, so any scoped
  /// entry at all satisfies [Cap.detachmentView] for that detachment. Granting
  /// someone `shift.manage` in Homs lets them see Homs without a second grant.
  bool canIn(String? detachmentId, String key) {
    // TODO(security): UX gate only. The backend enforces this on every request.
    if (!Cap.all.contains(key)) return false;
    if (global.contains(key)) return true;
    if (detachmentId == null) return false;

    final held = scoped[detachmentId];
    if (held == null || held.isEmpty) return false;
    if (held.contains(key)) return true;

    return key == Cap.detachmentView;
  }

  /// True when **any** of [keys] is held. The resolver for two-key routes such
  /// as [Cap.shiftRoute].
  bool canAnyIn(String? detachmentId, Iterable<String> keys) =>
      keys.any((key) => canIn(detachmentId, key));

  /// True when [key] is held **anywhere** — globally, or inside at least one
  /// named detachment.
  ///
  /// The question a surface that is not itself detachment-scoped has to ask.
  /// The announcement management screen and its route guard are the first
  /// callers: the screen spans every detachment the session may publish in,
  /// so `canIn(null, key)` is the wrong question — it would refuse a scoped
  /// admin who genuinely holds the key in one detachment. Still the single
  /// resolver: every branch below delegates to [canIn].
  bool canAnywhere(String key) =>
      canIn(null, key) || scoped.keys.any((id) => canIn(id, key));

  /// Detachment ids this session can see, in grant order. Empty for a session
  /// scoped to nothing — which for a Main Admin is normal, since their grants
  /// are global.
  Iterable<String> get visibleDetachmentIds =>
      scoped.entries.where((e) => e.value.isNotEmpty).map((e) => e.key);

  /// Wire format. Unknown keys are kept as sent rather than dropped — [canIn]
  /// already denies them, and a client that does not understand a key has no
  /// business deleting it from a grant it may hand back.
  factory Capabilities.fromJson(Map<String, dynamic> j) => Capabilities(
        global: ((j['global'] as List?) ?? const []).cast<String>().toSet(),
        scoped: {
          for (final e in ((j['scoped'] as Map?) ?? const {}).entries)
            e.key as String: (e.value as List).cast<String>().toSet(),
        },
      );

  Map<String, dynamic> toJson() => {
        'global': global.toList(),
        'scoped': {
          for (final e in scoped.entries) e.key: e.value.toList(),
        },
      };

  Capabilities copyWith({
    Set<String>? global,
    Map<String, Set<String>>? scoped,
  }) =>
      Capabilities(
        global: global ?? this.global,
        scoped: scoped ?? this.scoped,
      );

  // Value equality so a rebuilt session with identical grants does not rebuild
  // every gated control in the tree.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Capabilities &&
          _sameSet(global, other.global) &&
          _sameMap(scoped, other.scoped);

  @override
  int get hashCode => Object.hash(
        global.length,
        scoped.length,
        Object.hashAllUnordered(global),
        Object.hashAllUnordered(scoped.keys),
      );

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  static bool _sameMap(Map<String, Set<String>> a, Map<String, Set<String>> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      final other = b[e.key];
      if (other == null || !_sameSet(e.value, other)) return false;
    }
    return true;
  }

  @override
  String toString() => 'Capabilities(global: ${global.length}, '
      'scoped: ${scoped.length} detachment(s))';
}
