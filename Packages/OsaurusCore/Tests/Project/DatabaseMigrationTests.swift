//
//  DatabaseMigrationTests.swift
//  osaurus
//
//  Verifies that MemoryDatabase V4 and WorkDatabase V5 migrations apply correctly
//  by inspecting schema via SQLite PRAGMA statements.
//

import Foundation
import SQLite3
import Testing

@testable import OsaurusCore

@Suite(.serialized)
struct DatabaseMigrationTests {

    // MARK: - Helpers

    /// Returns the set of column names for the given table in an open SQLite connection.
    private func columnNames(in db: OpaquePointer, table: String) -> Set<String> {
        var columns = Set<String>()
        var stmt: OpaquePointer?
        let sql = "PRAGMA table_info(\(table))"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            return columns
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if let raw = sqlite3_column_text(statement, 1) {
                columns.insert(String(cString: raw))
            }
        }
        return columns
    }

    /// Returns the set of index names for the given table in an open SQLite connection.
    private func indexNames(in db: OpaquePointer, table: String) -> Set<String> {
        var indexes = Set<String>()
        var stmt: OpaquePointer?
        let sql = "PRAGMA index_list(\(table))"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            return indexes
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if let raw = sqlite3_column_text(statement, 1) {
                indexes.insert(String(cString: raw))
            }
        }
        return indexes
    }

    // MARK: - MemoryDatabase V4 Tests
    // MemoryDatabase supports openInMemory() — no overrideRoot needed.

    @Test func memoryDatabaseV4AddsProjectIdToMemoryEntries() throws {
        let db = MemoryDatabase()
        try db.openInMemory()
        defer { db.close() }

        try db.execute { connection in
            let columns = self.columnNames(in: connection, table: "memory_entries")
            #expect(columns.contains("project_id"), "memory_entries should have project_id column")
        }
    }

    @Test func memoryDatabaseV4AddsProjectIdToConversationSummaries() throws {
        let db = MemoryDatabase()
        try db.openInMemory()
        defer { db.close() }

        try db.execute { connection in
            let columns = self.columnNames(in: connection, table: "conversation_summaries")
            #expect(columns.contains("project_id"), "conversation_summaries should have project_id column")
        }
    }

    @Test func memoryDatabaseV4AddsProjectIdToConversations() throws {
        let db = MemoryDatabase()
        try db.openInMemory()
        defer { db.close() }

        try db.execute { connection in
            let columns = self.columnNames(in: connection, table: "conversations")
            #expect(columns.contains("project_id"), "conversations should have project_id column")
        }
    }

    @Test func memoryDatabaseV4AddsProjectIdToEntities() throws {
        let db = MemoryDatabase()
        try db.openInMemory()
        defer { db.close() }

        try db.execute { connection in
            let columns = self.columnNames(in: connection, table: "entities")
            #expect(columns.contains("project_id"), "entities should have project_id column")
        }
    }

    @Test func memoryDatabaseV4AddsProjectIdToRelationships() throws {
        let db = MemoryDatabase()
        try db.openInMemory()
        defer { db.close() }

        try db.execute { connection in
            let columns = self.columnNames(in: connection, table: "relationships")
            #expect(columns.contains("project_id"), "relationships should have project_id column")
        }
    }

    @Test func memoryDatabaseV4CreatesMemoryEntriesAgentProjectIndex() throws {
        let db = MemoryDatabase()
        try db.openInMemory()
        defer { db.close() }

        try db.execute { connection in
            let indexes = self.indexNames(in: connection, table: "memory_entries")
            #expect(indexes.contains("idx_memory_entries_agent_project"))
        }
    }

    @Test func memoryDatabaseV4CreatesSummariesAgentProjectIndex() throws {
        let db = MemoryDatabase()
        try db.openInMemory()
        defer { db.close() }

        try db.execute { connection in
            let indexes = self.indexNames(in: connection, table: "conversation_summaries")
            #expect(indexes.contains("idx_summaries_agent_project"))
        }
    }

    @Test func memoryDatabaseV4CreatesConversationsAgentProjectIndex() throws {
        let db = MemoryDatabase()
        try db.openInMemory()
        defer { db.close() }

        try db.execute { connection in
            let indexes = self.indexNames(in: connection, table: "conversations")
            #expect(indexes.contains("idx_conversations_agent_project"))
        }
    }

    // MARK: - WorkDatabase V5 Tests
    // WorkDatabase.shared is a singleton with private init. Open and query schema directly.

    @Test func workDatabaseV5CreatesProjectAgentsTable() throws {
        let db = WorkDatabase.shared
        try db.open()
        defer { db.close() }

        try db.execute { connection in
            let columns = self.columnNames(in: connection, table: "project_agents")
            #expect(!columns.isEmpty, "project_agents table should exist after V5 migration")
            #expect(columns.contains("project_id"), "project_agents should have project_id column")
            #expect(columns.contains("agent_id"), "project_agents should have agent_id column")
            #expect(columns.contains("added_at"), "project_agents should have added_at column")
        }
    }

    @Test func workDatabaseV5CreatesIndexOnAgentId() throws {
        let db = WorkDatabase.shared
        try db.open()
        defer { db.close() }

        try db.execute { connection in
            let indexes = self.indexNames(in: connection, table: "project_agents")
            #expect(indexes.contains("idx_project_agents_agent"))
        }
    }
}
