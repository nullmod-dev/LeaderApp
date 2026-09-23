import '../domain/shift_conflict_snapshot.dart';

/// In-memory [ShiftConflictSnapshotStore]. MOCK — holds snapshots for the
/// lifetime of the object only, exactly like `InMemoryOutboxStore` and
/// `InMemoryConflictReviewStore`.
///
/// A second `ProviderContainer` built over the *same instance* models an app
/// relaunch, which is enough to prove a captured snapshot survives a
/// restart; it is **not** durable across an OS process restart. A concrete
/// store writes the snapshot's `Shift.toJson()` plus its two version strings
/// to the encrypted DB.
class InMemoryShiftConflictSnapshotStore implements ShiftConflictSnapshotStore {
  InMemoryShiftConflictSnapshotStore({
    Map<String, ShiftConflictSnapshot>? seed,
  }) : _rows = {...?seed};

  final Map<String, ShiftConflictSnapshot> _rows;

  @override
  Future<ShiftConflictSnapshot?> read(String conflictId) async =>
      _rows[conflictId];

  @override
  Future<void> upsert(String conflictId, ShiftConflictSnapshot snapshot) async {
    // Replace, never append: one "current as of detection" per conflict.
    _rows[conflictId] = snapshot;
  }

  @override
  Future<void> remove(String conflictId) async {
    _rows.remove(conflictId);
  }
}
