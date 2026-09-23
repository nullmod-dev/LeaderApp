import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_info.dart';
import '../../../core/motion/motion_tokens.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../l10n/strings.dart';
import '../data/app_version_providers.dart';
import '../domain/app_version_models.dart';

/// The forced-upgrade screen — a blocking application state.
///
/// ## Why it looks like this
///
/// MTM already has a shape for a full-screen system state: the auth screens,
/// `ErrorStateView` and `EmptyState` all put a tinted tile, a title, a line
/// of explanation and one filled button straight onto `c.bg`. Cards in this
/// app carry *data* — a detachment, a shift, a stock item — so wrapping a
/// system state in one would be a new idiom, not a reused one. This screen
/// follows the state pattern and borrows exactly one thing from the card
/// vocabulary: the bordered `c.surface` row group the settings screens use
/// for label/value pairs, because the two version numbers *are* a label
/// /value pair.
///
/// ## Why there is no way out
///
/// No app bar, so no back arrow. No skip, no later, no close. `PopScope`
/// refuses the system back gesture, and the router's `redirect` sends every
/// other location here for as long as the gate is shut — so even a deep
/// link cannot land inside the app.
///
/// ## Motion
///
/// Nothing here loops and nothing delays the update button. The route
/// itself fades in through the app's shared transition; within the screen
/// only the parts that actually change are cross-faded, at
/// `MotionTokens.short` scaled by the user's level — which is zero at
/// `performance`, so that level gets no animation at all. The checking
/// spinner is looping ambience and is dropped at the levels that turn
/// ambience off, leaving its label behind.
class UpgradeRequiredPage extends ConsumerWidget {
  const UpgradeRequiredPage({super.key});

  /// The one location the router lets through while the gate is shut.
  static const String location = '/upgrade-required';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final t = Theme.of(context).textTheme;
    final state = ref.watch(appVersionProvider);
    final failed = state.status == AppVersionStatus.checkFailed;

    return PopScope(
      // The state is not dismissible: the system back gesture must not close
      // the app out of it either.
      canPop: false,
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xxl,
                AppSpacing.xl,
                AppSpacing.xl,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Brand(failed: failed),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      failed ? S.upgradeCheckFailedTitle : S.upgradeTitle,
                      style: t.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      failed
                          ? (state.message ?? S.upgradeCheckFailedBody)
                          : S.upgradeBody,
                      style: t.bodyMedium?.copyWith(color: c.ink3),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    _VersionCard(minimumVersion: state.minimumVersion),
                    const SizedBox(height: AppSpacing.xxl),
                    const _UpdateButton(),
                    const SizedBox(height: AppSpacing.md),
                    _SecondaryAction(status: state.status),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The mark, the name, and a badge saying what kind of state this is.
///
/// The logo is the launcher artwork, drawn unmodified: no recolour, no
/// redraw, no stretch — a single uniform scale inside a square clip.
class _Brand extends StatelessWidget {
  const _Brand({required this.failed});

  final bool failed;

  static const double _tile = 88;
  static const double _badge = 30;

  /// Uniform zoom that used to crop the legacy file's baked-in white
  /// margin. The Leader mark is exported to its own bounds with transparent
  /// corners, so there is nothing left to crop — zooming it now would cut
  /// 8% off the artwork on every side. Kept as a named constant, and not
  /// inlined away, because the next artwork may need it again.
  static const double _trim = 1.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: _tile,
          height: _tile,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.xxl),
                child: Transform.scale(
                  scale: _trim,
                  child: Image.asset(
                    AppInfo.logoAsset,
                    width: _tile,
                    height: _tile,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
              PositionedDirectional(
                bottom: -AppSpacing.xs,
                start: -AppSpacing.xs,
                child: _StateBadge(failed: failed),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // The Latin wordmark reads left-to-right inside an RTL screen, and
        // it appears once. The full name sits under it as an eyebrow rather
        // than being repeated in the body copy.
        const Directionality(
          textDirection: TextDirection.ltr,
          child: _Wordmark(),
        ),
      ],
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      children: [
        // The tracked wordmark is the Latin name: letter-spacing pulls joined
        // Arabic letters apart, so the Arabic name sits beneath, untracked.
        Text(
          S.productNameEn,
          style: AppTypography.titleLg(c).copyWith(letterSpacing: 1.5),
        ),
        const SizedBox(height: 2),
        Text(
          S.productNameAr,
          style: AppTypography.eyebrow(c).copyWith(letterSpacing: 0),
        ),
      ],
    );
  }
}

/// Small circular glyph on the corner of the mark: an update arrow normally,
/// a dropped-connection glyph when the last check could not complete.
class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.failed});

  final bool failed;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (icon, fg, bg) = failed
        ? (Icons.cloud_off_rounded, c.crit, c.critTint)
        : (Icons.system_update_alt_rounded, c.warn, c.warnTint);
    return AnimatedSwitcher(
      duration: effectiveDuration(context, MotionTokens.short),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: Container(
        key: ValueKey(failed),
        width: _Brand._badge,
        height: _Brand._badge,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          // Rings the badge in the page ground so it reads as sitting on
          // top of the mark rather than inside it.
          border: Border.all(color: c.bg, width: 2),
        ),
        child: Icon(icon, size: 16, color: fg),
      ),
    );
  }
}

