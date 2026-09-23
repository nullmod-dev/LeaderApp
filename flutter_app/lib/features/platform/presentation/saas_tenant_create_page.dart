import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion/animated_counter.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings.dart';
import '../data/platform_tenant_fixtures.dart';
import '../data/saas_tenant_providers.dart';
import '../domain/saas_tenant_models.dart';
import '../domain/saas_tenant_validation.dart';
import '../domain/team_code.dart';
import 'saas_tenant_copy.dart';
import 'saas_tenant_routes.dart';
import 'widgets/platform_page.dart';

/// `/platform/tenants/new` — register a SaaS subscriber.
///
/// Four fields and one button. What the form deliberately does **not** ask
/// for: a plan, a price, a seat count, a storage limit, a feature flag, an
/// initial status. Those are Points 7–8, and a field collected now would be a
/// field some screen starts displaying before anything can set it truthfully.
/// Every subscriber registered here starts in a trial with its Main Admin
/// waiting to complete first-time setup, and the form says both in plain words
/// rather than offering a choice that does not exist.
///
/// **No password is generated, shown, or stored — anywhere.** The tempting
/// version of this screen ends with a one-time temporary credential and a Copy
/// button, and §36 of the brief allows it under strict conditions. It is
/// refused for one reason: this client has no honest way to produce or deliver
/// one. A password minted in Dart is not a credential a backend ever agreed
/// to; the real flow proves the Main Admin owns their mailbox by OTP, takes
/// the Team Code, and has them set their own password on first sign-in — and
/// in that flow the client never receives a stored password at any point. So
/// what this form provisions is a *state*: the Main Admin exists, is
/// identified by email, and is `pendingSetup`. Security correctness over
/// visual completeness, and the later authentication Point inherits nothing it
/// has to undo.
class SaasTenantCreatePage extends ConsumerStatefulWidget {
  const SaasTenantCreatePage({super.key});

  static String get location => SaasTenantRoutes.create;

  @override
  ConsumerState<SaasTenantCreatePage> createState() =>
      _SaasTenantCreatePageState();
}

class _SaasTenantCreatePageState extends ConsumerState<SaasTenantCreatePage> {
  final _name = TextEditingController();
  final _adminName = TextEditingController();
  final _adminEmail = TextEditingController();
  late final TextEditingController _code =
      TextEditingController(text: suggestTeamCode(_seed));

  /// Which suggestion is on offer. Bumped by «اقترح رمزا آخر», so the
  /// generator stays a deterministic function of a number a test can pin.
  int _seed = 1;

  /// Field errors, keyed by the wire field name. Populated only after a submit
  /// attempt: marking a field red before the operator has finished typing it
  /// is a form arguing with someone who is still working.
  Map<String, SaasTenantFieldError> _errors = const {};

  /// A non-field refusal — offline, a repository failure, a taken code — as
  /// one sentence above the button.
  String? _banner;

  @override
  void dispose() {
    _name.dispose();
    _adminName.dispose();
    _adminEmail.dispose();
    _code.dispose();
    super.dispose();
  }

  void _suggestAnother() {
    setState(() {
      _seed++;
      _code.text = suggestTeamCode(_seed);
      _errors = {..._errors}..remove('teamCode');
    });
  }

  SaasTenantDraft get _draft => SaasTenantDraft(
        displayName: _name.text,
        mainAdminName: _adminName.text,
        mainAdminEmail: _adminEmail.text,
        teamCode: _code.text,
      );

