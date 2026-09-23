import '../domain/conflict_review_entry.dart';
import '../domain/conflict_review_store.dart';

/// In-memory [ConflictReviewStore]. MOCK — holds entries for the lifetime of
/// the object only, exactly like `InMemoryOutboxStore` and
/// `MockSettingsRepository`.
///
/// A second `ProviderContainer` built over the *same instance* models an app
/// relaunch (the idiom `forced_upgrade_test.dart` and the outbox tests use),
/// which is enough to prove an unresolved conflict survives a restart; it is
/// **not** durable across an OS process restart. A concrete store writes
/// `ConflictReviewEntry.toJson()` to the encrypted DB.
class InMemoryConflictReviewStore implements ConflictReviewStore {
  InMemoryConflictReviewStore({List<ConflictReviewEntry>? seed})
      : _rows = {
          for (final e in seed ?? const <ConflictReviewEntry>[]) e.conflictId: e
        };

  final Map<String, ConflictReviewEntry> _rows;

  @override
  Future<List<ConflictReviewEntry>> readAll() async =>
      List.unmodifiable(_rows.values);

  @override
  Future<void> upsert(ConflictReviewEntry entry) async {
    // Replace, never append: one "current as of detection" per conflict.
    _rows[entry.conflictId] = entry;
  }

  @override
  Future<void> remove(String conflictId) async {
    _rows.remove(conflictId);
  }
}
