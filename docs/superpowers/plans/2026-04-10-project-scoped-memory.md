# Project-Scoped Memory Implementation Plan

> **Status:** **Implemented** 2026-04-10 (commits `b4ea58be`..`021b8be2` on `feat/projects-first-class`).
>
> This plan guided the implementation. Checkboxes below are preserved for reference but the work is complete. See the companion spec for design rationale.

**Goal:** Wire `project_id` through every layer of the memory system so that project-scoped chats produce project-tagged memories and see project + global entries.

**Architecture:** Add V5 migration for `pending_signals.project_id`, add `projectId` to 3 model structs, update all INSERT/SELECT paths in MemoryDatabase, forward projectId through MemoryService → MemorySearchService → MemoryContextAssembler → callers, and replace the static MemorySummaryView with a live display.

**Tech Stack:** Swift 6.2, SQLite3 (direct C API), SwiftUI, VecturaKit (vector search)

**Spec:** `docs/superpowers/specs/2026-04-10-project-scoped-memory-design.md`

**Verify changes compile (never use xcodebuild):**

```bash
cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"
```

**Run tests:**

```bash
swift test --package-path Packages/OsaurusCore
```

---

## File Structure

| File                                                                | Responsibility                  | Action                                                                                 |
| ------------------------------------------------------------------- | ------------------------------- | -------------------------------------------------------------------------------------- |
| `Packages/OsaurusCore/Models/Memory/MemoryModels.swift`             | Data structs                    | Modify: add `projectId` to 3 structs                                                   |
| `Packages/OsaurusCore/Storage/MemoryDatabase.swift`                 | SQLite persistence              | Modify: V5 migration, INSERTs, SELECTs, readers, new convenience method                |
| `Packages/OsaurusCore/Services/Memory/MemoryService.swift`          | Recording + extraction pipeline | Modify: forward projectId, add conversationProjectIds map, fix all 5 summary callsites |
| `Packages/OsaurusCore/Services/Memory/MemorySearchService.swift`    | Hybrid search                   | Modify: add projectId to 3 search methods                                              |
| `Packages/OsaurusCore/Services/Memory/MemoryContextAssembler.swift` | Context building                | Modify: fix 2 stub bugs, forward projectId                                             |
| `Packages/OsaurusCore/Views/Chat/ChatView.swift`                    | Chat UI                         | Modify: pass projectId to recordConversationTurn + upsertConversation                  |
| `Packages/OsaurusCore/Views/Work/WorkSession.swift`                 | Work mode                       | Modify: pass projectId to recordConversationTurn                                       |
| `Packages/OsaurusCore/Networking/HTTPHandler.swift`                 | HTTP ingest                     | Modify: add project_id to request, pass through                                        |
| `Packages/OsaurusCore/Services/Chat/SystemPromptComposer.swift`     | Prompt composition              | Modify: pass projectId in injectAgentContext                                           |
| `Packages/OsaurusCore/Managers/Chat/ChatWindowState.swift`          | Window state                    | Modify: pass projectId to flushSession                                                 |
| `Packages/OsaurusCore/Views/Projects/MemorySummaryView.swift`       | Inspector memory panel          | Modify: replace placeholder with live display                                          |
| `Packages/OsaurusCore/Tests/Project/DatabaseMigrationTests.swift`   | Migration tests                 | Modify: add V5 test                                                                    |
| `Packages/OsaurusCore/Tests/Memory/MemoryProjectScopingTests.swift` | Project scoping tests           | Create: 10 new tests                                                                   |

---

### Task 1: V5 Migration — pending_signals project_id

**Files:**

- Modify: `Packages/OsaurusCore/Storage/MemoryDatabase.swift:34` (schemaVersion), `:155-161` (runMigrations), after `:509` (new migrateToV5)
- Modify: `Packages/OsaurusCore/Tests/Project/DatabaseMigrationTests.swift`

- [ ] **Step 1: Write the V5 migration test**

Add to `DatabaseMigrationTests.swift` after the V4 tests (after line 143):

```swift
// MARK: - MemoryDatabase V5 Tests

@Test func memoryDatabaseV5AddsProjectIdToPendingSignals() throws {
    let db = MemoryDatabase()
    try db.openInMemory()
    defer { db.close() }

    try db.execute { connection in
        let columns = self.columnNames(in: connection, table: "pending_signals")
        #expect(columns.contains("project_id"), "pending_signals should have project_id column after V5")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/OsaurusCore --filter DatabaseMigrationTests/memoryDatabaseV5AddsProjectIdToPendingSignals`
Expected: FAIL — pending_signals has no project_id column yet.

- [ ] **Step 3: Implement V5 migration**

In `MemoryDatabase.swift`:

1. Change line 34:

```swift
private static let schemaVersion = 5
```

2. Add to `runMigrations()` at line 161 (before the closing `}`):

```swift
if currentVersion < 5 { try migrateToV5() }
```

3. Add after `migrateToV4()`:

```swift
/// V5: Add project_id to pending_signals for project-scoped summary generation
private func migrateToV5() throws {
    MemoryLogger.database.info("Running migration to v5")

    try executeRaw("ALTER TABLE pending_signals ADD COLUMN project_id TEXT")

    try executeRaw(
        "INSERT OR IGNORE INTO schema_version (version, description) VALUES (5, 'Add project_id to pending_signals')"
    )
    try setSchemaVersion(5)
    MemoryLogger.database.info("Migration to v5 completed")
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/OsaurusCore --filter DatabaseMigrationTests/memoryDatabaseV5AddsProjectIdToPendingSignals`
Expected: PASS

- [ ] **Step 5: Run all existing migration tests to verify no regressions**

Run: `swift test --package-path Packages/OsaurusCore --filter DatabaseMigrationTests`
Expected: All tests PASS

- [ ] **Step 6: Compile check**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: No errors

- [ ] **Step 7: Commit**

```bash
git add Packages/OsaurusCore/Storage/MemoryDatabase.swift Packages/OsaurusCore/Tests/Project/DatabaseMigrationTests.swift
git commit -m "feat(memory): V5 migration — add project_id to pending_signals"
```

---

### Task 2: Model Changes — Add projectId to 3 structs

**Files:**

- Modify: `Packages/OsaurusCore/Models/Memory/MemoryModels.swift:100-185` (MemoryEntry), `:190-222` (ConversationSummary), `:262-291` (PendingSignal)

- [ ] **Step 1: Add projectId to MemoryEntry**

In `MemoryModels.swift`, modify `MemoryEntry` (line 100):

1. Add property after `validUntil` (line 115):

```swift
public var projectId: String?
```

2. Add to CodingKeys enum (line 119-123) — add `projectId` at end:

