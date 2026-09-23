/// What the *server* says about a session beyond "who is this".
///
/// **Why this is a separate model and not fields on `AuthUser`.** `AuthUser`
/// is the account: identity, product surface, tenant, grant. These are
/// lifecycle facts *about* the account and the customer it belongs to — a
/// suspension, a deletion, an unfinished signup, a demo workspace — and they
/// change without the account changing. Keeping them apart is also what lets
/// every existing `AuthUser` fixture in the app stay valid.
///
/// The auth/session backend remains authoritative. In development only, the
/// canonical process-memory tenant store composes its known tenant lifecycle
/// into this envelope so a live mock session can be ejected after a Point 9A
/// mutation. A production repository must supply and enforce the same fact at
/// session refresh and protected requests. See `API_CONTRACT.md` §Session.
///
/// **Nothing here may be inferred.** Not from an empty capability set, not
/// from `orgName`, not from an email domain, not from an id shape. A session
/// with no usable capabilities is `tenantNoAccess` — an authorization outcome
/// — and calling it a suspension would tell a user their account was punished
/// when in fact nobody has assigned them anything yet. Every value below
/// arrives from the server or it stays at its default.
///
/// ## Absent vs. present-but-unsupported — 2026-09-08
///
/// Point 3 shipped one rule for every field this file reads: *an unknown value
/// reads as the normal value.* That rule quietly conflated two different
/// facts, and the second half of it was a **fail-open** on a security gate:
///
///  - **Absent** — the server has not implemented this field. Partial
///    implementation is the expected path (`API_CONTRACT.md` says every
///    property is optional), so absence must go on meaning the documented
///    default. Unchanged.
///  - **Present, and this build does not recognise the value** — the server
///    *is* asserting a lifecycle state, and an installed client has no way to
///    know whether it is more permissive or more restrictive than the ones it
///    knows. `accountStatus: "locked"` read as `active` hands a locked account
///    the whole application.
///
/// So the two are now told apart. A known value parses; an unrecognised one is
/// recorded in [SessionAccess.unsupported] and the field falls back to its
/// default *for display only* — [SessionAccess.hasUnsupportedState] is what
/// the startup classifier reads, and it fails closed onto
/// `StartupDestination.unsupportedAccessState`. Nothing guesses which way an
/// unknown state leans.
///
/// **What this deliberately does not do.** It does not fail on an unknown
/// *property name*. A server that adds `lastPasswordChangeAt` to this envelope
/// is adding metadata, not a gate, and refusing a session over a field the
/// client never reads would make the contract unextendable. The line is: a
/// value inside a field this client already gates on. The consequence for the
/// backend is written into `API_CONTRACT.md` — a new **restrictive** state has
/// to arrive as a new *value* of an existing field, because a new field name
/// is invisible to every build already in the field.
library;

import 'package:flutter/foundation.dart';

import '../../../core/access/saas_tenant_status.dart';

/// The account's own lifecycle state.
enum AccountStatus {
  /// Ordinary. The only value any real session has today.
  active('active'),

  /// Temporarily blocked. Reversible, and the user is not told why unless the
  /// server supplies a reason — the client never invents one.
  suspended('suspended'),

  /// Access has been withdrawn. Terminal from the client's point of view, and
  /// deliberately not phrased as a transient failure.
  revoked('revoked'),

  /// Authenticated, but the account is not finished: identity verification,
  /// or the one-time team code that links it to a real `SaasTenant`, has not
  /// been completed. The *state* only — this build has no screen that collects
  /// either, and must not pretend to.
  pendingSetup('pending_setup');

  const AccountStatus(this.wire);

  final String wire;

  /// The status [wire] names, or `null` when this build has never heard of it.
  ///
  /// `null` is not a default — it is the caller's signal that the server
  /// asserted something this build cannot interpret. [SessionAccess.fromJson]
  /// is the only caller, and it fails closed on that. See the library note.
  static AccountStatus? tryParse(String wire) {
    for (final status in values) {
      if (status.wire == wire) return status;
    }
    return null;
  }
}

/// Whether this session is a **customer demo** — the future product feature,
/// not the development personas.
///
/// The two are unrelated and must not be conflated. A development persona
/// (`DemoPersona`) authenticates as a real `AuthRole` against the real mock
/// repositories in a debug build; a customer demo is a product offering with
/// an isolated workspace, no `saasTenantId` and no access to any real tenant
/// repository. The login product-demo action creates this state through the
/// authentication repository; its limits and timer remain server policy. The
/// values let the startup classifier keep it out of both real surfaces.
///
/// An unrecognised demo mode is the sharpest case for failing closed: a future
/// `"restricted"` or `"read_only"` demo read as [DemoMode.none] would hand a
/// demo session the real product.
enum DemoMode {
  none('none'),
  active('active'),
  expired('expired');

  const DemoMode(this.wire);

  final String wire;

