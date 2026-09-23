import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/app_date.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../core/problem/problem.dart';
import '../../../core/problem/problem_presentation.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../data/saas_tenant_providers.dart';
import '../data/platform_main_admin_providers.dart';
import '../domain/platform_main_admin_models.dart';
import '../domain/saas_tenant_models.dart';
import '../domain/tenant_lifecycle_models.dart';
import 'saas_subscription_copy.dart';
import 'platform_main_admin_copy.dart';
import 'saas_tenant_copy.dart';
import 'saas_tenant_routes.dart';
import 'tenant_lifecycle_management_section.dart';
import 'widgets/platform_meta.dart';
import 'widgets/platform_page.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';

/// `/platform/tenants/:tenantId` — one subscriber's control-plane record.
///
/// **One scrolling page with real sections, not tabs** (§20, option A). The
/// original plan sketched five tabs — Overview, Subscription, Usage and
/// Limits, Feature Flags, Security. Two of those have nothing in them until
/// Points 7–9, and a tab bar whose second half opens empty rooms is a worse
/// answer than a page that shows what exists. Everything Point 6 knows fits in
/// one comfortable scroll on a phone, so it is one scroll; when a later Point
/// brings enough content to justify a nested route, it lands under this
/// location without moving what is already here.
///
/// A finalized tenant resolves on the same route as a restricted tombstone,
/// never as a normal not-found and never as a partly populated tenant record.
class SaasTenantDetailPage extends ConsumerWidget {
  const SaasTenantDetailPage({super.key, required this.tenantId});

  final String tenantId;

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(saasTenantDetailProvider(tenantId))
      ..invalidate(saasTenantHistoryProvider(tenantId))
      ..invalidate(deletedTenantTombstoneProvider(tenantId))
      ..invalidate(mainAdminAccountProvider(tenantId));
    await ref.read(saasTenantDetailProvider(tenantId).future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(saasTenantDetailProvider(tenantId));
    final tombstone = ref.watch(deletedTenantTombstoneProvider(tenantId));

    return PlatformPage(
      title: tombstone == null ? S.platformTenantDetailTitle : 'سجل فريق محذوف',
      onRefresh: () => _refresh(ref),
      children: _content(context, ref, async, tombstone),
    );
  }

  List<Widget> _content(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Result<SaasTenant>> async,
    DeletedTenantTombstone? tombstone,
  ) {
    if (async.isLoading && !async.hasValue) {
      return const [_DetailSkeleton()];
    }
    if (async.hasError || !async.hasValue) {
      return [ErrorStateView(onRetry: () => _refresh(ref))];
    }

    return async.requireValue.when(
      success: (tenant, {stale = false}) =>
          _body(context, ref, tenant, stale: stale),
      failure: (message, code) {
        final parsed = ProblemCode.parse(code);
        // "This tenant does not exist" is a different answer from "the read
        // failed", and only one of them is worth retrying. A retry button on a
        // 404 is a button that will keep producing the same 404.
        if (parsed == ProblemCode.notFound) {
          if (tombstone != null) return [_TombstoneBody(tombstone: tombstone)];
          return [
            EmptyState(
              key: const Key('platform-tenant-not-found'),
              icon: Icons.search_off_rounded,
              title: S.platformTenantNotFoundTitle,
              body: S.platformTenantNotFoundBody,
              actionLabel: S.platformTenantBackToList,
              onAction: () => context.go(SaasTenantRoutes.list),
            ),
          ];
        }
        final view = resolveProblem(Problem.of(
          parsed,
          rawCode: code,
          detail: message,
        ));
        return [
          ErrorStateView(
            key: const Key('platform-tenant-failure'),
            title: view.title,
            body: view.message,
            onRetry: () => _refresh(ref),
          ),
        ];
      },
      offline: (cached) => cached == null
          ? [
              EmptyState(
                key: const Key('platform-tenant-offline-empty'),
                icon: Icons.cloud_off_rounded,
                title: S.offlineTitle,
                body: S.noCachedCopy,
                actionLabel: S.retry,
                onAction: () => _refresh(ref),
              ),
            ]
          : _body(context, ref, cached, offline: true),
    );
  }