```swift
private enum CodingKeys: String, CodingKey {
    case id, agentId, type, content, confidence, model, sourceConversationId
    case tagsJSON, status, supersededBy, createdAt, lastAccessed, accessCount
    case validFrom, validUntil, projectId
}
```

3. Add `projectId: String? = nil` parameter to init (after `validUntil` param, line 147):

```swift
projectId: String? = nil
```

And add assignment at end of init body (after line 164):

```swift
self.projectId = projectId
```

4. Add to custom decoder `init(from:)` (after line 183):

```swift
projectId = try c.decodeIfPresent(String.self, forKey: .projectId)
```

- [ ] **Step 2: Add projectId to ConversationSummary**

In `ConversationSummary` (line 190):

1. Add property after `createdAt` (line 199):

```swift
public var projectId: String?
```

2. Add `projectId: String? = nil` parameter to init (after `createdAt` param, line 210):

```swift
projectId: String? = nil
```

And add assignment at end of init body (after line 220):

```swift
self.projectId = projectId
```

- [ ] **Step 3: Add projectId to PendingSignal**

In `PendingSignal` (line 262):

1. Add property after `createdAt` (line 270):

```swift
public var projectId: String?
```

2. Add `projectId: String? = nil` parameter to init (after `createdAt` param, line 280):

```swift
projectId: String? = nil
```

And add assignment at end of init body (after line 289):

```swift
self.projectId = projectId
```

- [ ] **Step 4: Compile check**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: No errors (all defaults are nil, so every existing callsite compiles unchanged)

- [ ] **Step 5: Commit**

```bash
git add Packages/OsaurusCore/Models/Memory/MemoryModels.swift
git commit -m "feat(memory): add projectId to MemoryEntry, ConversationSummary, PendingSignal"
```

---

### Task 3: Database Layer — Column Lists, Readers, INSERTs

**Files:**

- Modify: `Packages/OsaurusCore/Storage/MemoryDatabase.swift`

This is the largest task. All changes are in `MemoryDatabase.swift`.

- [ ] **Step 1: Update memoryEntryColumns and readMemoryEntry**

1. Line 36-38 — append `, project_id` to column list:

```swift
private static let memoryEntryColumns = """
    id, agent_id, type, content, confidence, model, source_conversation_id, tags, status,
    superseded_by, created_at, last_accessed, access_count, valid_from, valid_until, project_id
    """
```

2. Line 1076 — update `readMemoryEntry()` to read column 15:

```swift
private static func readMemoryEntry(_ stmt: OpaquePointer) -> MemoryEntry {
    MemoryEntry(
        id: String(cString: sqlite3_column_text(stmt, 0)),
        agentId: String(cString: sqlite3_column_text(stmt, 1)),
        type: MemoryEntryType(rawValue: String(cString: sqlite3_column_text(stmt, 2))) ?? .fact,
        content: String(cString: sqlite3_column_text(stmt, 3)),
        confidence: sqlite3_column_double(stmt, 4),
        model: String(cString: sqlite3_column_text(stmt, 5)),
        sourceConversationId: sqlite3_column_text(stmt, 6).map { String(cString: $0) },
        tagsJSON: sqlite3_column_text(stmt, 7).map { String(cString: $0) },
        status: String(cString: sqlite3_column_text(stmt, 8)),
        supersededBy: sqlite3_column_text(stmt, 9).map { String(cString: $0) },
        createdAt: String(cString: sqlite3_column_text(stmt, 10)),
        lastAccessed: String(cString: sqlite3_column_text(stmt, 11)),
        accessCount: Int(sqlite3_column_int(stmt, 12)),
        validFrom: String(cString: sqlite3_column_text(stmt, 13)),
        validUntil: sqlite3_column_text(stmt, 14).map { String(cString: $0) },
        projectId: sqlite3_column_text(stmt, 15).map { String(cString: $0) }
    )
}
```

- [ ] **Step 2: Update insertEntrySQL and bindInsertEntry**

1. Line 799-803 — add `project_id` column and `?11` placeholder:

```swift
private static let insertEntrySQL = """
    INSERT INTO memory_entries (id, agent_id, type, content, confidence, model,
        source_conversation_id, tags, status, valid_from, project_id)
    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
    """
```

2. Line 822-834 — add binding at end of `bindInsertEntry()`:
   After `Self.bindText(stmt, index: 10, value: validFrom)` add:

```swift
Self.bindText(stmt, index: 11, value: entry.projectId)
```

- [ ] **Step 3: Update insertSummary and insertSummaryAndMarkProcessed**

1. Line 1098-1111 — update `insertSummary()`:

```swift
public func insertSummary(_ summary: ConversationSummary) throws {
    _ = try executeUpdate(
        """
        INSERT INTO conversation_summaries (agent_id, conversation_id, summary, token_count, model, conversation_at, project_id)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
        """
    ) { stmt in
        Self.bindText(stmt, index: 1, value: summary.agentId)
        Self.bindText(stmt, index: 2, value: summary.conversationId)
        Self.bindText(stmt, index: 3, value: summary.summary)
        sqlite3_bind_int(stmt, 4, Int32(summary.tokenCount))
        Self.bindText(stmt, index: 5, value: summary.model)
        Self.bindText(stmt, index: 6, value: summary.conversationAt)
        Self.bindText(stmt, index: 7, value: summary.projectId)
    }
}
```

2. Line 1115-1136 — update `insertSummaryAndMarkProcessed()` (the INSERT within the transaction):

```swift
public func insertSummaryAndMarkProcessed(_ summary: ConversationSummary) throws {
    try inTransaction { _ in
        try self.transactionalStep(
            """
            INSERT INTO conversation_summaries (agent_id, conversation_id, summary, token_count, model, conversation_at, project_id)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
            """
        ) { stmt in
            Self.bindText(stmt, index: 1, value: summary.agentId)
            Self.bindText(stmt, index: 2, value: summary.conversationId)
            Self.bindText(stmt, index: 3, value: summary.summary)
            sqlite3_bind_int(stmt, 4, Int32(summary.tokenCount))
            Self.bindText(stmt, index: 5, value: summary.model)
            Self.bindText(stmt, index: 6, value: summary.conversationAt)
            Self.bindText(stmt, index: 7, value: summary.projectId)
        }
        try self.transactionalStep(
            "UPDATE pending_signals SET status = 'processed' WHERE conversation_id = ?1 AND status = 'pending'"
        ) { stmt in
            Self.bindText(stmt, index: 1, value: summary.conversationId)
        }
    }
}
```

- [ ] **Step 4: Update readSummary to include project_id**

All summary SELECT statements need `, project_id` appended. There are multiple locations:

