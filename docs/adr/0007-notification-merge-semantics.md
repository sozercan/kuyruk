# ADR-0007: API Fetch as Source of Truth for Notification Merge

## Status

Accepted

## Context

`NotificationsViewModel` merges freshly fetched notifications with the in-memory
list on every sync. The previous merge had three behaviors:

1. **Preserve optimistic read state** — if a thread was marked read locally but the
   API still reported it unread (the API hadn't caught up), keep the local read state.
2. **Adopt fresh data** otherwise.
3. **Retain non-fresh read items** — any locally-known notification *not* present in
   the fresh fetch was kept in the list as long as it was read.

Behavior (3) was added to avoid losing read notifications when the active fetch was
unread-scoped. The default fetch (`fetchAllNotifications` / `fetchAllNotificationsForced`)
requests `all: false`, so it returns only unread threads. Keeping non-fresh read items
meant a thread that was read on GitHub (or `Done`-ed in another client) lingered in
Kuyruk indefinitely, because an unread-scoped fetch can never report its absence.

This caused two problems:

- **Stale inbox**: threads cleared elsewhere never disappeared locally.
- **Divergent persistence**: `SyncService` already called
  `markDeletedNotifications(currentIds:)` to soft-delete threads missing from a sync,
  so the cache and the in-memory list could disagree about what still exists.

The new Digest dashboard makes this worse: its repository-activity and "actions ready"
counts are derived from the in-memory list, so retained-but-gone threads inflate the
numbers users see.

## Decision

Treat the API fetch as the **source of truth** for which threads exist.

`mergeNotifications` is reimplemented as a pure, `nonisolated static`
`mergedNotifications(existing:fresh:)`:

- The result set is exactly the **fresh** threads.
- Optimistic read state is still preserved: when an existing thread is locally read but
  the fresh copy is unread, keep the local (read) copy. This retains the race-condition
  protection from the old behavior (1).
- Threads absent from the fresh fetch are **dropped** from the in-memory list (behavior 3
  is removed).

In addition, `markDeletedNotifications(currentIds:)` is now called from the view model's
fetch paths (progressive load and forced refresh), not only from `SyncService`, so the
SwiftData cache stays consistent with the in-memory list.

Extracting the merge as a pure static function also makes it unit-testable without
constructing a full view model.

## Consequences

### Easier

- **Accurate inbox**: threads resolved on GitHub or in another client disappear on the
  next sync.
- **Consistent state**: in-memory list, SwiftData cache, and soft-delete flags agree.
- **Correct Digest metrics**: counts reflect only live threads.
- **Testable**: `mergedNotifications` is covered by unit tests
  (`NotificationsViewModelMergeTests`).

### More difficult / risks

- **Read history is not retained across syncs.** Because the default fetch is
  unread-scoped, a thread the user just marked read locally will drop out of the list on
  the following sync (the API no longer returns it). This is acceptable for an
  inbox-style "what still needs attention" model, but it means Kuyruk is not a browsable
  archive of past notifications. If a "recently read" view is wanted later, fetch with
  `all: true` for that surface rather than relying on retention.
- **Within a single progressive sync, batches are cumulative**, so paginated loads do not
  transiently drop items. This relies on `fetchAllNotificationsProgressive` passing the
  accumulated set (not per-page slices) to the batch callback — verified at time of
  writing. A future change to emit partial pages would break this assumption.

## References

- [ADR 0005: SwiftData for Local Persistence](0005-swiftdata-persistence.md)
- `Sources/Kuyruk/ViewModels/NotificationsViewModel.swift` — `mergedNotifications`
- `Sources/Kuyruk/Services/Persistence/DataStore.swift` — `markDeletedNotifications`
- `Tests/KuyrukTests/KuyrukTests.swift` — `NotificationsViewModelMergeTests`
