import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The address typed on one entry screen, handed to the next so nobody types
/// it twice — today `/login`'s "no account yet" step → `/signup`.
///
/// Memory only, never persisted, and cleared by the screen that takes it. An
/// address is not a secret, but a stale one pre-filled for the next person
/// on a shared phone would still say who used it last.
final authEntryEmailProvider = StateProvider<String?>((ref) => null);
