import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings.dart';
import '../domain/conflict_models.dart';

/// Differences-first conflict resolution for one record.
///
/// MTM conflicts are expected to be uncommon and the field worker's question
/// is narrow: what changed, and which complete version should win? Showing
/// only feature-approved differences answers that quickly without duplicating
/// two full records or creating a generic merge engine. The owning feature
/// retains the complete typed records and formats every value before it enters
/// [ConflictPresentation].
class ConflictResolutionPage extends StatefulWidget {
  const ConflictResolutionPage({
    super.key,
    required this.conflict,
    required this.onDecision,
  });

  static const routePath = '/conflicts/:conflictId';

  static String locationFor(String conflictId) =>
      '/conflicts/${Uri.encodeComponent(conflictId)}';

  final ConflictPresentation conflict;
  final ConflictDecisionHandler onDecision;

  @override
  State<ConflictResolutionPage> createState() => _ConflictResolutionPageState();
}

class _ConflictResolutionPageState extends State<ConflictResolutionPage> {
  bool _saving = false;
  bool _allowPop = false;

  Future<void> _submit(ConflictResolutionIntent intent) async {
    // `_allowPop` as well as `_saving`: a decision that has already been
    // applied leaves the screen on the next frame, and a tap landing in that
    // one-frame gap must not apply a second one.
    if (_saving || _allowPop) return;
    setState(() => _saving = true);

    final decision = ConflictResolutionDecision.forConflict(
      widget.conflict,
      intent,
    );

    try {
      // Awaiting is intentional: navigation cannot close before the owner has
      // persisted the choice (or explicitly kept the conflict unresolved).
      await widget.onDecision(decision);
    } on ConflictResolutionException catch (failure) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_failureMessage(failure.reason))),
      );
      // The conflict on screen is not the conflict any more — it was decided
      // elsewhere, or the record moved again underneath it. Offering the same
      // two buttons again would be offering a choice that cannot be applied,
      // so this leaves for the review list, which rebuilds from the current
      // state. Anything unresolved is still there when it does.
      if (failure.isStale) _leave(failure);
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(S.conflictDecisionFailed)),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _saving = false);
    _leave(decision);
  }

  /// Closes the screen with [result].
  ///
  /// A blocked system-back callback is still inside Navigator's current pop
  /// dispatch. Defer the real pop to the next frame so it is not swallowed
  /// by that in-progress dispatch.
  void _leave(Object result) {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop(result);
    });
  }

  /// Choosing the shared version throws away an unsynced local edit and
  /// cannot be undone, so it is the one action here that asks first (§17).
  /// "استخدام تعديلي" and "مراجعة لاحقاً" lose nothing and ask nothing.
  Future<void> _confirmUseCurrent() async {
    if (_saving || _allowPop) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('conflict-use-current-confirm-dialog'),
        title: const Text(S.conflictUseCurrentConfirmTitle),
        content: const Text(S.conflictUseCurrentConfirmBody),
        actions: [
          TextButton(
            key: const Key('conflict-use-current-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(S.cancel),
          ),
          FilledButton(
            key: const Key('conflict-use-current-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(S.conflictUseCurrent),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _submit(ConflictResolutionIntent.useCurrent);
  }

  /// What went wrong, in words that answer "what happened, is my data safe,
  /// what can I do now". No wire code, no exception text, no record id.
  static String _failureMessage(ConflictResolutionFailure reason) =>
      switch (reason) {
        ConflictResolutionFailure.alreadyResolved => S.conflictAlreadyResolved,
        ConflictResolutionFailure.recordChanged => S.conflictRecordChanged,
        ConflictResolutionFailure.recordDeleted => S.conflictRecordDeleted,
        ConflictResolutionFailure.notPermitted => S.conflictNotPermitted,
        ConflictResolutionFailure.offline => S.conflictOfflineDecision,
        ConflictResolutionFailure.couldNotApply => S.conflictDecisionFailed,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = Theme.of(context).textTheme;

    return PopScope<Object?>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        // A completed explicit choice may fail to pop when this page is the
        // root route (for example in a direct-entry test). Do not mistake
        // that failed pop for a fresh back gesture and submit review-later
        // repeatedly.
        if (!didPop && !_saving && !_allowPop) {
          _submit(ConflictResolutionIntent.reviewLater);
        }
      },
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(title: const Text(S.conflictReviewTitle)),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.xl,
                  ),
                  children: [
                    _ConflictIntro(conflict: widget.conflict),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      S.conflictDifferencesTitle,
                      style: t.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      S.conflictDifferencesBody,
                      style: t.bodySmall?.copyWith(color: c.ink3),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const _VersionLegend(),
                    const SizedBox(height: AppSpacing.sm),
                    _DifferencesGroup(
                      differences: widget.conflict.differences,
                    ),
                  ],
                ),
              ),
              _Actions(
                saving: _saving,
                // Also locked while the screen is closing on an applied
                // decision: the buttons have nothing left to do, and a tap
                // landing in that frame must not decide twice.
                locked: _saving || _allowPop,
                onUseLocal: () => _submit(ConflictResolutionIntent.useLocal),
                onUseCurrent: _confirmUseCurrent,
                onReviewLater: () =>
                    _submit(ConflictResolutionIntent.reviewLater),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConflictIntro extends StatelessWidget {
  const _ConflictIntro({required this.conflict});

  final ConflictPresentation conflict;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.warnTint,
            borderRadius: BorderRadius.circular(AppRadii.xl),
          ),
          child: Icon(
            Icons.compare_arrows_rounded,
            color: c.warn,
            size: 28,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(S.conflictTitle, style: t.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        Text(
          S.conflictDescription,
          style: t.bodyMedium?.copyWith(color: c.ink2, height: 1.55),
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(conflict.recordTitle, style: t.titleSmall),
              if (conflict.recordSubtitle != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  conflict.recordSubtitle!,
                  style: t.bodySmall?.copyWith(color: c.ink3),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _VersionLegend extends StatelessWidget {
  const _VersionLegend();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 340;
        const local = _VersionLabel(
          key: Key('local-version-legend'),
          local: true,
          title: S.conflictLocalVersion,
          subtitle: S.conflictLocalVersionSub,
        );
        const current = _VersionLabel(
          key: Key('current-version-legend'),
          local: false,
          title: S.conflictCurrentVersion,
          subtitle: S.conflictCurrentVersionSub,
        );
        if (stacked) {
          return const Column(
            children: [
              local,
              SizedBox(height: AppSpacing.sm),
              current,
            ],
          );
        }
        return const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: local),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: current),
          ],
        );
      },
    );
  }
}

