import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/app_date.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/time/clock.dart';
import '../../../core/widgets/reading_column.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/tenant_lifecycle_providers.dart';
import '../domain/saas_tenant_models.dart';
import '../domain/tenant_lifecycle_models.dart';
import '../domain/tenant_lifecycle_repository.dart';
import 'tenant_lifecycle_confirmation.dart';
import 'tenant_lifecycle_copy.dart';
import 'widgets/platform_confirmation_dialog.dart';

/// The Super Admin's operational lifecycle control for one canonical tenant.
///
/// It renders only legal actions for the current versioned state. Consequence
/// review and commands remain typed; this widget owns presentation, validation
/// feedback and safe recovery copy, never the transition rules themselves.
class TenantLifecycleManagementSection extends ConsumerStatefulWidget {
  const TenantLifecycleManagementSection({
    super.key,
    required this.tenant,
  });

  final SaasTenant tenant;

  @override
  ConsumerState<TenantLifecycleManagementSection> createState() =>
      _TenantLifecycleManagementSectionState();
}

class _TenantLifecycleManagementSectionState
    extends ConsumerState<TenantLifecycleManagementSection> {
  final Map<TenantLifecycleAction, String> _reasonDrafts = {};

  SaasTenant get tenant => widget.tenant;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final busy = ref.watch(tenantLifecycleActionControllerProvider);
    final now = ref.watch(clockProvider)().toUtc();
    final deletion = tenant.lifecycle.deletion;
    final finalizationAvailable =
        deletion != null && !now.isBefore(deletion.scheduledFor.toUtc());

    return Column(
      key: const Key('tenant-lifecycle-management'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'إدارة وصول الفريق',
          style: AppTypography.eyebrow(c),
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          container: true,
          label:
              'حالة وصول الفريق: ${tenantLifecycleStatusLabel(tenant.tenantStatus)}',
          child: Container(
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
                _LifecycleHeader(tenant: tenant),
                const SizedBox(height: AppSpacing.lg),
                _LifecycleFacts(tenant: tenant, now: now),
                const SizedBox(height: AppSpacing.lg),
                _LifecycleBoundaryNote(status: tenant.tenantStatus),
                const SizedBox(height: AppSpacing.xl),
                Divider(color: c.line),
                const SizedBox(height: AppSpacing.lg),
                _LifecycleActions(
                  status: tenant.tenantStatus,
                  busy: busy,
                  finalizationAvailable: finalizationAvailable,
                  onAction: _confirmAndRun,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'تُنفّذ إجراءات دورة الحياة عبر المنصة المتصلة فقط، ولا تُضاف إلى قائمة المزامنة دون اتصال.',
          style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5),
        ),
      ],
    );
  }

  Future<void> _confirmAndRun(TenantLifecycleAction action) async {
    String? reason;
    if (action == TenantLifecycleAction.suspend ||
        action == TenantLifecycleAction.beginDeletion) {
      reason = await _requestReason(action);
      if (reason == null || !mounted) return;
    }

    final consequence = TenantLifecycleConfirmation.forTenant(tenant, action);
    final confirmed = consequence.typedConfirmation == null
        ? await showPlatformConfirmationSpec(
            context: context,
            title: consequence.title,
            identity: consequence.identity,
            change: consequence.change,
            unchanged: consequence.unchanged,
            effective: consequence.effective,
            confirmLabel: consequence.confirmLabel,
            severity: consequence.severity,
          )
        : await showPlatformFinalDeletionConfirmation(
            context: context,
            title: consequence.title,
            identity: consequence.identity,
            change: consequence.change,
            unchanged: consequence.unchanged,
            effective: consequence.effective!,
            confirmLabel: consequence.confirmLabel,
            typedConfirmation: consequence.typedConfirmation!,
          );
    if (!confirmed || !mounted) return;

    final controller =
        ref.read(tenantLifecycleActionControllerProvider.notifier);
    final key = tenantLifecycleIdempotencyKey(
      tenantId: tenant.id,
      expectedVersion: tenant.tenantVersion,
      action: action,
    );
    final pending = switch (action) {
      TenantLifecycleAction.suspend => controller.suspend(SuspendTenantCommand(
          tenantId: tenant.id,
          expectedVersion: tenant.tenantVersion,
          idempotencyKey: key,
          reason: reason!,
        )),
      TenantLifecycleAction.reactivate =>
        controller.reactivate(ReactivateTenantCommand(
          tenantId: tenant.id,
          expectedVersion: tenant.tenantVersion,
          idempotencyKey: key,
        )),
      TenantLifecycleAction.beginDeletion =>
        controller.beginDeletion(BeginTenantDeletionCommand(
          tenantId: tenant.id,
          expectedVersion: tenant.tenantVersion,
          idempotencyKey: key,
          reason: reason!,
        )),
      TenantLifecycleAction.cancelDeletion =>
        controller.cancelDeletion(CancelTenantDeletionCommand(
          tenantId: tenant.id,
          expectedVersion: tenant.tenantVersion,
          idempotencyKey: key,
        )),
      TenantLifecycleAction.finalizeDeletion =>
        controller.finalizeDeletion(FinalizeTenantDeletionCommand(
          tenantId: tenant.id,
          expectedVersion: tenant.tenantVersion,
          idempotencyKey: key,
        )),
    };
    final result = await pending;
    if (!mounted) return;
    if (result is TenantLifecycleActionSucceeded) {
      _reasonDrafts.remove(action);
    }
    _showOutcome(result, action);
  }

  Future<String?> _requestReason(TenantLifecycleAction action) async {
    final initial = _reasonDrafts[action] ?? '';
    final answer = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _LifecycleReasonDialog(
        action: action,
        initialValue: initial,
        onChanged: (value) => _reasonDrafts[action] = value,
      ),
    );
    return answer;
  }

  void _showOutcome(
    TenantLifecycleActionOutcome outcome,
    TenantLifecycleAction action,
  ) {
    final message = switch (outcome) {
      TenantLifecycleActionSucceeded() => tenantLifecycleSuccessMessage(action),
      TenantLifecycleActionOffline() =>
        'لا يمكن تنفيذ هذا الإجراء دون اتصال. احتُفظ بالنص لتتمكن من المحاولة بعد الاتصال.',
      TenantLifecycleActionStale() => tenantLifecycleProblemMessage(
          TenantLifecycleProblemCode.staleTenant,
        ),
      TenantLifecycleActionInvalid(:final code) =>
        tenantLifecycleProblemMessage(code),
      TenantLifecycleActionNotPermitted() => tenantLifecycleProblemMessage(
          TenantLifecycleProblemCode.notPermitted,
        ),
      TenantLifecycleActionFailed() =>
        'تعذّر إتمام العملية بأمان. تحقّق من الاتصال وحدّث البيانات ثم حاول مجدداً.',
      TenantLifecycleActionIgnored() =>
        'هناك إجراء آخر قيد التنفيذ. انتظر حتى يكتمل.',
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LifecycleReasonDialog extends StatefulWidget {
  const _LifecycleReasonDialog({
    required this.action,
    required this.initialValue,
    required this.onChanged,
  });

  final TenantLifecycleAction action;
  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  State<_LifecycleReasonDialog> createState() => _LifecycleReasonDialogState();
}

class _LifecycleReasonDialogState extends State<_LifecycleReasonDialog> {
  late final TextEditingController _controller;
  late String _value;
  late bool _touched;

  String get _normalized => normalizeTenantLifecycleReason(_value);

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
    _touched = _value.isNotEmpty;
    _controller = TextEditingController(text: _value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final empty = _normalized.isEmpty;
    return AlertDialog(
      scrollable: true,
      title: Text(widget.action == TenantLifecycleAction.suspend
          ? 'سبب إيقاف الوصول'
          : 'سبب بدء الحذف'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kDialogMaxWidth),
        child: TextField(
          key: const Key('tenant-lifecycle-reason'),
          controller: _controller,
          maxLength: kTenantLifecycleReasonMaxLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          minLines: 3,
          maxLines: 5,
          textInputAction: TextInputAction.newline,
          onChanged: (next) => setState(() {
            _value = next;
            _touched = true;
            widget.onChanged(next);
          }),
          decoration: InputDecoration(
            labelText: 'سبب إداري خاص بالمنصة',
            hintText: 'اكتب سبباً موجزاً وواضحاً',
            helperText: 'لا يظهر هذا السبب لمستخدمي الفريق.',
            errorText: _touched && empty ? 'السبب الإداري مطلوب.' : null,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('tenant-lifecycle-reason-continue'),
          onPressed: empty ? null : () => Navigator.pop(context, _normalized),
          child: const Text('مراجعة النتائج'),
        ),
      ],
    );
  }
}

class _LifecycleHeader extends StatelessWidget {
  const _LifecycleHeader({required this.tenant});

  final SaasTenant tenant;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final status = tenant.tenantStatus;
    final icon = switch (status) {
      SaasTenantStatus.active => Icons.verified_user_outlined,
      SaasTenantStatus.suspended => Icons.pause_circle_outline_rounded,
      SaasTenantStatus.deletionPending => Icons.hourglass_top_rounded,
      SaasTenantStatus.deleted => Icons.folder_off_outlined,
    };
    final tint = switch (status) {
      SaasTenantStatus.active => (fg: c.ok, bg: c.okTint),
      SaasTenantStatus.suspended => (fg: c.crit, bg: c.critTint),
      SaasTenantStatus.deletionPending => (fg: c.warn, bg: c.warnTint),
      SaasTenantStatus.deleted => (fg: c.crit, bg: c.critTint),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.bg,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(icon, color: tint.fg, size: 23),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusChip(
                kind: tenantLifecycleStatusKind(status),
                label: tenantLifecycleStatusLabel(status),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                tenantLifecycleStatusSummary(status),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: c.ink3, height: 1.55),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LifecycleFacts extends StatelessWidget {
  const _LifecycleFacts({required this.tenant, required this.now});

  final SaasTenant tenant;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final facts = switch (tenant.tenantStatus) {
      SaasTenantStatus.active => <(String, String)>[
          ('آخر تحديث للسجل', _dateTime(tenant.updatedAt)),
        ],
      SaasTenantStatus.suspended => <(String, String)>[
          (
            'وقت إيقاف الوصول',
            _dateTime(tenant.lifecycle.suspension!.suspendedAt),
          ),
          ('السبب الإداري', tenant.lifecycle.suspension!.reason),
        ],
      SaasTenantStatus.deletionPending => <(String, String)>[
          ('طُلب الحذف', _dateTime(tenant.lifecycle.deletion!.requestedAt)),
          (
            'موعد الحذف النهائي',
            _dateTime(tenant.lifecycle.deletion!.scheduledFor),
          ),
          (
            'الوقت المتبقي',
            tenantDeletionRemainingLabel(
              now,
              tenant.lifecycle.deletion!.scheduledFor,
            ),
          ),
          (
            'الحالة عند الإلغاء',
            tenantDeletionRestoreLabel(
              tenant.lifecycle.deletion!.previousStatus,
            ),
          ),
          ('السبب الإداري', tenant.lifecycle.deletion!.reason),
        ],
      SaasTenantStatus.deleted => const <(String, String)>[],
    };

    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 480 ? 2 : 1;
      final width =
          (constraints.maxWidth - AppSpacing.lg * (columns - 1)) / columns;
      return Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.md,
        children: [
          for (final (label, value) in facts)
            SizedBox(
              width: width,
              child: _LifecycleFact(label: label, value: value),
            ),
        ],
      );
    });
  }

  static String _dateTime(DateTime value) =>
      AppDate.dayMonthTime(value.toLocal());
}

