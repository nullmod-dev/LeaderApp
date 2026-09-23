import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/app_date.dart';
import '../../../core/problem/problem.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../data/saas_subscription_providers.dart';
import '../domain/saas_subscription_models.dart';
import 'saas_subscription_copy.dart';
import 'saas_tenant_routes.dart';
import 'widgets/platform_confirmation_dialog.dart';
import 'widgets/platform_page.dart';

class SaasTenantSubscriptionPage extends ConsumerStatefulWidget {
  const SaasTenantSubscriptionPage({super.key, required this.tenantId});
  final String tenantId;

  @override
  ConsumerState<SaasTenantSubscriptionPage> createState() =>
      _SaasTenantSubscriptionPageState();
}

class _SaasTenantSubscriptionPageState
    extends ConsumerState<SaasTenantSubscriptionPage> {
  Future<void> _refresh() async {
    ref
      ..invalidate(tenantSubscriptionProvider(widget.tenantId))
      ..invalidate(saasPlansProvider);
    await ref.read(tenantSubscriptionProvider(widget.tenantId).future);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(tenantSubscriptionProvider(widget.tenantId));
    final plans = ref.watch(saasPlansProvider);
    final action = ref.watch(subscriptionActionControllerProvider);
    return PlatformPage(
      title: 'الاشتراك والخطة',
      onRefresh: _refresh,
      children: [
        _buildState(async, plans, action),
      ],
    );
  }

  Widget _buildState(
    AsyncValue<Result<TenantSubscriptionDetails>> async,
    AsyncValue<Result<List<SaasPlan>>> plansAsync,
    SubscriptionActionState action,
  ) {
    if (async.isLoading && !async.hasValue) {
      return const _SubscriptionSkeleton();
    }
    if (async.hasError || !async.hasValue) {
      return ErrorStateView(onRetry: _refresh);
    }
    return async.requireValue.when(
      success: (details, {stale = false}) => _loaded(
        details,
        _plansFrom(plansAsync),
        action,
        stale: stale,
      ),
      failure: (message, code) {
        if (ProblemCode.parse(code) == ProblemCode.notFound) {
          return EmptyState(
            key: const Key('subscription-tenant-not-found'),
            icon: Icons.search_off_rounded,
            title: 'الفريق غير موجود',
            body: 'تعذّر العثور على فريق SaaS بهذا المعرّف.',
            actionLabel: 'العودة إلى الفرق',
            onAction: () => context.go(SaasTenantRoutes.list),
          );
        }
        if (code == 'subscription_not_found') {
          return EmptyState(
            key: const Key('subscription-unavailable'),
            icon: Icons.receipt_long_outlined,
            title: 'الاشتراك غير متاح',
            body: 'لا يمكن قراءة حالة الاشتراك لهذا الفريق الآن.',
            actionLabel: 'إعادة المحاولة',
            onAction: _refresh,
          );
        }
        return ErrorStateView(
          key: const Key('subscription-failure'),
          title: 'تعذّر تحميل الاشتراك',
          body: 'لم نتمكن من تحميل بيانات الاشتراك بأمان.',
          onRetry: _refresh,
        );
      },
      offline: (cached) => cached == null
          ? EmptyState(
              key: const Key('subscription-offline'),
              icon: Icons.cloud_off_rounded,
              title: 'لا يوجد اتصال',
              body:
                  'عمليات المنصة لا تُحفظ للإرسال لاحقًا. أعد المحاولة عند عودة الاتصال.',
              actionLabel: 'إعادة المحاولة',
              onAction: _refresh,
            )
          : _loaded(cached, _plansFrom(plansAsync), action, offline: true),
    );
  }

  List<SaasPlan> _plansFrom(AsyncValue<Result<List<SaasPlan>>> async) {
    if (!async.hasValue) return const [];
    return async.requireValue.when(
      success: (items, {stale = false}) => items,
      failure: (_, __) => const [],
      offline: (cached) => cached ?? const [],
    );
  }

  Widget _loaded(
    TenantSubscriptionDetails details,
    List<SaasPlan> plans,
    SubscriptionActionState action, {
    bool stale = false,
    bool offline = false,
  }) {
    final subscription = details.subscription;
    return Column(
      key: const Key('subscription-loaded'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (offline)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.lg),
            child: _Notice(
              text:
                  'نسخة محفوظة للعرض فقط؛ لا يمكن تنفيذ عمليات المنصة دون اتصال.',
            ),
          )
        else if (stale)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.lg),
            child: StaleBadge(),
          ),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(details.tenantName,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              StatusChip(
                kind: subscriptionStatusKind(subscription.status),
                label: subscriptionStatusLabel(subscription.status),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        Text('الاشتراك الحالي', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ValueRow(
                label: 'الخطة',
                value: details.currentPlan?.name ?? 'لا توجد خطة معيّنة',
              ),
              _ValueRow(
                label: 'الحالة التجارية',
                value: subscriptionStatusLabel(subscription.status),
              ),
              if (subscription.relevantDate != null)
                _ValueRow(
                  label: _dateLabel(subscription.status),
                  value: AppDate.dayMonthYear(
                    subscription.relevantDate!.toLocal(),
                  ),
                ),
              if (subscription.status == SubscriptionStatus.grace)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    'فترة السماح مهلة تجارية مؤقتة. لا تعني حذف البيانات أو تعليق الفريق تلقائيًا.',
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        Text('الإجراءات المتاحة',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        _ActionWrap(
          children: _actions(details, plans, action, offline: offline),
        ),
        const SizedBox(height: AppSpacing.xxl),
        Text('ملخص الخطة', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        _PlanSummary(plan: details.currentPlan, subscription: subscription),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          key: const Key('open-tenant-limits'),
          onPressed: () =>
              context.push(SaasTenantRoutes.limits(details.tenantId)),
          icon: const Icon(Icons.data_usage_rounded),
          label: const Text('الاستخدام والحدود'),
        ),
      ],
    );
  }

  List<Widget> _actions(
    TenantSubscriptionDetails details,
    List<SaasPlan> plans,
    SubscriptionActionState state, {
    required bool offline,
  }) {
    final status = details.subscription.status;
    final busy = state.isSubmitting;
    Widget button(
      Key key,
      String label,
      IconData icon,
      VoidCallback onPressed, {
      bool primary = false,
    }) {
      final child = primary
          ? FilledButton.icon(
              key: key,
              onPressed: busy || offline ? null : onPressed,
              icon: Icon(icon),
              label: Text(label),
            )
          : OutlinedButton.icon(
              key: key,
              onPressed: busy || offline ? null : onPressed,
              icon: Icon(icon),
              label: Text(label),
            );
      return child;
    }

    return [
      if (status != SubscriptionStatus.active)
        button(
          const Key('activate-subscription'),
          'تفعيل الاشتراك',
          Icons.check_circle_outline_rounded,
          () => _activate(details, plans),
          primary: true,
        ),
      if (status == SubscriptionStatus.trial)
        button(
          const Key('extend-trial'),
          'تمديد التجربة',
          Icons.more_time_rounded,
          () => _extendTrial(details),
        ),
      if (status == SubscriptionStatus.trial)
        button(
          const Key('end-trial'),
          'إنهاء التجربة',
          Icons.hourglass_bottom_rounded,
          () => _endTrial(details),
        ),
      if (status == SubscriptionStatus.active)
        button(
          const Key('move-to-grace'),
          'النقل إلى فترة السماح',
          Icons.schedule_rounded,
          () => _moveToGrace(details),
        ),
      if (plans.isNotEmpty)
        button(
          const Key('change-plan'),
          details.currentPlan == null ? 'اختيار خطة' : 'تغيير الخطة',
          Icons.layers_outlined,
          () => _changePlan(details, plans),
        ),
      if (busy)
        const Padding(
          padding: EdgeInsets.all(AppSpacing.sm),
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
    ];
  }

  Future<void> _activate(
    TenantSubscriptionDetails details,
    List<SaasPlan> plans,
  ) async {
    var plan = details.currentPlan;
    plan ??= await _choosePlan(plans);
    if (plan == null || !mounted) return;
    final ok = await showPlatformConfirmation(
      context: context,
      title: 'تفعيل الاشتراك',
      change:
          'سيُعلّم الاشتراك كفعّال على منصة ${S.productNameAr} بالخطة ${plan.name}.',
      unchanged: 'لن تُنفّذ دفعة ولن تتغير بيانات الفريق أو حالة وصوله.',
      effective: 'يسري التغيير فور تأكيده.',
      confirmLabel: 'تفعيل الاشتراك',
    );
    if (!ok || !mounted) return;
    await _showOutcome(
        ref.read(subscriptionActionControllerProvider.notifier).activate(
              ActivateSubscriptionCommand(
                tenantId: details.tenantId,
                expectedVersion: details.subscription.version,
                planId: plan.id,
              ),
            ));
  }

  Future<void> _extendTrial(TenantSubscriptionDetails details) async {
    final current = details.subscription.trialEndsAt;
    if (current == null) return;
    final days = await showAppSheet<int>(
      context: context,
      title: 'تمديد الفترة التجريبية',
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The figure and its plural travel together, the way the
              // report ranges already do: «٧ أيام» is not «٧ يوماً», and a
              // Latin «7» directly above «٢٥ أيلول ٢٠٢٦» is two numeral
              // systems in one row.
              for (final (days, label) in const [
                (7, '٧ أيام'),
                (14, '١٤ يوماً'),
                (30, '٣٠ يوماً'),
              ])
                Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    key: Key('extend-trial-$days'),
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: Text('إضافة $label'),
                    subtitle: Text(AppDate.dayMonthYear(
                      current.add(Duration(days: days)).toLocal(),
                    )),
                    onTap: () =>
                        Navigator.of(context, rootNavigator: true).pop(days),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (days == null || !mounted) return;
    await _showOutcome(
        ref.read(subscriptionActionControllerProvider.notifier).extendTrial(
              ExtendTrialCommand(
                tenantId: details.tenantId,
                expectedVersion: details.subscription.version,
                newEndsAt: current.add(Duration(days: days)).toUtc(),
              ),
            ));
  }

  Future<void> _endTrial(TenantSubscriptionDetails details) async {
    final ok = await showPlatformConfirmation(
      context: context,
      title: 'إنهاء الفترة التجريبية',
      change: 'ستنتهي التجربة الآن ويبدأ للفريق نطاق سماح لمدة 14 يومًا.',
      unchanged: 'لن يُحذف أي سجل ولن يُعلّق وصول الفريق تلقائيًا.',
      confirmLabel: 'إنهاء التجربة',
      warning: true,
    );
    if (!ok || !mounted) return;
    await _showOutcome(
        ref.read(subscriptionActionControllerProvider.notifier).endTrial(
              SubscriptionVersionedCommand(
                tenantId: details.tenantId,
                expectedVersion: details.subscription.version,
              ),
            ));
  }

  Future<void> _moveToGrace(TenantSubscriptionDetails details) async {
    final ok = await showPlatformConfirmation(
      context: context,
      title: 'النقل إلى فترة السماح',
      change: 'سيصبح الاشتراك في فترة سماح لمدة 14 يومًا.',
      unchanged: 'لن يُعلّق الفريق ولن تُحذف بياناته.',
      confirmLabel: 'بدء فترة السماح',
      warning: true,
    );
    if (!ok || !mounted) return;
    await _showOutcome(
        ref.read(subscriptionActionControllerProvider.notifier).moveToGrace(
              SubscriptionVersionedCommand(
                tenantId: details.tenantId,
                expectedVersion: details.subscription.version,
              ),
            ));
  }

  Future<void> _changePlan(
    TenantSubscriptionDetails details,
    List<SaasPlan> plans,
  ) async {
    final plan = await _choosePlan(plans, currentId: details.currentPlan?.id);
    if (plan == null || !mounted) return;
    final ok = await showPlatformConfirmation(
      context: context,
      title: 'تغيير الخطة',
      change:
          'سيتم تغيير خطة الفريق إلى ${plan.name} وقد تتغير الحدود الفعّالة.',
      unchanged:
          'لن تُحذف البيانات الحالية. تُراجع الحدود المخصصة بصورة مستقلة.',
      confirmLabel: 'تغيير الخطة',
      warning: true,
    );
    if (!ok || !mounted) return;
    await _showOutcome(
        ref.read(subscriptionActionControllerProvider.notifier).changePlan(
              ChangePlanCommand(
                tenantId: details.tenantId,
                expectedVersion: details.subscription.version,
                planId: plan.id,
              ),
            ));
  }

  Future<SaasPlan?> _choosePlan(List<SaasPlan> plans, {String? currentId}) {
    return showAppSheet<SaasPlan>(
      context: context,
      title: 'اختيار خطة',
      expanded: true,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: plans.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (sheetContext, index) {
          final plan = plans[index];
          final selected = plan.id == currentId;
          return _PlanOption(
            plan: plan,
            selected: selected,
            onTap: selected || !plan.selectable
                ? null
                : () => Navigator.pop(sheetContext, plan),
          );
        },
      ),
    );
  }

  Future<void> _showOutcome(Future<SubscriptionActionOutcome> pending) async {
    final outcome = await pending;
    if (!mounted || outcome is SubscriptionActionIgnored) return;
    final text = switch (outcome) {
      SubscriptionActionSucceeded(:final message) => message,
      SubscriptionActionOffline() =>
        'لا يمكن تنفيذ عملية منصة دون اتصال. لم يُحفظ الإجراء للإرسال لاحقًا.',
      SubscriptionActionStale() =>
        'تغيّرت بيانات الاشتراك. تم تحديث الصفحة؛ راجعها ثم أعد المحاولة.',
      SubscriptionActionInvalid(:final message) => message,
      SubscriptionActionFailed(:final message) => message,
      SubscriptionActionIgnored() => '',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

String _dateLabel(SubscriptionStatus status) => switch (status) {
      SubscriptionStatus.trial => 'تنتهي التجربة',
      SubscriptionStatus.active => 'التجديد الإداري القادم',
      SubscriptionStatus.grace => 'تنتهي فترة السماح',
      SubscriptionStatus.inactive => 'التاريخ',
    };

class _SubscriptionSkeleton extends StatelessWidget {
  const _SubscriptionSkeleton();
  @override
  Widget build(BuildContext context) => const Column(
        key: Key('subscription-loading'),
        children: [
          SkeletonRow(),
          SizedBox(height: AppSpacing.lg),
          SkeletonRow(),
          SizedBox(height: AppSpacing.lg),
          SkeletonRow(),
        ],
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: context.c.surface,
          border: Border.all(color: context.c.line),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: child,
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.c.warnTint,
          border: Border.all(color: context.c.warn),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.cloud_off_rounded, color: context.c.warn),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                child: Text(label, style: TextStyle(color: context.c.ink3))),
            const SizedBox(width: AppSpacing.md),
            Flexible(child: Text(value, textAlign: TextAlign.end)),
          ],
        ),
      );
}

