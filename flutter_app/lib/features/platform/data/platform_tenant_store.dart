import '../../../core/text/search_key.dart';
import '../domain/platform_overview_models.dart';
import '../domain/saas_subscription_models.dart';
import '../domain/saas_tenant_models.dart';
import '../domain/tenant_lifecycle_models.dart';
import '../../tenant_feature/data/tenant_feature_fixtures.dart';
import '../../tenant_feature/domain/tenant_feature_models.dart';
import 'platform_tenant_fixtures.dart';

/// The **one** in-memory copy of the platform's subscriber records, shared by
/// every Point 5–9 platform repository that describes them.
///
/// Point 5's overview and Point 6's list are two views of the same customers.
/// While each mock owned its own fixtures they could disagree — and worse, a
/// tenant created on the list would never appear in the overview's count,
/// which is the cross-screen consistency §25 of the brief asks for. One store,
/// held by a provider and injected into both mocks, makes that impossible
/// rather than merely unlikely, and it does it without an event bus: Riverpod
/// invalidation is the only notification mechanism used.
///
/// **Process memory, and nothing more.** This is not a cache and not
/// persistence. It lives as long as the provider that made it, a relaunch
/// starts again from [canonicalSaasTenants], and no screen claims otherwise.
/// A real backend replaces this class entirely.
class PlatformTenantStore {
  PlatformTenantStore({required DateTime Function() clock}) : _clock = clock;

  final DateTime Function() _clock;

  /// Seeded on first read rather than in the constructor, so the fixtures are
  /// positioned against the clock at the moment the data is actually wanted —
  /// which is what lets a test pin `clockProvider` after the container is
  /// built and still get the dates it expects.
  List<SaasTenant>? _tenants;

  /// Ids created through [create], oldest first. Only used to number the next
  /// one; a real backend assigns ids and the client never constructs one.
  int _created = 0;
  final Map<String, List<SaasTenantEvent>> _events = {};
  final Map<String, TenantFeatureSet> _featureSets = {};
  final Map<String, DeletedTenantTombstone> _tombstones = {};
  final Map<String, List<SaasTenantEvent>> _deletedHistories = {};
  final Set<String> _retiredTeamCodes = {};

  List<SaasTenant> get tenants =>
      _tenants ??= canonicalSaasTenants(_clock().toUtc());

  SaasTenant? byId(String tenantId) {
    for (final tenant in tenants) {
      if (tenant.id == tenantId) return tenant;
    }
    return null;
  }

  DeletedTenantTombstone? tombstoneById(String tenantId) =>
      _tombstones[tenantId];

  List<DeletedTenantTombstone> get tombstones =>
      List.unmodifiable(_tombstones.values);

  SaasTenantStatus? lifecycleStatusOf(String tenantId) =>
      byId(tenantId)?.tenantStatus ??
      (_tombstones.containsKey(tenantId) ? SaasTenantStatus.deleted : null);

  /// Whether [normalizedCode] is already assigned.
  ///
  /// Comparison is on the canonical form, so `mtm 4k7p qx92` cannot slip past
  /// `MTM-4K7P-QX92`. **A mock check, and only that** — it proves the client
  /// handles a conflict, and asserts nothing about a backend that has to
  /// enforce this under concurrency (`API_CONTRACT.md`).
  bool isTeamCodeTaken(String normalizedCode) =>
      _retiredTeamCodes.contains(normalizedCode) ||
      tenants.any((tenant) => tenant.teamCode == normalizedCode);

  /// Whether onboarding may currently resolve [normalizedCode] to an active
  /// tenant. This mock does not implement onboarding; the method makes the
  /// final-deletion and non-active access semantics explicit and testable.
  bool teamCodeLinksToTenant(String normalizedCode) => tenants.any(
        (tenant) =>
            tenant.teamCode == normalizedCode &&
            tenant.tenantStatus == SaasTenantStatus.active,
      );

  /// The rows matching [query], the total before paging, and the page.
  ///
  /// Filter first, then page — the order a backend has to use for `total` to
  /// mean anything. The cursor is opaque to the caller and happens to be an
  /// index here; nothing outside this class may assume that.
  SaasTenantPage page(SaasTenantQuery query) {
    final needle = _needle(query.search);
    final matched = [
      for (final tenant in tenants)
        if (query.status == null || tenant.listStatus == query.status)
          if (tenant.matches(needle)) tenant,
    ];

    final start = int.tryParse(query.cursor ?? '0') ?? 0;
    final from = start.clamp(0, matched.length);
    final to = (from + query.limit).clamp(0, matched.length);
    return SaasTenantPage(
      items: matched.sublist(from, to),
      total: matched.length,
      nextCursor: to < matched.length ? '$to' : null,
    );
  }

