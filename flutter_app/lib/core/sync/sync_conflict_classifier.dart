import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../problem/problem.dart';
import 'sync_state.dart';

/// Classifies the wire `code` of a failed push into "temporary, keep
/// retrying" (`false`) or "this is a stale-write conflict, stop retrying
/// automatically and let a human decide" (`true`).
///
/// This is the seam `SyncCoordinator` calls instead of deciding for itself,
/// so the classification rule can live and change in exactly one place, and
/// so a test can exercise the `SyncState.conflict` transition honestly
/// without asserting a production wire code (roadmap §6).
typedef SyncConflictClassifier = bool Function(String? problemCode);

/// The classifier shipped today: recognises exactly one wire code —
/// [ProblemCode.staleWrite] (`'stale_write'`, `HTTP 409`) — as a genuine
/// stale-write conflict. Everything else, including `null` and the
/// *in-progress* / same-key-different-body codes `FRONTEND-BACKEND-
/// INTEGRATION.md` §3 still leaves `Backend contract decision required`,
/// stays a temporary [SyncState.failed] and keeps retrying exactly as before
/// Task 2/3 (roadmap §6 "generic temporary failures must retain their
/// current behaviour").
///
/// `stale_write` is the Task 3 contract decision: a **different** wire code
/// from the generic `conflict` (`ProblemCode.conflict`, `HTTP 409`) an
/// ordinary synchronous call uses for "someone else changed this record"
/// (e.g. `ShiftRepository.assignVolunteer` per `API_CONTRACT.md`) — reusing
/// one string for both would conflate "this idempotent retry is stale" with
/// an unrelated business-rule condition. Comparing through
/// [ProblemCode.parse] rather than a raw string keeps `stale_write` in the
/// one Problem-code vocabulary instead of a second, parallel one.
///
/// This function can already return `true` in a shipped build; nothing
/// production sends `stale_write` today because `OfflineSyncTransport` is
/// the only `SyncTransport` and it never returns anything but `Offline` — so
/// no push can be classified either way until a real backend and transport
/// exist. See `FRONTEND-BACKEND-INTEGRATION.md` §3/§4.
bool defaultSyncConflictClassifier(String? problemCode) =>
    ProblemCode.parse(problemCode) == ProblemCode.staleWrite;

/// Override this in a test (e.g. with a private, never-real wire code — see
/// `conflict_outbox_test.dart`) to exercise the [SyncState.conflict]
/// transition without asserting the production `stale_write` string, or in a
/// real build if the agreed code ever needs to change without touching
/// `SyncCoordinator`.
final syncConflictClassifierProvider = Provider<SyncConflictClassifier>(
  (ref) => defaultSyncConflictClassifier,
);