class _VersionLabel extends StatelessWidget {
  const _VersionLabel({
    super.key,
    required this.local,
    required this.title,
    required this.subtitle,
  });

  final bool local;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final foreground = local ? c.primary : c.info;
    final background = local ? c.primaryTint : c.infoTint;

    return Semantics(
      container: true,
      label: '$title، $subtitle',
      // Excluded below so a screen reader announces the composed label once
      // instead of the label followed by the same title/subtitle again as it
      // descends into the visible Text nodes.
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: foreground),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                local ? Icons.edit_note_rounded : Icons.groups_2_outlined,
                size: 20,
                color: foreground,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DifferencesGroup extends StatelessWidget {
  const _DifferencesGroup({required this.differences});

  final List<ConflictFieldComparison> differences;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < differences.length; i++) ...[
            _DifferenceRow(difference: differences[i]),
            if (i != differences.length - 1) Divider(height: 1, color: c.line),
          ],
        ],
      ),
    );
  }
}

class _DifferenceRow extends StatelessWidget {
  const _DifferenceRow({required this.difference});

  final ConflictFieldComparison difference;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            difference.label,
            style: TextStyle(
              color: c.ink2,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 316;
              final local = _ConflictValue(
                key: Key('conflict-local-${difference.fieldId}'),
                fieldLabel: difference.label,
                versionLabel: S.conflictLocalVersion,
                value: difference.localValue,
                local: true,
                direction: difference.valueDirection,
              );
              final current = _ConflictValue(
                key: Key('conflict-current-${difference.fieldId}'),
                fieldLabel: difference.label,
                versionLabel: S.conflictCurrentVersion,
                value: difference.currentValue,
                local: false,
                direction: difference.valueDirection,
              );
              if (stacked) {
                return Column(
                  children: [
                    local,
                    const SizedBox(height: AppSpacing.sm),
                    current,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: local),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: current),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ConflictValue extends StatelessWidget {
  const _ConflictValue({
    super.key,
    required this.fieldLabel,
    required this.versionLabel,
    required this.value,
    required this.local,
    required this.direction,
  });

  final String fieldLabel;
  final String versionLabel;
  final String value;
  final bool local;
  final ConflictValueDirection direction;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final foreground = local ? c.primary : c.info;
    final background = local ? c.primaryTint : c.infoTint;
    final valueText = Text(
      value,
      style: TextStyle(
        color: foreground,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
    );

    return Semantics(
      container: true,
      label: '$versionLabel، $fieldLabel، $value',
      // Excluded below for the same reason as `_VersionLabel`: without this,
      // a screen reader announces the composed label and then the same value
      // again from the descendant Text node.
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          alignment: AlignmentDirectional.centerStart,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: direction == ConflictValueDirection.ltr
              ? Directionality(
                  textDirection: TextDirection.ltr,
                  child: valueText,
                )
              : valueText,
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.saving,
    required this.locked,
    required this.onUseLocal,
    required this.onUseCurrent,
    required this.onReviewLater,
  });

  final bool saving;
  final bool locked;
  final VoidCallback onUseLocal;
  final VoidCallback onUseCurrent;
  final VoidCallback onReviewLater;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              key: const Key('conflict-use-local'),
              onPressed: locked ? null : onUseLocal,
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.edit_note_rounded, size: 20),
              label: const Text(S.conflictUseLocal),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              key: const Key('conflict-use-current'),
              onPressed: locked ? null : onUseCurrent,
              icon: const Icon(Icons.groups_2_outlined, size: 19),
              label: const Text(S.conflictUseCurrent),
            ),
            TextButton(
              key: const Key('conflict-review-later'),
              onPressed: locked ? null : onReviewLater,
              child: const Text(S.conflictReviewLater),
            ),
          ],
        ),
      ),
    );
  }
}

/// Safe route fallback when a deep link arrives before a conflict can be
/// loaded from the future durable review store. No ids or route payloads are
/// shown, and no mock conflict is fabricated.
class ConflictUnavailablePage extends StatelessWidget {
  const ConflictUnavailablePage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text(S.conflictReviewTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fact_check_outlined, size: 36, color: c.ink3),
              const SizedBox(height: AppSpacing.md),
              Text(
                S.conflictUnavailableTitle,
                style: t.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                S.conflictUnavailableBody,
                style: t.bodyMedium?.copyWith(color: c.ink3),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text(S.back),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