  /// See [AccountStatus.tryParse].
  static DemoMode? tryParse(String wire) {
    for (final mode in values) {
      if (mode.wire == wire) return mode;
    }
    return null;
  }
}

/// One property of the session envelope that **gates access**.
///
/// Typed rather than a bare string so the set of fields the client fails
/// closed on is enumerable — the tests iterate it, the contract table lists
/// it, and a field added here cannot be forgotten by the parser.
enum AccessLifecycleField {
  accountStatus('accountStatus'),
  tenantStatus('tenantStatus'),
  demoMode('demoMode'),
  mfaRequired('mfaRequired'),
  sessionExpiresAt('sessionExpiresAt');

  const AccessLifecycleField(this.wire);

  /// The property name on the wire.
  final String wire;
}

@immutable
class SessionAccess {
  const SessionAccess({
    this.account = AccountStatus.active,
    this.tenant = SaasTenantStatus.active,
    this.demo = DemoMode.none,
    this.mfaRequired = false,
    this.sessionExpiresAt,
    this.unsupported = const {},
  });

  /// What every session in this build resolves to.
  static const normal = SessionAccess();

  /// A session envelope whose [field] carried a value this build cannot
  /// interpret — the shape a future backend produces against an old client.
  ///
  /// Named rather than assembled inline because the *only* thing that matters
  /// about it is that it is unclassifiable; the raw string is kept for a log
  /// and for [toJson], never for a decision.
  factory SessionAccess.unsupportedValue(
    AccessLifecycleField field,
    String raw,
  ) =>
      SessionAccess(unsupported: {field: raw});

  final AccountStatus account;
  final SaasTenantStatus tenant;
  final DemoMode demo;

  /// Whether the server considers authentication **incomplete** until a
  /// second factor is presented.
  ///
  /// A hook, not a feature. MTM's MFA screens already exist and are entered
  /// deliberately from Security; nothing in the current contract marks a
  /// session as challenge-pending, so this is always `false`. It is here so
  /// that when a backend does mark one, the challenge outranks `/home` and
  /// `/platform` by the classifier's ordinary priority rather than by a new
  /// clause bolted onto the router.
  final bool mfaRequired;

  /// The server-issued instant at which this session stops being valid.
  ///
  /// This is not a client timeout and does not replace the authoritative
  /// `401 authentication_expired` response. At startup it lets the client
  /// avoid opening a product surface with a session whose own envelope says
  /// it has already ended. Absent means the backend has not supplied the
  /// advisory field and preserves the existing 401-driven behaviour.
  final DateTime? sessionExpiresAt;

  /// Compares absolute instants, never wall-clock components. Both sides are
  /// normalized to UTC so a timestamp with an RFC 3339 offset behaves exactly
  /// like its `Z` equivalent. Equality is expired: validity ends *at* the
  /// server-issued instant, not one tick after it.
  bool isExpiredAt(DateTime now) =>
      sessionExpiresAt != null &&
      !now.toUtc().isBefore(sessionExpiresAt!.toUtc());

  /// Every gating field that arrived carrying a value this build does not
  /// support, mapped to the raw value as received.
  ///
  /// **Empty for every conforming session**, including one from a backend that
  /// implements none of this envelope — an absent field is not unsupported.
  /// Non-empty means the app fails closed: see [hasUnsupportedState] and
  /// `StartupDestination.unsupportedAccessState`.
  ///
  /// The raw values are kept so [toJson] round-trips and so a diagnostic can
  /// name what arrived. Nothing branches on their content.
  final Map<AccessLifecycleField, String> unsupported;

  /// Whether any gating field carried a value this build cannot interpret.
  ///
  /// The one question the startup classifier asks about forward compatibility.
  bool get hasUnsupportedState => unsupported.isNotEmpty;

  bool get isDemo => demo != DemoMode.none;

  SessionAccess copyWith({
    AccountStatus? account,
    SaasTenantStatus? tenant,
    DemoMode? demo,
    bool? mfaRequired,
    DateTime? sessionExpiresAt,
    Map<AccessLifecycleField, String>? unsupported,
  }) =>
      SessionAccess(
        account: account ?? this.account,
        tenant: tenant ?? this.tenant,
        demo: demo ?? this.demo,
        mfaRequired: mfaRequired ?? this.mfaRequired,
        sessionExpiresAt: sessionExpiresAt ?? this.sessionExpiresAt,
        unsupported: unsupported ?? this.unsupported,
      );

