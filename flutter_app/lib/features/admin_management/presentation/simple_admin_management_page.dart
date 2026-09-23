import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result/result.dart';
import '../../../core/sync/outbox_controller.dart' show newOperationIdProvider;
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/clock.dart';
import '../../../core/widgets/confirmation_dialog.dart';
import '../../../l10n/strings.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../../shell/main_shell.dart';
import '../../tenant_feature/data/tenant_feature_providers.dart';
import '../data/simple_admin_providers.dart';
import '../domain/simple_admin_models.dart';

class SimpleAdminManagementPage extends ConsumerWidget {
  const SimpleAdminManagementPage({super.key});

  static const routePath = '/more/simple-admins';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(simpleAdminSnapshotProvider);
    return Scaffold(
      backgroundColor: context.c.bg,
      appBar: AppBar(title: const Text(S.simpleAdminsTitle)),
      body: FloatingNavPadding(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => _Failure(
              onRetry: () => ref.invalidate(simpleAdminSnapshotProvider)),
          data: (result) => result.when(
            success: (snapshot, {stale = false}) =>
                _Content(snapshot: snapshot),
            failure: (_, __) => _Failure(
                onRetry: () => ref.invalidate(simpleAdminSnapshotProvider)),
            offline: (_) => _Failure(
                onRetry: () => ref.invalidate(simpleAdminSnapshotProvider)),
          ),
        ),
      ),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({required this.snapshot});

  final SimpleAdminManagementSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Whether an invitation still reads as pending is decided by "now", so it
    // comes from the injectable clock rather than `DateTime.now()` directly —
    // same default in production, pinnable from a test.
    final now = ref.watch(clockProvider)();
    return ListView(
      key: const Key('simple-admin-management'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(S.simpleAdminsLead,
            style: TextStyle(color: context.c.ink2, height: 1.6)),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          key: const Key('invite-simple-admin'),
          onPressed: () =>
              context.push('${SimpleAdminManagementPage.routePath}/invite'),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text(S.simpleAdminInvite),
        ),
        const SectionLabel(S.simpleAdminsCurrent),
        if (snapshot.accounts.isEmpty)
          const _Empty(message: S.simpleAdminsCurrentEmpty)
        else
          SettingsSection(children: [
            for (final account in snapshot.accounts)
              _AccountRow(account: account),
          ]),
        const SectionLabel(S.simpleAdminInvitations),
        if (snapshot.invitations.isEmpty)
          const _Empty(message: S.simpleAdminInvitationsEmpty)
        else
          SettingsSection(children: [
            for (final invitation in snapshot.invitations)
              _InvitationRow(
                invitation: invitation,
                status: invitation.effectiveStatus(now),
                revision: snapshot.revision,
              ),
          ]),
        const SizedBox(height: AppSpacing.lg),
        const _InfoNote(text: S.simpleAdminOnboardingNote),
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account});

  final SimpleAdminAccount account;

  @override
  Widget build(BuildContext context) => ListTile(
        minVerticalPadding: AppSpacing.sm,
        leading: const Icon(Icons.badge_outlined),
        title: Text(account.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(account.email, textAlign: TextAlign.left),
            ),
            Text(account.status == SimpleAdminAccountStatus.active
                ? S.simpleAdminActive
                : S.simpleAdminSuspended),
            // The grant at a glance, so "what can this person do" never
            // needs a tap to answer.
            Text('${account.capabilities.global.length}'
                '${S.simpleAdminCapabilityCountSuffix}'),
          ],
        ),
        trailing: IconButton(
          tooltip: S.simpleAdminEditCapabilities,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: () => context.push(
            '${SimpleAdminManagementPage.routePath}/${account.id}/capabilities',
          ),
          icon: const Icon(Icons.tune_rounded),
        ),
      );
}

class _InvitationRow extends ConsumerWidget {
  const _InvitationRow({
    required this.invitation,
    required this.status,
    required this.revision,
  });

