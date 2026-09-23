/// **The canonical platform dataset.** Eight SaaS subscribers, and the one
/// place the frontend states what MTM's customer base looks like.
///
/// Point 5's overview reported `8 tenants — 4 active, 2 trials, 1 grace, 1
/// suspended` as four hard-coded integers. Point 6 needs the records those
/// integers were describing, and the moment both exist there are two truths
/// that can disagree — the overview saying eight while the list shows five is
/// the exact failure §12 of the brief names. So the numbers were deleted and
/// the records became the source: `PlatformTenantStore.tenantSummary()`
/// derives the buckets by counting this list, and a tenant created through the
/// platform surface changes both screens because there is only one thing to
/// change.
///
/// **Deterministic from the injected clock.** Every date is an offset from the
/// one instant passed in, so two reads at the same instant are byte-identical
/// and a test that pins the clock knows exactly what it will get. Nothing here
/// calls `DateTime.now()`.
///
/// **No customer data of any kind.** These are invented teams, invented
/// coordinators and invented mailboxes. There is no patient, no medical
/// record, no real address, no credential and no secret in this file, and
/// nothing in it may ever be treated as one.
library;

import '../domain/saas_tenant_models.dart';
import '../domain/saas_subscription_models.dart';
import '../domain/tenant_lifecycle_models.dart';

/// How long a newly registered subscriber's trial runs.
///
/// A platform default, not a plan setting: Point 7 owns plans, and until it
/// lands the honest statement is that the platform grants the same window to
/// everyone. `API_CONTRACT.md` records that the backend owns this number.
const int kDefaultTrialDays = 14;

/// How long a lapsed subscription keeps working before suspension.
const int kDefaultGraceDays = 14;

const int _gib = 1024 * 1024 * 1024;
const int _mib = 1024 * 1024;

/// One fixture's shape, before it is positioned against a clock.
class _Fixture {
  const _Fixture({
    required this.id,
    required this.displayName,
    required this.teamCode,
    required this.tenantStatus,
    required this.subscriptionStatus,
    required this.createdDaysAgo,
    required this.adminName,
    required this.adminEmail,
    required this.provisioning,
    required this.counts,
    required this.storageUsedBytes,
    this.storageAllowanceBytes,
    this.lastActivityHoursAgo,
    this.statusChangedDaysAgo,
    this.planId,
    this.limitOverrides = const {},
  });

  final String id;
  final String displayName;
  final String teamCode;
  final SaasTenantStatus tenantStatus;
  final SubscriptionStatus subscriptionStatus;
  final int createdDaysAgo;
  final String adminName;
  final String adminEmail;
  final MainAdminProvisioning provisioning;
  final SaasTenantCounts counts;
  final int storageUsedBytes;
  final int? storageAllowanceBytes;
  final int? lastActivityHoursAgo;

  /// When the record entered [status], for the tenants whose status is not
  /// the one they were created in.
  final int? statusChangedDaysAgo;
  final String? planId;
  final Map<PlanLimitKey, int> limitOverrides;
}

