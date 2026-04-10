//
//  ProjectIdSerializationTests.swift
//  osaurus
//
//  Tests that projectId: UUID? round-trips correctly through JSON encoding/decoding
//  on ChatSessionData, Schedule, Watcher, and WorkTask.
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite("ProjectId Serialization Tests")
struct ProjectIdSerializationTests {

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - ChatSessionData

    @Test("ChatSessionData encodes and decodes projectId when set")
    func chatSessionDataWithProjectId() throws {
        let projectId = UUID()
        let original = ChatSessionData(
            id: UUID(),
            title: "Test Session",
            createdAt: Date(),
            updatedAt: Date(),
            selectedModel: nil,
            turns: [],
            agentId: nil,
            projectId: projectId
        )

        let data = try makeEncoder().encode(original)
        let decoded = try makeDecoder().decode(ChatSessionData.self, from: data)

        #expect(decoded.projectId == projectId)
        #expect(decoded.id == original.id)
        #expect(decoded.title == original.title)
    }

    @Test("ChatSessionData preserves nil projectId through round-trip")
    func chatSessionDataWithNilProjectId() throws {
        let original = ChatSessionData(
            id: UUID(),
            title: "No Project Session",
            createdAt: Date(),
            updatedAt: Date(),
            selectedModel: nil,
            turns: [],
            agentId: nil,
            projectId: nil
        )

        let data = try makeEncoder().encode(original)
        let decoded = try makeDecoder().decode(ChatSessionData.self, from: data)

        #expect(decoded.projectId == nil)
        #expect(decoded.id == original.id)
    }