  final SimpleAdminInvitation invitation;
  final SimpleAdminInvitationStatus status;
  final int revision;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(simpleAdminActionControllerProvider);
    return ListTile(
      minVerticalPadding: AppSpacing.sm,
      leading: Icon(_icon(status)),
      title: Directionality(
        textDirection: TextDirection.ltr,
        child: Text(invitation.email, textAlign: TextAlign.left),
      ),
      subtitle: Text(_label(status)),
      trailing: status == SimpleAdminInvitationStatus.pending
          ? IconButton(
              key: Key('cancel-invitation-${invitation.id}'),
              tooltip: S.simpleAdminCancelInvitation,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: busy ? null : () => _cancel(context, ref),
              icon: const Icon(Icons.close_rounded),
            )
          : null,
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppConfirmation(
      context: context,
      title: S.simpleAdminCancelInvitationTitle,
      // A Latin address inside an Arabic dialog: isolated so the local part
      // and the domain are never reordered around each other.
      identity: invitation.email,
      identityLtr: true,
      change: S.simpleAdminCancelInvitationChange,
      unchanged: S.simpleAdminCancelInvitationUnchanged,
      confirmLabel: S.simpleAdminCancelInvitation,
      // Cancelling is final — the invitation cannot be un-cancelled, only
      // replaced by a new one.
      severity: ConfirmationSeverity.destructive,
      // The confirm label is «إلغاء الدعوة»; a dismiss button also reading
      // «إلغاء» would be two buttons saying cancel.
      dismissLabel: S.dismiss,
    );
    if (!confirmed || !context.mounted) return;
    final result =
        await ref.read(simpleAdminActionControllerProvider.notifier).cancel(
              CancelSimpleAdminInvitationCommand(
                invitationId: invitation.id,
                expectedRevision: revision,
              ),
            );
    if (result == null || !context.mounted) return;
    result.when(
      success: (_, {stale = false}) => ScaffoldMessenger.of(context)
          .showSnackBar(
              const SnackBar(content: Text(S.simpleAdminInvitationCancelled))),
      failure: (_, __) => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(S.simpleAdminActionFailed))),
      offline: (_) => ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(S.offlineTitle))),
    );
  }

  static String _label(SimpleAdminInvitationStatus status) => switch (status) {
        SimpleAdminInvitationStatus.pending => S.simpleAdminInvitationPending,
        SimpleAdminInvitationStatus.cancelled =>
          S.simpleAdminInvitationCancelledStatus,
        SimpleAdminInvitationStatus.accepted => S.simpleAdminInvitationAccepted,
        SimpleAdminInvitationStatus.expired => S.simpleAdminInvitationExpired,
      };

  static IconData _icon(SimpleAdminInvitationStatus status) => switch (status) {
        SimpleAdminInvitationStatus.pending => Icons.schedule_send_outlined,
        SimpleAdminInvitationStatus.cancelled => Icons.cancel_outlined,
        SimpleAdminInvitationStatus.accepted => Icons.check_circle_outline,
        SimpleAdminInvitationStatus.expired => Icons.event_busy_outlined,
      };
}

class SimpleAdminInvitePage extends ConsumerStatefulWidget {
  const SimpleAdminInvitePage({super.key});

  @override
  ConsumerState<SimpleAdminInvitePage> createState() =>
      _SimpleAdminInvitePageState();
}