1. `loadSummaries()` (lines 1142-1148, 1150-1155) — both SQL variants:
   Add `, project_id` after `created_at` in both SELECT statements.

2. `loadAllSummaries()` (lines 1176-1180, 1183-1187) — both SQL variants:
   Add `, project_id` after `created_at` in both SELECT statements.

3. `loadSummariesByIds()` (line 1207):
   Add `, project_id` after `created_at`.

4. `searchSummaries()` (line 1718):
   Add `, project_id` after `created_at`.

5. `loadSummariesByCompositeKeys()` (line 1799):
   Add `, project_id` after `created_at`.

6. Update `readSummary()` (line 1252) to read the new column (index 9):

```swift
private static func readSummary(_ stmt: OpaquePointer) -> ConversationSummary {
    ConversationSummary(
        id: Int(sqlite3_column_int(stmt, 0)),
        agentId: String(cString: sqlite3_column_text(stmt, 1)),
        conversationId: String(cString: sqlite3_column_text(stmt, 2)),
        summary: String(cString: sqlite3_column_text(stmt, 3)),
        tokenCount: Int(sqlite3_column_int(stmt, 4)),
        model: String(cString: sqlite3_column_text(stmt, 5)),
        conversationAt: String(cString: sqlite3_column_text(stmt, 6)),
        status: String(cString: sqlite3_column_text(stmt, 7)),
        createdAt: String(cString: sqlite3_column_text(stmt, 8)),
        projectId: sqlite3_column_text(stmt, 9).map { String(cString: $0) }
    )
}
```

- [ ] **Step 5: Update insertPendingSignal and loadPendingSignals**

1. `insertPendingSignal()` (line 1423) — add `project_id` column:

```swift
public func insertPendingSignal(_ signal: PendingSignal) throws {
    _ = try executeUpdate(
        """
        INSERT INTO pending_signals (agent_id, conversation_id, signal_type, user_message, assistant_message, status, project_id)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
        """
    ) { stmt in
        Self.bindText(stmt, index: 1, value: signal.agentId)
        Self.bindText(stmt, index: 2, value: signal.conversationId)
        Self.bindText(stmt, index: 3, value: signal.signalType)
        Self.bindText(stmt, index: 4, value: signal.userMessage)
        Self.bindText(stmt, index: 5, value: signal.assistantMessage)
        Self.bindText(stmt, index: 6, value: signal.status)
        Self.bindText(stmt, index: 7, value: signal.projectId)
    }
}
```

2. Both `loadPendingSignals` overloads (lines 1439, 1464) — add `project_id` to SELECT and read it:

For `loadPendingSignals(agentId:)` (line 1439):
Change SELECT to include `, project_id` after `created_at`. Read column 8 as projectId in the `PendingSignal` init:

```swift
projectId: sqlite3_column_text(stmt, 8).map { String(cString: $0) }
```

For `loadPendingSignals(conversationId:)` (line 1464):
Same change — add `, project_id` to SELECT, read column 8.

- [ ] **Step 6: Update upsertConversation**

Line 1268 — add `projectId: String? = nil` parameter:

```swift
public func upsertConversation(id: String, agentId: String, title: String?, projectId: String? = nil) throws {
    _ = try executeUpdate(
        """
        INSERT INTO conversations (id, agent_id, title, started_at, last_message_at, message_count, project_id)
        VALUES (?1, ?2, ?3, datetime('now'), datetime('now'), 0, ?4)
        ON CONFLICT(id) DO UPDATE SET
            last_message_at = datetime('now'),
            message_count = conversations.message_count + 1,
            title = COALESCE(?3, conversations.title)
        """
    ) { stmt in
        Self.bindText(stmt, index: 1, value: id)
        Self.bindText(stmt, index: 2, value: agentId)
        Self.bindText(stmt, index: 3, value: title)
        Self.bindText(stmt, index: 4, value: projectId)
    }
}
```

Note: ON CONFLICT does NOT update project_id — preserves the original value.

- [ ] **Step 7: Compile check**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: No errors (all new params have defaults)

- [ ] **Step 8: Commit**

```bash
git add Packages/OsaurusCore/Storage/MemoryDatabase.swift
git commit -m "feat(memory): add project_id to all INSERT paths and column readers"
```

---

### Task 4: Database Layer — Query Methods with projectId filtering

**Files:**

- Modify: `Packages/OsaurusCore/Storage/MemoryDatabase.swift`
- Create: `Packages/OsaurusCore/Tests/Memory/MemoryProjectScopingTests.swift`

- [ ] **Step 1: Write project scoping tests**

Create `Packages/OsaurusCore/Tests/Memory/MemoryProjectScopingTests.swift`:

