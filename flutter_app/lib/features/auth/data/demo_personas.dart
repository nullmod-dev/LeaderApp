/// The three development demo accounts — one per product surface.
///
/// **Development fixtures. Not product data.** Every value in this file is a
/// stand-in for something a real backend will issue, and nothing here is
/// reachable from a release build: every entry point checks
/// `demoAccountsAllowed` (`core/env/build_mode.dart`), which is `const false`
/// outside debug, so this file's contents are tree-shaken out of a shipping
/// artefact.
///
/// The three exist because MTM has three account levels and they cannot be
/// told apart by capability breadth alone:
///
/// | Persona | Role | SaasTenant | What it is |
/// |---|---|---|---|
/// | [DemoPersona.superAdmin] | `super_admin` | none | the platform owner |
/// | [DemoPersona.mainAdmin] | `main_admin` | [kDemoSaasTenantId] | the leader of one paying team |
/// | [DemoPersona.simpleAdmin] | `admin` | [kDemoSaasTenantId] | a scoped admin in **that same** team |
///
/// Main Admin and Simple Admin deliberately share one `saasTenantId`: they are
/// two administrators of one customer, and a demo set where they were two
/// customers would prove nothing about scoping.
library;

import '../../../core/access/capability.dart';
import '../../../core/access/capability_presets.dart';
import '../../../l10n/strings.dart';
import '../domain/auth_models.dart';

/// The one development `SaasTenant` id.
///
/// DEVELOPMENT-ONLY. There is no `SaasTenant` model yet — Point 6 builds
/// that — and Point 2 needs exactly one thing from it: a stable id that ties
/// the Main Admin and the Simple Admin to the same paying customer. A typed
/// `AuthUser.saasTenantId` carrying this constant is the whole of it, and
/// nothing may grow a `SaasTenant` repository around it here.
const String kDemoSaasTenantId = 'saas_hilal';

/// The two seeded detachments the Simple Admin is scoped to.
///
/// Real ids from `MockDetachmentRepository`, chosen so the persona lands on
/// populated data — a scoped account with an empty detachment would look like
/// a permission bug rather than a scope. `d_dam_central` is the seed the
/// dashboard opens on; `d_homs` proves the scope is a *set* and not just "the
/// first one".
const List<String> kDemoSimpleAdminDetachments = ['d_dam_central', 'd_homs'];

/// A development demo account.
///
/// The enum is the stable identity: [wire] is what is persisted across a
/// development restart (`DemoSessionStore`), and the whole [user] is rebuilt
/// from it on the next launch. Nothing serialises the account itself — a
/// persisted capability set would be a second source of truth for a grant
/// this file already states.
enum DemoPersona {
  superAdmin('super_admin_demo'),
  mainAdmin('main_admin_demo'),
  simpleAdmin('simple_admin_demo');

  const DemoPersona(this.wire);

  /// The persisted persona id. Never shown to a user.
  final String wire;

  /// The persona a stored [wire] names, or `null` when it names none.
  static DemoPersona? parse(String? wire) {
    for (final persona in values) {
      if (persona.wire == wire) return persona;
    }
    return null;
  }

  /// The account this persona authenticates as.
  AuthUser get user => switch (this) {
        DemoPersona.superAdmin => _superAdmin,
        DemoPersona.mainAdmin => _mainAdmin,
        DemoPersona.simpleAdmin => _simpleAdmin,
      };
}

/// **Super Admin — the platform owner.**
///
/// `saasTenantId` is null because this account is not inside a paying team;
/// it administers the platform every team lives on.
///
/// **`Capabilities.none`, and that is the honest fixture.** The 30 capability
/// keys in `Cap` are all *tenant-operational* — detachments, members, shifts,
/// inventory, workshops, announcements, one organisation's settings. None of
/// them describes platform authority, and handing this account the tenant set
/// so that it has "something to see" would assert exactly the thing the
/// product model denies: that the platform owner is a very powerful team
/// admin. Platform capabilities arrive with the platform surface (Point 4+),
/// issued against platform repositories that do not exist yet. Until then
/// this account holds nothing here, is refused every tenant screen by the
/// checks already in place, and is kept out of the tenant application by the
/// router's holding state rather than by an empty grant alone.
const AuthUser _superAdmin = AuthUser(
  id: 'u_demo_platform',
  name: 'مدير منصة ${S.productNameAr}',
  email: 'nullmod.dev@gmail.com',
  role: AuthRole.superAdmin,
  saasTenantId: null,
  capabilities: Capabilities.none,
  orgName: 'منصة ${S.productNameAr}',
  avatarInitials: 'من',
);

/// **Main Admin — the leader of one SaasTenant.**
///
/// Identity and grant are the account the mock has always booted into, moved
/// here unchanged so every existing screen and fixture keeps the operational
/// data it was built against.
///
/// The grant is `Capabilities(global: Cap.all)` rather than
/// `CapabilityPreset.mainAdmin.grant()` for the reason the old mock already
/// recorded: a preset grant lists per-detachment keys *per detachment id*, so
/// a detachment created at runtime would come up with no grant at all and its
/// Add Member action would vanish. A tenant leader holds their keys
/// organisation-wide; `canIn` reads a global holding as "everywhere in this
/// organisation", which is precisely what a Main Admin is.
const AuthUser _mainAdmin = AuthUser(
  id: 'u_demo_main',
  name: 'ليلى ياسين',
  email: 'pbea4007@mtu.edu.iq',
  role: AuthRole.mainAdmin,
  saasTenantId: kDemoSaasTenantId,
  capabilities: Capabilities(global: Cap.all),
  orgName: 'فريق الإسعاف التطوعي · دمشق',
  avatarInitials: 'لي',
);

/// **Simple Admin — a scoped administrator in the SAME SaasTenant.**
///
/// Same `saasTenantId` as the Main Admin, deliberately: one customer, two
/// administrators. Everything else is narrower, and narrower through the
/// mechanism the product already has rather than a second one — the grant is
/// `CapabilityPreset.subAdmin` (`CAPABILITIES.md` §3, the preset the product
/// calls the sub-Admin tier) issued over two named detachments.
///
/// What that withholds, and it is the whole list: `admin.manage`, `org.edit`,
/// `detachment.create`, `detachment.edit`, `detachment.archive`,
/// `member.deactivate`, `shift.delete`, `shift.attendance.override`,
/// `announcement.publish`, `workshop.archive`, `workshop.payment.record`.
/// So this account resolves to `AdminExperience.scoped`, sees two detachments
/// instead of every one, reads Plan without the organisation-wide usage
/// figures that `org.edit` gates (Point 15), and gets no organisation section
/// on the dashboard — visibly, through the same
/// checks that gate a real scoped account, with no label invented to make the
/// difference look bigger than it is.
final AuthUser _simpleAdmin = AuthUser(
  id: 'u_demo_simple',
  name: 'سامر الحلبي',
  email: 'hamodekaherhm@gmail.com',
  role: AuthRole.admin,
  saasTenantId: kDemoSaasTenantId,
  capabilities:
      CapabilityPreset.subAdmin.grant(detachments: kDemoSimpleAdminDetachments),
  orgName: 'فريق الإسعاف التطوعي · دمشق',
  avatarInitials: 'سا',
);
