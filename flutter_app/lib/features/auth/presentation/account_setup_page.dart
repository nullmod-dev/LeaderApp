import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings.dart';
import '../data/onboarding_controller.dart';
import '../domain/onboarding_models.dart';
import '../domain/onboarding_repository.dart';
import '_auth_scaffold.dart';
import 'onboarding_ui.dart';

/// `/account-setup` — Point 17B.
///
/// Re-scoped from the Point 17A holding page. Collects only what §11 of the
/// brief approves: a display name. No Terms/Privacy, no role picker, no
/// capability picker, no tenant picker, no MFA enrolment — all deliberately
/// deferred (`HANDOFF.md` "POINT 17A" §H). Completion runs
/// `OnboardingRepository.completeSetup`, which on the backend also performs
/// the Point 14 Main Admin seat transition when the linked authorization is a
/// seat; this screen never decides that itself.
class AccountSetupPage extends ConsumerStatefulWidget {
  const AccountSetupPage({super.key});

  @override
  ConsumerState<AccountSetupPage> createState() => _AccountSetupPageState();
}

class _AccountSetupPageState extends ConsumerState<AccountSetupPage> {
  final _name = TextEditingController();
  bool _prefilled = false;
  bool _busy = false;
  String? _error;
  bool _offline = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
      _offline = false;
    });
    final result = await ref
        .read(onboardingControllerProvider.notifier)
        .completeSetup(displayName: _name.text);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case Success(:final data):
        switch (data) {
          case EntryReady():
            await awaitFullSessionReady(ref);
            if (!mounted) return;
            context.go('/home');
          case EntryVerificationRequired():
          case EntryContinueOnboarding():
            // The mock never answers `completeSetup` either way; kept
            // exhaustive for a real backend.
            break;
        }
      case Failure():
        setState(() =>
            _error = onboardingErrorMessage(onboardingErrorKindOf(result)!));
      case Offline():
        setState(() => _offline = true);
    }
  }

  /// The "state moved under you" retry for a snapshot that already says
  /// `setup: completed` — the exchange this screen owns finishing
  /// (`HANDOFF.md` "POINT 17A" §K). Re-reads the authoritative snapshot; a
  /// backend that has genuinely finished the exchange answers with
  /// `setup_already_completed`, which the controller turns into
  /// `EntryNone(notice: setupCompletedElsewhere)` — the classifier then sends
  /// the app to `/login`, where that notice explains what happened.
  Future<void> _retryExchange() async {
    setState(() {
      _busy = true;
      _offline = false;
    });
    final result =
        await ref.read(onboardingControllerProvider.notifier).refresh();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result case Offline()) setState(() => _offline = true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final entry = ref.watch(authEntryStateProvider);
    if (entry is! EntryOnboarding || entry.snapshot.tenant == null) {
      return const AuthScaffold(
        title: S.accountSetupTitle,
        subtitle: '',
        child: SizedBox.shrink(),
      );
    }
    final snapshot = entry.snapshot;
    final tenant = snapshot.tenant!;

    if (!_prefilled) {
      _prefilled = true;
      _name.text = snapshot.displayNameSuggestion ?? '';
    }

    if (snapshot.setup == AccountSetupStatus.completed) {
      return AuthScaffold(
        title: S.accountSetupTitle,
        subtitle: tenant.displayName,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Column(
                children: [
                  const SizedBox(height: AppSpacing.md),
                  const CircularProgressIndicator(strokeWidth: 2),
                  const SizedBox(height: AppSpacing.lg),
                  Text(S.settingUpNotice, style: TextStyle(color: c.ink2)),
                ],
              ),
            ),
            if (_offline) ...[
              const SizedBox(height: AppSpacing.xl),
              const OnboardingOfflineNotice(),
            ],
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton(
              onPressed: _busy ? null : _retryExchange,
              child: const Text(S.retry),
            ),
            const SizedBox(height: AppSpacing.xl),
            const OnboardingExitRow(),
          ],
        ),
      );
    }

    return AuthScaffold(
      title: S.accountSetupTitle,
      subtitle: tenant.displayName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Row(
              children: [
                Icon(Icons.groups_outlined, color: c.primary, size: 22),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tenant.displayName,
                          style: TextStyle(
                              color: c.ink, fontWeight: FontWeight.w600)),
                      Text(onboardingRoleLabel(tenant.role),
                          style: TextStyle(color: c.ink3, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          TextField(
            key: const Key('setup-display-name'),
            controller: _name,
            readOnly: _busy,
            decoration: const InputDecoration(labelText: S.displayNameLabel),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          if (_offline) ...[
            const SizedBox(height: AppSpacing.md),
            const OnboardingOfflineNotice(),
          ] else if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            OnboardingErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppSpacing.xl),
          OnboardingPrimaryButton(
            label: S.completeSetupAction,
            busy: _busy,
            onPressed: _submit,
          ),
          const SizedBox(height: AppSpacing.xl),
          const OnboardingExitRow(),
        ],
      ),
    );
  }
}