  List<Widget> _body(
    BuildContext context,
    WidgetRef ref,
    SaasTenant tenant, {
    bool stale = false,
    bool offline = false,
  }) {
    return [
      if (offline || stale) ...[
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: offline
              ? const StatusChip(kind: StatusKind.warn, label: S.offlineTitle)
              : const StaleBadge(),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
      _IdentityCard(tenant: tenant),
      const SizedBox(height: AppSpacing.xxl),
      TenantLifecycleManagementSection(tenant: tenant),
      const SizedBox(height: AppSpacing.xxl),
      _AdminSection(tenant: tenant),
      const SizedBox(height: AppSpacing.xxl),
      _SubscriptionSection(tenant: tenant),
      const SizedBox(height: AppSpacing.xxl),
      _UsageSection(tenant: tenant),
      const SizedBox(height: AppSpacing.xxl),
      _CountsSection(tenant: tenant),
      const SizedBox(height: AppSpacing.xxl),
      _HistorySection(tenantId: tenant.id),
    ];
  }
}

class _TombstoneBody extends StatelessWidget {
  const _TombstoneBody({required this.tombstone});

  final DeletedTenantTombstone tombstone;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = Theme.of(context).textTheme;
    return Semantics(
      key: const Key('platform-tenant-tombstone'),
      container: true,
      label: 'سجل منصة مقيّد لفريق محذوف',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.critTint,
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Icon(Icons.folder_off_outlined, color: c.crit, size: 26),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(tombstone.displayNameSnapshot, style: t.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          const StatusChip(
            kind: StatusKind.crit,
            label: 'محذوف نهائياً',
          ),
          const SizedBox(height: AppSpacing.xl),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('سجل منصة مختصر', style: t.titleSmall),
                const SizedBox(height: AppSpacing.md),
                _Field(
                  label: 'معرّف الفريق',
                  value: TechnicalText(tombstone.tenantId),
                ),
                _Field(
                  label: 'تاريخ الحذف',
                  value: _plain(
                    context,
                    AppDate.dayMonthTime(tombstone.deletedAt.toLocal()),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: c.critTint,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_outline_rounded, color: c.crit, size: 20),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'هذا سجل تحكّم مقيّد وقد يظل معرّفاً للعميل. لا يحتوي على بيانات تشغيلية أو رمز فريق أو معلومات مدير أو اشتراك أو إعدادات.',
                          style: t.bodySmall?.copyWith(
                            color: c.ink2,
                            height: 1.55,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          OutlinedButton.icon(
            key: const Key('platform-tombstone-back-to-list'),
            onPressed: () => context.go(SaasTenantRoutes.list),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('العودة إلى قائمة الفرق'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------

/// A titled group: a small label, a bordered card, an optional footnote.
///
/// The same grouped-card idiom the settings hub and `PlatformNoteCard` use, so
/// the surfaces a Super Admin moves between agree about what a group looks
/// like.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.body,
    this.note,
    this.rows = const [],
    this.sectionKey,
  });

  final String title;

  /// The section's own facts, inside the card's padding.
  final Widget body;

  /// The footnote that annotates this section.
  ///
  /// **Inside the card, not under it.** The page carried four muted
  /// paragraphs floating between cards, which read as page copy rather than
  /// as an annotation on the group above them and made the whole screen more
  /// prose than control (UI audit P1-8).
  final String? note;

  /// Where this section leads. Full-bleed `NavigationRow`s under a hairline —
  /// *navigation*, drawn as navigation, so that suspending a customer up the
  /// page is no longer styled the same as opening a subscription screen.
  final List<Widget> rows;

  final Key? sectionKey;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      key: sectionKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.eyebrow(c)),
        const SizedBox(height: AppSpacing.sm),
        // A `Material`, so a `ListTile` inside paints its ink where it should.
        Material(
          color: c.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            side: BorderSide(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  note == null ? AppSpacing.lg : AppSpacing.sm,
                ),
                child: SizedBox(width: double.infinity, child: body),
              ),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: Text(
                    note!,
                    style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5),
                  ),
                ),
              for (final row in rows) ...[
                Divider(height: 1, color: c.line),
                row,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One label/value pair.
///
/// [value] is a widget rather than a string because half of these are
/// technical fields that have to lay out LTR inside the RTL page — see
/// [TechnicalText].
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.trailing});

  final String label;
  final Widget value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: c.ink3, fontSize: 12)),
          const SizedBox(height: 2),
          if (trailing == null)
            value
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: value),
                const SizedBox(width: AppSpacing.sm),
                trailing!,
              ],
            ),
        ],
      ),
    );
  }
}

