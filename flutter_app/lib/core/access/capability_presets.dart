import 'capability.dart';

/// The three starting grant sets a Main Admin picks from when creating an
/// account. Ruled 2026-09-02 — see `CAPABILITIES.md` §3.
///
/// A preset is **not** the user's identity and is never consulted at check
/// time. After creation the Main Admin adds or removes individual keys, so a
/// real capability set may match no preset at all. This is the whole reason
/// `UserRole` was removed.
///
/// There is no Super Admin preset. Cross-organisation administration is
/// vendor-run outside the app and the in-organisation root admin is a Main
/// Admin, so the mobile app has no cross-org actor to render
/// (`CAPABILITIES.md` §5).
///
/// Pure Dart — see the note at the top of `capability.dart`.
enum CapabilityPreset { mainAdmin, subAdmin, volunteer }

extension CapabilityPresetGrant on CapabilityPreset {
  /// The keys this preset starts with.
  ///
  /// Listed explicitly rather than derived by subtraction so that a key added
  /// to [Cap] later is withheld by every preset until someone grants it
  /// deliberately. Fail closed, not open.
  Set<String> get keys => switch (this) {
        CapabilityPreset.mainAdmin => Cap.all,
        CapabilityPreset.subAdmin => _subAdmin,
        CapabilityPreset.volunteer => _volunteer,
      };

  /// Build a grant for this preset over [detachments].
  ///
  /// Global keys land in the global set, per-detachment keys are copied into
  /// every id in [detachments]. A Main Admin usually needs no detachment list
  /// at all — their scoped keys are better held globally — but the mock and
  /// the admin screen both want the scoped form so per-detachment isolation
  /// is visible.
  Capabilities grant({Iterable<String> detachments = const []}) {
    final granted = keys;
    final scopedKeys = granted.where(Cap.scoped.contains).toSet();
    return Capabilities(
      global: granted.where(Cap.global.contains).toSet(),
      scoped: {
        for (final id in detachments) id: scopedKeys,
      },
    );
  }
}

/// Every operational act; no lifecycle act, no money, no administration.
///
/// Withheld on purpose, and this is the whole list: `detachment.create`,
/// `detachment.edit`, `detachment.archive`, `member.deactivate`,
/// `shift.delete`, `shift.attendance.override`, `workshop.archive`,
/// `workshop.payment.record`, `admin.manage`, `org.edit`.
///
/// Two of those look inconsistent and are not. A member's *role* is a roster
/// label, not a grant of app capabilities, so `member.role.assign` is
/// operational and stays — while deactivation retires a record and rewrites
/// how attendance history reads, which is lifecycle. And `stats.view` stays
/// because an operator running shifts needs attendance rates; the privacy
/// concern is answered by scope, since a sub-Admin sees their own detachment
/// and not the organisation.
const _subAdmin = <String>{
  Cap.detachmentView,
  Cap.memberView,
  Cap.memberContactView,
  Cap.memberInvite,
  Cap.memberEdit,
  Cap.memberRoleAssign,
  Cap.shiftManage,
  Cap.shiftAssign,
  Cap.shiftPublish,
  Cap.shiftAttendanceRecord,
  Cap.shiftOccurrenceManage,
  Cap.inventoryAdjust,
  Cap.inventoryItemManage,
  Cap.workshopCreate,
  Cap.workshopEdit,
  Cap.workshopPeopleManage,
  Cap.workshopAttendanceRecord,
  Cap.workshopSectionManage,
  Cap.statsView,
};

/// Exactly two keys, and that is deliberate.
///
/// `shift.view`, `inventory.view` and `workshop.view` were dropped on
/// 2026-09-02 because they were granted to every role and so gated nothing.
/// Everything else a volunteer sees — the schedule, the stock list, the
/// workshop list — now follows from membership. What is left is the pair that
/// gates something real: which detachments they see, and the roster without
/// the phone numbers.
const _volunteer = <String>{
  Cap.detachmentView,
  Cap.memberView,
};
