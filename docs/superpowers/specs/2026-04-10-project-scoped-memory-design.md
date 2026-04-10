# Project-Scoped Memory — Design Spec

**Date:** 2026-04-10
**Status:** Implemented (commits `b4ea58be`..`021b8be2` on `feat/projects-first-class`)
**Author:** Daniel Smith + Claude

---

## Problem

The V4 MemoryDatabase migration added `project_id TEXT` columns to 5 tables (memory_entries, conversation_summaries, conversations, entities, relationships) and created 3 composite indexes. However, the application code never populates or queries these columns. Every memory entry has `project_id = NULL`. The `MemorySummaryView` in the project inspector is a static placeholder. Project-scoped memory does not function.

## Goal

Wire `project_id` through every layer of the memory system so that:

1. Conversations in a project produce project-tagged memory entries, summaries, entities, and relationships
2. Project-scoped chats see their project's memories PLUS global (unscoped) memories
3. The MemorySummaryView in the project inspector displays live project memory data
4. All existing data (project_id = NULL) continues to work unchanged

## Design Decisions

### Query Semantics

When `projectId` is non-nil:

```sql
WHERE agent_id = ?N AND (project_id = ?M OR project_id IS NULL)
```

Returns project-specific entries PLUS workspace-global entries. Agents retain general knowledge while inside a project.

When `projectId` is nil: no project filter added (backward compatible).

### Layer-by-Layer Scoping (per original Projects spec)

| Layer               | Scoping                                                        | Rationale                                   |
| ------------------- | -------------------------------------------------------------- | ------------------------------------------- |
| L1 — User Profile   | **Global** (no change)                                         | Profile describes the user, not a project   |
| L2 — Working Memory | Project + Global                                               | Project-scoped facts + general knowledge    |
| L3 — Summaries      | Project + Global                                               | Project conversations summarized separately |
| L4 — Chunks         | Via `conversations.project_id` JOIN                            | Cascades through conversation's project_id  |
| Knowledge Graph     | **Global** (entities/relationships always `project_id = NULL`) | See Entity Scoping below                    |

### Entity & Relationship Scoping

Entities and relationships are **always stored with `project_id = NULL`**. Rationale:

- Entities are globally deduped by `(name, type)` using `INSERT OR IGNORE`. The first project to extract an entity would "own" it via `project_id`, making it invisible to other projects' `project_id = ?M OR project_id IS NULL` queries — because the entity would have `project_id = 'P1'` which fails both conditions when querying for `P2`.
- Entities represent real-world concepts (people, systems, technologies) that are inherently cross-project. "HVAC System" or "Daniel Smith" should be visible everywhere.
- Relationships between entities are similarly cross-project — "Daniel works at CIMCO" is true regardless of which project established it.
- Since both entities and relationships already have `project_id` columns from the V4 migration (always NULL), no schema change is needed. The columns remain unused but available for future per-project entity partitioning if needed.
- Knowledge graph queries (`queryEntityGraph`, `queryRelationships`, `loadRecentRelationships`) do **not** get a `projectId` parameter — they remain global.

### VecturaKit Limitation

The vector index has no `project_id` dimension. Semantic search returns candidates across all projects. Project scoping is achieved by post-retrieval SQLite filtering. Acceptable at current scale (500 entries per agent cap). No changes to VecturaKit indexing.

### What Does NOT Change

- Token budgets (profile 2000, working memory 3000, summaries 3000, chunks 3000, graph 300)
- 3-layer verification pipeline (Jaccard dedup, contradiction detection, semantic dedup)
- Profile regeneration (global, triggered after 10 contributions)
- Embedding backend or model configuration
- Entity/relationship insertion — `insertEntity()`, `insertRelationship()`, `insertGraphData()` remain unchanged
- Knowledge graph queries — `queryEntityGraph()`, `queryRelationships()`, `loadRecentRelationships()` remain global

---

## Architecture

### 1. V5 Migration — pending_signals

The V4 migration missed the `pending_signals` table. Signals carry projectId through the background processing pipeline (recording -> extraction -> summary generation). Without this column, summaries lose project context.

**MemoryDatabase V5 migration:**

```sql
ALTER TABLE pending_signals ADD COLUMN project_id TEXT;
```

