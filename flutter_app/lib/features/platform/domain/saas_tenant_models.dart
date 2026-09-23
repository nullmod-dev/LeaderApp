/// The `SaasTenant` — **one paying MTM subscriber**, and the canonical
/// platform record for it.
///
/// The three words this file is careful about, because the codebase has
/// already been renamed once to keep them apart:
///
///  - **`SaasTenant`** — a customer. The subscription, billing, security and
///    data-isolation boundary. Its wire id is `tenantId`.
///  - **`DetachmentGroup`** — a local grouping of detachments *inside* one
///    `SaasTenant`. Never a tenant; it has no subscription and no boundary.
///  - **`Detachment`** — an operational medical field unit.
///
/// Everything here belongs to the control plane. A tenant-operational screen
/// must never import this file, and this file imports nothing from a tenant
/// feature.
library;

import 'package:flutter/foundation.dart';

import '../../../core/access/saas_tenant_status.dart';
import '../../../core/text/search_key.dart';
import 'saas_subscription_models.dart';
import 'team_code.dart';
import 'tenant_lifecycle_models.dart';

export '../../../core/access/saas_tenant_status.dart';

// ---------------------------------------------------------------------------
// Status
// ---------------------------------------------------------------------------

/// The list filters/badges exposed by tenant management. This is an explicit
/// projection: lifecycle-blocking states take precedence; the four commercial
/// states otherwise come from the separate subscription snapshot.
enum SaasTenantListStatus {
  trial('trial'),
  active('active'),
  grace('grace'),
  inactive('inactive'),
  suspended('suspended'),
  deletionPending('deletion_pending'),
  deleted('deleted');

  const SaasTenantListStatus(this.wire);
  final String wire;
}

/// How far the tenant's **initial Main Admin** has got.
///
/// The platform side of the provisioning story only. The flow that moves a
/// record from [pendingSetup] to [active] — email-ownership proof by OTP, the
/// Team Code, a forced password change on first sign-in — is a later Point and
/// none of it is collected, stored or simulated here.
enum MainAdminProvisioning {
  /// Identified by the Super Admin; has not completed first-time setup.
  ///
  /// The wire string matches `AccountStatus.pendingSetup`, which is the same
  /// concept seen from the account side.
  pendingSetup('pending_setup'),

  /// Has completed setup and holds a working account.
  active('active');

  const MainAdminProvisioning(this.wire);
  final String wire;

  static MainAdminProvisioning? parse(String? wire) {
    if (wire == null) return null;
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    return null;
  }
}

/// What kind of lifecycle event a history row records.
///
/// Tenant lifecycle history, **not** the platform audit log: it says what
/// tenant/subscription state changed and when, but not who acted from which
/// address. The immutable actor-attributed record is Point 11 and is a
/// different resource.
enum SaasTenantEventType {
  tenantCreated('tenant_created'),
  trialStarted('trial_started'),
  trialEnded('trial_ended'),
  trialExtended('trial_extended'),
  subscriptionActivated('subscription_activated'),
  movedToGrace('moved_to_grace'),
  planChanged('plan_changed'),
  limitOverrideChanged('limit_override_changed'),
  tenantSuspended('tenant_suspended'),
  tenantReactivated('tenant_reactivated'),
  deletionRequested('deletion_requested'),
  deletionCancelled('deletion_cancelled'),
  tenantDeleted('tenant_deleted');

  const SaasTenantEventType(this.wire);
  final String wire;

