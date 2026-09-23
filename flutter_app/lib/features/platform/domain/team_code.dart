/// The Team Code — a SaaS tenant's platform-assigned link identifier.
///
/// **What it is.** A short, readable, unambiguous handle that identifies one
/// `SaasTenant` during a future verified first-time link (`API_CONTRACT.md` —
/// "First-time setup"). A Main Admin who joins their team quotes it; support
/// quotes it; the Super Admin assigns it.
///
/// **What it is not, and the reason this file has a header.** It is *not* a
/// credential. It authenticates nobody on its own, it is shown in plain sight
/// on the tenant detail screen, and the linking flow that will consume it also
/// requires email-ownership proof. Formatting it like a password — long,
/// mixed-case, punctuated — would teach an operator to treat it as one, and
/// the first consequence of that is somebody refusing to read it aloud to the
/// customer who needs it. So it is grouped, upper-case and Latin, and it looks
/// like an order number.
///
/// **Platform-controlled.** Assigned at creation by the Super Admin and
/// immutable thereafter in this Point; the tenant application never offers an
/// edit. Nothing in the tenant feature tree imports this file.
library;

/// The alphabet a code may use.
///
/// Digits and upper-case Latin minus `I`, `O`, `L`, `U`, `0`, `1` — the pairs
/// that are misread when a code is copied off a screen onto paper or dictated
/// over a phone, plus `U` because it is the letter people hear as "you". A
/// code is going to be transcribed by humans, which is the whole design
/// constraint.
const String kTeamCodeAlphabet = '23456789ABCDEFGHJKMNPQRSTVWXYZ';

/// The fixed prefix. Present so a code is recognisable as one when it appears
/// on its own in an email or a support ticket.
const String kTeamCodePrefix = 'MTM';

/// Characters per group, and how many groups follow the prefix.
const int kTeamCodeGroupSize = 4;
const int kTeamCodeGroups = 2;

/// `MTM-4K7P-QX92` — the canonical rendering, and the only accepted one after
/// [normalizeTeamCode].
final RegExp _canonical = RegExp(
  '^$kTeamCodePrefix'
  '(-[$kTeamCodeAlphabet]{$kTeamCodeGroupSize}){$kTeamCodeGroups}\$',
);

/// Why a typed code was refused. Presentation maps these to Arabic copy; the
/// repository maps [TeamCodeError.malformed] to `invalid_tenant_code`.
enum TeamCodeError {
  /// Nothing was typed.
  empty,

  /// Typed, but not a Team Code: wrong prefix, wrong length, or a character
  /// outside [kTeamCodeAlphabet].
  malformed,
}

/// [raw] in canonical comparison form: upper-cased, every separator and space
/// removed, then regrouped.
///
/// Accepts what an operator actually pastes — `mtm 4k7p qx92`,
/// `MTM4K7PQX92`, `mtm-4k7p-qx92` — and produces one spelling, so the
/// uniqueness check cannot be defeated by punctuation. A string that is not a
/// code at all comes back stripped rather than repaired, and [validateTeamCode]
/// then refuses it.
String normalizeTeamCode(String raw) {
  final bare = raw.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
  if (!bare.startsWith(kTeamCodePrefix)) return bare;
  final body = bare.substring(kTeamCodePrefix.length);
  final groups = <String>[];
  for (var i = 0; i < body.length; i += kTeamCodeGroupSize) {
    groups.add(body.substring(
      i,
      i + kTeamCodeGroupSize > body.length
          ? body.length
          : i + kTeamCodeGroupSize,
    ));
  }
  return [kTeamCodePrefix, ...groups].join('-');
}

/// `null` when [raw] is a well-formed Team Code, the reason otherwise.
///
/// **Format only.** Uniqueness is not a client fact — see
/// `SaasTenantRepository.create`, which is the authority, and
/// `API_CONTRACT.md`, which records that the backend must enforce it.
TeamCodeError? validateTeamCode(String raw) {
  if (raw.trim().isEmpty) return TeamCodeError.empty;
  return _canonical.hasMatch(normalizeTeamCode(raw))
      ? null
      : TeamCodeError.malformed;
}

/// A deterministic code drawn from [seed].
///
/// **A seam, not a security primitive.** It exists so the create form can
/// offer a suggestion and so a test can assert an exact string; it makes no
/// uniqueness or unpredictability claim whatsoever, which is why the
/// repository still refuses a duplicate and why `API_CONTRACT.md` records that
/// the real code is generated server-side. A mixing step keeps consecutive
/// seeds from producing visibly consecutive codes — a cosmetic property, and
/// stated here as cosmetic so nobody later mistakes it for entropy.
String teamCodeFromSeed(int seed) {
  var state = (seed ^ 0x5DEECE66D) & 0xFFFFFFFFFFFF;
  final buffer = StringBuffer(kTeamCodePrefix);
  for (var group = 0; group < kTeamCodeGroups; group++) {
    buffer.write('-');
    for (var i = 0; i < kTeamCodeGroupSize; i++) {
      state = (state * 0x5DEECE66D + 0xB) & 0xFFFFFFFFFFFF;
      buffer.write(kTeamCodeAlphabet[(state >> 17) % kTeamCodeAlphabet.length]);
    }
  }
  return buffer.toString();
}