  /// Reads the session envelope's access fields.
  ///
  /// Three outcomes per field, and they are three on purpose (see the library
  /// note at the top of this file):
  ///
  ///  - **absent** → the documented default, so a backend that has not
  ///    implemented any of this produces exactly [SessionAccess.normal];
  ///  - **a value this build knows** → that value;
  ///  - **anything else**, including a value of the wrong JSON type → recorded
  ///    in [unsupported]. The field still takes its default so nothing
  ///    downstream reads a half-parsed object, but [hasUnsupportedState] is
  ///    now true and the classifier refuses every product surface.
  factory SessionAccess.fromJson(Map<String, dynamic> j) {
    final unsupported = <AccessLifecycleField, String>{};

    /// Reads one enum-valued field. [parse] answers `null` for a string this
    /// build does not recognise.
    T read<T>(
      AccessLifecycleField field,
      T fallback,
      T? Function(String) parse,
    ) {
      final raw = j[field.wire];
      if (raw == null) return fallback;
      if (raw is! String) {
        unsupported[field] = raw.toString();
        return fallback;
      }
      final parsed = parse(raw);
      if (parsed == null) {
        unsupported[field] = raw;
        return fallback;
      }
      return parsed;
    }

    final account = read(
      AccessLifecycleField.accountStatus,
      AccountStatus.active,
      AccountStatus.tryParse,
    );
    final tenant = read(
      AccessLifecycleField.tenantStatus,
      SaasTenantStatus.active,
      SaasTenantStatus.tryParse,
    );
    final demo = read(
      AccessLifecycleField.demoMode,
      DemoMode.none,
      DemoMode.tryParse,
    );

    // `mfaRequired` is the one boolean, so it gets the same three outcomes
    // without a parser: absent is `false`, a real boolean is itself, and
    // anything else is a gate this build cannot read — which is exactly as
    // serious as an unknown account status.
    final rawMfa = j[AccessLifecycleField.mfaRequired.wire];
    var mfaRequired = false;
    if (rawMfa is bool) {
      mfaRequired = rawMfa;
    } else if (rawMfa != null) {
      unsupported[AccessLifecycleField.mfaRequired] = rawMfa.toString();
    }

    final rawExpiry = j[AccessLifecycleField.sessionExpiresAt.wire];
    DateTime? sessionExpiresAt;
    if (rawExpiry is String) {
      // RFC 3339 requires an explicit offset. Dart also accepts local
      // timestamps; accepting one here would make the same payload expire at
      // different instants on different devices, so those are refused.
      final hasOffset =
          RegExp(r'(?:[zZ]|[+-]\d{2}:\d{2})$').hasMatch(rawExpiry);
      final parsed = hasOffset ? DateTime.tryParse(rawExpiry) : null;
      if (parsed == null) {
        unsupported[AccessLifecycleField.sessionExpiresAt] = rawExpiry;
      } else {
        sessionExpiresAt = parsed.toUtc();
      }
    } else if (rawExpiry != null) {
      unsupported[AccessLifecycleField.sessionExpiresAt] = rawExpiry.toString();
    }

    return SessionAccess(
      account: account,
      tenant: tenant,
      demo: demo,
      mfaRequired: mfaRequired,
      sessionExpiresAt: sessionExpiresAt,
      unsupported: Map.unmodifiable(unsupported),
    );
  }

  /// Round-trips, including the values this build could not interpret: an
  /// unsupported field is written back **as it arrived**, never as the default
  /// it fell back to, so serialising a session cannot launder a state the
  /// client refused into one it accepts.
  Map<String, dynamic> toJson() => {
        AccessLifecycleField.accountStatus.wire:
            unsupported[AccessLifecycleField.accountStatus] ?? account.wire,
        AccessLifecycleField.tenantStatus.wire:
            unsupported[AccessLifecycleField.tenantStatus] ?? tenant.wire,
        AccessLifecycleField.demoMode.wire:
            unsupported[AccessLifecycleField.demoMode] ?? demo.wire,
        AccessLifecycleField.mfaRequired.wire:
            unsupported[AccessLifecycleField.mfaRequired] ?? mfaRequired,
        if (unsupported.containsKey(AccessLifecycleField.sessionExpiresAt))
          AccessLifecycleField.sessionExpiresAt.wire:
              unsupported[AccessLifecycleField.sessionExpiresAt]
        else if (sessionExpiresAt != null)
          AccessLifecycleField.sessionExpiresAt.wire:
              sessionExpiresAt!.toUtc().toIso8601String(),
      };

  static bool _sameUnsupported(
    Map<AccessLifecycleField, String> a,
    Map<AccessLifecycleField, String> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionAccess &&
          other.account == account &&
          other.tenant == tenant &&
          other.demo == demo &&
          other.mfaRequired == mfaRequired &&
          other.sessionExpiresAt == sessionExpiresAt &&
          _sameUnsupported(other.unsupported, unsupported);

  @override
  int get hashCode => Object.hash(
        account,
        tenant,
        demo,
        mfaRequired,
        sessionExpiresAt,
        // Order-independent, so two equal maps built in a different order
        // cannot disagree about their hash.
        Object.hashAllUnordered(
          unsupported.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );

  @override
  String toString() => 'SessionAccess(${account.wire}, ${tenant.wire}, '
      'demo: ${demo.wire}, mfa: $mfaRequired, expires: $sessionExpiresAt'
      '${hasUnsupportedState ? ', unsupported: $unsupported' : ''})';
}
