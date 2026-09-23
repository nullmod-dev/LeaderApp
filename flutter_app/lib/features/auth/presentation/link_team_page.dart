import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/startup/startup_destination.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/forward_chevron.dart';
import '../../../l10n/strings.dart';
import '../data/customer_demo_controller.dart';
import '../data/onboarding_controller.dart';
import '../domain/onboarding_models.dart';
import '../domain/onboarding_repository.dart';
import '_auth_scaffold.dart';
import 'onboarding_ui.dart';

/// `/link-team` — Point 17B.
///
/// **The Team Code path only.** The invitation-bound path (a Simple Admin
/// invitation the backend already resolved to a tenant) never reaches this
/// screen at all: `MockOnboardingRepository` links such an account the
/// moment it verifies, so its snapshot already arrives `linked` and the
/// classifier sends it straight to `/account-setup`, which shows the tenant
/// name and role as the "safe organisation confirmation" the invitation path
/// needs (`HANDOFF.md` "POINT 17A" §9/§K). A snapshot only lands here when
/// [OnboardingSnapshot.link] is `unlinked` or `withdrawn` — the case that
/// genuinely needs a code, chiefly the initial Main Admin.
///
/// **Point 17C:** an invitee can still land here — verified before the
/// invitation was sent, or its invitation was withdrawn/expired and later
/// reissued. It has no Team Code, so the screen also offers "check for my
/// invitation": a plain `refresh()`, on which the backend links any valid
/// invitation for this verified address, moving the invitee on to
/// `/account-setup`. This screen never learns whether an invitation exists
/// until one links.
///
/// **Point 18B — the verified, unlinked identity's one decision.** An
/// `unlinked` snapshot first sees two options: **الانضمام إلى فريق** (the Team
/// Code form below) or **تجربة ليدر** (the isolated Customer Demo). It is a
/// state of this route, not a route of its own, so the startup classifier is
/// unchanged and its precedence holds by construction: a valid Simple Admin
/// invitation arrives `linked` and goes to `/account-setup` without ever
/// rendering this screen, and reaching it at all means identity is already
/// proved — by the code for a password sign-up, by the backend's own
/// `email_verified` verdict for Google (no second code). A `withdrawn`
/// account already chose a team, so it opens on the Team Code form.
///
/// Choosing the demo never links, never spends a Team Code and never creates
/// a tenant relationship: it starts the same isolated demo session `/login`
/// starts and discards this device's restricted onboarding session
/// ([CustomerDemoController.start] with `leavingOnboarding`).
class LinkTeamPage extends ConsumerStatefulWidget {
  const LinkTeamPage({super.key});

  @override
  ConsumerState<LinkTeamPage> createState() => _LinkTeamPageState();
}

class _LinkTeamPageState extends ConsumerState<LinkTeamPage> {
  final _code = TextEditingController();
  bool _busy = false;
  bool _checking = false;
  bool _noInvitation = false;
  String? _error;
  bool _offline = false;