Increment `schemaVersion` from 4 to 5. Wire into migration chain.

### 2. Model Changes

Add `public var projectId: String?` (with `nil` default) to 3 structs:

| Struct                | File                               | Additional Changes                                   |
| --------------------- | ---------------------------------- | ---------------------------------------------------- |
| `MemoryEntry`         | `Models/Memory/MemoryModels.swift` | Update CodingKeys, both init methods, custom decoder |
| `ConversationSummary` | `Models/Memory/MemoryModels.swift` | Update init                                          |
| `PendingSignal`       | `Models/Memory/MemoryModels.swift` | Update init                                          |

**NOT modified:** `GraphEntity` and `GraphRelationship` — these remain global (see Entity Scoping above).

All with `projectId: String? = nil` defaults — every existing callsite compiles unchanged.

### 3. Database Layer

**File:** `Storage/MemoryDatabase.swift`

#### Column Lists & Readers

- `memoryEntryColumns` (line 36): append `, project_id` (becomes column index 15)
- `readMemoryEntry()` (line 1076): read column 15 as `projectId`
- All summary SELECT statements: append `, project_id` as last column
- `readSummary()` (line 1252): read new column as `projectId`
- `loadPendingSignals(agentId:)` (line 1439): add `project_id` to SELECT, read into `PendingSignal.projectId`
- `loadPendingSignals(conversationId:)` (line 1464): add `project_id` to SELECT, read into `PendingSignal.projectId`

#### INSERT Statements (4 methods)

| Method                                 | Line     | Change                                                                                |
| -------------------------------------- | -------- | ------------------------------------------------------------------------------------- |
| `insertEntrySQL` + `bindInsertEntry()` | 799, 822 | Add `project_id` column + bind from `entry.projectId`                                 |
| `insertSummary()`                      | 1098     | Add `project_id` + bind from `summary.projectId`                                      |
| `insertSummaryAndMarkProcessed()`      | 1115     | Add `project_id` to the INSERT within the transaction + bind from `summary.projectId` |
| `insertPendingSignal()`                | 1423     | Add `project_id` + bind from `signal.projectId`                                       |

**Note:** `insertSummaryAndMarkProcessed()` is the primary summary insert path — called by `generateConversationSummary()`. The standalone `insertSummary()` exists for direct use. Both must include `project_id`.

#### Conversation Upsert

`upsertConversation()` (line 1268): add `projectId: String?` parameter. Bind `project_id` on INSERT, preserve existing value on CONFLICT (do not overwrite).

#### Query Methods (add `projectId: String? = nil` param)

When projectId is non-nil, append: `AND (project_id = ?N OR project_id IS NULL)`

| Method                                           | Line | Notes                                                                                                                                                                                                                                                             |
| ------------------------------------------------ | ---- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `loadActiveEntries(agentId:limit:)`              | 849  | Core working memory query                                                                                                                                                                                                                                         |
| `loadAllActiveEntries(limit:)`                   | 872  | Bulk load                                                                                                                                                                                                                                                         |
| `loadSummaries(agentId:days:)`                   | 1138 | All 4 SQL variants need the filter                                                                                                                                                                                                                                |
| `loadAllSummaries(days:)`                        | 1172 | Both SQL variants                                                                                                                                                                                                                                                 |
| `loadAllChunks(agentId:days:limit:)`             | 1317 | Filter via `c.project_id` on conversations JOIN                                                                                                                                                                                                                   |
| `searchMemoryEntries(query:agentId:)`            | 1634 | Text search fallback                                                                                                                                                                                                                                              |
| `searchChunks(query:agentId:days:)`              | 1378 | Filter via `c.project_id` JOIN                                                                                                                                                                                                                                    |
| `searchSummaries(query:agentId:days:)`           | 1715 | Text search                                                                                                                                                                                                                                                       |
| `loadEntriesByIds(_:agentId:)`                   | 891  | **Special:** uses dynamic `?N` numbering — projectId binding index must be computed as `ids.count + (agentId != nil ? 2 : 1)`                                                                                                                                     |
| `loadEntriesAsOf(agentId:asOf:)`                 | 1660 | Temporal query                                                                                                                                                                                                                                                    |
| `loadSummariesByCompositeKeys(_:filterAgentId:)` | 1790 | Vector search path for summaries. **Special:** dynamic binding — `filterProjectId` index must be computed as `keys.count * 3 + (filterAgentId != nil ? 2 : 1)`. Also add `project_id` to SELECT (via `readSummary()`).                                            |
| `loadChunksByKeys(_:)`                           | 1347 | Vector search path for chunks. The `conversations` JOIN already exists in SQL but has no `project_id` filter — add `AND (c.project_id = ?N OR c.project_id IS NULL)` to the WHERE clause. **Special:** dynamic binding — projectId index at `keys.count * 2 + 1`. |