/// The eight, in no particular order — [canonicalSaasTenants] sorts them.
const List<_Fixture> _fixtures = [
  _Fixture(
    id: 'saas_hilal',
    displayName: 'فرق الهلال الطبية',
    teamCode: 'MTM-4K7P-QX92',
    tenantStatus: SaasTenantStatus.active,
    subscriptionStatus: SubscriptionStatus.active,
    planId: 'mtm_advanced',
    createdDaysAgo: 612,
    adminName: 'سلمى الحارثي',
    adminEmail: 'salma@hilal-medical.org',
    provisioning: MainAdminProvisioning.active,
    counts: SaasTenantCounts(
      detachmentGroups: 6,
      detachments: 23,
      members: 418,
      workshops: 37,
    ),
    storageUsedBytes: 7 * _gib,
    storageAllowanceBytes: 20 * _gib,
    lastActivityHoursAgo: 2,
  ),
  _Fixture(
    id: 'saas_najd',
    displayName: 'فريق نجد للاستجابة',
    teamCode: 'MTM-9WCT-3H5R',
    tenantStatus: SaasTenantStatus.active,
    subscriptionStatus: SubscriptionStatus.active,
    planId: 'mtm_standard',
    createdDaysAgo: 388,
    adminName: 'بدر العنزي',
    adminEmail: 'badr@najd-response.sa',
    provisioning: MainAdminProvisioning.active,
    counts: SaasTenantCounts(
      detachmentGroups: 3,
      detachments: 11,
      members: 176,
      workshops: 14,
    ),
    storageUsedBytes: 2 * _gib + 640 * _mib,
    storageAllowanceBytes: 10 * _gib,
    lastActivityHoursAgo: 9,
  ),
  _Fixture(
    id: 'saas_sahel',
    displayName: 'جمعية الساحل الصحية',
    teamCode: 'MTM-2FGD-8NVJ',
    tenantStatus: SaasTenantStatus.active,
    subscriptionStatus: SubscriptionStatus.active,
    planId: 'mtm_standard',
    limitOverrides: {PlanLimitKey.detachments: 10},
    createdDaysAgo: 205,
    adminName: 'ريم القحطاني',
    adminEmail: 'reem.q@sahel-health.org',
    provisioning: MainAdminProvisioning.active,
    counts: SaasTenantCounts(
      detachmentGroups: 2,
      detachments: 7,
      members: 94,
      workshops: 6,
    ),
    storageUsedBytes: 880 * _mib,
    storageAllowanceBytes: 10 * _gib,
    lastActivityHoursAgo: 30,
  ),
  _Fixture(
    id: 'saas_wadi',
    displayName: 'فرق الوادي التطوعية',
    teamCode: 'MTM-7RMB-KZ64',
    tenantStatus: SaasTenantStatus.active,
    subscriptionStatus: SubscriptionStatus.active,
    planId: 'mtm_core',
    createdDaysAgo: 96,
    adminName: 'ماجد الدوسري',
    adminEmail: 'majed@wadi-volunteers.org',
    provisioning: MainAdminProvisioning.active,
    counts: SaasTenantCounts(
      detachmentGroups: 1,
      detachments: 4,
      members: 52,
      workshops: 3,
    ),
    storageUsedBytes: 310 * _mib,
    storageAllowanceBytes: 5 * _gib,
    lastActivityHoursAgo: 5,
  ),
  _Fixture(
    id: 'saas_nabd',
    displayName: 'فريق نبض التطوعي',
    teamCode: 'MTM-5JQX-2TWD',
    tenantStatus: SaasTenantStatus.active,
    subscriptionStatus: SubscriptionStatus.trial,
    createdDaysAgo: 4,
    adminName: 'هدى الشمري',
    adminEmail: 'huda@nabd-team.org',
    // Created four days ago and still has not finished first-time setup —
    // the state the detail screen exists to make visible.
    provisioning: MainAdminProvisioning.pendingSetup,
    counts: SaasTenantCounts(
      detachmentGroups: 0,
      detachments: 1,
      members: 8,
      workshops: 0,
    ),
    storageUsedBytes: 12 * _mib,
    lastActivityHoursAgo: 26,
  ),
  _Fixture(
    id: 'saas_masar',
    displayName: 'مسار الإسعاف الأهلي',
    teamCode: 'MTM-6PTH-9BSK',
    tenantStatus: SaasTenantStatus.active,
    subscriptionStatus: SubscriptionStatus.trial,
    planId: 'mtm_core',
    createdDaysAgo: 11,
    adminName: 'ياسر المطيري',
    adminEmail: 'yasser@masar-aid.org',
    provisioning: MainAdminProvisioning.active,
    counts: SaasTenantCounts(
      detachmentGroups: 1,
      detachments: 3,
      members: 31,
      workshops: 1,
    ),
    storageUsedBytes: 140 * _mib,
    lastActivityHoursAgo: 1,
  ),
  _Fixture(
    id: 'saas_afiah',
    displayName: 'جمعية عافية',
    teamCode: 'MTM-3XDN-7VGM',
    tenantStatus: SaasTenantStatus.active,
    subscriptionStatus: SubscriptionStatus.grace,
    planId: 'mtm_standard',
    limitOverrides: {PlanLimitKey.detachments: 20},
    createdDaysAgo: 466,
    adminName: 'نورة الزهراني',
    adminEmail: 'noura@afiah.org',
    provisioning: MainAdminProvisioning.active,
    counts: SaasTenantCounts(
      detachmentGroups: 4,
      detachments: 15,
      members: 233,
      workshops: 19,
    ),
    storageUsedBytes: 4 * _gib + 200 * _mib,
    storageAllowanceBytes: 20 * _gib,
    lastActivityHoursAgo: 14,
    statusChangedDaysAgo: 3,
  ),
  _Fixture(
    id: 'saas_rukn',
    displayName: 'فريق الركن الطبي',
    teamCode: 'MTM-8SVZ-4CQR',
    tenantStatus: SaasTenantStatus.suspended,
    subscriptionStatus: SubscriptionStatus.inactive,
    planId: 'mtm_standard',
    createdDaysAgo: 731,
    adminName: 'فهد العتيبي',
    adminEmail: 'fahd@rukn-medical.org',
    provisioning: MainAdminProvisioning.active,
    counts: SaasTenantCounts(
      detachmentGroups: 2,
      detachments: 9,
      members: 118,
      workshops: 11,
    ),
    storageUsedBytes: 3 * _gib + 90 * _mib,
    storageAllowanceBytes: 10 * _gib,
    lastActivityHoursAgo: 62 * 24,
    statusChangedDaysAgo: 41,
  ),
];