  static SaasTenantEventType? parse(String? wire) {
    if (wire == null) return null;
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Value objects
// ---------------------------------------------------------------------------

/// The tenant's initial Main Admin, as the platform holds them.
///
/// **Carries no secret and has nowhere to put one.** No password, no
/// temporary password, no OTP, no token, no recovery code — see
/// `HANDOFF.md` for why Point 6 deliberately does not generate a temporary
/// credential at all. What the Super Admin needs is who the invitation went
/// to and whether it has been accepted, and that is exactly what is here.
@immutable
class MainAdminContact {
  const MainAdminContact({
    required this.name,
    required this.email,
    required this.provisioning,
  });

  final String name;

  /// A technical field: always rendered LTR, even inside the RTL UI.
  final String email;

  final MainAdminProvisioning provisioning;

  bool get setupPending => provisioning == MainAdminProvisioning.pendingSetup;

  factory MainAdminContact.fromJson(Map<String, dynamic> json) =>
      MainAdminContact(
        name: json['name'] as String,
        email: json['email'] as String,
        provisioning:
            MainAdminProvisioning.parse(json['provisioning'] as String?) ??
                (throw FormatException(
                  'unknown main admin provisioning state',
                  json['provisioning'],
                )),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'provisioning': provisioning.wire,
      };
}

/// What one tenant is using, as a platform aggregate.
///
/// Backend-neutral by rule: bytes and a last-activity instant, never a
/// database, host, vendor or RAM figure — the same restraint
/// `PlatformUsageSummary` states for the platform-wide number.
@immutable
class SaasTenantUsage {
  const SaasTenantUsage({
    required this.storageUsedBytes,
    this.storageAllowanceBytes,
    this.lastActivityAt,
  })  : assert(storageUsedBytes >= 0),
        assert(storageAllowanceBytes == null || storageAllowanceBytes > 0);

  final int storageUsedBytes;

  /// Omitted when no truthful allowance exists. Not a plan limit — Point 7
  /// owns limits; this is the capacity figure the platform can actually state.
  final int? storageAllowanceBytes;

  final DateTime? lastActivityAt;

  /// `null` when there is no allowance to be a ratio of.
  double? get storageRatio => storageAllowanceBytes == null
      ? null
      : storageUsedBytes / storageAllowanceBytes!;

  factory SaasTenantUsage.fromJson(Map<String, dynamic> json) =>
      SaasTenantUsage(
        storageUsedBytes: json['storageUsedBytes'] as int,
        storageAllowanceBytes: json['storageAllowanceBytes'] as int?,
        lastActivityAt: _optionalDate(json['lastActivityAt']),
      );

  Map<String, dynamic> toJson() => {
        'storageUsedBytes': storageUsedBytes,
        if (storageAllowanceBytes != null)
          'storageAllowanceBytes': storageAllowanceBytes,
        if (lastActivityAt != null)
          'lastActivityAt': lastActivityAt!.toUtc().toIso8601String(),
      };
}

/// How large the tenant's organisation is.
///
/// **These are platform figures, supplied with the tenant record.** The
/// control plane must never obtain them by reading a tenant-operational
/// repository — that is the isolation rule of Points 4–5, and counting
/// detachments by listing them would break it while looking harmless.
@immutable
class SaasTenantCounts {
  const SaasTenantCounts({
    required this.detachmentGroups,
    required this.detachments,
    required this.members,
    required this.workshops,
  })  : assert(detachmentGroups >= 0),
        assert(detachments >= 0),
        assert(members >= 0),
        assert(workshops >= 0);

  final int detachmentGroups;
  final int detachments;
  final int members;
  final int workshops;

  factory SaasTenantCounts.fromJson(Map<String, dynamic> json) =>
      SaasTenantCounts(
        detachmentGroups: json['detachmentGroups'] as int,
        detachments: json['detachments'] as int,
        members: json['members'] as int,
        workshops: json['workshops'] as int,
      );

  Map<String, dynamic> toJson() => {
        'detachmentGroups': detachmentGroups,
        'detachments': detachments,
        'members': members,
        'workshops': workshops,
      };
}

// ---------------------------------------------------------------------------
// The record
// ---------------------------------------------------------------------------

/// One SaaS subscriber.
///
/// The same representation serves the list and the detail. Point 6's record is
/// small enough that a separate `…ListItem` would buy nothing but a second
/// shape to keep in step; `API_CONTRACT.md` records that the backend may split
/// them later, and the client would then narrow this class rather than grow a
/// parallel one.
@immutable
class SaasTenant {
  const SaasTenant({
    required this.id,
    required this.displayName,
    required this.teamCode,
    required this.lifecycle,
    required this.createdAt,
    required this.updatedAt,
    required this.mainAdmin,
    required this.subscription,
    required this.usage,
    required this.counts,
  });

  /// The wire `tenantId`. Opaque to the client.
  final String id;

  /// The customer's own name for their team.
  final String displayName;

  /// Platform-assigned, unique, and immutable from the tenant application.
  /// See `domain/team_code.dart`.
  final String teamCode;

  final SaasTenantLifecycle lifecycle;
  final DateTime createdAt;
  final DateTime updatedAt;
  final MainAdminContact mainAdmin;
  final SaasSubscription subscription;
  final SaasTenantUsage usage;
  final SaasTenantCounts counts;

  SaasTenantStatus get tenantStatus => lifecycle.status;
  int get tenantVersion => lifecycle.version;

  /// The fields a Super Admin actually searches by, pre-normalized.
  ///
  /// The Team Code is included because looking a customer up from a code they
  /// quoted in a support message is the operational reason the code is visible
  /// on this surface at all.
  List<String> get searchKeys => [
        searchKey(displayName),
        searchKey(mainAdmin.name),
        searchKey(mainAdmin.email),
        searchKey(teamCode),
      ];

  bool matches(String needle) {
    if (needle.isEmpty) return true;
    return searchKeys.any((key) => key.contains(needle));
  }

  SaasTenantListStatus get listStatus {
    switch (tenantStatus) {
      case SaasTenantStatus.suspended:
        return SaasTenantListStatus.suspended;
      case SaasTenantStatus.deletionPending:
        return SaasTenantListStatus.deletionPending;
      case SaasTenantStatus.deleted:
        return SaasTenantListStatus.deleted;
      case SaasTenantStatus.active:
        break;
    }
    return switch (subscription.status) {
      SubscriptionStatus.trial => SaasTenantListStatus.trial,
      SubscriptionStatus.active => SaasTenantListStatus.active,
      SubscriptionStatus.grace => SaasTenantListStatus.grace,
      SubscriptionStatus.inactive => SaasTenantListStatus.inactive,
    };
  }

  SaasTenant copyWith({
    SaasTenantLifecycle? lifecycle,
    DateTime? updatedAt,
    MainAdminContact? mainAdmin,
    SaasSubscription? subscription,
    SaasTenantUsage? usage,
    SaasTenantCounts? counts,
  }) =>
      SaasTenant(
        id: id,
        displayName: displayName,
        teamCode: teamCode,
        lifecycle: lifecycle ?? this.lifecycle,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        mainAdmin: mainAdmin ?? this.mainAdmin,
        subscription: subscription ?? this.subscription,
        usage: usage ?? this.usage,
        counts: counts ?? this.counts,
      );

  /// Parses one record, **refusing** rather than repairing.
  ///
  /// An unrecognised lifecycle status throws. A code that is not a Team Code
  /// throws for the same reason — a malformed
  /// identifier displayed as if it were valid is what a support call later
  /// fails on.
  factory SaasTenant.fromJson(Map<String, dynamic> json) {
    final code = json['teamCode'] as String;
    if (validateTeamCode(code) != null) {
      throw FormatException('malformed team code', code);
    }
    return SaasTenant(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      teamCode: normalizeTeamCode(code),
      lifecycle: SaasTenantLifecycle.fromJson(
        json['lifecycle'] as Map<String, dynamic>,
      ),
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
      mainAdmin:
          MainAdminContact.fromJson(json['mainAdmin'] as Map<String, dynamic>),
      subscription: SaasSubscription.fromJson(
        json['subscription'] as Map<String, dynamic>,
      ),
      usage: SaasTenantUsage.fromJson(json['usage'] as Map<String, dynamic>),
      counts: SaasTenantCounts.fromJson(json['counts'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'teamCode': teamCode,
        'lifecycle': lifecycle.toJson(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'mainAdmin': mainAdmin.toJson(),
        'subscription': subscription.toJson(),
        'usage': usage.toJson(),
        'counts': counts.toJson(),
      };
}

/// One row of a tenant's lifecycle history.
@immutable
class SaasTenantEvent {
  const SaasTenantEvent({
    required this.id,
    required this.type,
    required this.occurredAt,
    this.note,
  });

  final String id;
  final SaasTenantEventType type;
  final DateTime occurredAt;

  /// A short platform-authored line. Never a customer record, never a
  /// credential, never an operator's identity — that is the audit log's job.
  final String? note;

  factory SaasTenantEvent.fromJson(Map<String, dynamic> json) {
    final type = SaasTenantEventType.parse(json['type'] as String?);
    if (type == null) {
      throw FormatException('unknown tenant event type', json['type']);
    }
    return SaasTenantEvent(
      id: json['id'] as String,
      type: type,
      occurredAt: _date(json['occurredAt']),
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.wire,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        if (note != null) 'note': note,
      };
}

// ---------------------------------------------------------------------------
// Query and page
// ---------------------------------------------------------------------------

/// What the list screen is asking for.
///
/// **Repository parameters rather than client-side selectors**, and the choice
/// is about where this goes rather than where it is. A subscriber list is the
/// one collection in this product with no natural ceiling — every customer MTM
/// ever signs is a row — so the read that a backend will eventually have to
/// filter and page is written that way now. The mock applies all of it in
/// memory; nothing about the screen changes when a real endpoint takes over.
///
/// Value equality, because it is a Riverpod family key: two identical queries
/// must be the same provider, or every rebuild refetches.
@immutable
class SaasTenantQuery {
  const SaasTenantQuery({
    this.search = '',
    this.status,
    this.cursor,
    this.limit = 50,
  }) : assert(limit > 0);

  /// Free text over team name, Main Admin name, Main Admin email and Team
  /// Code. Normalized by the repository, never by the caller.
  final String search;

  /// `null` means every status — "not filtering" rather than "match nothing".
  final SaasTenantListStatus? status;

  /// **Opaque.** Whatever the previous page returned as `nextCursor`, handed
  /// back unread. The client must never construct one, parse one, or assume it
  /// encodes an offset, an id or a sort key — that is what keeps the contract
  /// free of a database.
  final String? cursor;

  final int limit;

  SaasTenantQuery copyWith({
    String? search,
    SaasTenantListStatus? status,
    bool clearStatus = false,
    String? cursor,
    bool clearCursor = false,
    int? limit,
  }) =>
      SaasTenantQuery(
        search: search ?? this.search,
        status: clearStatus ? null : status ?? this.status,
        cursor: clearCursor ? null : cursor ?? this.cursor,
        limit: limit ?? this.limit,
      );

  /// The same query from the first page. Changing a filter must never carry a
  /// cursor from the old one.
  SaasTenantQuery get firstPage => copyWith(clearCursor: true);

  bool get isFiltered => search.trim().isNotEmpty || status != null;

  @override
  bool operator ==(Object other) =>
      other is SaasTenantQuery &&
      other.search == search &&
      other.status == status &&
      other.cursor == cursor &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(search, status, cursor, limit);
}

/// One page of subscribers.
@immutable
class SaasTenantPage {
  SaasTenantPage({
    required List<SaasTenant> items,
    required this.total,
    this.nextCursor,
  })  : items = List.unmodifiable(items),
        assert(total >= 0);

  final List<SaasTenant> items;

  /// How many records match the query in full, before [items] was cut to a
  /// page. The list screen shows a result count, and a count of what is on
  /// screen would be a different and less useful number.
  final int total;

  /// Opaque; `null` on the last page. See [SaasTenantQuery.cursor].
  final String? nextCursor;

  bool get hasMore => nextCursor != null;

  factory SaasTenantPage.fromJson(Map<String, dynamic> json) => SaasTenantPage(
        items: (json['items'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(SaasTenant.fromJson)
            .toList(),
        total: json['total'] as int,
        nextCursor: json['nextCursor'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'items': [for (final item in items) item.toJson()],
        'total': total,
        if (nextCursor != null) 'nextCursor': nextCursor,
      };
}

/// What the create form supplies. Typed, so no `Map` reaches the repository.
@immutable
class SaasTenantDraft {
  const SaasTenantDraft({
    required this.displayName,
    required this.mainAdminName,
    required this.mainAdminEmail,
    required this.teamCode,
  });

  final String displayName;
  final String mainAdminName;
  final String mainAdminEmail;
  final String teamCode;

  /// The same draft with every field trimmed and the code canonicalised.
  /// Applied by the repository, so a caller cannot skip it.
  SaasTenantDraft get normalized => SaasTenantDraft(
        displayName: collapseWhitespace(displayName),
        mainAdminName: collapseWhitespace(mainAdminName),
        mainAdminEmail: collapseWhitespace(mainAdminEmail).toLowerCase(),
        teamCode: normalizeTeamCode(teamCode),
      );
}

// ---------------------------------------------------------------------------

DateTime _date(Object? raw) {
  if (raw is! String) throw const FormatException('timestamp must be a string');
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) throw FormatException('invalid timestamp', raw);
  return parsed.toUtc();
}

DateTime? _optionalDate(Object? raw) => raw == null ? null : _date(raw);
