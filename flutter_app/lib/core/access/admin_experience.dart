/// How much of the application one administrator's session is shown.
///
/// **This is presentation, not authorization.** Nothing in this file grants
/// anything. Every value here is *derived* from a [Capabilities] grant that
/// was already issued by the server, and every actual access decision still
/// goes through `Capabilities.canIn` — the single-resolver rule at the top of
/// `capability.dart`. A screen may ask this file how much to show; it must
/// never ask it whether an action may run.
///
/// **This is not the account's role, and must never be read as one.**
/// `AuthUser.role` (`AuthRole`, added for Point 2) says which *product
/// surface* an account belongs to — the platform, or one paying SaasTenant.
/// This file answers a different question, one level down: *inside the tenant
/// application*, how broad is this particular session's UI. The two are
/// independent by construction —
///
///   - a `main_admin` whose keys were narrowed is still a Main Admin, and is
///     honestly shown the [AdminExperience.scoped] UI;
///   - an `admin` granted `org.edit` is still a Simple Admin, and is honestly
///     shown the [AdminExperience.full] one;
///   - a `super_admin` is not classified here **at all**. It is not in the
///     tenant application; the router holds it outside, on its own shell (see
///     `features/platform/presentation/platform_shell.dart`), and its grant is
///     `Capabilities.none`, so were this ever asked about one it answers
///     [AdminExperience.scoped] — deny, which is the safe direction but not a
///     statement about the account.
///
/// So "Main Admin" *here* has always meant, and still means, a *label
/// computed from capability breadth* — never the role property. The mapping
/// is deterministic and stated once, in [AdminExperience.of]:
///
///   full  ⟺ the session holds at least one of the three administration
///           capabilities — `admin.manage`, `org.edit`, `detachment.create`.
///   scoped ⟺ otherwise.
///
/// Those three are exactly the group `CAPABILITIES.md` §3 names
/// "Administration", and they are the three a sub-Admin preset is defined by
/// *not* holding. Nothing else in the app may invent a second definition.
///
/// Pure Dart on purpose, like the rest of `core/access/` — the later web
/// dashboard reuses it verbatim, and `AdminScope` below is the seam a
/// capability-aware Global Search will ask "what may this admin search".
library;

import 'capability.dart';

/// The two experiences the product ships.
///
/// Deliberately two values and not four: this is the answer to "how broad is
/// this session's UI", and a third shade would immediately be mistaken for a
/// rank. What an account *actually holds* is reported truthfully elsewhere —
/// see `AdminAccountSummary` on the account screen.
enum AdminExperience {
  /// Organisation-level control. The session administers the organisation
  /// itself, so it is offered the organisation-wide surfaces — subject, still,
  /// to a capability check at every one of them.
  full,

  /// Operational access confined to what this session was actually granted.
  /// Not a degraded [full]: the organisation-level sections are *absent*, not
  /// present-and-disabled.
  scoped,
}

/// A data category a capability-aware surface may offer.
///
/// Today the dashboard and the navigation read this. Global Search (the next
/// task) is the reason it is an enum rather than a pile of booleans: a search
/// screen needs to ask one question — "which categories may this admin
/// search" — and get an answer that was derived in exactly one place.
enum AdminDataCategory {
  detachments,
  members,
  shifts,
  inventory,
  statistics,
  workshops,
}

/// The organisation-level capabilities. Holding any one of them is what makes
/// a session an administrator *of the organisation* rather than an operator
/// inside it.
const _administration = <String>{
  Cap.adminManage,
  Cap.orgEdit,
  Cap.detachmentCreate,
};

/// Every `workshop.*` key. Workshops are org-level (`CAPABILITIES.md` §0/Q2),
/// so they are checked globally and scoped to nothing.
const _workshop = <String>{
  Cap.workshopCreate,
  Cap.workshopEdit,
  Cap.workshopArchive,
  Cap.workshopPeopleManage,
  Cap.workshopAttendanceRecord,
  Cap.workshopPaymentRecord,
  Cap.workshopSectionManage,
};

/// What one session's UI is allowed to be shaped like.
///
/// Built once per grant and read wherever breadth is decided, so there is no
/// `if (isMainAdmin)` anywhere in the widget tree. Every field is a plain
/// projection of [capabilities]; none of them is consulted before an action
/// runs.
class AdminView {
  const AdminView({
    required this.capabilities,
    required this.experience,
    required this.managesAdmins,
    required this.editsOrganisation,
    required this.createsContainers,
    required this.organisationWideDetachments,
    required this.namedDetachmentIds,
    required this.workshops,
  });

  /// The grant everything below was derived from. Kept so a caller that needs
  /// a real check has the authoritative object in hand and is never tempted to
  /// substitute one of the flags for it.
  final Capabilities capabilities;

  final AdminExperience experience;

  /// Holds `admin.manage`.
  final bool managesAdmins;

  /// Holds `org.edit`.
  final bool editsOrganisation;

