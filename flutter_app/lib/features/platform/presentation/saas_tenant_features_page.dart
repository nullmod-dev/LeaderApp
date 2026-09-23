import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../../tenant_feature/data/tenant_feature_providers.dart';
import '../../tenant_feature/domain/tenant_feature_models.dart';
import '../../tenant_feature/domain/tenant_feature_repository.dart';
import 'saas_tenant_routes.dart';
import 'widgets/platform_confirmation_dialog.dart';
import 'widgets/platform_page.dart';

class SaasTenantFeaturesPage extends ConsumerWidget {
  const SaasTenantFeaturesPage({super.key, required this.tenantId});

  final String tenantId;

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(tenantFeaturesProvider(tenantId));
    await ref.read(tenantFeaturesProvider(tenantId).future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tenantFeaturesProvider(tenantId));
    return PlatformPage(
      title: 'ميزات الفريق',
      onRefresh: () => _refresh(ref),
      children: _content(context, ref, async),
    );
  }

  List<Widget> _content(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Result<TenantFeatureSet>> async,
  ) {
    if (async.isLoading && !async.hasValue) return const [_FeatureSkeleton()];
    if (async.hasError || !async.hasValue) {
      return [
        ErrorStateView(
          key: const Key('tenant-features-failure'),
          onRetry: () => _refresh(ref),
        ),
      ];
    }

    return async.requireValue.when(
      success: (features, {stale = false}) =>
          _loaded(context, ref, features, stale: stale),
      offline: (cached) => cached == null
          ? [
              EmptyState(
                key: const Key('tenant-features-offline-empty'),
                icon: Icons.cloud_off_rounded,
                title: 'لا يمكن تحميل الميزات دون اتصال',
                body:
                    'لا توجد نسخة معروفة يمكن الاعتماد عليها. أعد المحاولة بعد استعادة الاتصال.',
                actionLabel: 'إعادة المحاولة',
                onAction: () => _refresh(ref),
              ),
            ]
          : _loaded(context, ref, cached, offline: true),
      failure: (message, code) {
        final parsed = TenantFeatureProblemCode.parse(code);
        if (parsed == TenantFeatureProblemCode.tenantNotFound) {
          return [
            EmptyState(
              key: const Key('tenant-features-not-found'),
              icon: Icons.search_off_rounded,
              title: 'الفريق غير موجود',
              body:
                  'تعذّر العثور على الفريق المطلوب في منصة ${S.productNameAr}.',
              actionLabel: 'العودة إلى الفرق',
              onAction: () => context.go(SaasTenantRoutes.list),
            ),
          ];
        }
        if (parsed == TenantFeatureProblemCode.featureNotFound) {
          return [
            EmptyState(
              key: const Key('tenant-features-unavailable'),
              icon: Icons.extension_off_outlined,
              title: 'حالة الميزات غير متاحة',
              body:
                  'لم تصل حالة موثوقة لهذا الفريق، لذلك لن تُفترض أي ميزة مفعّلة.',
              actionLabel: 'إعادة المحاولة',
              onAction: () => _refresh(ref),
            ),
          ];
        }
        return [
          ErrorStateView(
            key: const Key('tenant-features-failure'),
            title: 'تعذّر تحميل الميزات',
            body: 'لم نتمكن من تحميل حالة موثوقة. حاول مجددًا.',
            onRetry: () => _refresh(ref),
          ),
        ];
      },
    );
  }

  List<Widget> _loaded(
    BuildContext context,
    WidgetRef ref,
    TenantFeatureSet features, {
    bool stale = false,
    bool offline = false,
  }) {
    final action = ref.watch(tenantFeatureActionControllerProvider);
    return [
      // The tenant's name is content, not a repeat of the app bar, so it
      // stays — as one line above the lead rather than under a 52 dp tile.
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          Text(
            features.tenantName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (offline)
            const StatusChip(kind: StatusKind.warn, label: 'دون اتصال')
          else if (stale)
            const StatusChip(kind: StatusKind.muted, label: 'نسخة مخزنة'),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      const PlatformPageIntro(
        lead:
            'تتحكم هذه الإعدادات في توفر وحدات المنتج لكل أعضاء الفريق. صلاحيات كل مسؤول وحدود الخطة تُطبّق بصورة مستقلة.',
      ),
      const SizedBox(height: AppSpacing.xl),
      if (offline) const _ReadOnlyNotice() else const _RetentionNotice(),
      const SizedBox(height: AppSpacing.lg),
      Container(
        key: const Key('tenant-features-loaded'),
        decoration: BoxDecoration(
          color: context.c.surface,
          border: Border.all(color: context.c.line),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < tenantFeatureCatalog.length; i++) ...[
              _FeatureRow(
                definition: tenantFeatureCatalog[i],
                state: features.stateOf(tenantFeatureCatalog[i].key),
                busy: action.isSubmitting,
                readOnly: offline,
                onChanged: (enabled) => _change(
                  context,
                  ref,
                  features,
                  tenantFeatureCatalog[i],
                  enabled,
                ),
              ),
              if (i != tenantFeatureCatalog.length - 1)
                Divider(height: 1, color: context.c.line),
            ],
          ],
        ),
      ),
    ];
  }

  Future<void> _change(
    BuildContext context,
    WidgetRef ref,
    TenantFeatureSet set,
    TenantFeatureDefinition definition,
    bool enabled,
  ) async {
    final current = set.stateOf(definition.key);
    if (current == null || current.enabled == enabled) return;

    if (!enabled && definition.confirmDisable) {
      final confirmed = await showPlatformConfirmation(
        context: context,
        title: 'تعطيل ${definition.arabicLabel}',
        change:
            'ستختفي ${definition.arabicLabel} من تنقل ${set.tenantName} وتتوقف مساراتها عن الفتح.',
        unchanged:
            'لن تُحذف البيانات الحالية. تعيد إعادة التفعيل الوصول إليها وفق صلاحيات المستخدم.',
        effective: 'يسري التغيير فور تحديث إعدادات الفريق.',
        confirmLabel: 'تعطيل الميزة',
        warning: definition.warning == TenantFeatureWarning.workflow,
      );
      if (!confirmed || !context.mounted) return;
    }

    final outcome = await ref
        .read(tenantFeatureActionControllerProvider.notifier)
        .setEnabled(SetTenantFeatureCommand(
          tenantId: set.tenantId,
          key: definition.key,
          enabled: enabled,
          expectedVersion: current.version,
        ));
    if (!context.mounted || outcome is TenantFeatureActionIgnored) return;

    final message = switch (outcome) {
      TenantFeatureActionSucceeded() => enabled
          ? 'تم تفعيل ${definition.arabicLabel}.'
          : 'تم تعطيل ${definition.arabicLabel} مع الاحتفاظ بالبيانات.',
      TenantFeatureActionOffline() =>
        'لا يمكن تغيير الميزات دون اتصال. لم تتغير الحالة الحالية.',
      TenantFeatureActionStale() =>
        'تغيّرت الحالة لدى مشرف آخر. حُدّثت الصفحة؛ راجعها ثم أعد المحاولة.',
      TenantFeatureActionInvalid() =>
        'لا يمكن تطبيق هذا التغيير على الحالة الحالية.',
      TenantFeatureActionFailed() =>
        'تعذّر حفظ التغيير بأمان. بقيت الحالة الحالية كما هي.',
      TenantFeatureActionIgnored() => '',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.definition,
    required this.state,
    required this.busy,
    required this.readOnly,
    required this.onChanged,
  });

  final TenantFeatureDefinition definition;
  final TenantFeatureState? state;
  final bool busy;
  final bool readOnly;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = state?.enabled == true;
    final switcher = Semantics(
      label:
          '${definition.arabicLabel}، ${enabled ? 'مفعلة' : 'معطلة'}، إجراء تغيير حالة الميزة',
      toggled: enabled,
      button: true,
      child: Switch.adaptive(
        key: Key('tenant-feature-switch-${definition.key.wire}'),
        value: enabled,
        onChanged: state == null || busy || readOnly ? null : onChanged,
      ),
    );
    final consequence = Text(
      definition.disableConsequence,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: definition.warning == TenantFeatureWarning.workflow
                ? context.c.warn
                : context.c.ink3,
            height: 1.55,
          ),
    );

    return Padding(
      key: Key('tenant-feature-row-${definition.key.wire}'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The switch sits on the title's line, beside the thing it toggles.
          // It used to be on its own line at the opposite corner of the row,
          // under a description and a permanent warning sentence — a long
          // diagonal between a control and its label, four times on one
          // screen (UI audit, Tenant Features).
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      definition.arabicLabel,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    StatusChip(
                      kind: enabled ? StatusKind.ok : StatusKind.muted,
                      label: enabled ? 'مفعلة' : 'معطلة',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              switcher,
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            definition.description,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: context.c.ink3, height: 1.55),
          ),
          // Only while the feature is on — that is, only while the switch is
          // about to turn it *off*. On a module already disabled the sentence
          // describes something that has already happened, and four permanent
          // amber paragraphs made every row read as a warning.
          if (enabled) ...[
            const SizedBox(height: AppSpacing.xs),
            consequence,
          ],
        ],
      ),
    );
  }
}