  /// Registers [draft] and returns the stored record.
  ///
  /// The caller has already validated and checked the code; this is the state
  /// change only. Every new subscriber starts in [SubscriptionStatus.trial] with
  /// its Main Admin `pendingSetup` — the two facts Point 6 can state honestly,
  /// since activating a subscription is Point 7 and completing an account is
  /// the later authentication flow.
  SaasTenant create(SaasTenantDraft draft) {
    final now = _clock().toUtc();
    final tenant = SaasTenant(
      id: 'saas_new_${++_created}',
      displayName: draft.displayName,
      teamCode: draft.teamCode,
      lifecycle: SaasTenantLifecycle.active(),
      createdAt: now,
      updatedAt: now,
      mainAdmin: MainAdminContact(
        name: draft.mainAdminName,
        email: draft.mainAdminEmail,
        provisioning: MainAdminProvisioning.pendingSetup,
      ),
      subscription: SaasSubscription(
        status: SubscriptionStatus.trial,
        plan: const NoSaasPlan(),
        version: 1,
        trialEndsAt: now.add(const Duration(days: kDefaultTrialDays)),
      ),
      usage: const SaasTenantUsage(storageUsedBytes: 0),
      counts: const SaasTenantCounts(
        detachmentGroups: 0,
        detachments: 0,
        members: 0,
        workshops: 0,
      ),
    );

    _tenants = [...tenants, tenant]..sort(compareSaasTenants);
    _featureSets[tenant.id] = initialTenantFeatureSet(
      tenantId: tenant.id,
      tenantName: tenant.displayName,
      updatedAt: now,
    );
    return tenant;
  }

  /// The tenant-wide product modules for [tenantId], composed with the same
  /// canonical subscriber truth as identity and subscription data.
  TenantFeatureSet? featuresOf(String tenantId) {
    final tenant = byId(tenantId);
    if (tenant == null) return null;
    return _featureSets.putIfAbsent(
      tenantId,
      () => initialTenantFeatureSet(
        tenantId: tenantId,
        tenantName: tenant.displayName,
        updatedAt: tenant.updatedAt,
      ),
    );
  }

  /// Replaces only one feature state. No tenant-operational record is read,
  /// reset or deleted; re-enabling therefore reveals the same data again.
  TenantFeatureState updateFeature(
    String tenantId,
    TenantFeatureKey key,
    bool enabled,
  ) {
    final current = featuresOf(tenantId);
    if (current == null) throw StateError('tenant not found');
    final state = current.stateOf(key);
    if (state == null) throw StateError('feature not found');
    final updated = state.copyWith(
      enabled: enabled,
      version: state.version + 1,
      updatedAt: _clock().toUtc(),
    );
    _featureSets[tenantId] = current.replace(updated);
    return updated;
  }

  List<SaasTenantEvent> historyOf(SaasTenant tenant) {
    final events = [
      ...?_events[tenant.id],
      ...canonicalHistory(tenant),
    ];
    events.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return events;
  }

  List<SaasTenantEvent>? deletedHistoryOf(String tenantId) =>
      _deletedHistories[tenantId];

  /// Replaces only the commercial snapshot on the canonical tenant record and
  /// appends a compact lifecycle event. All platform reads then observe the
  /// same change without an event bus.
  SaasTenant updateSubscription(
    String tenantId,
    SaasSubscription subscription, {
    required SaasTenantEventType eventType,
    String? note,
  }) {
    final index = tenants.indexWhere((tenant) => tenant.id == tenantId);
    if (index < 0) throw StateError('tenant not found');
    final now = _clock().toUtc();
    final updated = tenants[index].copyWith(
      subscription: subscription,
      updatedAt: now,
    );
    final next = [...tenants]..[index] = updated;
    _tenants = next..sort(compareSaasTenants);
    final events = _events.putIfAbsent(tenantId, () => []);
    events.add(SaasTenantEvent(
      id: '${tenantId}_${eventType.wire}_${subscription.version}',
      type: eventType,
      occurredAt: now,
      note: note,
    ));
    return updated;
  }

  /// Replaces only the Main Admin contact summary on the canonical record —
  /// the Point 14 seat moving to a new account, or setup completing. Lifecycle,
  /// its version and history, subscription, features and counts are untouched:
  /// an account change is never a tenant lifecycle event.
  SaasTenant updateMainAdminContact(String tenantId, MainAdminContact contact) {
    final index = tenants.indexWhere((tenant) => tenant.id == tenantId);
    if (index < 0) throw StateError('tenant not found');
    final updated = tenants[index].copyWith(
      mainAdmin: contact,
      updatedAt: _clock().toUtc(),
    );
    _tenants = [...tenants]..[index] = updated;
    return updated;
  }