  /// "الانضمام إلى فريق" was chosen on the Point 18B chooser.
  bool _teamChosen = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _noInvitation = false;
      _error = null;
      _offline = false;
    });
    final result = await ref
        .read(onboardingControllerProvider.notifier)
        .linkTeam(_code.text);
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      success: (snapshot, {stale = false}) {
        // Never restored, whichever screen comes next.
        _code.clear();
        context.go(onboardingDestination(snapshot).location!);
      },
      failure: (_, __) {
        final kind = onboardingErrorKindOf(result)!;
        setState(() => _error = onboardingErrorMessage(kind));
      },
      offline: (_) => setState(() => _offline = true),
    );
  }

  Future<void> _checkInvitation() async {
    setState(() {
      _checking = true;
      _noInvitation = false;
      _error = null;
      _offline = false;
    });
    final result =
        await ref.read(onboardingControllerProvider.notifier).refresh();
    if (!mounted) return;
    setState(() => _checking = false);
    result.when(
      success: (snapshot, {stale = false}) {
        if (snapshot.link == TenantLinkStatus.linked) {
          _code.clear();
          context.go(onboardingDestination(snapshot).location!);
        } else {
          // An answer, not an error: shown beside the button that asked.
          setState(() => _noInvitation = true);
        }
      },
      failure: (_, __) {
        final kind = onboardingErrorKindOf(result);
        if (kind != null) {
          setState(() => _error = onboardingErrorMessage(kind));
        }
      },
      offline: (_) => setState(() => _offline = true),
    );
  }

  Future<void> _startDemo() async {
    setState(() {
      _noInvitation = false;
      _error = null;
      _offline = false;
    });
    final result = await ref
        .read(customerDemoControllerProvider.notifier)
        .start(leavingOnboarding: true);
    if (result == null || !mounted) return;
    result.when(
      success: (_, {stale = false}) => context.go('/home'),
      failure: (_, __) => setState(() => _error = S.customerDemoUnavailable),
      offline: (_) => setState(() => _offline = true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final entry = ref.watch(authEntryStateProvider);
    if (entry is! EntryOnboarding) {
      return const AuthScaffold(
        title: S.teamLinkTitle,
        subtitle: '',
        child: SizedBox.shrink(),
      );
    }
    final snapshot = entry.snapshot;
    final choosing = !_teamChosen && snapshot.link == TenantLinkStatus.unlinked;
    if (choosing) return _chooser(snapshot);
    return AuthScaffold(
      title: S.teamLinkTitle,
      subtitle: '${S.signedInAs}\u2066${snapshot.email}\u2069',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (snapshot.link == TenantLinkStatus.withdrawn) ...[
            const OnboardingErrorBanner(message: S.teamLinkWithdrawnNotice),
            const SizedBox(height: AppSpacing.md),
          ],
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              key: const Key('team-code'),
              controller: _code,
              readOnly: _busy,
              autofocus: true,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [UpperCaseTextFormatter()],
              decoration: const InputDecoration(
                labelText: S.teamCodeLabel,
                hintText: S.teamCodeHint,
              ),
              onSubmitted: (_) => _submit(),
            ),
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
            label: S.linkTeamAction,
            busy: _busy,
            onPressed: _submit,
          ),
          if (snapshot.link == TenantLinkStatus.unlinked) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              key: const Key('onboarding-choice-back'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _teamChosen = false;
                        _error = null;
                        _offline = false;
                      }),
              child: const Text(S.onboardingChoiceBack),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          ..._invitationCheck(c),
          const SizedBox(height: AppSpacing.xl),
          const OnboardingExitRow(),
        ],
      ),
    );
  }

  /// Point 18B — Team or Demo. The invitation check stays reachable here
  /// too: an invitee who verified before its invitation existed lands on
  /// this state first (Point 17C).
  Widget _chooser(OnboardingSnapshot snapshot) {
    final c = context.c;
    final demoPolicy = ref.watch(customerDemoPolicyProvider);
    final startingDemo = ref.watch(customerDemoControllerProvider);
    final locked = _checking || startingDemo;
    return AuthScaffold(
      title: S.onboardingChoiceTitle,
      subtitle: '${S.signedInAs}\u2066${snapshot.email}\u2069',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            S.onboardingChoiceLead,
            style: TextStyle(color: c.ink2, fontSize: 14, height: 1.6),
          ),
          const SizedBox(height: AppSpacing.lg),
          OnboardingChoiceCard(
            key: const Key('onboarding-choice-team'),
            icon: Icons.groups_2_outlined,
            title: S.onboardingChoiceTeam,
            body: S.onboardingChoiceTeamSub,
            onTap: locked
                ? null
                : () => setState(() {
                      _teamChosen = true;
                      _noInvitation = false;
                      _error = null;
                      _offline = false;
                    }),
          ),
          const SizedBox(height: AppSpacing.md),
          OnboardingChoiceCard(
            key: const Key('onboarding-choice-demo'),
            icon: Icons.science_outlined,
            title: S.onboardingChoiceDemo,
            body: S.onboardingChoiceDemoSub,
            busy: startingDemo,
            busyLabel: S.customerDemoStarting,
            // Closed by the platform: said in words, never only greyed out,
            // and never a quiet fall-through into a real tenant.
            unavailableNote:
                demoPolicy.available ? null : S.customerDemoUnavailable,
            onTap: locked || !demoPolicy.available ? null : _startDemo,
          ),
          if (_offline) ...[
            const SizedBox(height: AppSpacing.md),
            const OnboardingOfflineNotice(),
          ] else if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            OnboardingErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppSpacing.xl),
          ..._invitationCheck(c, disabled: startingDemo),
          const SizedBox(height: AppSpacing.xl),
          const OnboardingExitRow(),
        ],
      ),
    );
  }

  List<Widget> _invitationCheck(AppColors c, {bool disabled = false}) => [
        Text(
          S.teamLinkInvitationHint,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.ink2, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          key: const Key('check-invitation'),
          onPressed: _busy || _checking || disabled ? null : _checkInvitation,
          child: const Text(S.checkInvitationAction),
        ),
        if (_noInvitation) ...[
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            liveRegion: true,
            child: Text(
              S.noInvitationYet,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.ink2, fontSize: 13),
            ),
          ),
        ],
      ];
}

/// One option on the Point 18B chooser: a full-width, ≥48dp tappable card
/// whose state is always stated in words (a progress label, an
/// "unavailable" line) and never by colour alone.
class OnboardingChoiceCard extends StatelessWidget {
  const OnboardingChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
    this.busy = false,
    this.busyLabel,
    this.unavailableNote,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onTap;
  final bool busy;
  final String? busyLabel;
  final String? unavailableNote;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final enabled = onTap != null;
    final muted = !enabled && !busy;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: BorderSide(color: c.line2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: muted ? c.surface2 : c.primaryTint,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    alignment: Alignment.center,
                    child: busy
                        ? SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: c.primary),
                          )
                        : Icon(icon,
                            size: 22, color: muted ? c.ink3 : c.primary),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          busy ? (busyLabel ?? title) : title,
                          style: TextStyle(
                            color: muted ? c.ink3 : c.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          body,
                          style: TextStyle(
                              color: c.ink2, fontSize: 13, height: 1.5),
                        ),
                        if (unavailableNote != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: [
                              Icon(Icons.block_rounded,
                                  size: 16, color: c.ink2),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Text(
                                  unavailableNote!,
                                  style: TextStyle(
                                    color: c.ink2,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ForwardChevron(color: muted ? c.line2 : c.ink3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Uppercases as the person types. The Team Code alphabet has no lowercase
/// letters, so this never fights `normalizeTeamCodeInput`'s own folding — it
/// only saves a courtesy round trip through the shift key.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      TextEditingValue(
        text: newValue.text.toUpperCase(),
        selection: newValue.selection,
      );
}
