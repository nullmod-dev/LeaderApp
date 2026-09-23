/// Every model is immutable and has [fromJson] + [toJson] even though
/// only mock data exists — this is the wire format the real API will use.
library;

import '../../../core/access/capability.dart';

/// Which **product surface** an authenticated account belongs to.
///
/// Three administrator levels plus the isolated customer-demo identity:
///
/// - [superAdmin] — the platform / SaaS control plane. Not a member of any
///   paying team; owns subscribers, plans, platform health and platform
///   audit. **Not** a high-capability admin inside one team.
/// - [mainAdmin] — the leader of exactly one `SaasTenant`: one paying
///   team/customer and everything operational inside it.
/// - [admin] — an additional administrator inside the **same** `SaasTenant`
///   as its Main Admin, narrowed by capability and by detachment.
/// - [customerDemo] — a product demo workspace identity. It has no tenant,
///   no tenant capability grant and can only be paired with a demo session.
///
/// **Role selects the surface; capabilities authorize the actions.** Nothing
/// in this app may branch on a role to grant an action — every access
/// decision still resolves through `Capabilities.canIn`, the single-resolver
/// rule at the top of `core/access/capability.dart`. A role answers "which
/// application is this account looking at", which a capability set cannot
/// express: a Super Admin with every tenant capability would still be the
/// wrong product, and a Main Admin with none would still be in the right one.
///
/// This does **not** resurrect the `UserRole` enum removed on 2026-09-02.
/// That one named a rank inside one organisation and was used as an authority
/// check — exactly what capabilities replaced, and exactly what this must
/// never become. See `CAPABILITIES.md` §5.
enum AuthRole {
  superAdmin('super_admin'),
  mainAdmin('main_admin'),
  admin('admin'),
  customerDemo('customer_demo');

  const AuthRole(this.wire);

  /// The exact string carried on the wire. Never rendered to a user.
  final String wire;

  /// The matching role, or `null` when this build does not recognise [wire].
  ///
  /// `null` is refused rather than defaulted: a session whose role this build
  /// cannot classify must not be handed the tenant surface on a guess.
  static AuthRole? parse(String? wire) {
    for (final role in values) {
      if (role.wire == wire) return role;
    }
    return null;
  }

  /// True when this role lives **inside** one `SaasTenant`, and therefore
  /// must carry a [AuthUser.saasTenantId].
  bool get belongsToSaasTenant =>
      this == AuthRole.mainAdmin || this == AuthRole.admin;
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.saasTenantId,
    required this.capabilities,
    required this.orgName,
    this.avatarInitials,
  });

  final String id;
  final String name;
  final String email;

  /// Which product surface this account belongs to — platform, or one paying
  /// team. See [AuthRole]: it classifies, it never authorizes.
  final AuthRole role;

  /// The `SaasTenant` this account administers, or `null` for identities
  /// outside tenant operations (Platform and Customer Demo).
  ///
  /// **The invariant, and it is not negotiable** ([isWellFormed]):
  /// `super_admin`/`customer_demo` carry `null`; `main_admin` and `admin`
  /// carry a real id.
  /// A Main Admin and every Simple Admin under them carry the *same* id —
  /// that is what makes them administrators of one customer rather than two.
  ///
  /// Never inferred. [orgName] is a display string a person typed and two
  /// customers may share it; the isolation boundary is this id or nothing.
  final String? saasTenantId;

  /// What this session may do.
  ///
  /// This replaced `enum UserRole { superAdmin, mainAdmin, simpleAdmin,
  /// volunteer }` on 2026-09-02. Capabilities are runtime data the server
  /// grants per user, so two Main Admins can differ; a role enum cannot
  /// express that. Roles survive only as presets at grant time — see
  /// `core/access/capability_presets.dart` and `CAPABILITIES.md`.
  ///
  /// [role] does not change that. It says which product surface this account
  /// is looking at; this says what may run inside it, and it is still the
  /// only thing any check reads.
  final Capabilities capabilities;

  final String orgName;
  final String? avatarInitials;

  /// Whether [role] and [saasTenantId] agree.
  ///
  /// An account that fails this is **invalid authentication data**, not an
  /// account with a missing field. Nothing repairs it: the client does not
  /// drop the stray tenant id off a `super_admin`, and does not invent one
  /// for a `main_admin` that arrived without it — either would turn a server
  /// bug into a silently mis-scoped session. `auth_providers.dart` refuses
  /// such a payload and the app reads as signed out.
  bool get isWellFormed =>
      role.belongsToSaasTenant ==
      (saasTenantId != null && saasTenantId!.isNotEmpty);

  /// Parses an account payload.
  ///
  /// Throws [FormatException] for an unknown or absent `role` and for a
  /// role/tenant pair that violates [isWellFormed] — a malformed account is
  /// not an account, and returning a half-built one would push the decision
  /// onto every caller.
  factory AuthUser.fromJson(Map<String, dynamic> j) {
    final role = AuthRole.parse(j['role'] as String?);
    if (role == null) {
      throw FormatException('AuthUser.role is missing or unknown', j['role']);
    }
    final user = AuthUser(
      id: j['id'] as String,
      name: j['name'] as String,
      email: j['email'] as String,
      role: role,
      saasTenantId: j['saasTenantId'] as String?,
      capabilities: Capabilities.fromJson(
        (j['capabilities'] as Map<String, dynamic>?) ?? const {},
      ),
      orgName: j['orgName'] as String,
      avatarInitials: j['avatarInitials'] as String?,
    );
    if (!user.isWellFormed) {
      throw FormatException(
        'AuthUser.saasTenantId must be ${role.belongsToSaasTenant ? "present" : "null"} '
        'for role ${role.wire}',
        j['saasTenantId'],
      );
    }
    return user;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role.wire,
        'saasTenantId': saasTenantId,
        'capabilities': capabilities.toJson(),
        'orgName': orgName,
        if (avatarInitials != null) 'avatarInitials': avatarInitials,
      };
}

class MfaSetupData {
  const MfaSetupData({
    required this.otpauthUrl,
    required this.manualSecret,
    required this.backupCodes,
  });

  final String otpauthUrl;
  final String manualSecret;
  final List<String> backupCodes;

  factory MfaSetupData.fromJson(Map<String, dynamic> j) => MfaSetupData(
        otpauthUrl: j['otpauthUrl'] as String,
        manualSecret: j['manualSecret'] as String,
        backupCodes: (j['backupCodes'] as List).cast<String>(),
      );

  Map<String, dynamic> toJson() => {
        'otpauthUrl': otpauthUrl,
        'manualSecret': manualSecret,
        'backupCodes': backupCodes,
      };
}

class Session {
  const Session({
    required this.id,
    required this.device,
    required this.ipMasked,
    required this.locationLabel,
    required this.startedAt,
    required this.current,
  });

  final String id;
  final String device;
  final String ipMasked;
  final String locationLabel;
  final DateTime startedAt;
  final bool current;

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        id: j['id'] as String,
        device: j['device'] as String,
        ipMasked: j['ipMasked'] as String,
        locationLabel: j['locationLabel'] as String,
        startedAt: DateTime.parse(j['startedAt'] as String),
        current: j['current'] as bool,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'device': device,
        'ipMasked': ipMasked,
        'locationLabel': locationLabel,
        'startedAt': startedAt.toIso8601String(),
        'current': current,
      };
}