  /// Replaces only the operational lifecycle projection. Subscription, plan,
  /// overrides, feature rows, limits, usage and tenant-owned summaries are
  /// retained byte-for-byte through suspend/reactivate/request/cancel.
  SaasTenant updateLifecycle(
    String tenantId,
    SaasTenantLifecycle lifecycle, {
    required SaasTenantEventType eventType,
    String? note,
  }) {
    if (lifecycle.status == SaasTenantStatus.deleted) {
      throw ArgumentError('use finalizeTenant for deleted lifecycle');
    }
    final index = tenants.indexWhere((tenant) => tenant.id == tenantId);
    if (index < 0) throw StateError('tenant not found');
    final now = _clock().toUtc();
    final updated = tenants[index].copyWith(
      lifecycle: lifecycle,
      updatedAt: now,
    );
    final next = [...tenants]..[index] = updated;
    _tenants = next..sort(compareSaasTenants);
    _addEvent(
      tenantId,
      eventType,
      lifecycle.version,
      now,
      note: note,
    );
    return updated;
  }

  /// Models final backend deletion by removing the active resource and all
  /// mock control-plane configuration, while retaining one minimal tombstone.
  /// No Flutter storage or cryptographic erasure claim is made here.
  DeletedTenantTombstone finalizeTenant(
    String tenantId,
    SaasTenantLifecycle lifecycle,
  ) {
    if (lifecycle.status != SaasTenantStatus.deleted) {
      throw ArgumentError('final lifecycle must be deleted');
    }
    final index = tenants.indexWhere((tenant) => tenant.id == tenantId);
    if (index < 0) throw StateError('tenant not found');
    final tenant = tenants[index];
    final deletedAt = lifecycle.deletion!.deletedAt!;
    _addEvent(
      tenantId,
      SaasTenantEventType.tenantDeleted,
      lifecycle.version,
      deletedAt,
    );
    _deletedHistories[tenantId] = List.unmodifiable(historyOf(tenant));

    final tombstone = DeletedTenantTombstone(
      tenantId: tenant.id,
      displayNameSnapshot: tenant.displayName,
      deletedAt: deletedAt,
      lifecycleVersion: lifecycle.version,
      historyReference: 'tenant-lifecycle:${tenant.id}',
    );
    _tombstones[tenant.id] = tombstone;
    _retiredTeamCodes.add(tenant.teamCode);
    _featureSets.remove(tenant.id);
    _tenants = [...tenants]..removeAt(index);
    return tombstone;
  }

  void _addEvent(
    String tenantId,
    SaasTenantEventType eventType,
    int version,
    DateTime occurredAt, {
    String? note,
  }) {
    final events = _events.putIfAbsent(tenantId, () => []);
    events.add(SaasTenantEvent(
      id: '${tenantId}_${eventType.wire}_$version',
      type: eventType,
      occurredAt: occurredAt.toUtc(),
      note: note,
    ));
  }

  /// The aggregate Point 5 renders, **counted from these records** rather than
  /// stated separately.
  ///
  /// Commercial buckets come only from subscription state; suspension comes
  /// only from tenant access state. They are intentionally not one enum and
  /// the suspended number is not part of the commercial sum.
  PlatformTenantSummary tenantSummary() {
    var active = 0, trial = 0, grace = 0, suspended = 0, deletionPending = 0;
    for (final tenant in tenants) {
      switch (tenant.subscription.status) {
        case SubscriptionStatus.active:
          active++;
        case SubscriptionStatus.trial:
          trial++;
        case SubscriptionStatus.grace:
          grace++;
        case SubscriptionStatus.inactive:
          break;
      }
      if (tenant.tenantStatus == SaasTenantStatus.suspended) suspended++;
      if (tenant.tenantStatus == SaasTenantStatus.deletionPending) {
        deletionPending++;
      }
    }
    return PlatformTenantSummary(
      total: tenants.length,
      activeSubscriptions: active,
      activeTrials: trial,
      gracePeriod: grace,
      suspended: suspended,
      deletionPending: deletionPending,
    );
  }

  /// The typed query in the comparison form the records were indexed in.
  /// The app-wide [searchKey], so «احمد» finds «أحمد» here exactly as it does
  /// on a roster.
  static String _needle(String raw) => searchKey(raw);
}