```swift
//
//  MemoryProjectScopingTests.swift
//  osaurus
//
//  Verifies that project-scoped queries return project + global entries.
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite(.serialized)
struct MemoryProjectScopingTests {

    // MARK: - Helpers

    private func makeDB() throws -> MemoryDatabase {
        let db = MemoryDatabase()
        try db.openInMemory()
        return db
    }

    private func makeEntry(
        agentId: String = "agent1",
        content: String,
        projectId: String? = nil
    ) -> MemoryEntry {
        MemoryEntry(
            agentId: agentId,
            type: .fact,
            content: content,
            model: "test",
            projectId: projectId
        )
    }

    // MARK: - MemoryEntry Tests

    @Test func memoryEntryProjectIdRoundTrip() throws {
        let db = try makeDB()
        defer { db.close() }

        let entry = makeEntry(content: "test fact", projectId: "project-1")
        try db.insertMemoryEntry(entry)

        let loaded = try db.loadActiveEntries(agentId: "agent1")
        #expect(loaded.count == 1)
        #expect(loaded[0].projectId == "project-1")
    }

    @Test func projectPlusGlobalUnionQuery() throws {
        let db = try makeDB()
        defer { db.close() }

        try db.insertMemoryEntry(makeEntry(content: "global fact"))
        try db.insertMemoryEntry(makeEntry(content: "project1 fact", projectId: "P1"))
        try db.insertMemoryEntry(makeEntry(content: "project2 fact", projectId: "P2"))

        let p1Results = try db.loadActiveEntries(agentId: "agent1", projectId: "P1")
        let contents = Set(p1Results.map(\.content))
        #expect(contents.contains("global fact"), "Should include global entries")
        #expect(contents.contains("project1 fact"), "Should include P1 entries")
        #expect(!contents.contains("project2 fact"), "Should NOT include P2 entries")
        #expect(p1Results.count == 2)
    }

    @Test func nilProjectIdReturnsAll() throws {
        let db = try makeDB()
        defer { db.close() }

        try db.insertMemoryEntry(makeEntry(content: "global fact"))
        try db.insertMemoryEntry(makeEntry(content: "project fact", projectId: "P1"))

        let results = try db.loadActiveEntries(agentId: "agent1")
        #expect(results.count == 2, "Nil projectId returns all entries (no filter)")
    }

    // MARK: - ConversationSummary Tests

    @Test func summaryProjectIdRoundTrip() throws {
        let db = try makeDB()
        defer { db.close() }

        let summary = ConversationSummary(
            agentId: "agent1",
            conversationId: "conv1",
            summary: "test summary",
            tokenCount: 10,
            model: "test",
            conversationAt: "2026-01-01T00:00:00Z",
            projectId: "P1"
        )
        try db.insertSummary(summary)

        let loaded = try db.loadSummaries(agentId: "agent1", projectId: "P1")
        #expect(loaded.count == 1)
        #expect(loaded[0].projectId == "P1")
    }

    @Test func summaryAndMarkProcessedProjectId() throws {
        let db = try makeDB()
        defer { db.close() }

        let signal = PendingSignal(
            agentId: "agent1",
            conversationId: "conv1",
            signalType: "conversation",
            userMessage: "hello",
            projectId: "P1"
        )
        try db.insertPendingSignal(signal)

        let summary = ConversationSummary(
            agentId: "agent1",
            conversationId: "conv1",
            summary: "summary text",
            tokenCount: 5,
            model: "test",
            conversationAt: "2026-01-01T00:00:00Z",
            projectId: "P1"
        )
        try db.insertSummaryAndMarkProcessed(summary)

        let loaded = try db.loadSummaries(agentId: "agent1", projectId: "P1")
        #expect(loaded.count == 1)
        #expect(loaded[0].projectId == "P1")
    }

    // MARK: - Conversation Upsert

    @Test func conversationUpsertPreservesProjectId() throws {
        let db = try makeDB()
        defer { db.close() }

        try db.upsertConversation(id: "conv1", agentId: "agent1", title: "First", projectId: "P1")
        // Upsert again without projectId — should preserve original
        try db.upsertConversation(id: "conv1", agentId: "agent1", title: "Updated")

        // Verify via chunks query that the conversation still has project_id
        try db.insertChunk(
            conversationId: "conv1", chunkIndex: 0, role: "user",
            content: "test", tokenCount: 1
        )
        let chunks = try db.loadAllChunks(agentId: "agent1", projectId: "P1")
        #expect(chunks.count == 1, "Chunk should be visible via P1 project filter")
    }

    // MARK: - PendingSignal Tests

    @Test func pendingSignalProjectIdRoundTrip() throws {
        let db = try makeDB()
        defer { db.close() }

        let signal = PendingSignal(
            agentId: "agent1",
            conversationId: "conv1",
            signalType: "conversation",
            userMessage: "hello",
            projectId: "P1"
        )
        try db.insertPendingSignal(signal)

        let loaded = try db.loadPendingSignals(agentId: "agent1")
        #expect(loaded.count == 1)
        #expect(loaded[0].projectId == "P1")

        let byConv = try db.loadPendingSignals(conversationId: "conv1")
        #expect(byConv.count == 1)
        #expect(byConv[0].projectId == "P1")
    }

    // MARK: - pendingConversations

    @Test func pendingConversationsReturnsProjectId() throws {
        let db = try makeDB()
        defer { db.close() }

        let signal = PendingSignal(
            agentId: "agent1",
            conversationId: "conv1",
            signalType: "conversation",
            userMessage: "hello",
            projectId: "P1"
        )
        try db.insertPendingSignal(signal)

        let pending = try db.pendingConversations()
        #expect(pending.count == 1)
        #expect(pending[0].projectId == "P1")
    }

    // MARK: - loadEntriesByIds with projectId

    @Test func loadEntriesByIdsWithProjectId() throws {
        let db = try makeDB()
        defer { db.close() }

        let e1 = makeEntry(content: "global", projectId: nil)
        let e2 = makeEntry(content: "p1 entry", projectId: "P1")
        let e3 = makeEntry(content: "p2 entry", projectId: "P2")
        try db.insertMemoryEntry(e1)
        try db.insertMemoryEntry(e2)
        try db.insertMemoryEntry(e3)

        let ids = [e1.id, e2.id, e3.id]
        let filtered = try db.loadEntriesByIds(ids, agentId: "agent1", projectId: "P1")
        let contents = Set(filtered.map(\.content))
        #expect(contents.contains("global"))
        #expect(contents.contains("p1 entry"))
        #expect(!contents.contains("p2 entry"))
    }

    // MARK: - Entities remain global

    @Test func entitiesRemainGlobal() throws {
        let db = try makeDB()
        defer { db.close() }

        // resolveEntity creates entity with INSERT OR IGNORE — should NOT set project_id
        let entity = try db.resolveEntity(name: "HVAC System", type: "system", model: "test")
        #expect(entity.name == "HVAC System")

        // Query entity and verify project_id is nil via direct SQL
        try db.execute { connection in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(connection, "SELECT project_id FROM entities WHERE id = ?1", -1, &stmt, nil) == SQLITE_OK else {
                return
            }
            let idCStr = entity.id.cString(using: .utf8)!
            sqlite3_bind_text(stmt, 1, idCStr, -1, nil)
            if sqlite3_step(stmt!) == SQLITE_ROW {
                let projectId = sqlite3_column_text(stmt!, 0)
                #expect(projectId == nil, "Entity project_id should be NULL (global)")
            }
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path Packages/OsaurusCore --filter MemoryProjectScopingTests`
Expected: Most tests FAIL — projectId not wired through queries yet.

- [ ] **Step 3: Add projectId to loadActiveEntries**

Line 849 — add `projectId: String? = nil` parameter:

```swift
public func loadActiveEntries(agentId: String, limit: Int = 0, projectId: String? = nil) throws -> [MemoryEntry] {
    var entries: [MemoryEntry] = []
    var sql = """
        SELECT \(Self.memoryEntryColumns)
        FROM memory_entries WHERE agent_id = ?1 AND status = 'active'
        """
    if let projectId {
        sql += " AND (project_id = ?3 OR project_id IS NULL)"
    }
    sql += " ORDER BY last_accessed DESC"
    if limit > 0 { sql += " LIMIT ?2" }
    try prepareAndExecute(
        sql,
        bind: { stmt in
            Self.bindText(stmt, index: 1, value: agentId)
            if limit > 0 { sqlite3_bind_int(stmt, 2, Int32(limit)) }
            if let projectId { Self.bindText(stmt, index: 3, value: projectId) }
        },
        process: { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                entries.append(Self.readMemoryEntry(stmt))
            }
        }
    )
    return entries
}
```

- [ ] **Step 4: Add projectId to loadEntriesByIds**

