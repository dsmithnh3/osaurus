//
//  MemoryProjectScopingTests.swift
//  osaurus
//
//  Verifies that project-scoped queries return project + global entries.
//

import Foundation
import SQLite3
import Testing

@testable import OsaurusCore

@Suite(.serialized)
struct MemoryDatabaseProjectScopingTests {

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

        let entity = try db.resolveEntity(name: "HVAC System", type: "system", model: "test")
        #expect(entity.name == "HVAC System")

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