#### Pending Conversations (recovery path)

`pendingConversations()` (line 1512): add `project_id` to `SELECT DISTINCT`. Return type changes from `[(agentId: String, conversationId: String)]` to `[(agentId: String, conversationId: String, projectId: String?)]`.

#### Knowledge Graph Queries — NO CHANGES

These remain global (no `projectId` parameter):

- `queryEntityGraph(name:depth:)` (line 1958)
- `queryRelationships(relation:)` (line 1996)
- `loadRecentRelationships(limit:)` (line 2031)
- `insertEntity()` (line 1875)
- `insertRelationship()` (line 1890)

#### New Convenience Method

`countEntriesByProject(projectId: String) -> (total: Int, byType: [MemoryEntryType: Int])` — for MemorySummaryView.

### 4. MemoryService

**File:** `Services/Memory/MemoryService.swift`

#### recordConversationTurn() (line 33)

Already accepts `projectId: String?` but never uses it. Now forwards to:

| Target                   | What Changes                                    |
| ------------------------ | ----------------------------------------------- |
| `PendingSignal` init     | Set `projectId: projectId`                      |
| `db.loadActiveEntries()` | Pass `projectId` for scoped dedup context       |
| `buildMemoryEntries()`   | New `projectId` param, sets on each MemoryEntry |
| `upsertConversation()`   | Pass `projectId`                                |

**NOT changed:** `insertGraphData()` — entities/relationships remain global, no projectId threading needed.

#### generateConversationSummary() (line 350)

- Add `projectId: String?` parameter
- Set `projectId` on `ConversationSummary` before passing to `insertSummaryAndMarkProcessed()`
- For `recoverOrphanedSignals` and `syncNow`, derive projectId from the pending signals in the database (signals carry projectId after V5 migration + `insertPendingSignal` update)
- **Migration ordering:** `insertPendingSignal()` must be updated to write `project_id` before signal-read derivation is valid. Existing NULL signals from before the migration will produce NULL projectId (treated as global) — this is correct behavior

#### Summary Generation Callsites (5 total)

All paths that call `generateConversationSummary()` must thread `projectId`:

| Callsite                   | Location | How projectId is sourced                                                                                                                                                                                                                       |
| -------------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Session-change trigger     | line 151 | Previous conversation's projectId — store in **new** `conversationProjectIds: [String: String?]` map (keyed by conversationId), populated during `recordConversationTurn()`. Add this alongside existing `conversationSessionDates` (line 24). |
| Debounced summary          | line 159 | Current conversation's projectId — captured in closure from `recordConversationTurn(projectId:)`                                                                                                                                               |
| `flushSession()`           | line 332 | New `projectId: String?` parameter. Caller: `ChatWindowState.flushCurrentSession()` (`Managers/Chat/ChatWindowState.swift:318`) — source projectId from active project context.                                                                |
| `recoverOrphanedSignals()` | line 260 | `pendingConversations()` now returns projectId in tuple — read from DB column                                                                                                                                                                  |
| `syncNow()`                | line 284 | `pendingConversations()` now returns projectId in tuple — read from DB column                                                                                                                                                                  |

**Note:** The session-change trigger (line 151) fires immediately when the user switches conversations — it summarizes the _previous_ conversation, so it needs the _previous_ conversation's projectId, not the current one. The new `conversationProjectIds` map (added alongside `conversationSessionDates` at line 24) solves this by recording each conversation's projectId when `recordConversationTurn()` is called.

**No changes to:** `insertProfileFacts()` (profile is global), `insertGraphData()` (graph is global), verification pipeline thresholds, profile regeneration.