Line 891 — add `projectId: String? = nil` parameter. Dynamic binding index:

```swift
public func loadEntriesByIds(_ ids: [String], agentId: String? = nil, projectId: String? = nil) throws -> [MemoryEntry] {
    guard !ids.isEmpty else { return [] }
    let placeholders = ids.enumerated().map { "?\($0.offset + 1)" }.joined(separator: ",")
    var sql = """
        SELECT \(Self.memoryEntryColumns)
        FROM memory_entries WHERE status = 'active' AND id IN (\(placeholders))
        """
    var nextParam = ids.count + 1
    if agentId != nil {
        sql += " AND agent_id = ?\(nextParam)"
        nextParam += 1
    }
    if projectId != nil {
        sql += " AND (project_id = ?\(nextParam) OR project_id IS NULL)"
    }
    sql += " ORDER BY last_accessed DESC"

    var entries: [MemoryEntry] = []
    try prepareAndExecute(
        sql,
        bind: { stmt in
            for (i, id) in ids.enumerated() {
                Self.bindText(stmt, index: Int32(i + 1), value: id)
            }
            var bindIdx = Int32(ids.count + 1)
            if let agentId {
                Self.bindText(stmt, index: bindIdx, value: agentId)
                bindIdx += 1
            }
            if let projectId {
                Self.bindText(stmt, index: bindIdx, value: projectId)
            }
        },
        process: { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                entries.append(Self.readMemoryEntry(stmt))
            }
        }
    )
    return entries
}
```

- [ ] **Step 5: Add projectId to summary query methods**

For `loadSummaries(agentId:days:)` (line 1138) — add `projectId: String? = nil`:
When projectId is non-nil, append `AND (project_id = ?N OR project_id IS NULL)` to both SQL variants. Bind projectId at the appropriate index (after the existing parameters).

For `loadAllSummaries(days:)` (line 1172) — add `projectId: String? = nil`:
Same pattern.

For `searchSummaries(query:agentId:days:)` (line 1715) — add `projectId: String? = nil`:
Same pattern.

For `searchMemoryEntries(query:agentId:)` (line 1634) — add `projectId: String? = nil`:
Same pattern.

- [ ] **Step 6: Add projectId to chunk query methods**

For `loadAllChunks(agentId:days:limit:)` (line 1317) — add `projectId: String? = nil`:
Filter via `AND (c.project_id = ?N OR c.project_id IS NULL)`.

For `searchChunks(query:agentId:days:)` (line 1378) — add `projectId: String? = nil`:
Same pattern via `c.project_id`.

For `loadChunksByKeys(_:)` (line 1347) — add `projectId: String? = nil`:
Add `AND (c.project_id = ?N OR c.project_id IS NULL)` to WHERE clause. Binding index: `keys.count * 2 + 1`.

- [ ] **Step 7: Add projectId to loadEntriesAsOf**

Line 1660 — add `projectId: String? = nil`:

```swift
if let projectId {
    sql += " AND (project_id = ?3 OR project_id IS NULL)"
}
```

Bind at index 3.

- [ ] **Step 8: Add projectId to loadSummariesByCompositeKeys**

Line 1790 — add `filterProjectId: String? = nil`:
Binding index: `keys.count * 3 + (filterAgentId != nil ? 2 : 1)`.

- [ ] **Step 9: Update pendingConversations return type**

Line 1512 — add `project_id` to SELECT, return tuple with projectId:

```swift
public func pendingConversations() throws -> [(agentId: String, conversationId: String, projectId: String?)] {
    var results: [(agentId: String, conversationId: String, projectId: String?)] = []
    try prepareAndExecute(
        "SELECT DISTINCT agent_id, conversation_id, project_id FROM pending_signals WHERE status = 'pending'",
        bind: { _ in },
        process: { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(
                    (
                        agentId: String(cString: sqlite3_column_text(stmt, 0)),
                        conversationId: String(cString: sqlite3_column_text(stmt, 1)),
                        projectId: sqlite3_column_text(stmt, 2).map { String(cString: $0) }
                    )
                )
            }
        }
    )
    return results
}
```

- [ ] **Step 10: Add countEntriesByProject convenience method**

Add after the query methods section:

```swift
public func countEntriesByProject(projectId: String) throws -> (total: Int, byType: [MemoryEntryType: Int]) {
    var byType: [MemoryEntryType: Int] = [:]
    try prepareAndExecute(
        """
        SELECT type, COUNT(*) FROM memory_entries
        WHERE status = 'active' AND project_id = ?1
        GROUP BY type
        """,
        bind: { stmt in Self.bindText(stmt, index: 1, value: projectId) },
        process: { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                let typeStr = String(cString: sqlite3_column_text(stmt, 0))
                let count = Int(sqlite3_column_int(stmt, 1))
                if let entryType = MemoryEntryType(rawValue: typeStr) {
                    byType[entryType] = count
                }
            }
        }
    )
    let total = byType.values.reduce(0, +)
    return (total, byType)
}
```

- [ ] **Step 11: Run project scoping tests**

Run: `swift test --package-path Packages/OsaurusCore --filter MemoryProjectScopingTests`
Expected: All PASS

- [ ] **Step 12: Run all memory tests**

Run: `swift test --package-path Packages/OsaurusCore --filter MemoryTests`
Expected: All PASS (existing tests unaffected — default projectId is nil)

- [ ] **Step 13: Compile check**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: No errors

- [ ] **Step 14: Commit**

```bash
git add Packages/OsaurusCore/Storage/MemoryDatabase.swift Packages/OsaurusCore/Tests/Memory/MemoryProjectScopingTests.swift
git commit -m "feat(memory): project-scoped query methods with union semantics"
```

---

### Task 5: MemoryService — Forward projectId through pipeline

**Files:**

- Modify: `Packages/OsaurusCore/Services/Memory/MemoryService.swift`

- [ ] **Step 1: Add conversationProjectIds map**

At line 24, after `conversationSessionDates`, add:

```swift
private var conversationProjectIds: [String: String?] = [:]
```

- [ ] **Step 2: Update recordConversationTurn to forward projectId**

In `recordConversationTurn()` (line 33-167):

1. Line 42-50 — pass projectId to PendingSignal:

```swift
try db.insertPendingSignal(
    PendingSignal(
        agentId: agentId,
        conversationId: conversationId,
        signalType: "conversation",
        userMessage: userMessage,
        assistantMessage: assistantMessage,
        projectId: projectId
    )
)
```

2. Line 61 — pass projectId to loadActiveEntries:

```swift
allExistingEntries = try db.loadActiveEntries(agentId: agentId, projectId: projectId)
```

3. Line 85-90 — pass projectId to buildMemoryEntries:

