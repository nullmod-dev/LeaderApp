import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/problem/problem.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/saas_subscription_providers.dart';
import '../domain/saas_subscription_models.dart';
import 'saas_subscription_copy.dart';
import 'saas_tenant_routes.dart';
import 'widgets/platform_confirmation_dialog.dart';
import 'widgets/platform_page.dart';

class SaasTenantLimitsPage extends ConsumerStatefulWidget {
  const SaasTenantLimitsPage({super.key, required this.tenantId});
  final String tenantId;

  @override
  ConsumerState<SaasTenantLimitsPage> createState() =>
      _SaasTenantLimitsPageState();
}

class _SaasTenantLimitsPageState extends ConsumerState<SaasTenantLimitsPage> {
  Future<void> _refresh() async {
    ref.invalidate(tenantLimitsProvider(widget.tenantId));
    await ref.read(tenantLimitsProvider(widget.tenantId).future);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(tenantLimitsProvider(widget.tenantId));
    final action = ref.watch(subscriptionActionControllerProvider);
    return PlatformPage(
      title: 'الاستخدام والحدود',
      onRefresh: _refresh,
      children: [_state(async, action)],
    );
  }

  Widget _state(
    AsyncValue<Result<TenantLimitsSnapshot>> async,
    SubscriptionActionState action,
  ) {
    if (async.isLoading && !async.hasValue) {
      return const _LimitsSkeleton();
    }
    if (async.hasError || !async.hasValue) {
      return ErrorStateView(onRetry: _refresh);
    }
    return async.requireValue.when(
      success: (snapshot, {stale = false}) =>
          _loaded(snapshot, action, stale: stale),
      failure: (_, code) {
        if (ProblemCode.parse(code) == ProblemCode.notFound) {
          return EmptyState(
            key: const Key('limits-tenant-not-found'),
            icon: Icons.search_off_rounded,
            title: 'الفريق غير موجود',
            body: 'تعذّر العثور على فريق SaaS بهذا المعرّف.',
            actionLabel: 'العودة إلى الفرق',
            onAction: () => context.go(SaasTenantRoutes.list),
          );
        }
        if (code == 'plan_not_found') {
          return EmptyState(
            key: const Key('limits-no-plan'),
            icon: Icons.layers_clear_outlined,
            title: 'لا توجد خطة معيّنة',
            body: 'اختر خطة من شاشة الاشتراك قبل إدارة حدودها.',
            actionLabel: 'فتح الاشتراك',
            onAction: () => context.go(
              SaasTenantRoutes.subscription(widget.tenantId),
            ),
          );
        }
        return ErrorStateView(
          key: const Key('limits-failure'),
          title: 'الاستخدام غير متاح',
          body: 'تعذّر تحميل الاستخدام والحدود. لم تُعرض أرقام غير مؤكدة.',
          onRetry: _refresh,
        );
      },
      offline: (cached) => cached == null
          ? EmptyState(
              key: const Key('limits-offline'),
              icon: Icons.cloud_off_rounded,
              title: 'لا يوجد اتصال',
              body:
                  'لا يمكن تعديل حدود المنصة دون اتصال، ولن يُحفظ تعديل مؤجل.',
              actionLabel: 'إعادة المحاولة',
              onAction: _refresh,
            )
          : _loaded(cached, action, offline: true),
    );
  }