Widget _plain(BuildContext context, String value) => Text(
      value,
      style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(color: context.c.ink),
    );

String _dateLabel(DateTime value) => AppDate.dayMonthYear(value.toLocal());

/// Who this tenant is, in one card.
///
/// The first viewport has to answer *who*, *what state*, and *what plan*
/// before it offers anything to do (§21). The name and the two status chips
/// are the first line; the operational identifiers follow as fields, and the
/// dates — which nobody scans a control plane for — collapse into one metadata
/// line instead of two more label/value pairs.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.tenant});

  final SaasTenant tenant;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final subscriptionLine = tenantSubscriptionLine(tenant);
    return _Section(
      sectionKey: const Key('platform-tenant-identity'),
      title: S.platformTenantIdentity,
      note: S.platformTenantTeamCodeNote,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Text(tenant.displayName, style: t.titleMedium),
              StatusChip(
                kind: tenantStatusKind(tenant.listStatus),
                label: tenantStatusLabel(tenant.listStatus),
              ),
            ],
          ),
          if (subscriptionLine != null) ...[
            const SizedBox(height: AppSpacing.xs),
            PlatformMeta(parts: [PlatformMetaText(subscriptionLine)]),
          ],
          const SizedBox(height: AppSpacing.lg),
          _Field(
            label: S.platformTenantTeamCode,
            value: TechnicalText(
              tenant.teamCode,
              tabular: true,
              style: t.titleSmall,
            ),
            trailing: IconButton(
              key: const Key('platform-tenant-copy-code'),
              tooltip: S.platformTenantCopyCode,
              icon: const Icon(Icons.copy_rounded, size: 20),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: tenant.teamCode));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text(S.platformTenantCopiedCode)),
                );
              },
            ),
          ),
          // Labelled, and never the hero identity (§24). Routing to a team by
          // id is real Super Admin work — a support ticket quotes it — so it
          // is shown where that work happens, as a field with a name on it.
          _Field(
            label: S.platformSecurityTenantId,
            value: TechnicalText(tenant.id),
          ),
          // Two quiet lines rather than one metadata line: a labelled Arabic
          // date is long enough that at 320 dp and a 1.6 text scale the pair
          // wrapped mid-phrase and left the separator stranded. These are the
          // least-scanned facts on the card, so they cost a line each and
          // nothing else.
          PlatformMetaText(
            '${S.platformTenantCreatedAt} ${_dateLabel(tenant.createdAt)}',
          ),
          PlatformMetaText(
            '${S.platformTenantUpdatedAt} ${_dateLabel(tenant.updatedAt)}',
          ),
        ],
      ),
    );
  }
}

class _AdminSection extends ConsumerWidget {
  const _AdminSection({required this.tenant});

  final SaasTenant tenant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admin = tenant.mainAdmin;
    final async = ref.watch(mainAdminAccountProvider(tenant.id));
    MainAdminAccountSnapshot? snapshot;
    final result = async.valueOrNull;
    if (result != null) {
      snapshot = result.when(
        success: (value, {stale = false}) => value,
        failure: (_, __) => null,
        offline: (cached) => cached,
      );
    }
    final account = snapshot?.current;
    final unavailable = async.hasError ||
        (async.hasValue && snapshot == null) ||
        snapshot?.hasUnsupportedState == true;
    final loading = async.isLoading && !async.hasValue;
    final status = account?.status;
    final summary = loading
        ? S.mainAdminSummaryLoading
        : unavailable
            ? S.mainAdminSummaryUnavailable
            : snapshot == null
                ? (admin.setupPending
                    ? S.mainAdminSummaryPending
                    : S.mainAdminSummaryActive)
                : MainAdminCopy.summary(snapshot);
    return _Section(
      sectionKey: const Key('platform-tenant-admin'),
      title: S.mainAdminSummaryTitle,
      note: summary,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The *current* seat holder — after a replacement this is no
          // longer the first admin the tenant was created with.
          _Field(
            label: S.mainAdminSeatTitle,
            value: _plain(context, account?.displayName ?? admin.name),
          ),
          _Field(
            label: S.mainAdminLoginEmail,
            // Selectable and LTR: this address gets pasted into a mail client
            // or a support ticket, and one retyped by eye gets retyped wrong.
            value: TechnicalText(account?.loginEmail ?? admin.email),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: status == null
                ? StatusChip(
                    kind: unavailable ? StatusKind.muted : StatusKind.warn,
                    icon: loading
                        ? Icons.hourglass_top_rounded
                        : Icons.help_outline_rounded,
                    label: loading
                        ? S.mainAdminSummaryLoading
                        : unavailable
                            ? S.mainAdminSummaryUnavailable
                            : tenantProvisioningLabel(admin.provisioning),
                  )
                : StatusChip(
                    kind: MainAdminCopy.statusKind(status),
                    icon: MainAdminCopy.statusIcon(status),
                    label: MainAdminCopy.status(status),
                  ),
          ),
        ],
      ),
      // Navigation, drawn as navigation. It used to be a full-width filled
      // button identical to «إدارة الاشتراك والخطة» below it and one weight
      // away from «إيقاف وصول الفريق» above it (UI audit P1-8).
      rows: [
        NavigationRow(
          key: const Key('open-tenant-main-admin'),
          icon: Icons.manage_accounts_outlined,
          label: S.mainAdminSummaryOpen,
          onTap: () => context.push(SaasTenantRoutes.mainAdmin(tenant.id)),
        ),
      ],
    );
  }
}

