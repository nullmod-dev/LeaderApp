import '../../../core/access/capability.dart';

/// The **demo-only** capability envelope.
///
/// A Customer Demo session has to render and exercise the tenant product, and
/// every control in this app asks `Capabilities.canIn` rather than a role — so
/// a demo with no capabilities is a demo with no application. This is the set
/// it is given.
///
/// What keeps it honest:
///
/// - it is **not a production grant**. It is attached to the demo identity,
///   which has no `saasTenantId`, and it is never written to a tenant, a
///   membership, an invitation or a Team Code;
/// - it never reaches a production repository. A demo session's reads and
///   writes are served by `DemoWorkspace`, which is in-memory and thrown away
///   when the demo ends;
/// - the backend must refuse a demo session on every tenant endpoint whatever
///   this set says — the same contract every capability check in this app
///   carries (`core/access/capability.dart`);
/// - it deliberately excludes the two **administration** keys,
///   `admin.manage` and `org.edit`. Those govern real administrators, real
///   invitations, the organisation record and the plan; a trial has no
///   business demonstrating them with a working button. Platform / Super
///   Admin is out of reach for a different and stronger reason: it is a
///   different product surface and the demo role can never classify into it.
const demoCapabilityKeys = <String>{
  Cap.detachmentView,
  Cap.detachmentCreate,
  Cap.detachmentEdit,
  Cap.detachmentArchive,
  Cap.memberView,
  Cap.memberContactView,
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
  Cap.workshopCreate,
  Cap.workshopEdit,
  Cap.workshopArchive,
  Cap.workshopPeopleManage,
  Cap.workshopAttendanceRecord,
  Cap.workshopPaymentRecord,
  Cap.workshopSectionManage,
  Cap.statsView,
  Cap.announcementPublish,
};

/// Held globally, because the demo workspace is the whole organisation the
/// demo can see — there is no second tenant to scope away from.
const demoCapabilities = Capabilities(global: demoCapabilityKeys);