  Future<void> _submit() async {
    setState(() {
      _errors = const {};
      _banner = null;
    });

    final outcome = await ref
        .read(saasTenantCreateControllerProvider.notifier)
        .create(_draft);
    if (!mounted) return;

    switch (outcome) {
      case SaasTenantCreated(:final tenant):
        // `pushReplacement`: the form has done its job and the operator wants
        // the record, not a back button that returns to a filled-in form whose
        // submit would now be refused as a duplicate code.
        context.pushReplacement(SaasTenantRoutes.detail(tenant.id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(S.platformTenantCreateDone)),
        );
      case SaasTenantCreateInvalid(:final fieldErrors):
        setState(() {
          _errors = fieldErrors;
          _banner = S.platformTenantCreateInvalid;
        });
      case SaasTenantCodeTaken():
        setState(() {
          _errors = {'teamCode': SaasTenantFieldError.duplicateTeamCode};
          _banner = S.platformTenantCodeTaken;
        });
      case SaasTenantCreateOffline():
        setState(() => _banner = S.platformTenantCreateOffline);
      case SaasTenantCreateFailed():
        setState(() => _banner = S.platformTenantCreateFailed);
      // A second submit while the first is in flight. Nothing was sent and
      // nothing is said: the button is already showing that work is happening.
      case SaasTenantCreateIgnored():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final busy = ref.watch(saasTenantCreateControllerProvider);

    return PlatformPage(
      title: S.platformTenantCreateTitle,
      children: [
        Text(
          S.platformTenantCreateLead,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: c.ink3, height: 1.6),
        ),
        const SizedBox(height: AppSpacing.xl),
        _Field(
          fieldKey: const Key('platform-tenant-name-field'),
          controller: _name,
          label: S.platformTenantNameLabel,
          hint: S.platformTenantNameHint,
          error: _errors['displayName'],
          maxLength: kTeamNameMaxLength,
          enabled: !busy,
        ),
        _Field(
          fieldKey: const Key('platform-tenant-admin-name-field'),
          controller: _adminName,
          label: S.platformTenantAdminNameLabel,
          error: _errors['mainAdminName'],
          maxLength: kMainAdminNameMaxLength,
          enabled: !busy,
        ),
        _Field(
          fieldKey: const Key('platform-tenant-admin-email-field'),
          controller: _adminEmail,
          label: S.platformTenantAdminEmailLabel,
          help: S.platformTenantAdminEmailHelp,
          error: _errors['mainAdminEmail'],
          keyboardType: TextInputType.emailAddress,
          // An address is Latin and must lay out LTR even while the label
          // beside it is Arabic.
          ltr: true,
          enabled: !busy,
        ),
        _Field(
          fieldKey: const Key('platform-tenant-code-field'),
          controller: _code,
          label: S.platformTenantCodeLabel,
          help: S.platformTenantCodeHelp,
          error: _errors['teamCode'],
          ltr: true,
          enabled: !busy,
          // Typed in the alphabet the code is written in, and upper-cased as
          // it is typed so what the operator sees is what is compared.
          formatters: [
            FilteringTextInputFormatter.allow(RegExp('[0-9a-zA-Z-]')),
            TextInputFormatter.withFunction(
              (_, next) => next.copyWith(text: next.text.toUpperCase()),
            ),
            LengthLimitingTextInputFormatter(
              kTeamCodePrefix.length +
                  kTeamCodeGroups * (kTeamCodeGroupSize + 1),
            ),
          ],
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('platform-tenant-code-suggest'),
            onPressed: busy ? null : _suggestAnother,
            icon: const Icon(Icons.autorenew_rounded, size: 18),
            label: const Text(S.platformTenantCodeSuggest),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const _ProvisioningNote(),
        if (_banner != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _Banner(message: _banner!),
        ],
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          key: const Key('platform-tenant-submit'),
          // Disabled while in flight so the operator is told; the guard that
          // actually stops a second registration is in the controller, because
          // a disabled button is a picture of a rule and not the rule.
          onPressed: busy ? null : _submit,
          child: Text(
            busy
                ? S.platformTenantCreateSubmitting
                : S.platformTenantCreateSubmit,
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.enabled,
    this.hint,
    this.help,
    this.error,
    this.maxLength,
    this.keyboardType,
    this.ltr = false,
    this.formatters,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final bool enabled;
  final String? hint;
  final String? help;
  final SaasTenantFieldError? error;
  final int? maxLength;
  final TextInputType? keyboardType;

  /// Whether the *value* is a technical Latin string. The label and the error
  /// stay Arabic and RTL; only the input's own text direction flips.
  final bool ltr;

  final List<TextInputFormatter>? formatters;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      key: fieldKey,
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      textDirection: ltr ? TextDirection.ltr : null,
      textAlign: ltr ? TextAlign.left : TextAlign.start,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: help,
        helperMaxLines: 3,
        errorText: error == null ? null : tenantFieldErrorLabel(error!),
        errorMaxLines: 2,
        counterText: '',
      ),
      maxLength: maxLength,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: field,
    );
  }
}

/// The one paragraph that says what creation actually provisions.
///
/// It is on the screen rather than only in this file's header because the
/// absence of a temporary password is a design decision the operator has to
/// understand — otherwise the first thought on seeing no credential is that
/// the form is unfinished.
class _ProvisioningNote extends StatelessWidget {
  const _ProvisioningNote();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      key: const Key('platform-tenant-provisioning-note'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.infoTint,
        border: Border.all(color: c.info),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${S.platformTenantTrialNote}'
            '${toArabicIndic(kDefaultTrialDays.toString())}'
            '${S.platformTenantTrialDays}',
            style: TextStyle(color: c.ink, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            S.platformTenantProvisioningNote,
            style: TextStyle(color: c.ink2, fontSize: 12, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      key: const Key('platform-tenant-create-banner'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.critTint,
        border: Border.all(color: c.crit),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: c.crit),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: c.ink, fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