```swift
let entries = buildMemoryEntries(
    from: parsed.entries,
    agentId: agentId,
    conversationId: conversationId,
    model: coreModelId,
    projectId: projectId
)
```

4. After the `activeConversation[agentId] = conversationId` line (144), add:

```swift
conversationProjectIds[conversationId] = projectId
```

5. Line 151-153 — session-change trigger, pass previous projectId:

```swift
let prevProjectId = conversationProjectIds[prev]
Task {
    await self.generateConversationSummary(agentId: prevAgent, conversationId: prev, sessionDate: prevDate, projectId: prevProjectId ?? nil)
}
```

6. Line 159-167 — debounced summary, capture projectId:

```swift
let capturedProjectId = projectId
summaryTasks[conversationId] = Task {
    try? await Task.sleep(for: .seconds(debounceSeconds))
    guard !Task.isCancelled else { return }
    await self.generateConversationSummary(
        agentId: agentId,
        conversationId: conversationId,
        sessionDate: capturedDate,
        projectId: capturedProjectId
    )
}
```

- [ ] **Step 3: Update buildMemoryEntries to set projectId**

Line 700 — add `projectId: String? = nil` parameter:

```swift
private func buildMemoryEntries(
    from parsed: [ExtractionParseResult.EntryData],
    agentId: String,
    conversationId: String,
    model: String,
    projectId: String? = nil
) -> [MemoryEntry] {
```

In the `MemoryEntry` init call (line 714), add `projectId: projectId`:

```swift
return MemoryEntry(
    agentId: agentId,
    type: entryType,
    content: entry.content,
    confidence: entry.confidence ?? 0.8,
    model: model,
    sourceConversationId: conversationId,
    tagsJSON: tagsJSON,
    validFrom: entry.valid_from ?? "",
    projectId: projectId
)
```

- [ ] **Step 4: Update generateConversationSummary**

Line 350 — add `projectId: String? = nil` parameter:

```swift
private func generateConversationSummary(agentId: String, conversationId: String, sessionDate: String? = nil, projectId: String? = nil) async {
```

Line 398-405 — set projectId on summary:

```swift
let summaryObj = ConversationSummary(
    agentId: agentId,
    conversationId: conversationId,
    summary: summaryText,
    tokenCount: tokenCount,
    model: coreModelId,
    conversationAt: conversationAt,
    projectId: projectId
)
```

- [ ] **Step 5: Update flushSession**

Line 332 — add `projectId: String? = nil` parameter:

```swift
public func flushSession(agentId: String, conversationId: String, projectId: String? = nil) {
    summaryTasks[conversationId]?.cancel()
    summaryTasks[conversationId] = Task {
        await self.generateConversationSummary(agentId: agentId, conversationId: conversationId, projectId: projectId)
    }
}
```

- [ ] **Step 6: Update recoverOrphanedSignals**

Line 260-279 — thread projectId from updated `pendingConversations()`:

```swift
public func recoverOrphanedSignals() async {
    let config = MemoryConfigurationStore.load()
    guard config.enabled, await hasCoreModel() else { return }

    let conversations: [(agentId: String, conversationId: String, projectId: String?)]
    do {
        conversations = try db.pendingConversations()
    } catch {
        MemoryLogger.service.warning("Startup recovery: failed to check pending signals: \(error)")
        return
    }

    guard !conversations.isEmpty else { return }
    MemoryLogger.service.info(
        "Startup recovery: processing \(conversations.count) orphaned conversation(s)"
    )
    for conv in conversations {
        await generateConversationSummary(agentId: conv.agentId, conversationId: conv.conversationId, projectId: conv.projectId)
    }
    MemoryLogger.service.info("Startup recovery completed")
}
```

- [ ] **Step 7: Update syncNow**

Line 284-326 — same pattern as recoverOrphanedSignals:

```swift
let conversations: [(agentId: String, conversationId: String, projectId: String?)]
```

And in the for loop:

```swift
for conv in conversations {
    await generateConversationSummary(agentId: conv.agentId, conversationId: conv.conversationId, projectId: conv.projectId)
}
```

- [ ] **Step 8: Compile check**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: No errors

- [ ] **Step 9: Commit**

```bash
git add Packages/OsaurusCore/Services/Memory/MemoryService.swift
git commit -m "feat(memory): forward projectId through recording + summary pipeline"
```

---

### Task 6: MemorySearchService — Add projectId filtering

**Files:**

- Modify: `Packages/OsaurusCore/Services/Memory/MemorySearchService.swift`

- [ ] **Step 1: Add projectId to searchMemoryEntries**

Line 158 — add `projectId: String? = nil` parameter:

```swift
public func searchMemoryEntries(
    query: String,
    agentId: String? = nil,
    projectId: String? = nil,
    topK: Int = 10,
    lambda: Double? = nil,
    fetchMultiplier: Double? = nil
) async -> [MemoryEntry] {
```

Line 181 — pass projectId to loadEntriesByIds:

```swift
let entries = try MemoryDatabase.shared.loadEntriesByIds(idStrings, agentId: agentId, projectId: projectId)
```

Line 194 — pass projectId to text fallback:

```swift
return try MemoryDatabase.shared.searchMemoryEntries(query: query, agentId: agentId, projectId: projectId)
```

- [ ] **Step 2: Add projectId to searchConversations**

Line 241 — add `projectId: String? = nil` parameter:

```swift
public func searchConversations(
    query: String,
    agentId: String? = nil,
    projectId: String? = nil,
    days: Int = 30,
    ...
```

Line 269 — pass projectId to loadChunksByKeys:

```swift
let chunks = try MemoryDatabase.shared.loadChunksByKeys(keys, projectId: projectId)
```

Line 289 — pass projectId to text fallback:

```swift
return try MemoryDatabase.shared.searchChunks(query: query, agentId: agentId, days: days, projectId: projectId)
```

- [ ] **Step 3: Add projectId to searchSummaries**

Line 299 — add `projectId: String? = nil` parameter:

```swift
public func searchSummaries(
    query: String,
    agentId: String? = nil,
    projectId: String? = nil,
    days: Int = 30,
    ...
```

Line 327-330 — pass projectId to loadSummariesByCompositeKeys:

```swift
let summaries = try MemoryDatabase.shared.loadSummariesByCompositeKeys(
    compositeKeys,
    filterAgentId: agentId,
    filterProjectId: projectId
)
```

Line 348 — pass projectId to text fallback:

```swift
return try MemoryDatabase.shared.searchSummaries(query: query, agentId: agentId, days: days, projectId: projectId)
```

- [ ] **Step 4: Compile check**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: No errors

- [ ] **Step 5: Commit**