class _ActionWrap extends StatelessWidget {
  const _ActionWrap({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: children,
      );
}

class _PlanSummary extends StatelessWidget {
  const _PlanSummary({required this.plan, required this.subscription});
  final SaasPlan? plan;
  final SaasSubscription subscription;
  @override
  Widget build(BuildContext context) {
    if (plan == null) {
      return const _Card(
        child: Text(
            'لا توجد خطة ملتزم بها. اختر خطة عند التفعيل أو من إجراء اختيار الخطة.'),
      );
    }
    const preview = [
      PlanLimitKey.detachments,
      PlanLimitKey.members,
      PlanLimitKey.storageBytes,
    ];
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(plan!.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(plan!.description, style: TextStyle(color: context.c.ink3)),
          const SizedBox(height: AppSpacing.md),
          for (final key in preview)
            _ValueRow(
              label: planLimitLabel(key),
              value: formatLimitValue(
                key,
                subscription.effectiveLimit(key, plan!),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanOption extends StatelessWidget {
  const _PlanOption({required this.plan, required this.selected, this.onTap});
  final SaasPlan plan;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        selected: selected,
        label: 'خطة ${plan.name}',
        child: InkWell(
          key: Key('plan-option-${plan.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: selected ? context.c.primaryTint : context.c.surface,
              border: Border.all(
                color: selected ? context.c.primary : context.c.line,
              ),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    Text(plan.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    if (plan.recommended)
                      const StatusChip(
                          kind: StatusKind.info, label: 'موصى بها'),
                    if (selected)
                      const StatusChip(kind: StatusKind.ok, label: 'الحالية'),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(plan.description),
                const SizedBox(height: AppSpacing.md),
                for (final key in const [
                  PlanLimitKey.detachments,
                  PlanLimitKey.members,
                  PlanLimitKey.storageBytes,
                ])
                  Text(
                    '${planLimitLabel(key)}: ${formatLimitValue(key, plan.defaultLimits[key])}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
      );
}