class _LifecycleFact extends StatelessWidget {
  const _LifecycleFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: c.ink3, fontSize: 12)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: c.ink, height: 1.45),
        ),
      ],
    );
  }
}

class _LifecycleBoundaryNote extends StatelessWidget {
  const _LifecycleBoundaryNote({required this.status});

  final SaasTenantStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final text = switch (status) {
      SaasTenantStatus.active =>
        'حالة الوصول مستقلة عن الاشتراك. الميزات والصلاحيات وحدود الخطة تستمر بالتطبيق بصورة منفصلة.',
      SaasTenantStatus.suspended =>
        'الإيقاف لا يلغي الاشتراك ولا يحذف البيانات أو رمز الفريق، ولا يغيّر الميزات أو الحدود.',
      SaasTenantStatus.deletionPending =>
        'هذه مرحلة جدولة قابلة للإلغاء قبل الموعد؛ الحذف المادي لم يبدأ من تطبيق Flutter.',
      SaasTenantStatus.deleted =>
        'لا يعرض السجل المختصر أي بيانات تشغيلية للفريق.',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: c.info, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: c.ink2, height: 1.55),
            ),
          ),
        ],
      ),
    );
  }
}

class _LifecycleActions extends StatelessWidget {
  const _LifecycleActions({
    required this.status,
    required this.busy,
    required this.finalizationAvailable,
    required this.onAction,
  });

