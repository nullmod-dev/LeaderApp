/// What this *compiled artefact* is allowed to do — as compile-time
/// constants, so a release build does not merely hide a development
/// affordance, it does not contain one.
///
/// Nothing here is a setting and nothing here is read from storage. A
/// constant that is `false` in release makes every `if` below it dead code,
/// which Dart's tree shaker removes along with everything only that branch
/// reaches: the typed credential branch and the persona fixtures behind it.
/// A runtime flag cannot make that promise — the code would still be in the
/// binary, one bug away from being reachable.
library;

import 'package:flutter/foundation.dart';

/// Whether this build may offer the development demo accounts at all.
///
/// **The release guarantee.** `kDebugMode` is `const false` in a release
/// build, so `if (demoAccountsAllowed)` is eliminated. Login renders no
/// persona picker in any mode, and `MockAuthRepository` compiles with its
/// typed credential table and persona-restore path unreachable.
///
/// Profile mode counts as release here on purpose. A profile build is a
/// shipping artefact with debug asserts off; a demo login path in one would
/// be exactly the leak this constant exists to prevent.
///
/// **This is the outer gate, not the only one.** `demoAccountsEnabledProvider`
/// (`features/auth/data/auth_providers.dart`) sits inside it and defaults to
/// this value, so a test can simulate a release configuration by overriding
/// the provider to `false` while still running under the debug VM. Both are
/// checked at every demo entry point: the constant is what ships, the
/// provider is what is testable.
const bool demoAccountsAllowed = kDebugMode;