/// The commercial state, and the three screens that change it.
///
/// The chip and the one date that matters stay at the top — «ما هي الخطة» is
/// a first-viewport question (§21). The three destinations below used to be a
/// filled button and two outlined buttons in a `Wrap`; two of the three opened
/// a read-only screen.
class _SubscriptionSection extends StatelessWidget {
  const _SubscriptionSection({required this.tenant});

  final SaasTenant tenant;

  @override
  Widget build(BuildContext context) {
    final line = tenantSubscriptionLine(tenant);
    return _Section(
      sectionKey: const Key('platform-tenant-subscription'),
      title: S.platformTenantSubscription,
      note: 'حالة الاشتراك مستقلة عن حالة وصول الفريق.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: StatusChip(
              kind: subscriptionStatusKind(tenant.subscription.status),
              label: subscriptionStatusLabel(tenant.subscription.status),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _plain(context, line ?? S.platformTenantNoSubscriptionDate),
        ],
      ),
      rows: [
        NavigationRow(
          key: const Key('open-tenant-subscription'),
          icon: Icons.receipt_long_outlined,
          label: 'إدارة الاشتراك والخطة',
          onTap: () => context.push(SaasTenantRoutes.subscription(tenant.id)),
        ),
        NavigationRow(
          key: const Key('open-tenant-limits-from-detail'),
          icon: Icons.data_usage_rounded,
          label: 'الاستخدام والحدود',
          onTap: () => context.push(SaasTenantRoutes.limits(tenant.id)),
        ),
        NavigationRow(
          key: const Key('open-tenant-features-from-detail'),
          icon: Icons.extension_rounded,
          label: 'الميزات',
          onTap: () => context.push(SaasTenantRoutes.features(tenant.id)),
        ),
      ],
    );
  }
}

class _UsageSection extends StatelessWidget {
  const _UsageSection({required this.tenant});

  final SaasTenant tenant;

  @override
  Widget build(BuildContext context) {
    final usage = tenant.usage;
    final allowance = usage.storageAllowanceBytes;
    return _Section(
      sectionKey: const Key('platform-tenant-usage'),
      title: S.platformTenantUsage,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Field(
            label: S.platformTenantStorage,
            value: _plain(
              context,
              allowance == null
                  ? '${tenantBytesLabel(usage.storageUsedBytes)} — '
                      '${S.platformTenantNoAllowance}'
                  : '${tenantBytesLabel(usage.storageUsedBytes)}'
                      '${S.platformOverviewStorageOf}'
                      '${tenantBytesLabel(allowance)}',
            ),
          ),
          _Field(
            label: S.platformTenantLastActivity,
            value: _plain(
              context,
              usage.lastActivityAt == null
                  ? S.platformTenantNoActivity
                  : PlatformTime.dayTime(usage.lastActivityAt!),
            ),
          ),
        ],
      ),
    );
  }
}

/// How large the customer's organisation is.
///
/// **Supplied with the tenant record, never counted.** Reading the detachment
/// or member repositories to produce these four numbers would be the natural
/// implementation and it is exactly the one the platform boundary forbids
/// (§24): the control plane holds no tenant data and initialises no tenant
/// repository. The footnote says so on screen, because an operator reading
/// «٢٣ مفرزة» should know it is a platform aggregate and not a live query.
class _CountsSection extends StatelessWidget {
  const _CountsSection({required this.tenant});