/// The two version numbers, in the app's existing label/value row group.
class _VersionCard extends StatelessWidget {
  const _VersionCard({required this.minimumVersion});

  final String? minimumVersion;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        children: [
          const _VersionRow(
            label: S.upgradeCurrentVersion,
            version: AppInfo.version,
          ),
          // Omitted rather than guessed when the backend named no floor.
          if (minimumVersion != null) ...[
            Divider(height: 1, color: c.line),
            _VersionRow(
              label: S.upgradeMinimumVersion,
              version: minimumVersion!,
              emphasised: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.label,
    required this.version,
    this.emphasised = false,
  });

  final String label;
  final String version;

  /// The required version is the number the user is being asked to reach,
  /// so it carries the primary ink; their own version is plain.
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: c.ink3, fontSize: 13)),
          ),
          const SizedBox(width: AppSpacing.md),
          // A version is a technical identifier: Latin digits, forced LTR,
          // exactly as the app already treats times, emails and IPs.
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              version,
              style: AppTypography.digits(
                emphasised ? c.primary : c.ink,
                size: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The primary action. Always enabled and always in the same place: no
/// state on this screen is allowed to put the update out of reach.
class _UpdateButton extends ConsumerWidget {
  const _UpdateButton();

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final outcome =
        await ref.read(appVersionProvider.notifier).openUpdateDestination();
    final message = switch (outcome) {
      UpdateLaunchOutcome.opened => null,
      UpdateLaunchOutcome.copied => S.upgradeLinkCopied,
      UpdateLaunchOutcome.unavailable => S.upgradeLinkUnavailable,
    };
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilledButton.icon(
      onPressed: () => _open(context, ref),
      icon: const Icon(Icons.system_update_alt_rounded),
      label: const Text(S.upgradeAction),
    );
  }
}

/// Under the primary action: the retry, or the fact that a retry is running.
///
/// One slot rather than two, so the composition does not jump between
/// states — only its contents cross-fade.
class _SecondaryAction extends ConsumerWidget {
  const _SecondaryAction({required this.status});

  final AppVersionStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checking = status == AppVersionStatus.checking;
    return AnimatedSwitcher(
      duration: effectiveDuration(context, MotionTokens.short),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: checking
          ? const _CheckingIndicator()
          : OutlinedButton(
              key: const ValueKey('retry'),
              onPressed: () => ref.read(appVersionProvider.notifier).check(),
              child: const Text(S.retry),
            ),
    );
  }
}

class _CheckingIndicator extends StatelessWidget {
  const _CheckingIndicator();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final spec = motionSpec(context);
    return SizedBox(
      key: const ValueKey('checking'),
      // Matches the outlined button it replaces, so nothing reflows.
      height: 48,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // The spinner is looping ambience: at the levels that turn
          // ambience off it goes away and the label carries the state.
          if (spec.ambientLoops) ...[
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.ink3),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Text(
            S.upgradeChecking,
            style: TextStyle(color: c.ink3, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