/// The eight subscribers, positioned against [now] and sorted newest first.
///
/// Newest first is the list's stable order and the one an operator wants: a
/// tenant registered this morning is the one being asked about this morning.
/// Ties are broken by id so the order is total.
List<SaasTenant> canonicalSaasTenants(DateTime now) {
  final instant = now.toUtc();
  final tenants = [
    for (final fixture in _fixtures) _build(fixture, instant),
  ];
  tenants.sort(compareSaasTenants);
  return tenants;
}

/// The list's total order: newest first, then by id.
int compareSaasTenants(SaasTenant a, SaasTenant b) {
  final byDate = b.createdAt.compareTo(a.createdAt);
  return byDate != 0 ? byDate : a.id.compareTo(b.id);
}

SaasTenant _build(_Fixture f, DateTime now) {
  final createdAt = now.subtract(Duration(days: f.createdDaysAgo));
  final changedAt = f.statusChangedDaysAgo == null
      ? createdAt
      : now.subtract(Duration(days: f.statusChangedDaysAgo!));

  return SaasTenant(
    id: f.id,
    displayName: f.displayName,
    teamCode: f.teamCode,
    lifecycle: switch (f.tenantStatus) {
      SaasTenantStatus.active => SaasTenantLifecycle.active(),
      SaasTenantStatus.suspended => SaasTenantLifecycle(
          status: SaasTenantStatus.suspended,
          version: 1,
          suspension: TenantSuspensionMetadata(
            suspendedAt: changedAt,
            reason: 'مراجعة إدارية موثقة',
          ),
        ),
      SaasTenantStatus.deletionPending ||
      SaasTenantStatus.deleted =>
        throw StateError('canonical fixture cannot start deleted'),
    },
    createdAt: createdAt,
    updatedAt: changedAt,
    mainAdmin: MainAdminContact(
      name: f.adminName,
      email: f.adminEmail,
      provisioning: f.provisioning,
    ),
    subscription: switch (f.subscriptionStatus) {
      SubscriptionStatus.trial => SaasSubscription(
          status: SubscriptionStatus.trial,
          plan: f.planId == null
              ? const NoSaasPlan()
              : AssignedSaasPlan(f.planId!),
          version: 1,
          trialEndsAt: createdAt.add(const Duration(days: kDefaultTrialDays)),
          limitOverrides: f.limitOverrides,
        ),
      // Renewal is the next anniversary of registration after `now`, so the
      // date is derived from the record rather than invented per fixture.
      SubscriptionStatus.active => SaasSubscription(
          status: SubscriptionStatus.active,
          plan: AssignedSaasPlan(f.planId!),
          version: 1,
          renewsAt: _nextRenewal(createdAt, now),
          limitOverrides: f.limitOverrides,
        ),
      SubscriptionStatus.grace => SaasSubscription(
          status: SubscriptionStatus.grace,
          plan: AssignedSaasPlan(f.planId!),
          version: 1,
          renewsAt: _nextRenewal(createdAt, now),
          graceEndsAt: changedAt.add(const Duration(days: kDefaultGraceDays)),
          limitOverrides: f.limitOverrides,
        ),
      SubscriptionStatus.inactive => SaasSubscription(
          status: SubscriptionStatus.inactive,
          plan: f.planId == null
              ? const NoSaasPlan()
              : AssignedSaasPlan(f.planId!),
          version: 1,
          limitOverrides: f.limitOverrides,
        ),
    },
    usage: SaasTenantUsage(
      storageUsedBytes: f.storageUsedBytes,
      storageAllowanceBytes: f.storageAllowanceBytes,
      lastActivityAt: f.lastActivityHoursAgo == null
          ? null
          : now.subtract(Duration(hours: f.lastActivityHoursAgo!)),
    ),
    counts: f.counts,
  );
}