class _RetentionNotice extends StatelessWidget {
  const _RetentionNotice();

  @override
  Widget build(BuildContext context) => const _Notice(
        key: Key('tenant-features-retention-note'),
        icon: Icons.lock_clock_outlined,
        text:
            'تعطيل ميزة يزيل الوصول فقط. لا يحذف أي سجل أو يعيد الاستخدام والحدود إلى الصفر.',
      );
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

  @override
  Widget build(BuildContext context) => const _Notice(
        key: Key('tenant-features-offline-cached'),
        icon: Icons.cloud_off_rounded,
        text:
            'هذه آخر حالة معروفة. التغيير متوقف دون اتصال ولا يُحفظ للإرسال لاحقًا.',
      );
}

class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.c.infoTint,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19, color: context.c.info),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(height: 1.55),
              ),
            ),
          ],
        ),
      );
}

class _FeatureSkeleton extends StatelessWidget {
  const _FeatureSkeleton();

  @override
  Widget build(BuildContext context) => const Column(
        key: Key('tenant-features-loading'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(width: 52, height: 52, radius: AppRadii.lg),
          SizedBox(height: AppSpacing.lg),
          Skeleton(width: 190, height: 22),
          SizedBox(height: AppSpacing.sm),
          Skeleton(height: 16),
          SizedBox(height: AppSpacing.xxl),
          Skeleton(height: 130, radius: AppRadii.lg),
          SizedBox(height: AppSpacing.sm),
          Skeleton(height: 130, radius: AppRadii.lg),
        ],
      );
}