  final SaasTenant tenant;

  @override
  Widget build(BuildContext context) {
    final counts = tenant.counts;
    final entries = <(String, int)>[
      (S.platformTenantGroups, counts.detachmentGroups),
      (S.platformTenantDetachments, counts.detachments),
      (S.platformTenantMembers, counts.members),
      (S.platformTenantWorkshops, counts.workshops),
    ];

    return _Section(
      sectionKey: const Key('platform-tenant-counts'),
      title: S.platformTenantOrganisation,
      note: S.platformTenantCountsNote,
      body: LayoutBuilder(builder: (context, constraints) {
        // Two columns as soon as there is room for them, one when there is
        // not — measured from the width this card was actually given, not
        // from the window. A 390 dp phone leaves this card 326 dp of inner
        // width and gets two; a 320 dp phone leaves it 256 and stacks.
        final columns = constraints.maxWidth >= 300 ? 2 : 1;
        final width =
            (constraints.maxWidth - AppSpacing.md * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final (label, value) in entries)
              SizedBox(
                width: width,
                child: _CountTile(label: label, value: value),
              ),
          ],
        );
      }),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          toArabicIndic(value.toString()),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(label, style: TextStyle(color: c.ink3, fontSize: 12)),
      ],
    );
  }
}

/// The subscription's lifecycle, newest first.
///
/// **Not the audit log.** It says the subscription moved and when; it names no
/// operator, no address and no request. Point 11 owns the immutable
/// actor-attributed record, and conflating the two would put an audit claim on
/// a screen that cannot support one.
class _HistorySection extends ConsumerWidget {
  const _HistorySection({required this.tenantId});

  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(saasTenantHistoryProvider(tenantId));
    return _Section(
      sectionKey: const Key('platform-tenant-history'),
      title: S.platformTenantHistory,
      note: S.platformTenantHistoryNote,
      body: _historyBody(context, ref, async),
    );
  }

  Widget _historyBody(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Result<List<SaasTenantEvent>>> async,
  ) {
    if (async.isLoading && !async.hasValue) {
      return const Column(
        children: [
          SkeletonRow(),
          SizedBox(height: AppSpacing.sm),
          SkeletonRow(),
        ],
      );
    }
    if (async.hasError || !async.hasValue) {
      return const _HistoryNote(text: S.platformTenantHistoryFailed);
    }

    return async.requireValue.when(
      success: (events, {stale = false}) => _list(context, events),
      // The history is one section of a page that is otherwise fine, so it
      // fails in place with a sentence rather than replacing the record with a
      // full-screen error.
      failure: (_, __) =>
          const _HistoryNote(text: S.platformTenantHistoryFailed),
      offline: (cached) => cached == null
          ? const _HistoryNote(text: S.offlineTitle)
          : _list(context, cached),
    );
  }

  Widget _list(BuildContext context, List<SaasTenantEvent> events) {
    if (events.isEmpty) {
      return const _HistoryNote(text: S.platformTenantHistoryEmpty);
    }
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < events.length; index++) ...[
          _HistoryRow(event: events[index]),
          if (index != events.length - 1) Divider(color: c.line, height: 20),
        ],
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.event});

  final SaasTenantEvent event;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = Theme.of(context).textTheme;
    return Row(
      key: Key('platform-tenant-event-${event.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: c.ink3, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tenantEventLabel(event.type), style: t.bodyMedium),
              Text(
                _dateLabel(event.occurredAt),
                style: t.bodySmall?.copyWith(color: c.ink3),
              ),
              if (event.note != null)
                Text(
                  event.note!,
                  style: t.bodySmall?.copyWith(color: c.ink3),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HistoryNote extends StatelessWidget {
  const _HistoryNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(color: context.c.ink3, fontSize: 13, height: 1.5),
      );
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      key: const Key('platform-tenant-loading'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Skeleton(width: 200, height: 24),
        const SizedBox(height: AppSpacing.lg),
        for (var i = 0; i < 3; i++) ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: const Column(
              children: [
                SkeletonRow(),
                SizedBox(height: AppSpacing.sm),
                SkeletonRow(),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ],
    );
  }
}
