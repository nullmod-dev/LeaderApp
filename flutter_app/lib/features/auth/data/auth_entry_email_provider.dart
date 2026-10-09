import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The address typed on one entry screen, handed to the next so nobody types
/// it twice — today `/login`'s "no account yet" step → `/signup`.
///
/// Memory only, never persisted, and cleared by the screen that takes it. An
/// address is not a secret, but a stale one pre-filled for the next person
/// on a shared phone would still say who used it last.
final authEntryEmailProvider = StateProvider<String?>((ref) => null);

/// The address a password-reset code was sent to: set by `/forgot` once the
/// server accepted the request, read by `/otp` (its subtitle names it, and the
/// code is verified against it), cleared when the new password is saved.
///
/// Its own provider rather than [authEntryEmailProvider]: that one is taken
/// and cleared by `/signup`, and a reset that went back to the login screen
/// must not pre-fill a sign-up form with the address it was resetting.
/// Memory only, for the same reason.
final passwordResetEmailProvider = StateProvider<String?>((ref) => null);