  final SaasTenantStatus status;
  final TenantLifecycleActionState busy;
  final bool finalizationAvailable;
  final ValueChanged<TenantLifecycleAction> onAction;

  @override
  Widget build(BuildContext context) {
    final regular = switch (status) {
      SaasTenantStatus.active => TenantLifecycleAction.suspend,
      SaasTenantStatus.suspended => TenantLifecycleAction.reactivate,
      SaasTenantStatus.deletionPending when !finalizationAvailable =>
        TenantLifecycleAction.cancelDeletion,
      _ => null,
    };
    final destructive = switch (status) {
      SaasTenantStatus.active ||
      SaasTenantStatus.suspended =>
        TenantLifecycleAction.beginDeletion,
      SaasTenantStatus.deletionPending when finalizationAvailable =>
        TenantLifecycleAction.finalizeDeletion,
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'الإجراءات المتاحة',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _actionLead(status, finalizationAvailable),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: context.c.ink3, height: 1.5),
        ),
        if (regular != null) ...[
          const SizedBox(height: AppSpacing.md),
          _LifecycleActionButton(
            action: regular,
            busy: busy,
            onPressed: () => onAction(regular),
          ),
        ],
        if (destructive != null) ...[
          const SizedBox(height: AppSpacing.xl),
          Divider(color: context.c.line),
          const SizedBox(height: AppSpacing.md),
          Text(
            destructive == TenantLifecycleAction.finalizeDeletion
                ? 'إجراء نهائي عالي الخطورة'
                : 'إجراء حذف حساس',
            style: TextStyle(
              color: context.c.crit,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _LifecycleActionButton(
            action: destructive,
            busy: busy,
            destructive: true,
            onPressed: () => onAction(destructive),
          ),
        ],
        if (busy.isSubmitting) ...[
          const SizedBox(height: AppSpacing.md),
          Semantics(
            liveRegion: true,
            child: Text(
              'جارٍ تنفيذ الإجراء بأمان…',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: context.c.ink3),
            ),
          ),
        ],
      ],
    );
  }

  static String _actionLead(
    SaasTenantStatus status,
    bool finalizationAvailable,
  ) =>
      switch (status) {
        SaasTenantStatus.active =>
          'يمكن إيقاف الوصول مؤقتاً، أو بدء مرحلة انتظار الحذف عند وجود سبب إداري موثّق.',
        SaasTenantStatus.suspended =>
          'يمكن استئناف الوصول دون تغيير الاشتراك، أو بدء مرحلة انتظار الحذف.',
        SaasTenantStatus.deletionPending when !finalizationAvailable =>
          'يمكن إلغاء الطلب قبل الموعد وإعادة الفريق إلى حالته السابقة تماماً.',
        SaasTenantStatus.deletionPending =>
          'انتهت نافذة الإلغاء. راجع النتائج بعناية قبل طلب الحذف النهائي من الخادم.',
        SaasTenantStatus.deleted => 'لا توجد إجراءات عادية لسجل محذوف.',
      };
}