class _SimpleAdminInvitePageState extends ConsumerState<SimpleAdminInvitePage> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _selected = <String>{...simpleAdminAssignableKeys};
  bool _validated = false;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot =
        ref.watch(simpleAdminSnapshotProvider).valueOrNull?.dataOrNull;
    final submitting = ref.watch(simpleAdminActionControllerProvider);
    final available = _availableDefinitions(ref);
    return Scaffold(
      backgroundColor: context.c.bg,
      appBar: AppBar(title: const Text(S.simpleAdminInvite)),
      body: SafeArea(
        child: ListView(
          key: const Key('simple-admin-invite-form'),
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(S.simpleAdminInviteLead,
                style: TextStyle(color: context.c.ink2, height: 1.6)),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              key: const Key('simple-admin-name'),
              controller: _name,
              enabled: !submitting,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: S.simpleAdminNameLabel,
                errorText: _validated && _name.text.trim().isEmpty
                    ? S.simpleAdminNameRequired
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                key: const Key('simple-admin-email'),
                controller: _email,
                enabled: !submitting,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                textAlign: TextAlign.left,
                decoration: InputDecoration(
                  labelText: S.emailLabel,
                  errorText: _validated && !_validEmail(_email.text)
                      ? S.simpleAdminEmailInvalid
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SectionLabel(S.simpleAdminCapabilities),
            Text(S.simpleAdminCapabilitiesLead,
                style: TextStyle(
                    color: context.c.ink3, fontSize: 12, height: 1.5)),
            const SizedBox(height: AppSpacing.sm),
            CapabilitySelector(
              definitions: available,
              selected: _selected,
              enabled: !submitting,
              onChanged: (key, selected) => setState(() {
                selected ? _selected.add(key) : _selected.remove(key);
              }),
            ),
            if (_validated &&
                _selected
                    .intersection(available.map((d) => d.key).toSet())
                    .isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(S.simpleAdminCapabilityRequired,
                    style: TextStyle(color: context.c.crit)),
              ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              key: const Key('simple-admin-send-invitation'),
              onPressed: submitting || snapshot == null
                  ? null
                  : () => _submit(snapshot, available),
              icon: const Icon(Icons.send_outlined),
              label: Text(submitting
                  ? S.simpleAdminSaving
                  : S.simpleAdminSendInvitation),
            ),
            const SizedBox(height: AppSpacing.sm),
            const _InfoNote(text: S.simpleAdminNoPasswordNote),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(
    SimpleAdminManagementSnapshot snapshot,
    List<SimpleAdminCapabilityDefinition> available,
  ) async {
    setState(() => _validated = true);
    final allowed = available.map((d) => d.key).toSet();
    final selected = _selected.intersection(allowed);
    if (_name.text.trim().isEmpty ||
        !_validEmail(_email.text) ||
        selected.isEmpty) {
      return;
    }
    final result =
        await ref.read(simpleAdminActionControllerProvider.notifier).invite(
              InviteSimpleAdminCommand(
                email: _email.text,
                suggestedName: _name.text,
                capabilityKeys: selected,
                expectedRevision: snapshot.revision,
                idempotencyKey: ref.read(newOperationIdProvider)(),
              ),
            );
    if (result == null || !mounted) return;
    result.when(
      success: (_, {stale = false}) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(S.simpleAdminInvitationSent)));
        context.pop();
      },
      failure: (_, code) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(code == 'admin_invitation_exists'
              ? S.simpleAdminDuplicateInvitation
              : S.simpleAdminActionFailed))),
      offline: (_) => ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(S.offlineTitle))),
    );
  }

  static bool _validEmail(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
}

class SimpleAdminCapabilitiesPage extends ConsumerStatefulWidget {
  const SimpleAdminCapabilitiesPage({super.key, required this.accountId});

  final String accountId;

  @override
  ConsumerState<SimpleAdminCapabilitiesPage> createState() =>
      _SimpleAdminCapabilitiesPageState();
}

class _SimpleAdminCapabilitiesPageState
    extends ConsumerState<SimpleAdminCapabilitiesPage> {
  Set<String>? _selected;

  @override
  Widget build(BuildContext context) {
    final snapshot =
        ref.watch(simpleAdminSnapshotProvider).valueOrNull?.dataOrNull;
    final account =
        snapshot?.accounts.where((a) => a.id == widget.accountId).firstOrNull;
    final available = _availableDefinitions(ref);
    final submitting = ref.watch(simpleAdminActionControllerProvider);
    if (snapshot == null || account == null) {
      return Scaffold(
          appBar: AppBar(title: const Text(S.simpleAdminEditCapabilities)),
          body: const Center(child: CircularProgressIndicator()));
    }
    _selected ??= {...account.capabilities.global};
    return Scaffold(
      backgroundColor: context.c.bg,
      appBar: AppBar(title: const Text(S.simpleAdminEditCapabilities)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(account.name, style: Theme.of(context).textTheme.titleLarge),
            Directionality(
                textDirection: TextDirection.ltr,
                child: Text(account.email, textAlign: TextAlign.left)),
            const SectionLabel(S.simpleAdminCapabilitiesGranted),
            Text(S.simpleAdminCapabilitiesLead,
                style: TextStyle(
                    color: context.c.ink3, fontSize: 12, height: 1.5)),
            const SizedBox(height: AppSpacing.sm),
            CapabilitySelector(
              definitions: available,
              selected: _selected!,
              enabled: !submitting,
              onChanged: (key, selected) => setState(() {
                selected ? _selected!.add(key) : _selected!.remove(key);
              }),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              key: const Key('simple-admin-save-capabilities'),
              onPressed: submitting || _selected!.isEmpty
                  ? null
                  : () => _save(snapshot, account),
              child: Text(submitting ? S.simpleAdminSaving : S.save),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(SimpleAdminManagementSnapshot snapshot,
      SimpleAdminAccount account) async {
    final result = await ref
        .read(simpleAdminActionControllerProvider.notifier)
        .updateCapabilities(
          UpdateSimpleAdminCapabilitiesCommand(
              accountId: account.id,
              capabilityKeys: _selected!,
              expectedRevision: snapshot.revision),
        );
    if (result == null || !mounted) return;
    result.when(
      success: (_, {stale = false}) => context.pop(),
      failure: (_, __) => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(S.simpleAdminActionFailed))),
      offline: (_) => ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(S.offlineTitle))),
    );
  }
}