### 5. MemorySearchService

**File:** `Services/Memory/MemorySearchService.swift`

Add `projectId: String? = nil` to:

| Method                  | Line | Behavior                                                                                                                                                                   |
| ----------------------- | ---- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `searchMemoryEntries()` | 158  | Vector path: VecturaKit returns IDs → `loadEntriesByIds(projectId:)` post-filters. Text fallback: `searchMemoryEntries(query:agentId:projectId:)` in DB.                   |
| `searchConversations()` | 241  | Vector path: VecturaKit returns keys → `loadChunksByKeys(projectId:)` post-filters via `c.project_id` JOIN. Text fallback: `searchChunks(query:agentId:projectId:)` in DB. |
| `searchSummaries()`     | 299  | Vector path: VecturaKit returns keys → `loadSummariesByCompositeKeys(filterProjectId:)` post-filters. Text fallback: `searchSummaries(query:agentId:projectId:)` in DB.    |

### 6. MemoryContextAssembler

**File:** `Services/Memory/MemoryContextAssembler.swift`

**Bug fix:** Two existing methods already accept `projectId` but silently drop it:

| Method                                                      | Line | Current Bug                                                                                        | Fix                                   |
| ----------------------------------------------------------- | ---- | -------------------------------------------------------------------------------------------------- | ------------------------------------- |
| `assembleContextCached(agentId:config:projectId:)`          | 123  | Calls `buildContext(agentId:config:)` — drops projectId                                            | Forward projectId to `buildContext()` |
| `assembleContextWithQuery(agentId:config:query:projectId:)` | 85   | Calls `buildContext(agentId:config:)` and `buildQueryRelevantSection()` — drops projectId for both | Forward projectId to both calls       |

Other changes:

| Method                        | Line | Change                                                                                       |
| ----------------------------- | ---- | -------------------------------------------------------------------------------------------- |
| `buildContext()`              | 146  | New `projectId: String?` param, pass to `loadActiveEntries`, `loadSummaries`                 |
| `buildQueryRelevantSection()` | 344  | New `projectId: String?` param, pass to all 3 `async let` search calls (lines 356, 363, 371) |

The three concurrent search calls in `buildQueryRelevantSection()` that need `projectId`:

```swift
async let entriesResult = searchService.searchMemoryEntries(query:agentId:projectId:topK:lambda:fetchMultiplier:)   // line 356
async let chunksResult = searchService.searchConversations(query:agentId:projectId:days:topK:lambda:fetchMultiplier:)  // line 363
async let summariesResult = searchService.searchSummaries(query:agentId:projectId:topK:lambda:fetchMultiplier:)     // line 371
```

**Overloads that remain unchanged** (no-projectId, backward-compatible global paths):

- `assembleContextCached(agentId:config:)` (line 111) — no projectId param
- `assembleContextWithQuery(agentId:config:query:)` (line 60) — no projectId param
- `buildQueryRelevantSection(agentId:query:config:existingContext:)` — a new overload with `projectId` is added; the original signature remains for the non-projectId callers. **Important:** the projectId overloads of `assembleContextWithQuery` (line 85) and `assembleContextCached` (line 123) must call the _new_ projectId overloads of `buildContext` and `buildQueryRelevantSection`, not the originals

Cache key in the projectId overload already uses `"\(agentId):\(projectId ?? "global")"` — no change needed.

### 7. Callers

| Caller         | File:Line                                 | Change                                                                                                                                                                                             |
| -------------- | ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Chat recording | `ChatView.swift:716`                      | Pass `projectId` from active project context                                                                                                                                                       |
| Work recording | `WorkSession.swift:1471`                  | Pass `projectId` from work context                                                                                                                                                                 |
| HTTP ingest    | `HTTPHandler.swift:1439`                  | Add optional `project_id` to request payload                                                                                                                                                       |
| Agent context  | `SystemPromptComposer.swift:274`          | `injectAgentContext()` is `@MainActor` — read `ProjectManager.shared.activeProjectId` inline and pass to `appendMemory(agentId:projectId:query:)`, same pattern as `finalizeContext()` at line 117 |
| Session flush  | `Managers/Chat/ChatWindowState.swift:318` | Pass `projectId` from active project to `flushSession(projectId:)`                                                                                                                                 |