```bash
git add Packages/OsaurusCore/Services/Memory/MemorySearchService.swift
git commit -m "feat(memory): add projectId filtering to search service"
```

---

### Task 7: MemoryContextAssembler — Fix stub bugs and forward projectId

**Files:**

- Modify: `Packages/OsaurusCore/Services/Memory/MemoryContextAssembler.swift`

- [ ] **Step 1: Fix assembleContextWithQuery stub bug**

Line 85-109 — the projectId overload currently drops projectId. Fix:

```swift
private func assembleContextWithQuery(
    agentId: String,
    config: MemoryConfiguration,
    query: String,
    projectId: String?
) async -> String {
    guard config.enabled else { return "" }

    let baseContext = buildContext(agentId: agentId, config: config, projectId: projectId)

    guard !query.isEmpty else { return baseContext }

    let relevantSection = await buildQueryRelevantSection(
        agentId: agentId,
        query: query,
        config: config,
        existingContext: baseContext,
        projectId: projectId
    )

    if relevantSection.isEmpty {
        return baseContext
    }

    return baseContext.isEmpty ? relevantSection : baseContext + "\n\n" + relevantSection
}
```

- [ ] **Step 2: Fix assembleContextCached stub bug**

Line 123-134 — the projectId overload currently drops projectId. Fix:

```swift
private func assembleContextCached(agentId: String, config: MemoryConfiguration, projectId: String?) -> String {
    guard config.enabled else { return "" }

    let cacheKey = "\(agentId):\(projectId ?? "global")"
    if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < Self.cacheTTL {
        return cached.context
    }

    let context = buildContext(agentId: agentId, config: config, projectId: projectId)
    cache[cacheKey] = CacheEntry(context: context, timestamp: Date())
    return context
}
```

- [ ] **Step 3: Add projectId to buildContext**

Line 146 — add `projectId: String? = nil` parameter:

```swift
private func buildContext(agentId: String, config: MemoryConfiguration, projectId: String? = nil) -> String {
```

Find where `db.loadActiveEntries` is called inside buildContext and pass projectId:

```swift
let entries = try db.loadActiveEntries(agentId: agentId, limit: ..., projectId: projectId)
```

Find where `db.loadSummaries` is called and pass projectId:

```swift
let summaries = try db.loadSummaries(agentId: agentId, days: ..., projectId: projectId)
```

- [ ] **Step 4: Add projectId overload to buildQueryRelevantSection**

Add a new overload (keeping the original for non-projectId callers):

```swift
private func buildQueryRelevantSection(
    agentId: String,
    query: String,
    config: MemoryConfiguration,
    existingContext: String,
    projectId: String?
) async -> String {
    let searchService = MemorySearchService.shared

    let topK = config.recallTopK
    let lambda = config.mmrLambda
    let fetchMultiplier = config.mmrFetchMultiplier

    async let entriesResult = searchService.searchMemoryEntries(
        query: query,
        agentId: agentId,
        projectId: projectId,
        topK: topK,
        lambda: lambda,
        fetchMultiplier: fetchMultiplier
    )
    async let chunksResult = searchService.searchConversations(
        query: query,
        agentId: agentId,
        projectId: projectId,
        days: 3650,
        topK: topK,
        lambda: lambda,
        fetchMultiplier: fetchMultiplier
    )
    async let summariesResult = searchService.searchSummaries(
        query: query,
        agentId: agentId,
        projectId: projectId,
        topK: topK,
        lambda: lambda,
        fetchMultiplier: fetchMultiplier
    )
```

The rest of the method body is identical to the original — copy it from the existing `buildQueryRelevantSection`.

- [ ] **Step 5: Compile check**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: No errors

- [ ] **Step 6: Commit**

```bash
git add Packages/OsaurusCore/Services/Memory/MemoryContextAssembler.swift
git commit -m "feat(memory): fix assembler stub bugs, forward projectId to all data access"
```

---

### Task 8: Callers — Pass projectId from UI state

**Files:**

- Modify: `Packages/OsaurusCore/Views/Chat/ChatView.swift:659,716`
- Modify: `Packages/OsaurusCore/Views/Work/WorkSession.swift:1471`
- Modify: `Packages/OsaurusCore/Networking/HTTPHandler.swift:1400,1439`
- Modify: `Packages/OsaurusCore/Services/Chat/SystemPromptComposer.swift:274`
- Modify: `Packages/OsaurusCore/Managers/Chat/ChatWindowState.swift:318`

- [ ] **Step 1: Update ChatView — upsertConversation and recordConversationTurn**

Line 659 — pass projectId to upsertConversation. The active project is accessible via `ProjectManager.shared.activeProjectId`:

```swift
let activeProjectId = ProjectManager.shared.activeProjectId?.uuidString
do { try db.upsertConversation(id: convId, agentId: aid, title: title, projectId: activeProjectId) } catch {
```

Line 716-722 — pass projectId to recordConversationTurn:

```swift
await MemoryService.shared.recordConversationTurn(
    userMessage: context.userContent,
    assistantMessage: assistantContent,
    agentId: context.memoryAgentId,
    conversationId: context.memoryConversationId,
    sessionDate: today,
    projectId: activeProjectId
)
```

Note: Capture `activeProjectId` before the `Task.detached` to avoid @MainActor access from detached task.

- [ ] **Step 2: Update WorkSession**

Line 1471 — pass projectId. WorkSession may have a project context. Check if there's an active project:

```swift
let projectIdStr = await MainActor.run { ProjectManager.shared.activeProjectId?.uuidString }
await MemoryService.shared.recordConversationTurn(
    userMessage: userMessage,
    assistantMessage: assistantContent,
    agentId: agentStr,
    conversationId: convId,
    projectId: projectIdStr
)
```

- [ ] **Step 3: Update HTTPHandler ingest**

Line 1400 — pass project_id to upsertConversation:

```swift
try? db.upsertConversation(
    id: req.conversation_id,
    agentId: req.agent_id,
    title: nil,
    projectId: req.project_id
)
```

Line 1439 — pass project_id to recordConversationTurn:

```swift
await MemoryService.shared.recordConversationTurn(
    userMessage: turn.user,
    assistantMessage: turn.assistant,
    agentId: req.agent_id,
    conversationId: req.conversation_id,
    sessionDate: turnDate,
    projectId: req.project_id
)
```

Also add `project_id` field to the ingest request struct (find the `IngestRequest` Codable struct and add):

```swift
var project_id: String?
```

- [ ] **Step 4: Update SystemPromptComposer.injectAgentContext**

Line 274 — read active project inline (method is @MainActor so this is safe):

```swift
let activeProjectId = ProjectManager.shared.activeProjectId?.uuidString
await composer.appendMemory(agentId: agentId.uuidString, query: query.isEmpty ? nil : query, projectId: activeProjectId)
```