class CapabilitySelector extends StatelessWidget {
  const CapabilitySelector(
      {super.key,
      required this.definitions,
      required this.selected,
      required this.enabled,
      required this.onChanged});

  final List<SimpleAdminCapabilityDefinition> definitions;
  final Set<String> selected;
  final bool enabled;
  final void Function(String key, bool selected) onChanged;

  /// Point 18B — grouped by module in catalogue order, each group under a
  /// localized heading, so twenty checkboxes read as five small decisions.
  @override
  Widget build(BuildContext context) {
    final groups =
        <SimpleAdminCapabilityGroup, List<SimpleAdminCapabilityDefinition>>{};
    for (final definition in definitions) {
      (groups[definition.group] ??= []).add(definition);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.xs, AppSpacing.md, AppSpacing.xs, AppSpacing.xs),
            child: Semantics(
              header: true,
              child: Text(
                _groupLabel(entry.key),
                style: TextStyle(
                  color: context.c.ink2,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SettingsSection(children: [
            for (final definition in entry.value)
              CheckboxListTile(
                key: Key('capability-${definition.key}'),
                value: selected.contains(definition.key),
                onChanged: enabled
                    ? (value) => onChanged(definition.key, value ?? false)
                    : null,
                title: Text(definition.label),
                subtitle: Text(definition.description),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.sm, 0, AppSpacing.md, 0),
              ),
          ]),
        ],
      ],
    );
  }

  static String _groupLabel(SimpleAdminCapabilityGroup group) =>
      switch (group) {
        SimpleAdminCapabilityGroup.team => S.simpleAdminGroupTeam,
        SimpleAdminCapabilityGroup.shifts => S.simpleAdminGroupShifts,
        SimpleAdminCapabilityGroup.inventory => S.simpleAdminGroupInventory,
        SimpleAdminCapabilityGroup.workshops => S.simpleAdminGroupWorkshops,
        SimpleAdminCapabilityGroup.insights => S.simpleAdminGroupInsights,
      };
}

List<SimpleAdminCapabilityDefinition> _availableDefinitions(WidgetRef ref) {
  final features = ref.watch(currentTenantFeatureAccessProvider);
  return simpleAdminCapabilityCatalogue
      .where((definition) =>
          definition.feature == null ||
          features.isAvailable(definition.feature!))
      .toList(growable: false);
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
            color: context.c.surface,
            border: Border.all(color: context.c.line),
            borderRadius: BorderRadius.circular(AppRadii.lg)),
        child: Text(message,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.c.ink3)),
      );
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
            color: context.c.infoTint,
            borderRadius: BorderRadius.circular(AppRadii.md)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, color: context.c.info, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
              child: Text(text,
                  style: TextStyle(color: context.c.ink, height: 1.5))),
        ]),
      );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(S.simpleAdminLoadFailed),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onRetry, child: const Text(S.retry)),
          ]),
        ),
      );
}

extension _ResultData<T> on Result<T> {
  T? get dataOrNull => switch (this) {
        Success<T>(:final data) => data,
        Failure<T>() || Offline<T>() => null,
      };
}