  /// Holds `detachment.create` — may stand up a detachment group or a detachment, which
  /// is what makes the container hierarchy worth showing at all.
  final bool createsContainers;

  /// Holds `detachment.view` organisation-wide, so every detachment in the
  /// organisation is visible rather than a named few.
  final bool organisationWideDetachments;

  /// The detachment ids named in the grant, in grant order. Empty for an
  /// organisation-wide session, whose grants need no per-detachment entry.
  final List<String> namedDetachmentIds;

  /// Holds at least one `workshop.*` key.
  final bool workshops;

  /// Deny everything. The correct value while a session is still loading and
  /// for a signed-out user — and it resolves to [AdminExperience.scoped], so
  /// an unknown capability state never renders the broad experience.
  static final AdminView none = AdminView.of(Capabilities.none);

  factory AdminView.of(Capabilities caps) {
    final full = _administration.any((key) => caps.can(key));
    return AdminView(
      capabilities: caps,
      experience: full ? AdminExperience.full : AdminExperience.scoped,
      managesAdmins: caps.can(Cap.adminManage),
      editsOrganisation: caps.can(Cap.orgEdit),
      createsContainers: caps.can(Cap.detachmentCreate),
      // `detachment.view` is a per-detachment key, so a *global* holding of it
      // is precisely "sees them all". `canIn(null, ...)` is the union check
      // with no detachment in hand, which is the same question.
      organisationWideDetachments: caps.canIn(null, Cap.detachmentView),
      namedDetachmentIds: List.unmodifiable(caps.visibleDetachmentIds),
      workshops: _workshop.any((key) => caps.can(key)),
    );
  }

  bool get isFull => experience == AdminExperience.full;
  bool get isScoped => experience == AdminExperience.scoped;

  /// True when this session may see [detachmentId] at all.
  ///
  /// The check, not a shortcut around it: `detachment.view` is the anchor of
  /// the scoping model and any scoped grant implies it (`CAPABILITIES.md`
  /// §4/Q3), so this is the one question a list filter has to ask.
  bool coversDetachment(String detachmentId) =>
      capabilities.canIn(detachmentId, Cap.detachmentView);

  /// The session sees exactly one detachment and no more — the case where a
  /// switcher is noise rather than navigation.
  bool get hasSingleDetachment =>
      !organisationWideDetachments && namedDetachmentIds.length == 1;

  /// The session can see no detachment at all. A real state (an account
  /// created and not yet granted anything), and a designed screen — never a
  /// blank dashboard.
  bool get hasNoDetachment =>
      !organisationWideDetachments && namedDetachmentIds.isEmpty;

  /// Which data categories this session may be offered inside [detachmentId],
  /// or organisation-wide when it is null.
  ///
  /// **The Global Search seam.** A search screen asks this and searches
  /// nothing outside the answer; it still checks each result's own capability
  /// before offering an action on it. Shifts and inventory follow membership
  /// rather than a key — `shift.view` / `inventory.view` were dropped on
  /// 2026-09-02 because they gated nothing — so they are offered wherever the
  /// detachment itself is visible.
  Set<AdminDataCategory> categoriesIn(String? detachmentId) {
    final visible = detachmentId == null
        ? organisationWideDetachments || namedDetachmentIds.isNotEmpty
        : coversDetachment(detachmentId);
    return {
      if (visible) ...[
        AdminDataCategory.detachments,
        AdminDataCategory.shifts,
        AdminDataCategory.inventory,
      ],
      if (capabilities.canIn(detachmentId, Cap.memberView))
        AdminDataCategory.members,
      if (capabilities.canIn(detachmentId, Cap.statsView))
        AdminDataCategory.statistics,
      if (workshops) AdminDataCategory.workshops,
    };
  }

  /// Every category reachable anywhere in this session — the organisation-wide
  /// union for a full admin, and the union across the named detachments for a
  /// scoped one. This is the form Global Search will want first.
  Set<AdminDataCategory> get searchableCategories {
    if (organisationWideDetachments || namedDetachmentIds.isEmpty) {
      return categoriesIn(null);
    }
    return {
      for (final id in namedDetachmentIds) ...categoriesIn(id),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdminView && other.capabilities == capabilities;

  @override
  int get hashCode => capabilities.hashCode;

  @override
  String toString() => 'AdminView(${experience.name}, '
      'orgWide: $organisationWideDetachments, '
      'detachments: ${namedDetachmentIds.length})';
}

/// Filters [ids] down to the detachments [view] may see, preserving order.
///
/// Lives here rather than in the detachment feature so the dashboard, the
/// list, and later Global Search all narrow scope through the same function.
Iterable<T> visibleDetachments<T>(
  AdminView view,
  Iterable<T> items,
  String Function(T) idOf,
) =>
    view.organisationWideDetachments
        ? items
        : items.where((item) => view.coversDetachment(idOf(item)));