    @Test("ChatSessionData JSON omits projectId key when nil")
    func chatSessionDataNilProjectIdOmitted() throws {
        let original = ChatSessionData(projectId: nil)
        let data = try makeEncoder().encode(original)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["projectId"] == nil)
    }

    @Test("ChatSessionData JSON includes projectId key when set")
    func chatSessionDataProjectIdPresent() throws {
        let projectId = UUID()
        let original = ChatSessionData(projectId: projectId)
        let data = try makeEncoder().encode(original)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["projectId"] as? String == projectId.uuidString)
    }

    // MARK: - Schedule

    @Test("Schedule encodes and decodes projectId when set")
    func scheduleWithProjectId() throws {
        let projectId = UUID()
        let original = Schedule(
            id: UUID(),
            name: "Daily Digest",
            instructions: "Summarize the day's work",
            agentId: nil,
            mode: .chat,
            parameters: [:],
            folderPath: nil,
            folderBookmark: nil,
            frequency: .daily(hour: 9, minute: 0),
            isEnabled: true,
            lastRunAt: nil,
            lastChatSessionId: nil,
            createdAt: Date(),
            updatedAt: Date(),
            projectId: projectId
        )

        let data = try makeEncoder().encode(original)
        let decoded = try makeDecoder().decode(Schedule.self, from: data)

        #expect(decoded.projectId == projectId)
        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
    }

    @Test("Schedule preserves nil projectId through round-trip")
    func scheduleWithNilProjectId() throws {
        let original = Schedule(
            name: "Weekly Summary",
            instructions: "Review the week",
            frequency: .weekly(dayOfWeek: 6, hour: 17, minute: 0),
            projectId: nil
        )

        let data = try makeEncoder().encode(original)
        let decoded = try makeDecoder().decode(Schedule.self, from: data)

        #expect(decoded.projectId == nil)
        #expect(decoded.id == original.id)
    }

    @Test("Schedule JSON omits projectId key when nil")
    func scheduleNilProjectIdOmitted() throws {
        let original = Schedule(
            name: "Hourly Check",
            instructions: "Check status",
            frequency: .hourly(minute: 30),
            projectId: nil
        )
        let data = try makeEncoder().encode(original)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["projectId"] == nil)
    }

    @Test("Schedule JSON includes projectId key when set")
    func scheduleProjectIdPresent() throws {
        let projectId = UUID()
        let original = Schedule(
            name: "Cron Job",
            instructions: "Run on schedule",
            frequency: .cron(expression: "0 9 * * 1-5"),
            projectId: projectId
        )
        let data = try makeEncoder().encode(original)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["projectId"] as? String == projectId.uuidString)
    }

    // MARK: - Watcher

    @Test("Watcher encodes and decodes projectId when set")
    func watcherWithProjectId() throws {
        let projectId = UUID()
        let original = Watcher(
            id: UUID(),
            name: "Downloads Watcher",
            instructions: "Process new files in downloads folder",
            agentId: nil,
            parameters: [:],
            watchPath: "/Users/test/Downloads",
            watchBookmark: nil,
            isEnabled: true,
            recursive: false,
            responsiveness: .balanced,
            settleSeconds: 2.0,
            lastTriggeredAt: nil,
            lastChatSessionId: nil,
            createdAt: Date(),
            updatedAt: Date(),
            projectId: projectId
        )

        let data = try makeEncoder().encode(original)
        let decoded = try makeDecoder().decode(Watcher.self, from: data)

        #expect(decoded.projectId == projectId)
        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
    }

    @Test("Watcher preserves nil projectId through round-trip")
    func watcherWithNilProjectId() throws {
        let original = Watcher(
            name: "Desktop Watcher",
            instructions: "Watch for screenshots",
            projectId: nil
        )

        let data = try makeEncoder().encode(original)
        let decoded = try makeDecoder().decode(Watcher.self, from: data)

        #expect(decoded.projectId == nil)
        #expect(decoded.id == original.id)
    }

    @Test("Watcher JSON omits projectId key when nil")
    func watcherNilProjectIdOmitted() throws {
        let original = Watcher(
            name: "General Watcher",
            instructions: "Watch everything",
            projectId: nil
        )
        let data = try makeEncoder().encode(original)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["projectId"] == nil)
    }

    @Test("Watcher JSON includes projectId key when set")
    func watcherProjectIdPresent() throws {
        let projectId = UUID()
        let original = Watcher(
            name: "Project Watcher",
            instructions: "Watch project folder",
            projectId: projectId
        )
        let data = try makeEncoder().encode(original)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["projectId"] as? String == projectId.uuidString)
    }

    // MARK: - WorkTask

    @Test("WorkTask encodes and decodes projectId when set")
    func workTaskWithProjectId() throws {
        let projectId = UUID()
        let original = WorkTask(
            id: UUID().uuidString,
            title: "Implement feature",
            query: "Add dark mode support to the app",
            agentId: nil,
            status: .active,
            createdAt: Date(),
            updatedAt: Date(),
            projectId: projectId
        )

        let data = try makeEncoder().encode(original)
        let decoded = try makeDecoder().decode(WorkTask.self, from: data)

        #expect(decoded.projectId == projectId)
        #expect(decoded.id == original.id)
        #expect(decoded.title == original.title)
    }

    @Test("WorkTask preserves nil projectId through round-trip")
    func workTaskWithNilProjectId() throws {
        let original = WorkTask(
            title: "Standalone Task",
            query: "Do something without a project",
            projectId: nil
        )

        let data = try makeEncoder().encode(original)
        let decoded = try makeDecoder().decode(WorkTask.self, from: data)

        #expect(decoded.projectId == nil)
        #expect(decoded.id == original.id)
    }

    @Test("WorkTask JSON omits projectId key when nil")
    func workTaskNilProjectIdOmitted() throws {
        let original = WorkTask(
            title: "No Project Task",
            query: "A task with no project",
            projectId: nil
        )
        let data = try makeEncoder().encode(original)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["projectId"] == nil)
    }

    @Test("WorkTask JSON includes projectId key when set")
    func workTaskProjectIdPresent() throws {
        let projectId = UUID()
        let original = WorkTask(
            title: "Project Task",
            query: "A task tied to a project",
            projectId: projectId
        )
        let data = try makeEncoder().encode(original)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["projectId"] as? String == projectId.uuidString)
    }
}