class _LifecycleActionButton extends StatelessWidget {
  const _LifecycleActionButton({
    required this.action,
    required this.busy,
    required this.onPressed,
    this.destructive = false,
  });

  final TenantLifecycleAction action;
  final TenantLifecycleActionState busy;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final isBusy = busy.submitting == _stateKind(action);
    final icon = switch (action) {
      TenantLifecycleAction.suspend => Icons.pause_circle_outline_rounded,
      TenantLifecycleAction.reactivate => Icons.play_circle_outline_rounded,
      TenantLifecycleAction.beginDeletion => Icons.delete_outline_rounded,
      TenantLifecycleAction.cancelDeletion => Icons.undo_rounded,
      TenantLifecycleAction.finalizeDeletion => Icons.delete_forever_rounded,
    };
    final label = switch (action) {
      TenantLifecycleAction.suspend => 'إيقاف وصول الفريق',
      TenantLifecycleAction.reactivate => 'إعادة تفعيل الوصول',
      TenantLifecycleAction.beginDeletion => 'بدء طلب الحذف',
      TenantLifecycleAction.cancelDeletion => 'إلغاء طلب الحذف',
      TenantLifecycleAction.finalizeDeletion => 'طلب الحذف النهائي',
    };
    final key = switch (action) {
      TenantLifecycleAction.suspend => 'tenant-lifecycle-suspend',
      TenantLifecycleAction.reactivate => 'tenant-lifecycle-reactivate',
      TenantLifecycleAction.beginDeletion => 'tenant-lifecycle-begin-delete',
      TenantLifecycleAction.cancelDeletion => 'tenant-lifecycle-cancel-delete',
      TenantLifecycleAction.finalizeDeletion =>
        'tenant-lifecycle-finalize-delete',
    };

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth < 480
          ? constraints.maxWidth
          : (constraints.maxWidth * .56).clamp(260.0, 360.0);
      final callback = busy.isSubmitting ? null : onPressed;
      final button = destructive
          ? OutlinedButton.icon(
              key: Key(key),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.c.crit,
                side: BorderSide(color: context.c.crit),
              ),
              onPressed: callback,
              icon: isBusy ? const _ActionProgress() : Icon(icon),
              label: Text(label),
            )
          : FilledButton.icon(
              key: Key(key),
              onPressed: callback,
              icon: isBusy ? const _ActionProgress() : Icon(icon),
              label: Text(label),
            );
      return SizedBox(width: width, child: button);
    });
  }

  static TenantLifecycleActionStateKind _stateKind(
    TenantLifecycleAction action,
  ) =>
      switch (action) {
        TenantLifecycleAction.suspend => TenantLifecycleActionStateKind.suspend,
        TenantLifecycleAction.reactivate =>
          TenantLifecycleActionStateKind.reactivate,
        TenantLifecycleAction.beginDeletion =>
          TenantLifecycleActionStateKind.beginDeletion,
        TenantLifecycleAction.cancelDeletion =>
          TenantLifecycleActionStateKind.cancelDeletion,
        TenantLifecycleAction.finalizeDeletion =>
          TenantLifecycleActionStateKind.finalizeDeletion,
      };
}

class _ActionProgress extends StatelessWidget {
  const _ActionProgress();

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: IconTheme.of(context).color,
        ),
      );
}
