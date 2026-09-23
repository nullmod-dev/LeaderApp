import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/outbox_controller.dart';
import '../../../core/sync/pending_operation.dart';
import '../domain/conflict_review_entry.dart';
import '../domain/conflict_review_store.dart';
import '../domain/needs_review_item.dart';
import 'in_memory_conflict_review_store.dart';

/// Where durable Needs Review metadata is persisted. Override with a real
/// (encrypted-DB backed) [ConflictReviewStore] in a shipping build.
final conflictReviewStoreProvider = Provider<ConflictReviewStore>((ref) {
  return InMemoryConflictReviewStore();
});

/// The stored review metadata, live.
///
/// An [AsyncNotifier] for the same reason `OutboxController` is one — the
/// stored rows arrive asynchronously and the inbox must render in the
/// meantime. It only ever *stores and drops* metadata: it never changes an
/// operation's state, which stays `OutboxController`'s job, and it is never
/// the source of truth for whether something needs review.
class ConflictReviewController
    extends AsyncNotifier<List<ConflictReviewEntry>> {
  ConflictReviewStore get _store => ref.read(conflictReviewStoreProvider);

  @override
  Future<List<ConflictReviewEntry>> build() => _store.readAll();

  Future<void> _reload() async {
    state = AsyncData(await _store.readAll());
  }

  /// Stores (or supersedes) the metadata for one detected conflict. Called
  /// from the classification path — see `conflict_review_recording.dart`.
  /// Re-reads the store into state — see `OutboxController.refresh`.
  Future<void> refresh() => _reload();

  Future<void> record(ConflictReviewEntry entry) async {
    await _store.upsert(entry);
    await _reload();
  }

  /// Drops the metadata for a conflict that has been resolved, or whose
  /// operation has otherwise left the outbox. Never called for
  /// `reviewLater`.
  Future<void> forget(String conflictId) async {
    await _store.remove(conflictId);
    await _reload();
  }
}

final conflictReviewProvider =
    AsyncNotifierProvider<ConflictReviewController, List<ConflictReviewEntry>>(
  ConflictReviewController.new,
);

/// The Needs Review inbox: every operation waiting on a human decision,
/// newest conflict first, joined with whatever safe metadata was stored for
/// it (see [NeedsReviewItem] for why the join runs in this direction).
///
/// Loading until *both* sources have loaded, so the screen never flashes an
/// "empty inbox" over an outbox that simply has not arrived yet. The length
/// of this list is always `conflictOperationsCountProvider` — the count in
/// Settings and the list behind it cannot drift apart.
final needsReviewItemsProvider =
    Provider<AsyncValue<List<NeedsReviewItem>>>((ref) {
  return _join(
    ref.watch(outboxProvider),
    ref.watch(conflictReviewProvider),
  );
});

AsyncValue<List<NeedsReviewItem>> _join(
  AsyncValue<List<PendingOperation>> ops,
  AsyncValue<List<ConflictReviewEntry>> entries,
) {
  if (ops.isLoading || entries.isLoading) return const AsyncValue.loading();
  if (ops.hasError) {
    return AsyncValue.error(ops.error!, ops.stackTrace ?? StackTrace.empty);
  }
  if (entries.hasError) {
    return AsyncValue.error(
      entries.error!,
      entries.stackTrace ?? StackTrace.empty,
    );
  }

  final byId = {
    for (final e in entries.valueOrNull ?? const <ConflictReviewEntry>[])
      e.conflictId: e,
  };

  final items = [
    for (final op in ops.valueOrNull ?? const <PendingOperation>[])
      if (op.needsReview)
        NeedsReviewItem(
          conflictId: op.operationId,
          recordLabel: needsReviewRecordLabel(
            entityType: op.entityType,
            kind: op.kind,
          ),
          // The attempt that produced the conflict verdict; `createdAt` only
          // for a record restored without attempt bookkeeping.
          detectedAt: op.lastAttemptAt ?? op.createdAt,
          entry: byId[op.operationId],
        ),
  ]..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));

  return AsyncData(items);
}
