/// Field-level rules for creating a `SaasTenant`, as pure functions.
///
/// **One statement of each rule, read twice.** The create form reads them to
/// decide what to show under a field, and the repository reads them again to
/// decide whether to accept the draft at all. A form that validated on its own
/// would let a caller past by calling `create` directly, and two copies of an
/// email rule is two email rules.
library;

import 'saas_tenant_models.dart';
import 'team_code.dart';

/// The longest team name the platform stores. Generous — a real team name is
/// far shorter, and this exists so a paste of a whole paragraph is refused at
/// the field rather than at the far end.
const int kTeamNameMaxLength = 80;
const int kMainAdminNameMaxLength = 80;
const int kMainAdminEmailMaxLength = 254;

/// Why one field was refused. Presentation maps these to Arabic copy.
enum SaasTenantFieldError {
  required,
  tooLong,

  /// Not shaped like an email address.
  invalidEmail,

  /// Not shaped like a Team Code.
  invalidTeamCode,

  /// Well-formed, but already assigned to another tenant. Only the repository
  /// can decide this; the form may show it optimistically from the page it has
  /// already loaded, and is corrected by the repository's answer.
  duplicateTeamCode,
}

/// Deliberately permissive, and that is the design.
///
/// A client cannot know whether an address exists; it can only refuse the
/// shapes that are certainly not addresses. Anything stricter rejects real
/// mailboxes — the plus-addressed, the apostrophed, the long-TLD — and the
/// only honest proof of an address is the ownership check the later
/// authentication flow performs by sending mail to it.
final RegExp _email = RegExp(r'^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$');

SaasTenantFieldError? validateTeamName(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return SaasTenantFieldError.required;
  if (value.length > kTeamNameMaxLength) return SaasTenantFieldError.tooLong;
  return null;
}

SaasTenantFieldError? validateMainAdminName(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return SaasTenantFieldError.required;
  if (value.length > kMainAdminNameMaxLength) {
    return SaasTenantFieldError.tooLong;
  }
  return null;
}

SaasTenantFieldError? validateMainAdminEmail(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return SaasTenantFieldError.required;
  if (value.length > kMainAdminEmailMaxLength) {
    return SaasTenantFieldError.tooLong;
  }
  return _email.hasMatch(value) ? null : SaasTenantFieldError.invalidEmail;
}

SaasTenantFieldError? validateTeamCodeField(String raw) =>
    switch (validateTeamCode(raw)) {
      TeamCodeError.empty => SaasTenantFieldError.required,
      TeamCodeError.malformed => SaasTenantFieldError.invalidTeamCode,
      null => null,
    };

/// Every field error in [draft], keyed by field name.
///
/// The keys match the wire field names in `API_CONTRACT.md`, so a future `422`
/// carrying `fieldErrors` lands on the same inputs without a translation
/// table.
Map<String, SaasTenantFieldError> validateDraft(SaasTenantDraft draft) {
  final errors = <String, SaasTenantFieldError>{};
  void put(String field, SaasTenantFieldError? error) {
    if (error != null) errors[field] = error;
  }

  put('displayName', validateTeamName(draft.displayName));
  put('mainAdminName', validateMainAdminName(draft.mainAdminName));
  put('mainAdminEmail', validateMainAdminEmail(draft.mainAdminEmail));
  put('teamCode', validateTeamCodeField(draft.teamCode));
  return errors;
}