### 8. MemorySummaryView

**File:** `Views/Projects/MemorySummaryView.swift`

Replace static placeholder with live view:

- On `.task {}`, call `MemoryDatabase.shared.countEntriesByProject(projectId:)`
- Display total count, breakdown by type (facts, preferences, decisions, etc.)
- Show most recent 3-5 entries with content preview
- Preserve empty state ("No memories yet") when count is 0

---

## Testing

New test file: `Tests/Project/MemoryProjectScopingTests.swift` using `openInMemory()`.

| Test                              | What It Verifies                                                                                                               |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| MemoryEntry projectId round-trip  | Insert with projectId, load back, verify preserved                                                                             |
| Project + global union query      | Insert P1, NULL, P2 entries. Query P1 returns P1 + NULL, not P2                                                                |
| Nil projectId returns global only | Query with nil returns only NULL-project entries                                                                               |
| ConversationSummary projectId     | Insert with projectId (both `insertSummary` and `insertSummaryAndMarkProcessed`), load via `loadSummaries(projectId:)`, verify |
| Conversation upsert projectId     | `upsertConversation(projectId:)` preserves project_id                                                                          |
| PendingSignal projectId           | Insert and load back (both overloads), verify projectId survives                                                               |
| pendingConversations projectId    | Verify projectId is returned in the recovery tuple                                                                             |
| V5 migration                      | Verify `pending_signals` has `project_id` column after migration                                                               |
| loadEntriesByIds with projectId   | Insert entries with mixed projectIds, verify correct filtering with dynamic binding indices                                    |
| Entities remain global            | Insert entity during project context, verify `project_id` is NULL (not project-tagged)                                         |

---

## Files Modified

| File                                            | Changes                                                                                                                                                                 |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Models/Memory/MemoryModels.swift`              | Add `projectId: String?` to 3 structs (MemoryEntry, ConversationSummary, PendingSignal)                                                                                 |
| `Storage/MemoryDatabase.swift`                  | V5 migration, column lists, readers, 4 INSERT methods, conversation upsert, 12 query methods, pendingConversations return type, new convenience method                  |
| `Services/Memory/MemoryService.swift`           | Forward projectId through recording + summary pipeline, add `conversationProjectIds` map, fix all 5 summary callsites (session-change, debounce, flush, recovery, sync) |
| `Services/Memory/MemorySearchService.swift`     | Add projectId to 3 search methods                                                                                                                                       |
| `Services/Memory/MemoryContextAssembler.swift`  | Fix 2 existing stub bugs (projectId dropped), forward projectId to buildContext + query section                                                                         |
| `Views/Chat/ChatView.swift`                     | Pass projectId to recordConversationTurn                                                                                                                                |
| `Views/Work/WorkSession.swift`                  | Pass projectId to recordConversationTurn                                                                                                                                |
| `Networking/HTTPHandler.swift`                  | Add project_id to ingest request                                                                                                                                        |
| `Services/Chat/SystemPromptComposer.swift`      | Pass projectId in injectAgentContext                                                                                                                                    |
| `Managers/Chat/ChatWindowState.swift`           | Pass projectId to `flushSession()` in `flushCurrentSession()`                                                                                                           |
| `Views/Projects/MemorySummaryView.swift`        | Replace placeholder with live display                                                                                                                                   |
| `Tests/Project/MemoryProjectScopingTests.swift` | 10 new tests                                                                                                                                                            |
| `Tests/Project/DatabaseMigrationTests.swift`    | V5 migration test                                                                                                                                                       |

## Files NOT Modified

| File                                                                        | Reason                                                         |
| --------------------------------------------------------------------------- | -------------------------------------------------------------- |
| `GraphEntity` / `GraphRelationship` models                                  | Entities/relationships stay global — no projectId field needed |
| `insertEntity()` / `insertRelationship()`                                   | Graph insertion remains global                                 |
| `insertGraphData()` in MemoryService                                        | No projectId threading — graph data is cross-project           |
| `queryEntityGraph()` / `queryRelationships()` / `loadRecentRelationships()` | Knowledge graph queries remain global                          |