- [ ] **Step 5: Update ChatWindowState.flushCurrentSession**

Line 318-325 — pass projectId to flushSession:

```swift
private func flushCurrentSession() {
    guard let sid = session.sessionId else { return }
    let agentStr = (session.agentId ?? Agent.defaultId).uuidString
    let convStr = sid.uuidString
    let projectIdStr = ProjectManager.shared.activeProjectId?.uuidString
    Task {
        await MemoryService.shared.flushSession(agentId: agentStr, conversationId: convStr, projectId: projectIdStr)
    }
}
```

- [ ] **Step 6: Compile check**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: No errors

- [ ] **Step 7: Commit**

```bash
git add Packages/OsaurusCore/Views/Chat/ChatView.swift Packages/OsaurusCore/Views/Work/WorkSession.swift Packages/OsaurusCore/Networking/HTTPHandler.swift Packages/OsaurusCore/Services/Chat/SystemPromptComposer.swift Packages/OsaurusCore/Managers/Chat/ChatWindowState.swift
git commit -m "feat(memory): pass projectId from all UI callers to memory pipeline"
```

---

### Task 9: MemorySummaryView — Live project memory display

**Files:**

- Modify: `Packages/OsaurusCore/Views/Projects/MemorySummaryView.swift`

- [ ] **Step 1: Replace static placeholder with live view**

Replace the entire file content:

```swift
//
//  MemorySummaryView.swift
//  osaurus
//
//  Compact view of project-scoped memory entries for the inspector panel.
//

import SwiftUI

/// Compact view of project-scoped memory entries for the inspector panel.
struct MemorySummaryView: View {
    let projectId: UUID

    @Environment(\.theme) private var theme
    @State private var total: Int = 0
    @State private var byType: [MemoryEntryType: Int] = [:]
    @State private var recentEntries: [MemoryEntry] = []

    var body: some View {
        if total == 0 {
            VStack(spacing: 8) {
                Image(systemName: "brain")
                    .font(.system(size: 18))
                    .foregroundColor(theme.tertiaryText)
                Text("No memories yet")
                    .font(.caption)
                    .foregroundColor(theme.tertiaryText)
                Text("Memories from project conversations will appear here")
                    .font(.caption2)
                    .foregroundColor(theme.tertiaryText.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .task { await loadData() }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "brain")
                        .font(.system(size: 12))
                        .foregroundColor(theme.accentColor)
                    Text("\(total) memor\(total == 1 ? "y" : "ies")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.primaryText)
                }

                if !byType.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(byType.sorted(by: { $0.value > $1.value }), id: \.key) { type, count in
                            Text("\(type.displayName) \(count)")
                                .font(.system(size: 9))
                                .foregroundColor(theme.secondaryText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(theme.secondaryBackground.opacity(0.5))
                                )
                        }
                    }
                }

                if !recentEntries.isEmpty {
                    Divider()
                    ForEach(recentEntries.prefix(3), id: \.id) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(theme.accentColor.opacity(0.4))
                                .frame(width: 4, height: 4)
                                .padding(.top, 5)
                            Text(entry.content)
                                .font(.system(size: 10))
                                .foregroundColor(theme.secondaryText)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .task { await loadData() }
        }
    }

    private func loadData() async {
        let db = MemoryDatabase.shared
        guard db.isOpen else { return }
        let pid = projectId.uuidString
        do {
            let stats = try db.countEntriesByProject(projectId: pid)
            total = stats.total
            byType = stats.byType

            let entries = try db.loadActiveEntries(agentId: "", limit: 5, projectId: pid)
            // loadActiveEntries filters by agent_id — for project view we want all agents.
            // Use a direct query instead:
            recentEntries = try db.loadProjectEntries(projectId: pid, limit: 5)
        } catch {
            // Silently fail — empty state is fine
        }
    }
}
```

Note: We need a `loadProjectEntries` convenience that doesn't filter by agent_id. Add to MemoryDatabase:

```swift
public func loadProjectEntries(projectId: String, limit: Int = 5) throws -> [MemoryEntry] {
    var entries: [MemoryEntry] = []
    try prepareAndExecute(
        """
        SELECT \(Self.memoryEntryColumns)
        FROM memory_entries WHERE status = 'active' AND project_id = ?1
        ORDER BY last_accessed DESC LIMIT ?2
        """,
        bind: { stmt in
            Self.bindText(stmt, index: 1, value: projectId)
            sqlite3_bind_int(stmt, 2, Int32(limit))
        },
        process: { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                entries.append(Self.readMemoryEntry(stmt))
            }
        }
    )
    return entries
}
```

- [ ] **Step 2: Check if FlowLayout exists in the project**

Search for `FlowLayout` in the codebase. If it doesn't exist, replace the `FlowLayout` in MemorySummaryView with a simple `HStack` wrapping or `LazyVGrid`. If it does exist, use it.

- [ ] **Step 3: Compile check**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add Packages/OsaurusCore/Views/Projects/MemorySummaryView.swift Packages/OsaurusCore/Storage/MemoryDatabase.swift
git commit -m "feat(memory): replace MemorySummaryView placeholder with live project memory display"
```

---

### Task 10: Final Integration Test

- [ ] **Step 1: Run all tests**

Run: `swift test --package-path Packages/OsaurusCore`
Expected: All tests PASS

- [ ] **Step 2: Run project-specific tests**

Run: `swift test --package-path Packages/OsaurusCore --filter MemoryProjectScopingTests`
Expected: All 10 tests PASS

- [ ] **Step 3: Run memory tests**

Run: `swift test --package-path Packages/OsaurusCore --filter MemoryTests`
Expected: All existing tests still PASS

- [ ] **Step 4: Run migration tests**

Run: `swift test --package-path Packages/OsaurusCore --filter DatabaseMigrationTests`
Expected: All tests PASS including new V5 test

- [ ] **Step 5: Full compile check**

Run: `cd Packages/OsaurusCore && swift build 2>&1 | grep -E "error:" | grep -v "IkigaJSON"`
Expected: No errors

- [ ] **Step 6: Manual smoke test**

Open Xcode: `open osaurus.xcworkspace` → Run the "osaurus" scheme → Cmd+R

1. Open a project with a folder linked
2. Start a chat in that project
3. Send a message and wait for memory extraction
4. Open the project inspector → Memory section should show the new entry
5. Switch to a different project → Memory section should NOT show the first project's entries
6. Global (non-project) chat memories should appear in both projects

- [ ] **Step 7: Final commit if any fixups needed**

```bash
git add -A
git commit -m "fix(memory): integration fixups for project-scoped memory"
```
