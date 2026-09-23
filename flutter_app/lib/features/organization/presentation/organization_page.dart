import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings.dart';
import '../../about/presentation/about_page.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../../shell/main_shell.dart';
import '../domain/organization_models.dart';
import 'organization_copy.dart';
import 'organization_widgets.dart';
import 'plan_page.dart';

/// Organization (`/more/organization`) — which organisation this account
/// operates under, and its current standing. Point 15.
///
/// **Read-only by design.** There is no organisation-editing contract a
/// tenant session is authorized for, so nothing here edits, renames,
/// regenerates, suspends or deletes. What the platform owns is said to be
/// platform-owned, with the way to reach support beside it.
///
/// **What is deliberately absent.** The Team Code (control-plane owned; no
/// tenant-side read is authorized — `HANDOFF.md` Point 15), the Main Admin's
/// login email and account state (Point 14 keeps those Platform-only), and
/// the pre-SaaS profile fields of `SettingsRepository.orgInfo` (legal name,
/// address, public email), which came from a second record that disagreed
/// with the canonical tenant name.
///
/// Readable by both tenant roles: nothing on it is an organisation-wide
/// figure, which is what `org.edit` gates. Usage counts live on Plan, where
/// the read itself withholds them from a session without that key.
class OrganizationPage extends StatelessWidget {
  const OrganizationPage({super.key});

  static const routePath = '/more/organization';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.c.bg,
      appBar: AppBar(title: const Text(S.settingsOrg)),
      body: FloatingNavPadding(
        child: OrganizationPageWidth(
          child: OrganizationReadView(
            builder: (context, snapshot, freshness) => _OrganizationContent(
              snapshot: snapshot,
              freshness: freshness,
            ),
          ),
        ),
      ),
    );
  }
}

class _OrganizationContent extends StatelessWidget {
  const _OrganizationContent({required this.snapshot, required this.freshness});

  final OrganizationSnapshot snapshot;
  final OrganizationFreshness freshness;

  @override
  Widget build(BuildContext context) {
    final createdAt = snapshot.createdAt;
    final mainAdmin = snapshot.mainAdminName;
    return ListView(
      key: const Key('organization-page'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        OrganizationFreshnessNotice(
          freshness: freshness,
          readAt: snapshot.readAt,
        ),
        OrganizationColumns(
          start: [
            _Identity(snapshot: snapshot),
            const OrganizationSectionTitle(S.orgSectionDetails),
            SettingsSection(children: [
              if (createdAt != null)
                OrganizationFact(
                  key: const Key('org-registered'),
                  icon: Icons.event_outlined,
                  label: S.orgRegisteredLabel,
                  value: Text(OrganizationCopy.date(createdAt)),
                ),
              if (mainAdmin != null)
                OrganizationFact(
                  key: const Key('org-main-admin'),
                  icon: Icons.person_outline_rounded,
                  label: S.orgMainAdminLabel,
                  value: Text(mainAdmin),
                ),
              _TenantReference(tenantId: snapshot.tenantId),
            ]),
          ],
          end: [
            const OrganizationSectionTitle(S.orgSectionPlan),
            SettingsSection(children: [
              NavigationRow(
                key: const Key('org-open-plan'),
                icon: Icons.layers_outlined,
                label: OrganizationCopy.planTitle(snapshot.subscription.plan),
                subtitle: S.orgPlanRowSubtitle,
                onTap: () => context.push(PlanPage.routePath),
              ),
            ]),
            const SizedBox(height: AppSpacing.lg),
            OrganizationNote(
              key: const Key('org-managed-note'),
              icon: Icons.info_outline_rounded,
              body: S.orgManagedNote,
              action: TextButton.icon(
                key: const Key('org-contact-support'),
                onPressed: () => context.push(AboutPage.routePath),
                icon: const Icon(Icons.support_agent_rounded, size: 18),
                label: const Text(S.contactSupport),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The organisation's name, its mark and its two independent states.
///
/// Access (tenant lifecycle) and subscription (commercial) are two chips on
/// purpose: an organisation in a grace period still has active access, and
/// merging the two into one badge is the mistake Point 7 undid.
class _Identity extends StatelessWidget {
  const _Identity({required this.snapshot});

  final OrganizationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final lifecycle = snapshot.lifecycle;
    final status = snapshot.subscription.status;
    final accessLabel = OrganizationCopy.access(lifecycle);
    final subscriptionLabel = OrganizationCopy.subscription(status);
    return Column(
      key: const Key('org-identity'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Monogram(name: snapshot.displayName),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  snapshot.displayName,
                  key: const Key('org-name'),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700, height: 1.35),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            OrganizationStatusChip(
              key: const Key('org-access-chip'),
              label: accessLabel,
              kind: OrganizationCopy.accessKind(lifecycle),
              icon: OrganizationCopy.accessIcon(lifecycle),
              announcement: accessLabel,
            ),
            OrganizationStatusChip(
              key: const Key('org-subscription-chip'),
              label: subscriptionLabel,
              kind: OrganizationCopy.subscriptionKind(status),
              icon: OrganizationCopy.subscriptionIcon(status),
              announcement: S.orgSubscriptionAnnouncement
                  .replaceFirst('%s', subscriptionLabel),
            ),
          ],
        ),
      ],
    );
  }
}

/// The organisation's initial on a tinted tile — its mark in this app.
///
/// Derived from the name the organisation chose, so two organisations do not
/// share one generic building icon. The Arabic definite article is skipped:
/// «الهلال» is recognised by «ه», not by the «ا» every such name starts with.
class _Monogram extends StatelessWidget {
  const _Monogram({required this.name});

  final String name;

  static String initialOf(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    var word = words.isEmpty ? '' : words.first;
    if (word.startsWith('ال') && word.length > 3) word = word.substring(2);
    if (word.isEmpty) return '';
    return String.fromCharCode(word.runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ExcludeSemantics(
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.primaryTint,
          border: Border.all(color: c.primary.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Text(
          initialOf(name),
          style: TextStyle(
            color: c.primary,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
          textScaler: TextScaler.noScaling,
        ),
      ),
    );
  }
}

/// The organisation's support reference: LTR, selectable and copyable.
///
/// Shows [OrganizationCopy.supportReference] rather than the raw tenant id —
/// a customer has no use for a control-plane slug, and what they *do* need is
/// something to quote to support. Copying copies what is shown, so the two
/// can never disagree.
class _TenantReference extends StatelessWidget {
  const _TenantReference({required this.tenantId});

  final String tenantId;

  @override
  Widget build(BuildContext context) {
    final reference = OrganizationCopy.supportReference(tenantId);
    return OrganizationFact(
      key: const Key('org-reference'),
      icon: Icons.tag_rounded,
      label: S.orgIdLabel,
      help: S.orgIdHelp,
      // A Latin identifier inside Arabic: isolated LTR so its underscore and
      // letters are never reordered around the label.
      value: Directionality(
        textDirection: TextDirection.ltr,
        child: SelectableText(
          reference,
          key: const Key('org-reference-value'),
          style: const TextStyle(fontSize: 14, letterSpacing: 0.2),
        ),
      ),
      trailing: IconButton(
        key: const Key('org-reference-copy'),
        tooltip: S.orgIdCopy,
        icon: const Icon(Icons.copy_rounded, size: 20),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: reference));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(S.orgIdCopied)),
          );
        },
      ),
    );
  }
}