/// The first yearly anniversary of [createdAt] strictly after [now].
DateTime _nextRenewal(DateTime createdAt, DateTime now) {
  var next = createdAt;
  while (!next.isAfter(now)) {
    next = DateTime.utc(
      next.year + 1,
      next.month,
      next.day,
      next.hour,
      next.minute,
    );
  }
  return next;
}

/// One subscriber's lifecycle history, newest first.
///
/// Derived from the record rather than stored beside it, so a fixture and its
/// history cannot describe two different tenants. Only events that actually
/// happened to *this* tenant appear: a trial tenant has no activation row, and
/// a suspended fixture may independently carry an inactive commercial event.
/// Subscription history never causes or implies operational suspension.
///
/// This is lifecycle history, not the platform audit log — no actor, no
/// address, no request id. Point 11 owns that, and it is a different resource.
List<SaasTenantEvent> canonicalHistory(SaasTenant tenant) {
  final events = <SaasTenantEvent>[
    SaasTenantEvent(
      id: '${tenant.id}_created',
      type: SaasTenantEventType.tenantCreated,
      occurredAt: tenant.createdAt,
    ),
    SaasTenantEvent(
      id: '${tenant.id}_trial_started',
      type: SaasTenantEventType.trialStarted,
      occurredAt: tenant.createdAt,
    ),
  ];

  // Everything that is no longer a trial started as one and left it.
  if (tenant.subscription.status != SubscriptionStatus.trial) {
    final activatedAt =
        tenant.createdAt.add(const Duration(days: kDefaultTrialDays));
    events
      ..add(SaasTenantEvent(
        id: '${tenant.id}_trial_ended',
        type: SaasTenantEventType.trialEnded,
        occurredAt: activatedAt,
      ))
      ..add(SaasTenantEvent(
        id: '${tenant.id}_activated',
        type: SaasTenantEventType.subscriptionActivated,
        occurredAt: activatedAt,
      ));
  }

  if (tenant.subscription.status == SubscriptionStatus.grace) {
    events.add(SaasTenantEvent(
      id: '${tenant.id}_grace',
      type: SaasTenantEventType.movedToGrace,
      occurredAt: tenant.updatedAt,
    ));
  }

  if (tenant.tenantStatus == SaasTenantStatus.suspended) {
    events
      ..add(SaasTenantEvent(
        id: '${tenant.id}_grace',
        type: SaasTenantEventType.movedToGrace,
        occurredAt:
            tenant.updatedAt.subtract(const Duration(days: kDefaultGraceDays)),
      ))
      ..add(SaasTenantEvent(
        id: '${tenant.id}_suspended',
        type: SaasTenantEventType.tenantSuspended,
        occurredAt: tenant.updatedAt,
      ));
  }

  events.sort((a, b) {
    final byDate = b.occurredAt.compareTo(a.occurredAt);
    return byDate != 0 ? byDate : a.id.compareTo(b.id);
  });
  return events;
}