  Widget _loaded(
    TenantLimitsSnapshot snapshot,
    SubscriptionActionState action, {
    bool stale = false,
    bool offline = false,
  }) {
    return Column(
      key: const Key('limits-loaded'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (offline || stale)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: _WarningNote(
              icon: offline ? Icons.cloud_off_rounded : Icons.history_rounded,
              text: offline
                  ? 'نسخة للعرض فقط. التعديلات غير متاحة دون اتصال.'
                  : 'قد تكون هذه نسخة محفوظة؛ حدّث قبل التعديل.',
            ),
          ),
        Text(snapshot.tenantName,
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            StatusChip(kind: StatusKind.info, label: snapshot.plan.name),
            Text(
              'الاستخدام الحالي مقابل الحد الفعّال',
              style: TextStyle(color: context.c.ink3),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 600 ? 2 : 1;
          final width = columns == 1
              ? constraints.maxWidth
              : (constraints.maxWidth - AppSpacing.md) / 2;
          return Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              for (final key in PlanLimitKey.values)
                SizedBox(
                  width: width,
                  child: _LimitCard(
                    snapshot: snapshot,
                    limitKey: key,
                    editing: action.isSubmitting,
                    onEdit: offline ? null : () => _edit(snapshot, key),
                  ),
                ),
            ],
          );
        }),
        const SizedBox(height: AppSpacing.xxl),
        const _WarningNote(
          key: Key('limits-no-deletion-note'),
          icon: Icons.info_outline_rounded,
          text:
              'خفض الحد لا يحذف البيانات الحالية. يمنع فقط إنشاء عناصر إضافية من النوع نفسه حتى يصبح الاستخدام دون الحد.',
        ),
      ],
    );
  }

  Future<void> _edit(
    TenantLimitsSnapshot snapshot,
    PlanLimitKey key,
  ) async {
    final result = await showAppSheet<_LimitEditResult>(
      context: context,
      title: 'تعديل حد ${planLimitLabel(key)}',
      child: _LimitEditor(
        limitKey: key,
        effective: snapshot.effectiveLimit(key),
        planDefault: snapshot.plan.defaultLimits[key],
        hasOverride: snapshot.subscription.hasOverride(key),
      ),
    );
    if (result == null || !mounted) return;
    final proposed = result.reset ? null : result.value;
    if (proposed != null && snapshot.isBelowUsage(key, proposed)) {
      final ok = await showPlatformConfirmation(
        context: context,
        title: 'الحد الجديد أقل من الاستخدام',
        change:
            'الاستخدام الحالي ${formatLimitValue(key, snapshot.usage[key])}، والحد الجديد ${formatLimitValue(key, proposed)}. سيتوقف إنشاء عناصر إضافية حتى ينخفض الاستخدام تحت الحد.',
        unchanged: 'لن تُحذف البيانات الحالية ولن تختفي السجلات القديمة.',
        confirmLabel: 'حفظ الحد',
        warning: true,
      );
      if (!ok || !mounted) return;
    }
    await _showOutcome(
      ref.read(subscriptionActionControllerProvider.notifier).updateLimit(
            UpdateLimitOverrideCommand(
              tenantId: snapshot.tenantId,
              expectedVersion: snapshot.subscription.version,
              key: key,
              overrideValue: proposed,
            ),
          ),
    );
  }

  Future<void> _showOutcome(Future<SubscriptionActionOutcome> pending) async {
    final outcome = await pending;
    if (!mounted || outcome is SubscriptionActionIgnored) return;
    final text = switch (outcome) {
      SubscriptionActionSucceeded(:final message) => message,
      SubscriptionActionOffline() =>
        'لا يمكن حفظ الحد دون اتصال. بقيت القيمة في النموذج ولم تُرسل.',
      SubscriptionActionStale() =>
        'تغيّرت الحدود في مكان آخر. تم التحديث؛ راجع القيم ثم أعد المحاولة.',
      SubscriptionActionInvalid(:final message) => message,
      SubscriptionActionFailed(:final message) => message,
      SubscriptionActionIgnored() => '',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _LimitCard extends StatelessWidget {
  const _LimitCard({
    required this.snapshot,
    required this.limitKey,
    required this.editing,
    this.onEdit,
  });
  final TenantLimitsSnapshot snapshot;
  final PlanLimitKey limitKey;
  final bool editing;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final usage = snapshot.usage[limitKey];
    final limit = snapshot.effectiveLimit(limitKey);
    final above = usage > limit;
    final overridden = snapshot.subscription.hasOverride(limitKey);
    final semantics = '${planLimitLabel(limitKey)}، الاستخدام '
        '${formatLimitValue(limitKey, usage)} من '
        '${formatLimitValue(limitKey, limit)}';
    return Semantics(
      label: semantics,
      value: above ? 'الاستخدام أعلى من الحد' : 'ضمن الحد',
      child: Container(
        key: Key('limit-${limitKey.wire}'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: context.c.surface,
          border: Border.all(color: above ? context.c.warn : context.c.line),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(planLimitLabel(limitKey),
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'تعديل حد ${planLimitLabel(limitKey)}',
                  onPressed: editing ? null : onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                '${formatLimitValue(limitKey, usage)} / ${formatLimitValue(limitKey, limit)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              label: semantics,
              child: LinearProgressIndicator(
                value: snapshot.usage.ratio(limitKey, limit),
                color: above ? context.c.warn : context.c.primary,
                backgroundColor: context.c.surface3,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              overridden
                  ? 'حد مخصص — افتراضي الخطة ${formatLimitValue(limitKey, snapshot.plan.defaultLimits[limitKey])}'
                  : 'افتراضي الخطة',
              style: TextStyle(color: context.c.ink3, fontSize: 12),
            ),
            if (above)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  'الاستخدام الحالي أعلى من الحد، ولا يعني ذلك حذف البيانات.',
                  style: TextStyle(color: context.c.warn, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LimitEditResult {
  const _LimitEditResult.value(this.value) : reset = false;
  const _LimitEditResult.reset()
      : value = null,
        reset = true;
  final int? value;
  final bool reset;
}

class _LimitEditor extends StatefulWidget {
  const _LimitEditor({
    required this.limitKey,
    required this.effective,
    required this.planDefault,
    required this.hasOverride,
  });
  final PlanLimitKey limitKey;
  final int effective;
  final int planDefault;
  final bool hasOverride;

  @override
  State<_LimitEditor> createState() => _LimitEditorState();
}

class _LimitEditorState extends State<_LimitEditor> {
  late final TextEditingController _controller;
  String? _error;

  int get _unit => widget.limitKey.isBytes ? 1024 * 1024 * 1024 : 1;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.effective ~/ _unit}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null || parsed < 0) {
      setState(() => _error = 'أدخل رقمًا صحيحًا يساوي صفرًا أو أكثر.');
      return;
    }
    Navigator.pop(context, _LimitEditResult.value(parsed * _unit));
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'افتراضي الخطة: ${formatLimitValue(widget.limitKey, widget.planDefault)}',
              ),
              const SizedBox(height: AppSpacing.md),
              Directionality(
                textDirection: TextDirection.ltr,
                child: TextField(
                  key: const Key('limit-value-field'),
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText:
                        widget.limitKey.isBytes ? 'الحد بالغيغابايت' : 'الحد',
                    errorText: _error,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                key: const Key('save-limit'),
                onPressed: _save,
                child: const Text('متابعة'),
              ),
              if (widget.hasOverride) ...[
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  key: const Key('reset-limit'),
                  onPressed: () => Navigator.pop(
                    context,
                    const _LimitEditResult.reset(),
                  ),
                  child: const Text('إعادة إلى افتراضي الخطة'),
                ),
              ],
            ],
          ),
        ),
      );
}

class _WarningNote extends StatelessWidget {
  const _WarningNote({super.key, required this.icon, required this.text});
  final IconData icon;
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
            Icon(icon, color: context.c.warn),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

class _LimitsSkeleton extends StatelessWidget {
  const _LimitsSkeleton();
  @override
  Widget build(BuildContext context) => const Column(
        key: Key('limits-loading'),
        children: [
          SkeletonRow(),
          SizedBox(height: AppSpacing.md),
          SkeletonRow(),
          SizedBox(height: AppSpacing.md),
          SkeletonRow(),
        ],
      );
}
