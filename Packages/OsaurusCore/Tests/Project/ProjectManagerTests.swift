//
//  ProjectManagerTests.swift
//  osaurus
//
//  Tests for ProjectManager CRUD and context building.
//

import Foundation
import Testing

@testable import OsaurusCore

/// Tests operate on the real ProjectManager.shared singleton.
/// Each test creates and cleans up its own projects.
@Suite("ProjectManager Tests", .serialized)
struct ProjectManagerTests {

    private func makeMemoryEntry(projectId: UUID) -> MemoryEntry {
        MemoryEntry(
            agentId: "project-manager-tests",
            type: .fact,
            content: "Persist for \(projectId.uuidString)",
            model: "test",
            projectId: projectId.uuidString
        )
    }

    @Test("Create and retrieve a project")
    @MainActor
    func createProject() async throws {
        let manager = ProjectManager.shared
        let project = manager.createProject(name: "Test CIMCO \(UUID().uuidString.prefix(8))", icon: "snowflake")

        #expect(project.icon == "snowflake")
        #expect(manager.projects.contains(where: { $0.id == project.id }))
        manager.deleteProject(id: project.id)
        #expect(!manager.projects.contains(where: { $0.id == project.id }))
    }

    @Test("Active projects filters correctly")
    @MainActor
    func activeProjects() async throws {
        let manager = ProjectManager.shared
        let p1 = manager.createProject(name: "Active \(UUID().uuidString.prefix(8))")
        defer { manager.deleteProject(id: p1.id) }
        var p2 = manager.createProject(name: "Archived \(UUID().uuidString.prefix(8))")
        defer { manager.deleteProject(id: p2.id) }
        p2.isArchived = true
        manager.updateProject(p2)

        let active = manager.activeProjects
        #expect(active.contains(where: { $0.id == p1.id }))
        #expect(!active.contains(where: { $0.id == p2.id }))
    }

    @Test("Unarchive restores project to active visibility")
    @MainActor
    func unarchiveProject() async throws {
        let manager = ProjectManager.shared
        let project = manager.createProject(name: "Unarchive \(UUID().uuidString.prefix(8))")
        defer { manager.deleteProject(id: project.id) }

        manager.archiveProject(id: project.id)
        #expect(!manager.activeProjects.contains(where: { $0.id == project.id }))
        #expect(manager.archivedProjects.contains(where: { $0.id == project.id }))

        manager.unarchiveProject(id: project.id)
        #expect(manager.activeProjects.contains(where: { $0.id == project.id }))
        #expect(!manager.archivedProjects.contains(where: { $0.id == project.id }))
    }

    @Test("Last active project persists and validates")
    @MainActor
    func lastActiveProjectPersistence() async throws {
        let manager = ProjectManager.shared
        let project = manager.createProject(name: "Persist Test \(UUID().uuidString.prefix(8))")
        defer { manager.deleteProject(id: project.id) }

        manager.setActiveProject(project.id)
        #expect(manager.lastActiveProjectId == project.id)

        manager.setActiveProject(nil)
        #expect(manager.lastActiveProjectId == nil)
    }

    @Test("Last active project cleared on delete")
    @MainActor
    func lastActiveProjectClearedOnDelete() async throws {
        let manager = ProjectManager.shared
        let project = manager.createProject(name: "Delete Test \(UUID().uuidString.prefix(8))")

        manager.setActiveProject(project.id)
        #expect(manager.lastActiveProjectId == project.id)

        manager.deleteProject(id: project.id)
        #expect(manager.lastActiveProjectId == nil)
    }

    @Test("Last active project cleared on archive")
    @MainActor
    func lastActiveProjectClearedOnArchive() async throws {
        let manager = ProjectManager.shared
        let project = manager.createProject(name: "Archive Test \(UUID().uuidString.prefix(8))")
        defer { manager.deleteProject(id: project.id) }

        manager.setActiveProject(project.id)
        #expect(manager.lastActiveProjectId == project.id)

        manager.archiveProject(id: project.id)
        #expect(manager.lastActiveProjectId == nil)
    }

    @Test("Archive disables project-owned watchers and schedules")
    @MainActor
    func archiveDisablesProjectAutomations() async throws {
        let manager = ProjectManager.shared
        let project = manager.createProject(name: "Automations \(UUID().uuidString.prefix(8))")
        defer { manager.deleteProject(id: project.id) }

        let watcherId = UUID()
        let watcher = Watcher(
            id: watcherId,
            name: "Watcher \(watcherId.uuidString.prefix(6))",
            instructions: "Watch for changes",
            isEnabled: true,
            projectId: project.id
        )
        WatcherStore.save(watcher)
        WatcherManager.shared.refresh()
        defer {
            _ = WatcherManager.shared.delete(id: watcherId)
        }

        let scheduleId = UUID()
        let schedule = Schedule(
            id: scheduleId,
            name: "Schedule \(scheduleId.uuidString.prefix(6))",
            instructions: "Run later",
            frequency: .daily(hour: 9, minute: 0),
            isEnabled: true,
            projectId: project.id
        )
        ScheduleStore.save(schedule)
        ScheduleManager.shared.refresh()
        defer {
            _ = ScheduleManager.shared.delete(id: scheduleId)
        }

        manager.archiveProject(id: project.id)

        #expect(WatcherManager.shared.watcher(for: watcherId)?.isEnabled == false)
        #expect(ScheduleManager.shared.schedule(for: scheduleId)?.isEnabled == false)

        manager.unarchiveProject(id: project.id)
        #expect(WatcherManager.shared.watcher(for: watcherId)?.isEnabled == false)
        #expect(ScheduleManager.shared.schedule(for: scheduleId)?.isEnabled == false)
    }

    @Test("Project context builds from instructions")
    @MainActor
    func projectContext() async throws {
        let manager = ProjectManager.shared
        let project = manager.createProject(
            name: "Context \(UUID().uuidString.prefix(8))",
            instructions: "Always use metric units"
        )
        defer { manager.deleteProject(id: project.id) }

        let context = await manager.projectContext(for: project.id)
        #expect(context?.contains("Always use metric units") == true)
    }

    @Test("Delete leaves linked folder and memory untouched")
    @MainActor
    func deleteLeavesFolderAndMemoryUntouched() async throws {
        let manager = ProjectManager.shared
        let folderURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }
        if !MemoryDatabase.shared.isOpen {
            try MemoryDatabase.shared.open()
        }

        let project = manager.createProject(
            name: "Delete Safety \(UUID().uuidString.prefix(8))",
            folderPath: folderURL.path
        )

        let entry = makeMemoryEntry(projectId: project.id)
        try MemoryDatabase.shared.insertMemoryEntry(entry)
        defer { try? MemoryDatabase.shared.deleteMemoryEntry(id: entry.id) }

        let beforeDelete = try MemoryDatabase.shared.countEntriesByProject(projectId: project.id.uuidString)
        #expect(beforeDelete.total >= 1)

        manager.deleteProject(id: project.id)

        #expect(FileManager.default.fileExists(atPath: folderURL.path))

        let afterDelete = try MemoryDatabase.shared.countEntriesByProject(projectId: project.id.uuidString)
        #expect(afterDelete.total == beforeDelete.total)
    }
}
